require 'rails_helper'

# Phase 12B — WhatsApp outbound E2E harness (NO real Meta).
#
# Proves the full outbound chain end to end with a STUBBED Meta Graph endpoint:
#   outgoing Message (after_create_commit)
#     -> SendReplyJob (CHANNEL_SERVICES dispatch, run inline via perform_enqueued_jobs)
#     -> Whatsapp::SendOnWhatsappService
#     -> Channel::Whatsapp#send_message -> Whatsapp::Providers::WhatsappCloudService
#     -> POST graph.facebook.com/v13.0/<phone_number_id>/messages (WebMock-stubbed)
#     -> returned wamid stored in message.source_id
#
# Locks already-implemented behavior. All values are fake; the Graph endpoint is stubbed, and
# WebMock.disable_net_connect! guarantees no real network egress.
RSpec.describe 'Bloomwire WhatsApp outbound E2E', type: :request do
  let(:account) { create(:account) }
  let(:phone_number_id) { 'PNID-OUT-1' }
  let(:api_key) { 'FAKE-OUT-APIKEY' }
  let(:channel) do
    bw_aligned_whatsapp_channel(account: account, phone_number_id: phone_number_id,
                                display_phone_number: '15551230002', api_key: api_key)
  end
  let(:contact) { create(:contact, account: account, phone_number: '+15559990002') }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '15559990002') }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:graph_url) { bw_graph_messages_url(phone_number_id) }
  let(:success_body) { { messages: [{ id: 'wamid.SENT-OUT-1' }] }.to_json }

  before do
    ActiveJob::Base.queue_adapter = :test
    # A recent inbound message keeps the conversation inside the 24h session window (=> plain text send).
    create(:message, message_type: :incoming, content: 'customer says hi',
                     conversation: conversation, account: account)
  end

  def create_outgoing(content: 'agent reply body')
    message = nil
    perform_enqueued_jobs(only: SendReplyJob) do
      message = create(:message, message_type: :outgoing, content: content,
                                 conversation: conversation, account: account)
    end
    message
  end

  context 'when the Graph send succeeds' do
    before do
      stub_request(:post, graph_url).to_return(status: 200, body: success_body,
                                               headers: { 'content-type' => 'application/json' })
    end

    it 'enqueues SendReplyJob for the outgoing message (trigger)' do
      allow(SendReplyJob).to receive(:perform_later)
      message = create(:message, message_type: :outgoing, content: 'trigger only',
                                 conversation: conversation, account: account)
      expect(SendReplyJob).to have_received(:perform_later).with(message.id)
    end

    it 'sends via the stubbed Graph API and stores the returned wamid in source_id' do
      message = create_outgoing
      expect(message.reload.source_id).to eq('wamid.SENT-OUT-1')
    end

    it 'posts to the configured phone_number_id with the channel api_key as a Bearer token' do
      create_outgoing
      expect(
        a_request(:post, graph_url).with(headers: { 'Authorization' => "Bearer #{api_key}" })
      ).to have_been_made.once
    end
  end

  context 'when the Graph send fails' do
    before do
      stub_request(:post, graph_url).to_return(
        status: 401,
        body: { error: { message: 'Invalid OAuth access token', code: 190 } }.to_json,
        headers: { 'content-type' => 'application/json' }
      )
    end

    it 'marks the message failed and records the provider external_error' do
      message = create_outgoing
      expect(message.reload.status).to eq('failed')
      expect(message.reload.external_error).to be_present
      expect(message.reload.external_error).to include('Invalid OAuth access token')
    end
  end

  context 'without any real Meta network egress' do
    it 'blocks non-localhost Meta Graph connections unless explicitly stubbed' do
      expect(bw_meta_net_connect_blocked?).to be(true)
    end

    it 'only contacts Graph through the WebMock stub (one request, no real call)' do
      stub_request(:post, graph_url).to_return(status: 200, body: success_body,
                                               headers: { 'content-type' => 'application/json' })
      create_outgoing
      expect(a_request(:post, graph_url)).to have_been_made.once
    end
  end
end
