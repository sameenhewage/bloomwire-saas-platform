require 'rails_helper'

# Acceptance tests (Independent TDD Workflow — Acceptance Test Agent)
#
# Phase 3 — Business Onboarding / Tenant Setup, slice: "Chatwoot Readiness Mapping".
#
# Product truth:
#   Operators can see whether a tenant's underlying Chatwoot setup is ready.
#   The check is read-only over existing Chatwoot data and returns a safe status
#   label only (Ready / Needs inbox/channel / No Chatwoot account / No Bloomwire
#   profile). It never creates or configures inboxes/channels and never exposes
#   conversation/message/contact data.
RSpec.describe Bloomwire::ChatwootReadiness do
  describe '#status' do
    it 'is "No Chatwoot account" when there is no account' do
      expect(described_class.new(nil).status).to eq('No Chatwoot account')
    end

    it 'is "No Bloomwire profile" when the account has no business profile' do
      account = create(:account)

      expect(described_class.new(account).status).to eq('No Bloomwire profile')
    end

    it 'is "Needs inbox/channel" when the profile exists but the account has no inbox' do
      profile = create(:bloomwire_business_profile)

      expect(described_class.new(profile.account).status).to eq('Needs inbox/channel')
    end

    it 'is "Ready" when the profile exists and the account has at least one inbox' do
      profile = create(:bloomwire_business_profile)
      create(:inbox, account: profile.account)

      expect(described_class.new(profile.account).status).to eq('Ready')
    end

    it 'uses a provided profile without re-querying for it' do
      profile = create(:bloomwire_business_profile)
      create(:inbox, account: profile.account)

      expect(described_class.new(profile.account, profile: profile).status).to eq('Ready')
    end

    it 'always returns one of the enumerated safe labels' do
      profile = create(:bloomwire_business_profile)
      create(:inbox, account: profile.account)

      expect(described_class::STATUSES).to include(described_class.new(profile.account).status)
    end
  end
end
