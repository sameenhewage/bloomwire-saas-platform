require 'rails_helper'

# Phase 17E.3 — HARDENING FOLLOW-UP INVENTORY (characterization only; NOT a fix).
#
# Phase 17E.2 closed the contact ENUMERATION paths (index / search / show / filter / bulk) behind
# BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY, and EXPLICITLY DEFERRED four direct, ID-based contact paths to a
# future hardening phase: contact merge, CSAT report, Shopify integration, and the conversation-create contact
# lookup. The 17E.3 brief asks us to VERIFY + DOCUMENT whether those deferred paths are reachable in the mocked
# runtime with the gate ON — NOT to fix them (fixing requires separate, explicit approval).
#
# These examples therefore CHARACTERIZE the CURRENT behavior so the gap is visible and regression-locked. They are
# NOT an endorsement of the gap. When a future hardening phase scopes one of these paths, its characterization
# here will change (e.g. :success -> :not_found) and must be updated. No product code is changed in 17E.3; no real
# Meta/WhatsApp; no production.
RSpec.describe 'Bloomwire hardening follow-up inventory (deferred paths, characterization)', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent1)  { create(:user, account: account, role: :agent) }
  let(:inbox1)  { create(:inbox, account: account) }
  let(:inbox2)  { create(:inbox, account: account) }
  let!(:contact_in_scope)     { create(:contact, :with_email, name: 'In Scope', account: account) }
  let!(:contact_out_of_scope) { create(:contact, :with_email, name: 'Out Of Scope', account: account) }

  before do
    GlobalConfig.clear_cache
    create(:inbox_member, user: agent1, inbox: inbox1)
    create(:contact_inbox, contact: contact_in_scope, inbox: inbox1)
    create(:contact_inbox, contact: contact_out_of_scope, inbox: inbox2)
    # Gate ON — identical to Flow 4 in the main E2E spec.
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY', true)
  end

  after { GlobalConfig.clear_cache }

  def auth(user) = user.create_new_auth_token

  # Proves the 17E.2 gate is genuinely ON in this spec, so the "deferred gap" characterizations below are
  # meaningful (they bypass an ACTIVE gate that already blocks the enumeration path).
  it 'CONTROL: the 17E.2 gate is ON — an agent cannot open the out-of-scope contact via the scoped show path' do
    get "/api/v1/accounts/#{account.id}/contacts/#{contact_out_of_scope.id}", headers: auth(agent1), as: :json
    expect(response).to have_http_status(:not_found)
  end

  describe 'DEFERRED — contact merge (agent-reachable, NOT scoped by Bloomwire::ContactVisibility)' do
    it 'CHARACTERIZATION: an agent can reach + merge an out-of-scope contact (gap open; hardening deferred)' do
      post "/api/v1/accounts/#{account.id}/actions/contact_merge",
           headers: auth(agent1),
           params: { base_contact_id: contact_in_scope.id, mergee_contact_id: contact_out_of_scope.id }, as: :json
      # CURRENT behavior: reachable (found via Current.account.contacts, unscoped) and merged away.
      # When hardened, this should become :not_found — update this characterization at that time.
      aggregate_failures do
        expect(response).to have_http_status(:success)
        expect(Contact.exists?(contact_out_of_scope.id)).to be(false)
      end
    end
  end

  describe 'DEFERRED — conversation-create contact lookup (agent-reachable, NOT scoped by ContactVisibility)' do
    it 'CHARACTERIZATION: an agent can attach an out-of-scope contact to a conversation in their own inbox' do
      post "/api/v1/accounts/#{account.id}/conversations",
           headers: auth(agent1),
           params: { inbox_id: inbox1.id, contact_id: contact_out_of_scope.id, source_id: 'oos-conv-src-1' },
           as: :json
      # CURRENT behavior: the contact lookup is unscoped, so an out-of-scope contact is attachable.
      # When hardened, this should become :not_found / :unauthorized.
      expect(response).to have_http_status(:success)
    end
  end

  describe 'PROTECTED — CSAT report (admin-only policy; NOT agent-reachable)' do
    it 'blocks a plain agent from the CSAT report (admin-only — not a contact-leak vector for agents)' do
      get "/api/v1/accounts/#{account.id}/csat_survey_responses", headers: auth(agent1), as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DEFERRED (outside the mocked runtime) — Shopify orders contact lookup' do
    it 'is statically agent-reachable + unscoped, but needs a Shopify hook + external stub to exercise' do
      skip 'Documented deferred gap: Integrations::ShopifyController#orders looks up the contact via ' \
           'Current.account.contacts.find_by (unscoped) and is reachable by a plain agent, but exercising it ' \
           'requires an Integrations::Hook + a stubbed external Shopify API — outside the mocked-Meta WhatsApp ' \
           'runtime. Reachability confirmed by static analysis; fix deferred to the hardening phase.'
    end
  end
end
