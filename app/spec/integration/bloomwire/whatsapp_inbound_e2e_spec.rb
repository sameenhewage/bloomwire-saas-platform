require 'rails_helper'

# Phase 12B — WhatsApp inbound E2E harness (NO real Meta).
#
# Proves the full managed inbound flow end to end through the EXISTING pipeline:
#   signed POST /bloomwire/webhooks/whatsapp
#     -> Bloomwire::Webhooks::WhatsappController (verify signature + router gate)
#     -> Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup
#     -> Webhooks::WhatsappEventsJob (run inline via perform_enqueued_jobs)
#     -> Whatsapp::IncomingMessageWhatsappCloudService
#     -> Contact + Conversation + Message created in the mapped inbox (Chatwoot source of truth)
#
# Locks already-implemented behavior against regression. All values are fake; no graph.facebook.com call is
# made for a text message (no media), and WebMock.disable_net_connect! guarantees no real network egress.
RSpec.describe 'Bloomwire WhatsApp inbound E2E', type: :request do
  let(:account) { create(:account) }
  let(:phone_number_id) { 'PNID-INBOUND-1' }
  let(:display_phone_number) { '15551230001' }
  let(:customer_number) { '15559990001' }
  let(:wamid) { 'wamid.INBOUND-ABC123' }

  let!(:setup) do
    create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                          aligned_phone_number_id: phone_number_id,
                                                          aligned_display_phone_number: display_phone_number)
  end
  let(:inbox) { setup.channel_whatsapp.inbox }

  before do
    ActiveJob::Base.queue_adapter = :test
    bw_enable_router
    bw_set_app_secret
  end

  after { bw_clear_message_dedup }

  def post_inbound(pnid: phone_number_id, body: 'hello there', wamid: 'wamid.INBOUND-ABC123', signature: :valid)
    payload = bw_inbound_text_payload(phone_number_id: pnid, display_phone_number: display_phone_number,
                                      from: customer_number, wamid: wamid, body: body, name: 'Test Customer')
    perform_enqueued_jobs(only: Webhooks::WhatsappEventsJob) do
      bw_post_router(payload, signature: signature)
    end
  end

  context 'with a valid signed payload for a ready_for_webhook mapping' do
    it 'returns 200 and creates exactly one Contact, Conversation and Message in the mapped inbox' do
      expect do
        post_inbound(body: 'hello there', wamid: wamid)
      end.to change { inbox.messages.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(inbox.conversations.count).to eq(1)
      expect(account.contacts.count).to eq(1)

      message = inbox.messages.last
      expect(message.content).to eq('hello there')
      expect(message.source_id).to eq(wamid)
      expect(message.message_type).to eq('incoming')
    end

    it 'maps the sender to a ContactInbox keyed by the WhatsApp source id' do
      post_inbound
      contact_inbox = inbox.contact_inboxes.find_by(source_id: customer_number)
      expect(contact_inbox).to be_present
      expect(contact_inbox.contact.name).to eq('Test Customer')
    end

    it 'does not create any extra Bloomwire control-plane rows (no duplication of source of truth)' do
      expect { post_inbound }.not_to change(Bloomwire::WhatsappSetup, :count)
    end
  end

  context 'when the same wamid is delivered twice (idempotency)' do
    it 'does not create a second Message' do
      post_inbound(wamid: wamid)
      expect(inbox.messages.count).to eq(1)

      # Meta re-delivers the identical webhook (same wamid). Dedup must keep it at one message.
      expect do
        post_inbound(wamid: wamid)
      end.not_to(change { inbox.messages.count })
      expect(inbox.messages.count).to eq(1)
    end
  end

  context 'when the Meta signature is invalid (fail closed)' do
    it 'returns 401 and creates nothing' do
      expect do
        post_inbound(signature: 'sha256=deadbeefdeadbeef')
      end.not_to(change { Message.count + Conversation.count + Contact.count })
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when the phone_number_id has no ready mapping (fail closed)' do
    it 'returns a safe 200 and creates nothing' do
      expect do
        post_inbound(pnid: 'PNID-UNKNOWN-9999')
      end.not_to(change { Message.count + Conversation.count + Contact.count })
      expect(response).to have_http_status(:ok)
    end
  end

  context 'without any real Meta network egress' do
    it 'makes no request to graph.facebook.com for a text inbound message' do
      post_inbound
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end
end
