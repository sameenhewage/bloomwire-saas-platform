require 'rails_helper'

# Phase 13E.1 — out-of-window WhatsApp TEMPLATE send under Bloomwire managed mode (NO real Meta).
#
# Proves the EXISTING OSS template path works with all Bloomwire toggles ON (master + privacy + router +
# every restrict_* gate), end to end with a STUBBED Graph endpoint:
#   out-of-window conversation (can_reply? == false)
#     -> outgoing Message with additional_attributes.template_params (approved template)
#     -> SendReplyJob -> Whatsapp::SendOnWhatsappService (template path, not session)
#     -> Whatsapp::Providers::WhatsappCloudService#send_template (POST type:'template' with name/language/components)
#     -> returned wamid stored in message.source_id
#     -> status webhooks reconcile sent -> delivered -> read on that wamid
# Plus: managed-mode restrictions do NOT block template sending (agent API create succeeds), and a
# missing/blank template fails safely. All values fake; WebMock guarantees no graph.facebook.com egress.
RSpec.describe 'Bloomwire WhatsApp out-of-window template send (managed mode)', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:phone_number_id) { 'PNID-TPL-1' }
  let(:display_phone_number) { '15551230001' }
  let(:customer_number) { '15559990001' }
  let(:wamid) { 'wamid.TPL-SENT-1' }

  let!(:setup) do
    create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                          aligned_phone_number_id: phone_number_id,
                                                          aligned_display_phone_number: display_phone_number)
  end
  let(:channel) { setup.channel_whatsapp }
  let(:contact) { create(:contact, account: account, phone_number: "+#{customer_number}") }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: customer_number) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:graph_url) { bw_graph_messages_url(channel.provider_config['phone_number_id']) }
  let(:success_body) { { messages: [{ id: wamid }] }.to_json }

  # An APPROVED template present in the factory channel's message_templates (sample_shipping_confirmation/en_US).
  let(:template_params) do
    { 'name' => 'sample_shipping_confirmation', 'language' => 'en_US', 'category' => 'SHIPPING_UPDATE',
      'processed_params' => { 'body' => { '1' => '3' } } }
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    # Managed mode FULLY ON, including every restriction gate, to prove template send is not blocked.
    bw_enable_all
    bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
    bw_set_config('BLOOMWIRE_RESTRICT_PROVIDER_SETUP', true)
    bw_set_config('BLOOMWIRE_RESTRICT_ACCOUNT_ADMIN', true)
    bw_set_config('BLOOMWIRE_RESTRICT_BOT_MANAGEMENT', true)
  end

  after { bw_clear_message_dedup }

  def create_outgoing(template: template_params, content: 'Your package has been shipped.')
    aa = template ? { 'template_params' => template } : {}
    message = nil
    perform_enqueued_jobs(only: SendReplyJob) do
      message = create(:message, message_type: :outgoing, content: content, conversation: conversation,
                                 account: account, additional_attributes: aa)
    end
    message
  end

  def post_status(status:, wamid: self.wamid)
    payload = bw_status_payload(phone_number_id: phone_number_id, display_phone_number: display_phone_number,
                                wamid: wamid, status: status, recipient: customer_number)
    perform_enqueued_jobs(only: Webhooks::WhatsappEventsJob) { bw_post_router(payload) }
  end

  it 'precondition: the conversation is OUT of the 24h window' do
    expect(conversation.can_reply?).to be(false)
  end

  it 'managed-mode sanity: every Bloomwire restriction gate is ON' do
    expect(Bloomwire::Features.restrict_native_whatsapp_setup?).to be(true)
    expect(Bloomwire::Features.restrict_provider_setup?).to be(true)
    expect(Bloomwire::Features.restrict_account_admin?).to be(true)
    expect(Bloomwire::Features.restrict_bot_management?).to be(true)
  end

  context 'when the stubbed Graph template send succeeds' do
    before do
      stub_request(:post, graph_url).to_return(status: 200, body: success_body, headers: { 'content-type' => 'application/json' })
    end

    it 'uses the TEMPLATE path (type:template), stores template_params, and stores the returned wamid' do
      message = create_outgoing

      expect(a_request(:post, graph_url).with { |req| JSON.parse(req.body)['type'] == 'template' }).to have_been_made.once
      expect(message.reload.additional_attributes['template_params']).to be_present
      expect(message.reload.source_id).to eq(wamid)
      expect(message.reload.status).not_to eq('failed')
    end

    it 'sends the expected template name + language + components to Graph' do
      create_outgoing

      expect(
        a_request(:post, graph_url).with do |req|
          tpl = JSON.parse(req.body)['template']
          tpl && tpl['name'] == 'sample_shipping_confirmation' &&
            tpl.dig('language', 'code') == 'en_US' && tpl['components'].is_a?(Array)
        end
      ).to have_been_made.once
    end

    it 'reconciles sent -> delivered -> read on the template wamid' do
      message = create_outgoing
      expect(message.reload.source_id).to eq(wamid)

      post_status(status: 'delivered')
      expect(message.reload.status).to eq('delivered')

      post_status(status: 'read')
      expect(message.reload.status).to eq('read')
    end
  end

  context 'when no template is provided for an out-of-window conversation (missing template)' do
    it 'fails safely with a clear external_error and makes no Graph call' do
      message = create_outgoing(template: nil)

      expect(message.reload.status).to eq('failed')
      expect(message.reload.external_error).to include('Template not found')
      expect(a_request(:post, graph_url)).not_to have_been_made
    end
  end

  context 'when the requested template name is not approved (Meta rejects it)' do
    let(:template_params) do
      { 'name' => 'nonexistent_template_xyz', 'language' => 'en_US', 'processed_params' => { 'body' => {} } }
    end

    before do
      stub_request(:post, graph_url).to_return(
        status: 400,
        body: { error: { message: 'Template name does not exist in the translation', code: 132_001 } }.to_json,
        headers: { 'content-type' => 'application/json' }
      )
    end

    it 'marks the message failed with the provider error (redacted external_error)' do
      message = create_outgoing
      expect(message.reload.status).to eq('failed')
      expect(message.reload.external_error).to be_present
    end
  end

  context 'when an authenticated agent creates a template message in managed mode' do
    let(:agent) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, inbox: channel.inbox, user: agent) }

    it 'accepts the agent template-message create (200) and stores template_params' do
      post api_v1_account_conversation_messages_url(account_id: account.id, conversation_id: conversation.display_id),
           params: { content: 'Your package has been shipped.', template_params: template_params },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      created = conversation.messages.where(message_type: :outgoing).last
      expect(created.additional_attributes['template_params']).to be_present
      expect(created.additional_attributes['template_params']['name']).to eq('sample_shipping_confirmation')
    end
  end

  context 'without any real Meta egress' do
    it 'blocks non-localhost Graph connections unless explicitly stubbed' do
      expect(bw_meta_net_connect_blocked?).to be(true)
    end
  end
end
