require 'rails_helper'

# Phase 17F.3: guided TeamMember + InboxMember alignment. Local-only, admin-only, feature-gated transactional
# helper that additively aligns staff across an existing Team (category) and an existing Inbox. No schema, no
# persistent Team<->Inbox mapping, no Meta/WhatsApp/external call.
RSpec.describe 'Bloomwire Category<->Inbox membership alignment (17F.3)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/bloomwire/category_inbox_alignment" }

  let(:team) { create(:team, account: account) }
  let(:inbox) { whatsapp_inbox }
  let(:shared) { create(:user, account: account, role: :agent) }
  let(:team_only) { create(:user, account: account, role: :agent) }
  let(:inbox_only) { create(:user, account: account, role: :agent) }

  before { GlobalConfig.clear_cache }

  after { GlobalConfig.clear_cache }

  def enable_feature
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_CATEGORY_ADMIN_UI', true)
  end

  def whatsapp_inbox
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        provider_config: { 'api_key' => 'super_secret_token', 'phone_number_id' => "pnid#{SecureRandom.hex(4)}" },
                                        sync_templates: false, validate_provider_config: false)
    channel.inbox
  end

  # Drift fixture: team = [shared, team_only]; inbox = [shared, inbox_only]. Additive alignment of
  # [team_only, inbox_only] should add inbox_only to the team and team_only to the inbox, removing nobody.
  def setup_drift
    team.add_members([shared.id, team_only.id])
    inbox.add_members([shared.id, inbox_only.id])
  end

  def align(user, body)
    post url, headers: user.create_new_auth_token, params: body, as: :json
  end

  def member_counts
    [TeamMember.count, InboxMember.count]
  end

  describe 'POST #create' do
    context 'when the feature is ON' do
      before { enable_feature }

      it 'additively aligns membership for an administrator (adds missing on both sides, removes nobody)' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] })

        expect(response).to have_http_status(:ok)
        expect(team.reload.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
        expect(inbox.reload.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
      end

      it 'returns a safe additive diff DTO (added_to_team / added_to_inbox), never removing staff' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] })

        body = response.parsed_body
        expect(body['added_to_team'].pluck('id')).to contain_exactly(inbox_only.id)
        expect(body['added_to_inbox'].pluck('id')).to contain_exactly(team_only.id)
        expect(body['aligned']).to be(true)
        expect(response.body).not_to match(/provider_config|api_key|super_secret_token|access[_-]?token/i)
      end

      it 'denies a business agent and performs no writes' do
        setup_drift
        expect { align(agent, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:unauthorized)
      end

      it 'rejects a cross-account Team (404) and performs no writes' do
        other_team = create(:team, account: create(:account))
        expect { align(admin, { team_id: other_team.id, inbox_id: inbox.id, user_ids: [team_only.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:not_found)
      end

      it 'rejects a cross-account Inbox (404) and performs no writes' do
        other_inbox = create(:inbox, account: create(:account))
        expect { align(admin, { team_id: team.id, inbox_id: other_inbox.id, user_ids: [team_only.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:not_found)
      end

      it 'rejects a member user that does not belong to the account (422) and performs no writes' do
        foreign_user = create(:user, account: create(:account), role: :agent)
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [foreign_user.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'is idempotent — repeating the same alignment makes no further changes' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] })
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:ok)
      end

      it 'is a no-op when the staff are already aligned (adds nobody)' do
        team.add_members([shared.id])
        inbox.add_members([shared.id])
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [shared.id] }) }
          .not_to(change { member_counts })
        expect(response.parsed_body['added_to_team']).to eq([])
        expect(response.parsed_body['added_to_inbox']).to eq([])
      end

      it 'rolls back fully (atomic) when a membership write fails — no partial completion' do
        setup_drift
        allow_any_instance_of(InboxMember).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(InboxMember.new)) # rubocop:disable RSpec/AnyInstance
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'makes no Meta/WhatsApp/external call during alignment' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] })
        expect(a_request(:any, /graph\.facebook\.com|myshopify\.com/)).not_to have_been_made
      end

      it 'creates no persistent Team<->Inbox mapping (only join rows change; no schema column)' do
        setup_drift
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [team_only.id, inbox_only.id] }) }
          .to change(TeamMember, :count).by(1).and change(InboxMember, :count).by(1)
        expect(Inbox.column_names).not_to include('team_id')
        expect(Team.column_names).not_to include('inbox_id')
      end
    end

    context 'when the feature is OFF' do
      it 'returns 404 with only master ON (stock; no alignment surface)' do
        bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [] })
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 with Bloomwire fully OFF (stock Chatwoot preserved)' do
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [] })
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
