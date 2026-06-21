require 'rails_helper'

# Edge & security coverage (Independent TDD Workflow — Edge & Security Test Agent)
#
# Phase 3 — slice: "Chatwoot Readiness Mapping".
#
# Guarantees (see AGENTS.md rules 4, 6, 8):
# - Tenant isolation: readiness is computed strictly per account.
# - Read-only: computing readiness never creates/configures Chatwoot records.
# - Safe DTO: only enumerated, non-identifying status labels are returned.
RSpec.describe Bloomwire::ChatwootReadiness do
  describe 'tenant isolation' do
    it "does not let one tenant's inbox make another tenant look ready" do
      ready = create(:bloomwire_business_profile)
      create(:inbox, account: ready.account)
      other = create(:bloomwire_business_profile)

      expect(described_class.new(ready.account).status).to eq('Ready')
      expect(described_class.new(other.account).status).to eq('Needs inbox/channel')
    end

    it 'only reads inboxes belonging to the given account' do
      account_a = create(:bloomwire_business_profile).account
      account_b = create(:bloomwire_business_profile).account
      create(:inbox, account: account_a)

      expect(described_class.new(account_b).status).to eq('Needs inbox/channel')
    end
  end

  describe 'read-only (no Chatwoot mutation)' do
    it 'computes readiness without creating Chatwoot records' do
      profile = create(:bloomwire_business_profile)
      create(:inbox, account: profile.account)

      expect { described_class.new(profile.account).status }.not_to change(Inbox, :count)
      expect { described_class.new(profile.account).status }.not_to change(Conversation, :count)
      expect { described_class.new(profile.account).status }.not_to change(Contact, :count)
    end
  end

  describe 'safe status label (safe DTO)' do
    it 'returns only safe enumerated labels with no ids/counts' do
      profile = create(:bloomwire_business_profile)
      create(:inbox, account: profile.account)

      status = described_class.new(profile.account).status

      expect(described_class::STATUSES).to include(status)
      expect(status).not_to match(/\d/)
    end
  end
end
