require 'rails_helper'

# Phase 17E.2 — the single seam that scopes an agent's visible contacts to those reachable through their
# assigned inboxes (via contact_inboxes), gated by Bloomwire::Features.restrict_agent_contact_visibility?.
# Admins and the OFF (stock Chatwoot) state see ALL account contacts. No real Meta. Fake values only.
RSpec.describe Bloomwire::ContactVisibility do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent1) { create(:user, account: account, role: :agent) }
  let(:inbox1) { create(:inbox, account: account) }
  let(:inbox2) { create(:inbox, account: account) }

  # Contact A only in inbox1; Contact B only in inbox2; Contact C in BOTH (shared).
  let(:contact_a) { create(:contact, account: account) }
  let(:contact_b) { create(:contact, account: account) }
  let(:contact_c) { create(:contact, account: account) }

  before do
    GlobalConfig.clear_cache
    create(:inbox_member, user: agent1, inbox: inbox1)
    create(:contact_inbox, contact: contact_a, inbox: inbox1)
    create(:contact_inbox, contact: contact_b, inbox: inbox2)
    create(:contact_inbox, contact: contact_c, inbox: inbox1)
    create(:contact_inbox, contact: contact_c, inbox: inbox2)
  end

  # The GlobalConfig cache lives in Redis (not rolled back by the DB transaction), so clear it after each
  # example to avoid leaking the enabled Bloomwire gate into unrelated specs.
  after { GlobalConfig.clear_cache }

  def enable_gate
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY', true)
  end

  describe '.scope' do
    context 'when the gate is OFF (stock Chatwoot)' do
      it 'returns ALL account contacts even for an agent' do
        expect(described_class.scope(account: account, user: agent1)).to include(contact_a, contact_b, contact_c)
      end
    end

    context 'when the gate is ON' do
      before { enable_gate }

      it 'restricts an agent to contacts reachable via their assigned inboxes (+ shared), excluding others' do
        result = described_class.scope(account: account, user: agent1)
        aggregate_failures do
          expect(result).to include(contact_a, contact_c)
          expect(result).not_to include(contact_b)
        end
      end

      it 'returns ALL account contacts for an admin (never restricted)' do
        expect(described_class.scope(account: account, user: admin)).to include(contact_a, contact_b, contact_c)
      end

      it 'returns a shared contact exactly once (distinct — no duplicate rows from the join)' do
        result = described_class.scope(account: account, user: agent1)
        expect(result.to_a.count { |c| c.id == contact_c.id }).to eq(1)
      end

      it 'passes through to ALL contacts for a non-User principal (e.g. platform/nil)' do
        expect(described_class.scope(account: account, user: nil)).to include(contact_a, contact_b, contact_c)
      end
    end
  end
end
