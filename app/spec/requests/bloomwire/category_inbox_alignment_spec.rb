require 'rails_helper'

# Phase 17F.3: SERVER-AUTHORITATIVE guided TeamMember + InboxMember alignment. The request carries only the
# account-scoped Team + Inbox identity; the server recomputes eligibility + additive drift from fresh DB state and
# adds only those server-computed differences in one DATABASE transaction. No client-supplied membership authority,
# no schema, no persisted Team<->Inbox mapping, no Meta/WhatsApp/HTTP/external call.
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

  # Linked, unambiguous, drifted pair: team = [shared, team_only]; inbox = [shared, inbox_only]. The inbox overlaps
  # exactly one team (via `shared`), so it is a derived pair. Additive alignment should add inbox_only -> team and
  # team_only -> inbox, removing nobody.
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

      it 'additively aligns a derived pair bidirectionally from identity alone (team-only -> InboxMember, inbox-only -> TeamMember)' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id })

        expect(response).to have_http_status(:ok)
        expect(team.reload.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
        expect(inbox.reload.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
      end

      it 'returns the server-computed additive diff (never removing staff) as a safe DTO' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id })

        body = response.parsed_body
        expect(body['added_to_inbox'].pluck('id')).to contain_exactly(team_only.id)
        expect(body['added_to_team'].pluck('id')).to contain_exactly(inbox_only.id)
        expect(body['aligned']).to be(true)
        expect(response.body).not_to match(/provider_config|api_key|super_secret_token|access[_-]?token/i)
      end

      it 'recomputes drift server-side and IGNORES any client-submitted user_ids (no write authority)' do
        setup_drift
        outsider = create(:user, account: account, role: :agent) # in neither team nor inbox
        align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [outsider.id] })

        expect(response).to have_http_status(:ok)
        # only the server-computed drift is applied; the injected outsider is never added anywhere
        expect(team.reload.members.map(&:id)).not_to include(outsider.id)
        expect(inbox.reload.members.map(&:id)).not_to include(outsider.id)
        expect(team.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
        expect(inbox.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
      end

      it 'grants no user_ids mutation authority even when the pair is already aligned' do
        team.add_members([shared.id])
        inbox.add_members([shared.id])
        outsider = create(:user, account: account, role: :agent)

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id, user_ids: [outsider.id] }) }
          .not_to(change { member_counts })
        expect(response).to have_http_status(:ok)
        expect(inbox.reload.members.map(&:id)).not_to include(outsider.id)
      end

      it 'uses FRESH server state when membership changed after the preview (stale preview is safe, no duplicate)' do
        setup_drift
        # simulate a change between preview and confirm: team_only was granted inbox access out-of-band
        inbox.add_members([team_only.id])

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }
          .to change(TeamMember, :count).by(1) # only inbox_only -> team remains actionable
        expect(response).to have_http_status(:ok)
        expect(team.reload.members.map(&:id)).to contain_exactly(shared.id, team_only.id, inbox_only.id)
        # team_only is not double-added to the inbox
        expect(inbox.reload.inbox_members.where(user_id: team_only.id).count).to eq(1)
      end

      it 'is a no-op when the pair is already aligned' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id })

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['added_to_team']).to eq([])
        expect(response.parsed_body['added_to_inbox']).to eq([])
      end

      it 'fails closed for an UNRELATED same-account pair (inbox derived to a different team)' do
        other_team = create(:team, account: account)
        other_team.add_members([shared.id])       # inbox is derived to other_team (shares `shared`)
        inbox.add_members([shared.id, inbox_only.id])
        team.add_members([team_only.id])           # `team` does not overlap the inbox

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'fails closed for an AMBIGUOUS pair (inbox overlaps more than one team)' do
        team_b = create(:team, account: account)
        team.add_members([team_only.id])
        team_b.add_members([inbox_only.id])
        inbox.add_members([team_only.id, inbox_only.id]) # overlaps both team and team_b

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'fails closed for an UNLINKED pair (inbox overlaps no team)' do
        team.add_members([team_only.id])
        inbox.add_members([inbox_only.id]) # inbox_only is in no team => no overlap

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'fails closed when a previously-linked pair became AMBIGUOUS after the preview (stale)' do
        setup_drift # linked + drifted
        other_team = create(:team, account: account)
        other_team.add_members([inbox_only.id]) # now inbox overlaps team AND other_team => ambiguous

        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'rejects a cross-account Team (404) and performs no writes' do
        other_team = create(:team, account: create(:account))
        expect { align(admin, { team_id: other_team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:not_found)
      end

      it 'rejects a cross-account Inbox (404) and performs no writes' do
        other_inbox = create(:inbox, account: create(:account))
        expect { align(admin, { team_id: team.id, inbox_id: other_inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:not_found)
      end

      it 'denies a business agent and performs no writes' do
        setup_drift
        expect { align(agent, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:unauthorized)
      end

      it 'is database-atomic: a mid-write failure rolls back ALL membership rows' do
        setup_drift
        # inbox additions run first; force the later team-side write to fail so the already-written inbox row must roll back
        allow_any_instance_of(TeamMember).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(TeamMember.new)) # rubocop:disable RSpec/AnyInstance
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }.not_to(change { member_counts })
        expect(response).to have_http_status(:unprocessable_entity)
        # DB is fully rolled back. The stock InboxMember after_create round-robin (Redis LPUSH) is OUTSIDE this DB
        # transaction and may leave a transient entry; it self-heals from inbox.inbox_members via
        # AutoAssignment::InboxRoundRobinService (validate_queue? / reset_queue). We assert the DB guarantee here.
      end

      it 'keeps the round-robin queue reconcilable with the DB inbox members (local Redis callback, not authoritative)' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id })

        queue_key = format(Redis::Alfred::ROUND_ROBIN_AGENTS, inbox_id: inbox.id)
        queue_ids = Redis::Alfred.lrange(queue_key).map(&:to_i)
        # the local Redis round-robin callback ran and the queue reflects the DB source of truth (self-healing boundary)
        expect(queue_ids).to match_array(inbox.reload.inbox_members.pluck(:user_id))
      end

      it 'creates no persistent Team<->Inbox mapping (only join rows change; no schema column)' do
        setup_drift
        expect { align(admin, { team_id: team.id, inbox_id: inbox.id }) }
          .to change(TeamMember, :count).by(1).and change(InboxMember, :count).by(1)
        expect(Inbox.column_names).not_to include('team_id')
        expect(Team.column_names).not_to include('inbox_id')
      end

      it 'makes no Meta/WhatsApp/external call during alignment' do
        setup_drift
        align(admin, { team_id: team.id, inbox_id: inbox.id })
        expect(a_request(:any, /graph\.facebook\.com|myshopify\.com/)).not_to have_been_made
      end
    end

    context 'when the feature is OFF' do
      it 'returns 404 with only master ON (stock; no alignment surface)' do
        bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
        align(admin, { team_id: team.id, inbox_id: inbox.id })
        expect(response).to have_http_status(:not_found)
      end

      it 'returns 404 with Bloomwire fully OFF (stock Chatwoot preserved)' do
        align(admin, { team_id: team.id, inbox_id: inbox.id })
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
