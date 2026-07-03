require 'rails_helper'

# Phase 17E.4 — Contact ID hardening. Closes the direct, ID-based contact paths that Phase 17E.2/17E.3 deferred,
# by routing them through Bloomwire::ContactVisibility.scope(account:, user:): contact MERGE, conversation-create
# contact lookup, and Shopify ORDERS contact lookup. With the gate ON a business AGENT can no longer reach an
# out-of-scope contact by id; ADMINS and the gate-OFF (stock Chatwoot) state are unchanged. CSAT stays admin-only
# (its product code is intentionally untouched). No real Meta/WhatsApp; NO external Shopify egress for an
# out-of-scope contact. All values are fake.
RSpec.describe 'Bloomwire Phase 17E.4 — contact ID path hardening', type: :request do
  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent1)  { create(:user, account: account, role: :agent) }
  let(:inbox1)  { create(:inbox, account: account) }
  let(:inbox2)  { create(:inbox, account: account) }
  let!(:in_scope)     { create(:contact, :with_email, name: 'In Scope', account: account) }
  let!(:out_of_scope) { create(:contact, :with_email, name: 'Out Of Scope', account: account) }

  before do
    GlobalConfig.clear_cache
    create(:inbox_member, user: agent1, inbox: inbox1)
    create(:contact_inbox, contact: in_scope, inbox: inbox1)
    create(:contact_inbox, contact: out_of_scope, inbox: inbox2)
  end

  # GlobalConfig cache lives in Redis (not rolled back with the DB transaction) — clear it so the enabled gate
  # never leaks into unrelated specs.
  after { GlobalConfig.clear_cache }

  def auth(user) = user.create_new_auth_token

  def enable_gate
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY', true)
  end

  def merge(user:, base:, mergee:)
    post "/api/v1/accounts/#{account.id}/actions/contact_merge",
         headers: auth(user), params: { base_contact_id: base.id, mergee_contact_id: mergee.id }, as: :json
  end

  def create_conversation(user:, contact:, inbox:, source_id:)
    post "/api/v1/accounts/#{account.id}/conversations",
         headers: auth(user), params: { inbox_id: inbox.id, contact_id: contact.id, source_id: source_id }, as: :json
  end

  def get_shopify_orders(user:, contact:)
    get "/api/v1/accounts/#{account.id}/integrations/shopify/orders",
        headers: auth(user), params: { contact_id: contact.id }, as: :json
  end

  # A stand-in Shopify REST response (only #body is used by the controller); class-free so this spec is standalone.
  def shopify_response
    Struct.new(:body).new({ 'customers' => [{ 'id' => '1' }], 'orders' => [] })
  end

  # ============================================================================
  # Gate ON — an agent may only reach contacts within their assigned-inbox visibility
  # ============================================================================
  context 'with the gate ON (BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY)' do
    before { enable_gate }

    it 'CONTROL: an agent still cannot open an out-of-scope contact (17E.2 enumeration path stays closed)' do
      get "/api/v1/accounts/#{account.id}/contacts/#{out_of_scope.id}", headers: auth(agent1), as: :json
      expect(response).to have_http_status(:not_found)
    end

    describe 'contact merge' do
      let!(:other_in_scope) do
        contact = create(:contact, :with_email, account: account)
        create(:contact_inbox, contact: contact, inbox: inbox1)
        contact
      end

      it 'lets an agent merge two in-scope contacts' do
        merge(user: agent1, base: in_scope, mergee: other_in_scope)
        expect(response).to have_http_status(:success)
      end

      it 'blocks an agent from merging an out-of-scope MERGEE (404; contact untouched)' do
        merge(user: agent1, base: in_scope, mergee: out_of_scope)
        aggregate_failures do
          expect(response).to have_http_status(:not_found)
          expect(Contact.exists?(out_of_scope.id)).to be(true)
        end
      end

      it 'blocks an agent from using an out-of-scope BASE (404; contact untouched)' do
        merge(user: agent1, base: out_of_scope, mergee: in_scope)
        aggregate_failures do
          expect(response).to have_http_status(:not_found)
          expect(Contact.exists?(in_scope.id)).to be(true)
        end
      end

      it 'lets an admin merge across account contacts (both inboxes)' do
        merge(user: admin, base: in_scope, mergee: out_of_scope)
        expect(response).to have_http_status(:success)
      end
    end

    describe 'conversation create' do
      it 'lets an agent create a conversation with an in-scope contact in their own inbox' do
        create_conversation(user: agent1, contact: in_scope, inbox: inbox1, source_id: 'src-in-1')
        expect(response).to have_http_status(:success)
      end

      it 'blocks an agent from attaching an out-of-scope contact to their own inbox (404)' do
        create_conversation(user: agent1, contact: out_of_scope, inbox: inbox1, source_id: 'src-oos-1')
        expect(response).to have_http_status(:not_found)
      end

      it 'lets an admin attach any account contact' do
        create_conversation(user: admin, contact: out_of_scope, inbox: inbox1, source_id: 'src-admin-1')
        expect(response).to have_http_status(:success)
      end
    end

    describe 'shopify orders' do
      let(:shopify_client) { instance_double(ShopifyAPI::Clients::Rest::Admin) }

      before do
        create(:integrations_hook, :shopify, account: account)
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController)
          .to receive(:shopify_client).and_return(shopify_client)
        # rubocop:enable RSpec/AnyInstance
        allow(shopify_client).to receive(:get).and_return(shopify_response)
      end

      it 'lets an agent fetch orders for an in-scope contact (reaches the Shopify client)' do
        get_shopify_orders(user: agent1, contact: in_scope)
        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(shopify_client).to have_received(:get).at_least(:once)
        end
      end

      it 'blocks an agent for an out-of-scope contact and makes NO external Shopify request' do
        get_shopify_orders(user: agent1, contact: out_of_scope)
        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_entity)
          expect(shopify_client).not_to have_received(:get)
          expect(a_request(:any, /myshopify\.com/)).not_to have_been_made
        end
      end

      it 'lets an admin fetch orders for any account contact' do
        get_shopify_orders(user: admin, contact: out_of_scope)
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'CSAT report (unchanged — admin-only/protected; product code NOT touched in 17E.4)' do
      it 'still blocks a plain agent (admin-only policy)' do
        get "/api/v1/accounts/#{account.id}/csat_survey_responses", headers: auth(agent1), as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ============================================================================
  # Gate OFF — stock Chatwoot behavior is preserved (agent may act on any account contact)
  # ============================================================================
  context 'with the gate OFF (stock Chatwoot)' do
    it 'contact merge: an agent can still merge any account contacts' do
      merge(user: agent1, base: in_scope, mergee: out_of_scope)
      expect(response).to have_http_status(:success)
    end

    it 'conversation create: an agent can still attach any account contact to their inbox' do
      create_conversation(user: agent1, contact: out_of_scope, inbox: inbox1, source_id: 'src-off-1')
      expect(response).to have_http_status(:success)
    end

    describe 'shopify orders' do
      let(:shopify_client) { instance_double(ShopifyAPI::Clients::Rest::Admin) }

      before do
        create(:integrations_hook, :shopify, account: account)
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Api::V1::Accounts::Integrations::ShopifyController)
          .to receive(:shopify_client).and_return(shopify_client)
        # rubocop:enable RSpec/AnyInstance
        allow(shopify_client).to receive(:get).and_return(shopify_response)
      end

      it 'an agent can still fetch orders for any account contact (stock)' do
        get_shopify_orders(user: agent1, contact: out_of_scope)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
