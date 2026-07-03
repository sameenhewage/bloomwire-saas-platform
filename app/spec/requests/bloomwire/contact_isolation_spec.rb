require 'rails_helper'

# Phase 17E.2 — Bloomwire agent contact-visibility isolation for multi-category / multi-inbox accounts
# (ADR-0009 follow-up). With the gate ON, a business AGENT may only list/search/open contacts reachable
# through their assigned inboxes (via contact_inboxes); ADMINS see all; the gate OFF == stock Chatwoot
# (agents see all account contacts). Conversation isolation remains the primary enforcement (unchanged).
# No real Meta/WhatsApp. Fake values only.
RSpec.describe 'Bloomwire agent contact isolation', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent1) { create(:user, account: account, role: :agent) }
  let(:agent2) { create(:user, account: account, role: :agent) }
  let(:inbox1) { create(:inbox, account: account) }
  let(:inbox2) { create(:inbox, account: account) }

  # Category 1 contact (inbox1), Category 2 contact (inbox2), and a SHARED contact (both inboxes).
  let(:contact_a) { create(:contact, :with_email, name: 'Alpha One', account: account) }
  let(:contact_b) { create(:contact, :with_email, name: 'Beta Two', account: account) }
  let(:contact_c) { create(:contact, :with_email, name: 'Gamma Shared', account: account) }

  before do
    GlobalConfig.clear_cache
    create(:inbox_member, user: agent1, inbox: inbox1)
    create(:inbox_member, user: agent2, inbox: inbox2)
    create(:contact_inbox, contact: contact_a, inbox: inbox1)
    create(:contact_inbox, contact: contact_b, inbox: inbox2)
    create(:contact_inbox, contact: contact_c, inbox: inbox1)
    create(:contact_inbox, contact: contact_c, inbox: inbox2)
  end

  # The GlobalConfig cache lives in Redis (not rolled back by the DB transaction), so clear it after each
  # example to avoid leaking the enabled Bloomwire gate into unrelated specs.
  after { GlobalConfig.clear_cache }

  def enable_contact_isolation
    bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
    bw_set_config('BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY', true)
  end

  def payload_ids
    response.parsed_body['payload'].pluck('id')
  end

  describe 'GET /contacts (index)' do
    context 'with isolation ON' do
      before { enable_contact_isolation }

      it 'lets a category-1 agent list only inbox-1 contacts (A + shared C), never B' do
        get "/api/v1/accounts/#{account.id}/contacts", headers: agent1.create_new_auth_token, as: :json
        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(payload_ids).to include(contact_a.id, contact_c.id)
          expect(payload_ids).not_to include(contact_b.id)
        end
      end

      it 'lets a category-2 agent list only inbox-2 contacts (B + shared C), never A' do
        get "/api/v1/accounts/#{account.id}/contacts", headers: agent2.create_new_auth_token, as: :json
        aggregate_failures do
          expect(payload_ids).to include(contact_b.id, contact_c.id)
          expect(payload_ids).not_to include(contact_a.id)
        end
      end

      it 'lets an admin list all account contacts' do
        get "/api/v1/accounts/#{account.id}/contacts", headers: admin.create_new_auth_token, as: :json
        expect(payload_ids).to include(contact_a.id, contact_b.id, contact_c.id)
      end
    end

    context 'with isolation OFF (stock Chatwoot regression)' do
      it 'lets an agent list ALL account contacts (stock behavior preserved)' do
        get "/api/v1/accounts/#{account.id}/contacts", headers: agent1.create_new_auth_token, as: :json
        expect(payload_ids).to include(contact_a.id, contact_b.id, contact_c.id)
      end
    end
  end

  describe 'GET /contacts/search' do
    context 'with isolation ON' do
      before { enable_contact_isolation }

      it 'a category-1 agent cannot find a category-2 contact by name' do
        get "/api/v1/accounts/#{account.id}/contacts/search?q=Beta", headers: agent1.create_new_auth_token, as: :json
        expect(payload_ids).not_to include(contact_b.id)
      end

      it 'a category-1 agent can find their own category-1 contact by name' do
        get "/api/v1/accounts/#{account.id}/contacts/search?q=Alpha", headers: agent1.create_new_auth_token, as: :json
        expect(payload_ids).to include(contact_a.id)
      end

      it 'an admin can find any contact by name' do
        get "/api/v1/accounts/#{account.id}/contacts/search?q=Beta", headers: admin.create_new_auth_token, as: :json
        expect(payload_ids).to include(contact_b.id)
      end
    end
  end

  describe 'POST /contacts/filter' do
    let(:present_email_filter) do
      [{ attribute_key: 'email', filter_operator: 'contains', values: 'example.com',
         query_operator: nil, attribute_model: 'standard', custom_attribute_type: '' }]
    end

    context 'with isolation ON' do
      before { enable_contact_isolation }

      it 'a category-1 agent filter never returns a category-2 contact' do
        post "/api/v1/accounts/#{account.id}/contacts/filter",
             headers: agent1.create_new_auth_token, params: { payload: present_email_filter }, as: :json
        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(payload_ids).to include(contact_a.id)
          expect(payload_ids).not_to include(contact_b.id)
        end
      end

      it 'an admin filter returns all matching contacts' do
        post "/api/v1/accounts/#{account.id}/contacts/filter",
             headers: admin.create_new_auth_token, params: { payload: present_email_filter }, as: :json
        expect(payload_ids).to include(contact_a.id, contact_b.id, contact_c.id)
      end
    end
  end

  describe 'GET /contacts/:id (show)' do
    context 'with isolation ON' do
      before { enable_contact_isolation }

      it 'a category-1 agent can open their own contact A' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact_a.id}", headers: agent1.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'a category-1 agent cannot open a category-2 contact B (404, matching find-based style)' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact_b.id}", headers: agent1.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end

      it 'an admin can open any contact' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact_b.id}", headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'both category agents can open the SHARED contact C' do
        get "/api/v1/accounts/#{account.id}/contacts/#{contact_c.id}", headers: agent1.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
        get "/api/v1/accounts/#{account.id}/contacts/#{contact_c.id}", headers: agent2.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  # Phase 17E.2 (PR #114 review blocker): bulk contact label actions must NOT let a gated agent mutate contacts
  # outside their assigned-inbox visibility. The label mutation runs in an async job, so we wrap the request in
  # `perform_enqueued_jobs` to actually apply (or not) the label, then assert the contact's label_list.
  describe 'POST /bulk_actions (Contact label actions)' do
    include ActiveJob::TestHelper

    before { create(:label, account: account, title: 'vip') }

    def bulk_label(user:, ids:, add: nil, remove: nil)
      labels = {}
      labels[:add] = add if add
      labels[:remove] = remove if remove
      perform_enqueued_jobs do
        post "/api/v1/accounts/#{account.id}/bulk_actions",
             headers: user.create_new_auth_token,
             params: { type: 'Contact', ids: ids, labels: labels }, as: :json
      end
    end

    context 'with isolation ON' do
      before { enable_contact_isolation }

      it 'lets a category-1 agent bulk-add a label to their own contact A' do
        bulk_label(user: agent1, ids: [contact_a.id], add: ['vip'])
        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(contact_a.reload.label_list).to include('vip')
        end
      end

      it 'does NOT let a category-1 agent bulk-add a label to a category-2 contact B' do
        bulk_label(user: agent1, ids: [contact_b.id], add: ['vip'])
        expect(contact_b.reload.label_list).not_to include('vip')
      end

      it 'does NOT let a category-1 agent bulk-remove a label from a category-2 contact B' do
        contact_b.add_labels(['vip'])
        bulk_label(user: agent1, ids: [contact_b.id], remove: ['vip'])
        expect(contact_b.reload.label_list).to include('vip') # untouched — removal was blocked
      end

      it 'in a mixed bulk-add, labels only the in-scope contact A, never the out-of-scope B' do
        bulk_label(user: agent1, ids: [contact_a.id, contact_b.id], add: ['vip'])
        aggregate_failures do
          expect(contact_a.reload.label_list).to include('vip')
          expect(contact_b.reload.label_list).not_to include('vip')
        end
      end

      it 'lets either relevant agent bulk-label the SHARED contact C' do
        bulk_label(user: agent1, ids: [contact_c.id], add: ['vip'])
        expect(contact_c.reload.label_list).to include('vip')
      end

      it 'lets an admin bulk-label contacts from BOTH inboxes' do
        bulk_label(user: admin, ids: [contact_a.id, contact_b.id], add: ['vip'])
        aggregate_failures do
          expect(contact_a.reload.label_list).to include('vip')
          expect(contact_b.reload.label_list).to include('vip')
        end
      end
    end

    context 'with isolation OFF (stock Chatwoot regression)' do
      it 'lets an agent bulk-label any account contact (stock behavior preserved)' do
        bulk_label(user: agent1, ids: [contact_b.id], add: ['vip'])
        expect(contact_b.reload.label_list).to include('vip')
      end
    end
  end
end
