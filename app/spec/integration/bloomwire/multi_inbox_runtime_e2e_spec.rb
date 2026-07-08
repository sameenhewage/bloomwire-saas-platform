require 'rails_helper'

# Phase 17E.3 — Owner-operated runtime E2E for the Bloomwire multi-WhatsApp-inbox + customer/agent visibility
# workflow, end to end, with MOCKED META ONLY (no real Meta/WhatsApp, no production, no deploy). It ties the
# already-shipped slices together through the REAL runtime stack:
#
#   Flow 1  admin/owner setup ...... mocked Meta embedded signup (Standard + Coexistence) -> 2 WhatsApp inboxes,
#                                    each mapped to its own Channel::Whatsapp + Bloomwire::WhatsappSetup.
#   Flow 2  multi-inbox routing .... signed inbound webhook per phone_number_id -> Contact/Conversation/Message
#                                    under the correct inbox; unknown + crossed pnid fail closed; the router is
#                                    connection_mode-agnostic (Inbox 2 is a Coexistence inbox).
#   Flow 3  conversation isolation . a category agent lists/opens ONLY their own inbox's conversations (API);
#                                    admin sees both. Backend-enforced (ConversationFinder / ConversationPolicy).
#   Flow 4  contact isolation ...... with BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY ON, an agent lists/opens
#                                    only in-scope contacts; sub-resources 404; bulk label add/remove is scoped;
#                                    admin unaffected; feature OFF == stock.
#   Flow 5  UI-sanity (at the API) . the backend never returns cross-inbox inboxes/contacts to a category agent
#                                    (the UI relies on this — no frontend-only assumptions).
#
# Meta is stubbed at the seam (Whatsapp::TokenExchangeService / PhoneInfoService / FacebookApiClient +
# Bloomwire::GlobalWhatsappConfig); WebMock.disable_net_connect! guarantees no real egress. All values are fake.
RSpec.describe 'Bloomwire multi-inbox runtime E2E (mocked Meta)', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin)   { create(:user, account: account, role: :administrator) }
  let(:agent1)  { create(:user, account: account, role: :agent) }
  let(:agent2)  { create(:user, account: account, role: :agent) }

  # Two distinct fake WhatsApp numbers (Category 1 + Category 2). display = phone without the leading '+'.
  # Defined as methods (not `let`) to keep each group's memoized-helper count within RuboCop limits.
  def pnid1 = 'PNID-E2E-1'
  def pnid2 = 'PNID-E2E-2'
  def phone1 = '+15551230001'
  def phone2 = '+15551230002'
  def display1 = '15551230001'
  def display2 = '15551230002'

  before do
    ActiveJob::Base.queue_adapter = :test
    stub_platform_ready
    bw_enable_router
    bw_set_app_secret
  end

  after do
    GlobalConfig.clear_cache
    bw_clear_message_dedup
  end

  # --- mocked Meta seam (no real Meta) -----------------------------------------------------------------
  def stub_platform_ready
    allow(Bloomwire::GlobalWhatsappConfig).to receive(:new)
      .and_return(instance_double(Bloomwire::GlobalWhatsappConfig, result: { platform_ready: true }))
  end

  def stub_meta_for(phone_number_id:, phone_number:, business_name: 'Acme')
    allow(Whatsapp::TokenExchangeService).to receive(:new)
      .and_return(instance_double(Whatsapp::TokenExchangeService, perform: 'FAKE-CUSTOMER-TOKEN'))
    allow(Whatsapp::PhoneInfoService).to receive(:new)
      .and_return(instance_double(Whatsapp::PhoneInfoService,
                                  perform: { phone_number_id: phone_number_id, phone_number: phone_number,
                                             verified: true, business_name: business_name }))
    allow(Whatsapp::FacebookApiClient).to receive(:new)
      .and_return(instance_double(Whatsapp::FacebookApiClient, subscribe_app_to_waba: true, subscribed_to_waba?: true, register_phone_number: { 'success' => true },
                                                               override_waba_callback: nil, subscribe_waba_webhook: nil,
                                                               phone_number_status: 'CONNECTED',
                                                               token_actor_id: 'SYS-ACTOR-1', waba_user_tasks: %w[MANAGE]))
  end

  # Provision a managed WhatsApp inbox via the REAL embedded-signup service with Meta stubbed. Returns the setup.
  def provision_inbox(phone_number_id:, phone_number:, business_name:, coexistence: false)
    stub_meta_for(phone_number_id: phone_number_id, phone_number: phone_number, business_name: business_name)
    service = coexistence ? Bloomwire::WhatsappCoexistenceEmbeddedSignupService : Bloomwire::WhatsappEmbeddedSignupService
    result = service.new(account: account,
                         params: { code: "CODE-#{phone_number_id}", business_id: 'BIZ-1',
                                   waba_id: 'WABA-1', phone_number_id: phone_number_id }).perform
    raise "provisioning failed for #{phone_number_id}: #{result.error}" unless result.success?

    Bloomwire::WhatsappSetup.find_by!(phone_number_id: phone_number_id)
  end

  # Drive a signed inbound webhook through the real router + events job (run inline). Returns nothing.
  def post_inbound(pnid:, display:, from:, wamid:, body: 'hello there')
    payload = bw_inbound_text_payload(phone_number_id: pnid, display_phone_number: display,
                                      from: from, wamid: wamid, body: body, name: 'Customer')
    perform_enqueued_jobs(only: Webhooks::WhatsappEventsJob) { bw_post_router(payload, signature: :valid) }
  end

  def auth(user) = user.create_new_auth_token

  # ===================================================================================================
  # Flow 1 — Admin / owner setup via mocked Meta embedded signup (Standard + Coexistence)
  # ===================================================================================================
  describe 'Flow 1: admin/owner WhatsApp setup (mocked Meta embedded signup)' do
    before { enable_managed_mode }

    def enable_managed_mode
      bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
      bw_set_config('BLOOMWIRE_PRIVACY_HARDENING', true)
      bw_set_config('BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP', true)
      bw_set_config('BLOOMWIRE_MANAGED_WHATSAPP_ONBOARDING', true)
    end

    def signup(path, phone_number_id:, phone_number:)
      stub_meta_for(phone_number_id: phone_number_id, phone_number: phone_number)
      post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/#{path}",
           headers: auth(admin),
           params: { code: "CODE-#{phone_number_id}", business_id: 'BIZ-1', waba_id: 'WABA-1',
                     phone_number_id: phone_number_id },
           as: :json
    end

    it 'lets the admin create WhatsApp Inbox 1 (Standard) and Inbox 2 (Coexistence) under one account' do
      signup('embedded_signup', phone_number_id: pnid1, phone_number: phone1)
      expect(response).to have_http_status(:created)
      signup('coexistence_embedded_signup', phone_number_id: pnid2, phone_number: phone2)
      expect(response).to have_http_status(:created)

      setup1 = Bloomwire::WhatsappSetup.find_by(phone_number_id: pnid1)
      setup2 = Bloomwire::WhatsappSetup.find_by(phone_number_id: pnid2)
      aggregate_failures do
        # both inboxes exist under the SAME account, each mapped to its own channel + setup
        expect(account.inboxes.count).to eq(2)
        expect(Channel::Whatsapp.where(account: account).count).to eq(2)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(2)
        expect(setup1.channel_whatsapp_id).not_to eq(setup2.channel_whatsapp_id)
        expect(setup1.inbox_id).not_to eq(setup2.inbox_id)
        expect(setup1.setup_status).to eq('ready_for_webhook')
        expect(setup2.setup_status).to eq('ready_for_webhook')
        # Standard path vs Coexistence path (both available); connection_mode is always explicit (never nil)
        expect(setup1.channel_whatsapp.provider_config['connection_mode']).to eq('standard')
        expect(setup2.channel_whatsapp.provider_config['connection_mode']).to eq('coexistence')
      end
    end

    it 'exposes both inboxes to the admin and never leaks the customer token/api_key (safe DTO)' do
      signup('embedded_signup', phone_number_id: pnid1, phone_number: phone1)
      aggregate_failures do
        expect(response).to have_http_status(:created)
        expect(response.body).not_to include('FAKE-CUSTOMER-TOKEN')
        expect(response.body).not_to include('api_key')
        expect(response.parsed_body.dig('channel', 'source')).to eq('bloomwire_managed')
      end
    end

    it 'forbids a non-admin agent from running managed WhatsApp setup (permission polish)' do
      stub_meta_for(phone_number_id: pnid1, phone_number: phone1)
      post "/api/v1/accounts/#{account.id}/bloomwire/whatsapp/embedded_signup",
           headers: auth(agent1),
           params: { code: 'CODE-1', business_id: 'BIZ-1', waba_id: 'WABA-1', phone_number_id: pnid1 }, as: :json
      aggregate_failures do
        expect(response).not_to have_http_status(:created)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(0)
      end
    end
  end

  # ===================================================================================================
  # Flows 2-5 — routing + isolation on two provisioned inboxes (Inbox 1 Standard, Inbox 2 Coexistence)
  # ===================================================================================================
  describe 'Flows 2-5: routing, conversation isolation, contact isolation, UI sanity' do
    let!(:setup1) { provision_inbox(phone_number_id: pnid1, phone_number: phone1, business_name: 'Category One') }
    let!(:setup2) do
      provision_inbox(phone_number_id: pnid2, phone_number: phone2, business_name: 'Category Two', coexistence: true)
    end
    let(:inbox1) { setup1.inbox }
    let(:inbox2) { setup2.inbox }

    before do
      create(:inbox_member, user: agent1, inbox: inbox1)
      create(:inbox_member, user: agent2, inbox: inbox2)
    end

    def customer_a = '15559990001'
    def customer_b = '15559990002'

    # ---------------------------------------------------------------------------------------------
    # Flow 2 — multi-inbox routing (connection_mode agnostic; fail-closed on unknown/crossed)
    # ---------------------------------------------------------------------------------------------
    describe 'Flow 2: inbound webhook routing by phone_number_id' do
      it 'routes an inbound message for phone_number_id_1 to Inbox 1 (Standard)' do
        expect { post_inbound(pnid: pnid1, display: display1, from: customer_a, wamid: 'wamid.A1') }
          .to change { inbox1.messages.count }.by(1)
        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(inbox1.conversations.count).to eq(1)
          expect(inbox2.messages.count).to eq(0)
          expect(inbox1.contact_inboxes.find_by(source_id: customer_a)).to be_present
        end
      end

      it 'routes an inbound message for phone_number_id_2 to Inbox 2 (Coexistence) — router is connection_mode agnostic' do
        expect { post_inbound(pnid: pnid2, display: display2, from: customer_b, wamid: 'wamid.B1') }
          .to change { inbox2.messages.count }.by(1)
        aggregate_failures do
          expect(inbox1.messages.count).to eq(0)
          expect(inbox2.conversations.count).to eq(1)
        end
      end

      it 'fails closed for an unknown phone_number_id (safe 200, creates nothing)' do
        expect { post_inbound(pnid: 'PNID-UNKNOWN-9999', display: '15559999999', from: customer_a, wamid: 'wamid.U1') }
          .not_to(change { Message.count + Conversation.count + Contact.count })
        expect(response).to have_http_status(:ok)
      end

      it 'fails closed for a crossed phone_number_id / display_phone_number (creates nothing)' do
        # Inbox-1 phone_number_id paired with Inbox-2 display number => not handoff-safe => dropped.
        expect { post_inbound(pnid: pnid1, display: display2, from: customer_a, wamid: 'wamid.X1') }
          .not_to(change { Message.count + Conversation.count + Contact.count })
      end

      it 'makes no real Meta network egress for an inbound text message' do
        post_inbound(pnid: pnid1, display: display1, from: customer_a, wamid: 'wamid.A2')
        expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
      end
    end

    # ---------------------------------------------------------------------------------------------
    # Flow 3 — category agent conversation isolation (API level; backend-enforced)
    # ---------------------------------------------------------------------------------------------
    describe 'Flow 3: category agent conversation isolation' do
      let!(:convo1) { create(:conversation, account: account, inbox: inbox1) }
      let!(:convo2) { create(:conversation, account: account, inbox: inbox2) }

      # The conversations index payload keys each conversation by its account-scoped `display_id` (the `id`
      # field in the JSON), not the DB primary key — so compare against `conversation.display_id`.
      def conversation_display_ids(user)
        get "/api/v1/accounts/#{account.id}/conversations", params: { assignee_type: 'all' }, headers: auth(user), as: :json
        response.parsed_body['data']['payload'].pluck('id')
      end

      def show_status(user, conversation)
        get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: auth(user), as: :json
        response.status
      end

      it 'agent 1 (Inbox 1) lists only Inbox 1 conversations, never Inbox 2' do
        ids = conversation_display_ids(agent1)
        aggregate_failures do
          expect(ids).to include(convo1.display_id)
          expect(ids).not_to include(convo2.display_id)
        end
      end

      it 'agent 2 (Inbox 2) lists only Inbox 2 conversations, never Inbox 1' do
        ids = conversation_display_ids(agent2)
        aggregate_failures do
          expect(ids).to include(convo2.display_id)
          expect(ids).not_to include(convo1.display_id)
        end
      end

      it 'agent 1 can open its own Inbox 1 conversation but not an Inbox 2 conversation (401)' do
        aggregate_failures do
          expect(show_status(agent1, convo1)).to eq(200)
          expect(show_status(agent1, convo2)).to eq(401)
        end
      end

      it 'agent 2 can open its own Inbox 2 conversation but not an Inbox 1 conversation (401)' do
        aggregate_failures do
          expect(show_status(agent2, convo2)).to eq(200)
          expect(show_status(agent2, convo1)).to eq(401)
        end
      end

      it 'admin can list and open conversations from both inboxes' do
        aggregate_failures do
          expect(conversation_display_ids(admin)).to include(convo1.display_id, convo2.display_id)
          expect(show_status(admin, convo1)).to eq(200)
          expect(show_status(admin, convo2)).to eq(200)
        end
      end
    end

    # ---------------------------------------------------------------------------------------------
    # Flow 4 — contact isolation with the gate ON (list/search/show + sub-resource + bulk label)
    # ---------------------------------------------------------------------------------------------
    describe 'Flow 4: contact isolation (BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY ON)' do
      let!(:contact_a) { create(:contact, :with_email, name: 'Alpha One', account: account) }
      let!(:contact_b) { create(:contact, :with_email, name: 'Beta Two', account: account) }
      let!(:contact_c) { create(:contact, :with_email, name: 'Gamma Shared', account: account) }

      before do
        create(:contact_inbox, contact: contact_a, inbox: inbox1)
        create(:contact_inbox, contact: contact_b, inbox: inbox2)
        create(:contact_inbox, contact: contact_c, inbox: inbox1)
        create(:contact_inbox, contact: contact_c, inbox: inbox2)
      end

      def enable_contact_isolation
        bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
        bw_set_config('BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY', true)
      end

      def contact_index_ids(user)
        get "/api/v1/accounts/#{account.id}/contacts", headers: auth(user), as: :json
        response.parsed_body['payload'].pluck('id')
      end

      def bulk_label(user:, ids:, add: nil, remove: nil)
        labels = {}
        labels[:add] = add if add
        labels[:remove] = remove if remove
        perform_enqueued_jobs do
          post "/api/v1/accounts/#{account.id}/bulk_actions",
               headers: auth(user), params: { type: 'Contact', ids: ids, labels: labels }, as: :json
        end
      end

      context 'when the gate is ON' do
        before do
          enable_contact_isolation
          create(:label, account: account, title: 'vip')
        end

        it 'agent 1 lists/searches only in-scope contacts (A + shared C), never B' do
          aggregate_failures do
            expect(contact_index_ids(agent1)).to include(contact_a.id, contact_c.id)
            expect(contact_index_ids(agent1)).not_to include(contact_b.id)
          end
        end

        it 'agent 2 mirror: lists only B + shared C, never A' do
          aggregate_failures do
            expect(contact_index_ids(agent2)).to include(contact_b.id, contact_c.id)
            expect(contact_index_ids(agent2)).not_to include(contact_a.id)
          end
        end

        it 'admin lists all contacts; the shared contact C is visible to both agents' do
          aggregate_failures do
            expect(contact_index_ids(admin)).to include(contact_a.id, contact_b.id, contact_c.id)
            expect(contact_index_ids(agent1)).to include(contact_c.id)
            expect(contact_index_ids(agent2)).to include(contact_c.id)
          end
        end

        it 'agent 1 gets 404 opening an out-of-scope contact and its sub-resource' do
          get "/api/v1/accounts/#{account.id}/contacts/#{contact_b.id}", headers: auth(agent1), as: :json
          expect(response).to have_http_status(:not_found)
          get "/api/v1/accounts/#{account.id}/contacts/#{contact_b.id}/conversations", headers: auth(agent1), as: :json
          expect(response).to have_http_status(:not_found)
        end

        it 'bulk label add: agent 1 mutates its own contact A but NOT out-of-scope B; mixed touches only A' do
          bulk_label(user: agent1, ids: [contact_a.id, contact_b.id], add: ['vip'])
          aggregate_failures do
            expect(contact_a.reload.label_list).to include('vip')
            expect(contact_b.reload.label_list).not_to include('vip')
          end
        end

        it 'bulk label remove: agent 1 cannot remove a label from out-of-scope B' do
          contact_b.add_labels(['vip'])
          bulk_label(user: agent1, ids: [contact_b.id], remove: ['vip'])
          expect(contact_b.reload.label_list).to include('vip')
        end

        it 'bulk label: admin can mutate contacts from both inboxes' do
          bulk_label(user: admin, ids: [contact_a.id, contact_b.id], add: ['vip'])
          aggregate_failures do
            expect(contact_a.reload.label_list).to include('vip')
            expect(contact_b.reload.label_list).to include('vip')
          end
        end
      end

      context 'when the gate is OFF (stock Chatwoot)' do
        it 'agent 1 lists ALL account contacts (stock behavior preserved)' do
          expect(contact_index_ids(agent1)).to include(contact_a.id, contact_b.id, contact_c.id)
        end
      end
    end

    # ---------------------------------------------------------------------------------------------
    # Flow 5 — UI sanity at the API: no cross-inbox leakage to a category agent (backend-enforced)
    # ---------------------------------------------------------------------------------------------
    describe 'Flow 5: UI sanity (backend does not expose cross-inbox data to a category agent)' do
      before do
        bw_set_config('BLOOMWIRE_MODE_ENABLED', true)
        bw_set_config('BLOOMWIRE_RESTRICT_AGENT_CONTACT_VISIBILITY', true)
      end

      def inbox_ids(user)
        get "/api/v1/accounts/#{account.id}/inboxes", headers: auth(user), as: :json
        response.parsed_body['payload'].pluck('id')
      end

      it 'a category agent only sees their own inbox in the inbox list; the admin sees both' do
        aggregate_failures do
          expect(inbox_ids(agent1)).to contain_exactly(inbox1.id)
          expect(inbox_ids(agent2)).to contain_exactly(inbox2.id)
          expect(inbox_ids(admin)).to include(inbox1.id, inbox2.id)
        end
      end
    end
  end
end
