require 'rails_helper'

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

  def whatsapp_inbox(name: nil, connection_mode: nil, setup_status: nil)
    config = { 'api_key' => 'super_secret_token', 'phone_number_id' => "pnid#{SecureRandom.hex(4)}" }
    config['connection_mode'] = connection_mode if connection_mode
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        provider_config: config, sync_templates: false, validate_provider_config: false)
    channel.inbox.update!(name: name) if name

    if setup_status
      Bloomwire::WhatsappSetup.create!(account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                       setup_status: setup_status, phone_number_id: config['phone_number_id'])
    end

    channel.inbox
  end

  def link_members(record, *users)
    record.add_members(users.map(&:id))
  end

  def all_inbox_ids(body)
    body['categories'].flat_map { |category| category['derived_inboxes'].pluck('id') } +
      body.fetch('ambiguous_inboxes', []).pluck('id') +
      body['unlinked_inboxes'].pluck('id')
  end

  def get_overview(user = admin)
    get url, headers: user.create_new_auth_token, as: :json
    response.parsed_body
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
        body = get_overview

        expect(body['categories'].map { |category| category['id'] }).to include(team.id)
        expect(all_inbox_ids(body)).to include(inbox.id)
      end

      it 'blocks a business agent without an overview payload' do
        get url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include('categories', 'unlinked_inboxes', 'ambiguous_inboxes')
      end

      it 'does not leak another account teams or inboxes' do
        other = create(:account)
        other_team = create(:team, account: other)
        other_inbox = create(:inbox, account: other)
        body = get_overview

        expect(body['categories'].pluck('id')).not_to include(other_team.id)
        expect(all_inbox_ids(body)).not_to include(other_inbox.id)
      end

      it 'exposes only a safe WhatsApp summary and NO secrets/provider_config/tokens' do
        whatsapp_inbox
        get url, headers: admin.create_new_auth_token, as: :json

        expect(response.body).not_to match(/provider_config|api_key|super_secret_token|access[_-]?token|client_secret|verify_token/i)
      end

      it 'represents Standard and Coexistence only as safe badge values + setup status' do
        whatsapp_inbox(setup_status: 'configured')
        whatsapp_inbox(connection_mode: 'coexistence', setup_status: 'ready_for_webhook')
        body = get_overview
        wa = (body['categories'].flat_map { |category| category['derived_inboxes'] } +
              body.fetch('ambiguous_inboxes', []) + body['unlinked_inboxes']).filter_map { |inbox| inbox['whatsapp'] }

        expect(wa.pluck('connection_mode')).to include('standard', 'coexistence')
        expect(wa.pluck('setup_status')).to include('configured', 'ready_for_webhook')
      end

      it 'returns a safe fallback setup status when no Bloomwire setup exists for a WhatsApp inbox' do
        inbox = whatsapp_inbox(name: 'Setup missing')
        body = get_overview
        dto = (body['categories'].flat_map { |category| category['derived_inboxes'] } +
               body.fetch('ambiguous_inboxes', []) + body['unlinked_inboxes']).find { |item| item['id'] == inbox.id }

        expect(dto['whatsapp']['setup_status']).to eq('not_configured')
      end

      it 'keeps valid Bloomwire setup statuses unchanged' do
        %w[pending configured ready_for_webhook blocked].each { |status| whatsapp_inbox(setup_status: status) }
        body = get_overview
        statuses = (body['categories'].flat_map { |category| category['derived_inboxes'] } +
                    body.fetch('ambiguous_inboxes', []) + body['unlinked_inboxes']).filter_map do |inbox|
          inbox.dig('whatsapp', 'setup_status')
        end

        expect(statuses).to include('pending', 'configured', 'ready_for_webhook', 'blocked')
      end

      it 'marks exactly-one-team overlaps as linked relationships with drift details' do
        team = create(:team, account: account)
        inbox = whatsapp_inbox
        shared = create(:user, account: account, role: :agent)
        team_only = create(:user, account: account, role: :agent)
        inbox_only = create(:user, account: account, role: :agent)
        link_members(team, shared, team_only)
        link_members(inbox, shared, inbox_only)

        category = get_overview['categories'].find { |item| item['id'] == team.id }
        dto = category['derived_inboxes'].find { |item| item['id'] == inbox.id }

        expect(dto['relationship_status']).to eq('linked')
        expect(dto['matched_team_ids']).to eq([team.id])
        expect(dto['matched_team_count']).to eq(1)
        expect(dto['drift']['staff_missing_inbox_access'].pluck('id')).to contain_exactly(team_only.id)
        expect(dto['drift']['collaborators_not_in_team'].pluck('id')).to contain_exactly(inbox_only.id)
      end

      it 'surfaces multi-team overlaps as ambiguous instead of duplicating them as confirmed links' do
        sales = create(:team, account: account, name: 'Sales')
        support = create(:team, account: account, name: 'Support')
        inbox = whatsapp_inbox(name: 'Shared WA')
        sales_user = create(:user, account: account, role: :agent)
        support_user = create(:user, account: account, role: :agent)
        link_members(sales, sales_user)
        link_members(support, support_user)
        link_members(inbox, sales_user, support_user)

        body = get_overview
        duplicated_ids = body['categories'].flat_map { |category| category['derived_inboxes'].pluck('id') }
        ambiguous = body.fetch('ambiguous_inboxes', []).find { |item| item['id'] == inbox.id }

        expect(duplicated_ids).not_to include(inbox.id)
        expect(ambiguous['relationship_status']).to eq('ambiguous')
        expect(ambiguous['matched_team_ids']).to contain_exactly(sales.id, support.id)
        expect(ambiguous['matched_team_count']).to eq(2)
        expect(ambiguous['matched_teams'].pluck('name')).to contain_exactly('sales', 'support')
      end

      it 'marks zero-team overlaps as unlinked relationships' do
        inbox = whatsapp_inbox(name: 'Orphan WA')
        unlinked = get_overview['unlinked_inboxes'].find { |item| item['id'] == inbox.id }

        expect(unlinked['relationship_status']).to eq('unlinked')
        expect(unlinked['matched_team_ids']).to eq([])
        expect(unlinked['matched_team_count']).to eq(0)
      end

      it 'performs NO writes' do
        create(:team, account: account)
        whatsapp_inbox
        counts = lambda {
          [Team.count, Inbox.count, InboxMember.count, TeamMember.count, Conversation.count, Bloomwire::WhatsappSetup.count]
        }

        expect { get url, headers: admin.create_new_auth_token, as: :json }.not_to change(&counts)
      end

      it 'does not call external providers' do
        whatsapp_inbox
        get url, headers: admin.create_new_auth_token, as: :json

        expect(a_request(:any, /graph\.facebook\.com|myshopify\.com/)).not_to have_been_made
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
