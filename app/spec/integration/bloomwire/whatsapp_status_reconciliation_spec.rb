require 'rails_helper'

# Phase 12B — WhatsApp status reconciliation E2E harness (NO real Meta).
#
# Proves that Meta delivery-status webhooks reconcile onto the SAME Message (keyed by source_id / wamid),
# end to end through the existing pipeline:
#   signed POST /bloomwire/webhooks/whatsapp (status payload)
#     -> Bloomwire::Webhooks::WhatsappController -> WhatsappEventsJob (inline)
#     -> Whatsapp::IncomingMessageWhatsappCloudService#process_statuses
#     -> Message#status advances sent -> delivered -> read (failed sets external_error)
#
# Locks already-implemented behavior. All values are fake; no graph.facebook.com call is made.
RSpec.describe 'Bloomwire WhatsApp status reconciliation E2E', type: :request do
  let(:account) { create(:account) }
  let(:phone_number_id) { 'PNID-STATUS-1' }
  let(:display_phone_number) { '15551230001' }
  let(:customer_number) { '15559990001' }
  let(:sent_wamid) { 'wamid.OUT-STATUS-1' }

  let!(:setup) do
    create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                          aligned_phone_number_id: phone_number_id,
                                                          aligned_display_phone_number: display_phone_number)
  end
  let(:channel) { setup.channel_whatsapp }
  let(:contact) { create(:contact, account: account, phone_number: "+#{customer_number}") }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: customer_number) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }
  let!(:message) do
    create(:message, message_type: :outgoing, content: 'agent reply', conversation: conversation,
                     account: account, source_id: sent_wamid, status: :sent)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    bw_enable_router
    bw_set_app_secret
  end

  after { bw_clear_message_dedup }

  def post_status(status:, wamid: sent_wamid, errors: nil)
    payload = bw_status_payload(phone_number_id: phone_number_id, display_phone_number: display_phone_number,
                                wamid: wamid, status: status, recipient: customer_number, errors: errors)
    perform_enqueued_jobs(only: Webhooks::WhatsappEventsJob) do
      bw_post_router(payload)
    end
  end

  it 'advances the same Message sent -> delivered -> read (no new messages created)' do
    expect(message.reload.status).to eq('sent')

    expect { post_status(status: 'delivered') }.not_to change(Message, :count)
    expect(message.reload.status).to eq('delivered')

    post_status(status: 'read')
    expect(message.reload.status).to eq('read')
    expect(response).to have_http_status(:ok)
  end

  it 'records the provider error on a failed status' do
    post_status(status: 'failed', errors: [{ 'code' => 131_026, 'title' => 'Message undeliverable' }])
    expect(message.reload.status).to eq('failed')
    expect(message.reload.external_error).to be_present
    expect(message.reload.external_error).to include('Message undeliverable')
  end

  it 'is a no-op for an unknown source_id (fail closed, message unchanged)' do
    expect { post_status(status: 'delivered', wamid: 'wamid.UNKNOWN-DOES-NOT-EXIST') }
      .not_to(change { message.reload.status })
    expect(message.reload.status).to eq('sent')
    expect(response).to have_http_status(:ok)
  end

  it 'makes no request to graph.facebook.com while reconciling status' do
    post_status(status: 'delivered')
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end
end
