require 'rails_helper'

# Phase 17F.1 — administrator-only, READ-ONLY "Categories & Inboxes" overview.
# Gated by BLOOMWIRE_CATEGORY_ADMIN_UI (OFF => 404, stock Chatwoot). Admin-only (agent => not-authorized).
# Account-scoped; safe DTO only (never provider_config/tokens/secrets); performs NO writes; NO schema.
RSpec.describe 'Bloomwire Category & Inboxes overview (17F.1)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/category_inbox_overview" }

  before { GlobalConfig.clear_cache }
  after { GlobalConfig.clear_cache }

  def enable_feature
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_CATEGORY_ADMIN_UI', true)
  end

  def whatsapp_inbox(connection_mode: nil)
    config = { 'api_key' => 'super_secret_token', 'phone_number_id' => "pnid#{rand(10_000)}" }
    config['connection_mode'] = connection_mode if connection_mode
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        provider_config: config, sync_templates: false, validate_provider_config: false)
    channel.inbox
  end

  describe 'GET #show' do
    context 'when the feature is ON' do
      before { enable_feature }

      it 'returns 200 for an administrator' do
        get url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'returns every account Team (category) and Inbox to the administrator' do
        team = create(:team, account: account)
        inbox = whatsapp_inbox
        get url, headers: admin.create_new_auth_token, as: :json
        body = response.parsed_body
        expect(body['categories'].map { |c| c['id'] }).to include(team.id)
        all_inbox_ids = body['categories'].flat_map { |c| c['derived_inboxes'].pluck('id') } +
                        body['unlinked_inboxes'].pluck('id')
        expect(all_inbox_ids).to include(inbox.id)
      end

      it 'blocks a business agent (not authorized)' do
        get url, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not leak another account\'s teams or inboxes' do
        other = create(:account)
        other_team = create(:team, account: other)
        other_inbox = create(:inbox, account: other)
        get url, headers: admin.create_new_auth_token, as: :json
        body = response.parsed_body
        expect(body['categories'].pluck('id')).not_to include(other_team.id)
        leaked = body['categories'].flat_map { |c| c['derived_inboxes'].pluck('id') } + body['unlinked_inboxes'].pluck('id')
        expect(leaked).not_to include(other_inbox.id)
      end

      it 'exposes only a safe WhatsApp summary and NO secrets/provider_config/tokens' do
        whatsapp_inbox
        get url, headers: admin.create_new_auth_token, as: :json
        expect(response.body).not_to match(/provider_config|api_key|super_secret_token|access[_-]?token|client_secret|verify_token/i)
      end

      it 'represents Standard and Coexistence only as safe badge values + setup status' do
        whatsapp_inbox
        coex = whatsapp_inbox(connection_mode: 'coexistence')
        Bloomwire::WhatsappSetup.create!(account: account, inbox: coex, channel_whatsapp: coex.channel,
                                         setup_status: 'ready_for_webhook', phone_number_id: 'pnid-coex')
        get url, headers: admin.create_new_auth_token, as: :json
        wa = (response.parsed_body['categories'].flat_map { |c| c['derived_inboxes'] } +
              response.parsed_body['unlinked_inboxes']).filter_map { |i| i['whatsapp'] }
        modes = wa.pluck('connection_mode')
        expect(modes).to include('standard')
        expect(modes).to include('coexistence')
        expect(wa.pluck('setup_status')).to include('ready_for_webhook')
      end

      it 'performs NO writes' do
        create(:team, account: account)
        whatsapp_inbox
        counts = lambda {
          [Team.count, Inbox.count, InboxMember.count, TeamMember.count, Conversation.count, Bloomwire::WhatsappSetup.count]
        }
        expect { get url, headers: admin.create_new_auth_token, as: :json }.not_to change(&counts)
      end

      it 'includes safe staff/member summaries + drift signals without secrets' do
        team = create(:team, account: account)
        inbox = whatsapp_inbox
        u1 = create(:user, account: account, role: :agent)
        team.add_members([u1.id])
        inbox.add_members([u1.id])
        get url, headers: admin.create_new_auth_token, as: :json
        cat = response.parsed_body['categories'].find { |c| c['id'] == team.id }
        expect(cat['staff'].pluck('id')).to include(u1.id)
        expect(cat).to have_key('derived_inboxes')
      end
    end

    context 'when the feature is OFF' do
      it 'returns 404 for an administrator when only master is ON (feature OFF => stock, no overview)' do
        bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
        get url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 with Bloomwire fully OFF (stock Chatwoot preserved)' do
        get url, headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
