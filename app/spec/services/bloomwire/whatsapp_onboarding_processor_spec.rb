require 'rails_helper'

# Slice 2 (ADR-0010 v3) processor — GREEN. No real Meta calls (every Graph collaborator + the persistence seam are
# stubbed/injected). Covers the original cases PLUS the four correctness gaps: (1) two-stage token resumability,
# (2) capability-before-subscription, (3) lease safety across long Meta calls, (4) persisted-but-not-finalized
# crash resume for BOTH outcomes. Requires AR encryption keys (secret writes are fail-closed without them).
RSpec.describe Bloomwire::WhatsappOnboardingProcessor do
  before { skip 'AR encryption keys not configured in this env' unless Chatwoot.encryption_configured? }

  let(:account) { create(:account) }
  let(:owner) { 'worker-a' }
  let(:client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:phone_info) { { phone_number_id: 'PNID-1', phone_number: '+15551230001', business_name: 'Biz' } }
  let(:persister) { instance_double(Bloomwire::WhatsappOnboardingPersister) }
  let(:attempt) do
    Bloomwire::WhatsappOnboardingAttempt.create!(
      account: account, status: 'queued', waba_id: 'WABA-1', phone_number_id: 'PNID-1'
    )
  end

  def raw_col(id, col)
    ActiveRecord::Base.connection.select_value("SELECT #{col} FROM bloomwire_whatsapp_onboarding_attempts WHERE id = #{id}")
  end

  def run(target = attempt, as: owner, generation: nil)
    described_class.new(attempt: target, owner: as, generation: generation, persister: persister).process
  end

  # Stubs the whole Meta surface as spies (all real methods -> verify_partial_doubles safe). `persist:` controls the
  # injected persister: :transient (default) raises a transient error so step assertions stay isolated from the DB
  # persist path; a setup object makes it return that setup (completion path). Nothing here makes a real network call.
  def stub_meta(connected: true, subscribed: false, capability_ready: true, persist: :transient) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    allow(Whatsapp::TokenExchangeService).to receive(:new)
      .and_return(instance_double(Whatsapp::TokenExchangeService, perform: 'short-token'))
    allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(client)
    allow(client).to receive(:exchange_for_long_lived_token).and_return('long-token')
    allow(Whatsapp::PhoneInfoService).to receive(:new)
      .and_return(instance_double(Whatsapp::PhoneInfoService, perform: phone_info))
    allow(client).to receive(:phone_number_status).and_return(connected ? 'CONNECTED' : 'DISCONNECTED')
    pin_result = double(pin: '123456', error: nil) # rubocop:disable RSpec/VerifiedDoubles
    allow(Bloomwire::WhatsappRegistrationPin).to receive(:new)
      .and_return(instance_double(Bloomwire::WhatsappRegistrationPin, resolve: pin_result))
    allow(client).to receive(:register_phone_number)
    # not-subscribed => absent on the first GET, present after the subscribe POST (models a successful subscription)
    allow(client).to receive(:subscribed_to_waba?).and_return(*(subscribed ? [true] : [false, true]))
    allow(client).to receive(:subscribe_app_to_waba)
    resolution = double(ok?: true, waba_id: 'WABA-1', phone_number_id: 'PNID-1', error: nil) # rubocop:disable RSpec/VerifiedDoubles
    allow(Bloomwire::WhatsappConnectedNumberResolver).to receive(:new)
      .and_return(instance_double(Bloomwire::WhatsappConnectedNumberResolver, resolve: resolution))
    capability = Bloomwire::WhatsappMessagingCapability::Result.new(
      status: capability_ready ? :ready : :action_required,
      reason: capability_ready ? nil : 'outbound_messaging_permission_required'
    )
    allow(Bloomwire::WhatsappMessagingCapability).to receive(:new)
      .and_return(instance_double(Bloomwire::WhatsappMessagingCapability, ensure: capability))
    stub_persister(persist)
  end

  def stub_persister(mode)
    if mode == :transient
      allow(persister).to receive(:call)
        .and_raise(Whatsapp::GraphApiTimeoutError.new('Graph API POST timed out (Net::ReadTimeout)'))
    else
      allow(persister).to receive(:call).and_return(mode)
    end
  end

  # ---- Gap 1: two-stage OAuth token exchange resumability ------------------------------------------------
  describe 'two-stage token exchange (gap 1)' do
    it 'exchanges the code once, stores the short token + clears the code, then upgrades to long-lived' do
      stub_meta
      attempt.store_code!('OAUTH-CODE')
      run
      aggregate_failures do
        expect(Whatsapp::TokenExchangeService).to have_received(:new).once
        expect(attempt.reload.oauth_code).to be_nil
        expect(attempt.access_token).to eq('long-token')
        expect(attempt.token_stage).to eq('long_lived')
      end
    end

    it 'retains the short token (code cleared, stage short_lived) when the long-lived exchange fails' do
      stub_meta
      allow(client).to receive(:exchange_for_long_lived_token)
        .and_raise(Whatsapp::GraphApiTimeoutError.new('Graph API GET timed out (Net::ReadTimeout)'))
      attempt.store_code!('OAUTH-CODE')
      run
      aggregate_failures do
        expect(attempt.reload.access_token).to eq('short-token') # credential not lost between the two calls
        expect(attempt.oauth_code).to be_nil                     # consumed code cleared
        expect(attempt.token_stage).to eq('short_lived')
      end
    end

    it 'on retry with a stored short token, upgrades to long-lived WITHOUT re-exchanging the consumed code' do
      stub_meta
      attempt.update!(access_token: 'short-token', token_stage: 'short_lived')
      run
      aggregate_failures do
        expect(Whatsapp::TokenExchangeService).not_to have_received(:new)
        expect(client).to have_received(:exchange_for_long_lived_token)
        expect(attempt.reload.access_token).to eq('long-token')
        expect(attempt.token_stage).to eq('long_lived')
      end
    end
  end

  # ---- Gap 2: capability BEFORE subscription ------------------------------------------------------------
  describe 'capability-before-subscription (gap 2)' do
    it 'does NOT subscribe when capability is action_required (persists action_required, WABA unsubscribed)' do
      channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
      ar_setup = instance_double(Bloomwire::WhatsappSetup, setup_status: 'action_required', channel_whatsapp: channel,
                                                           channel_whatsapp_id: channel.id, inbox_id: channel.inbox.id,
                                                           waba_id: 'WABA-1', phone_number_id: 'PNID-1', display_phone_number: '15551230001')
      stub_meta(connected: true, subscribed: false, capability_ready: false, persist: ar_setup)
      attempt.store_code!('OAUTH-CODE')
      run
      aggregate_failures do
        expect(client).not_to have_received(:subscribe_app_to_waba)
        expect(attempt.reload.status).to eq('action_required')
      end
    end

    it 'when ready, reconciles (GET subscribed_apps) and subscribes only when absent' do
      stub_meta(connected: true, subscribed: false, capability_ready: true)
      attempt.store_code!('OAUTH-CODE')
      run
      aggregate_failures do
        expect(client).to have_received(:subscribed_to_waba?).at_least(:once)
        expect(client).to have_received(:subscribe_app_to_waba)
      end
    end

    it 'checks capability against the FINAL resolved WABA, not blindly the selected one' do
      stub_meta(connected: true)
      attempt.store_code!('OAUTH-CODE')
      run
      expect(Bloomwire::WhatsappMessagingCapability).to have_received(:new).with(hash_including(waba_id: 'WABA-1'))
    end
  end

  # ---- Gap 3: lease safety across long Meta calls ------------------------------------------------------
  describe 'lease safety (gap 3)' do
    it 'release_lease! is guarded: a stale worker cannot clear a newer owner\'s lease' do
      attempt.claim_lease!(owner: 'new-owner', expected_generation: 0)
      attempt.release_lease!(owner: 'stale-worker', expected_generation: 0)
      expect(attempt.reload.lease_held_by?('new-owner')).to be(true)
    end

    it 'does not write local state when the lease is lost during a Meta call' do
      stub_meta(connected: false)
      attempt.update!(access_token: 'long-token', token_stage: 'long_lived')
      allow(client).to receive(:register_phone_number) do
        # a newer worker takes over the lease while this Meta call is in flight
        Bloomwire::WhatsappOnboardingAttempt.find(attempt.id).update!(processing_owner: 'worker-b', lease_expires_at: 5.minutes.from_now)
      end
      run
      expect(attempt.reload.access_token).to eq('long-token') # stale worker did not clear/overwrite
    end

    it 'a retry GETs actual Meta state before any register/subscribe POST (reconcile-before-mutate)' do
      stub_meta(connected: true, subscribed: true)
      attempt.update!(access_token: 'long-token', token_stage: 'long_lived')
      run
      aggregate_failures do
        expect(client).to have_received(:phone_number_status).at_least(:once)
        expect(client).not_to have_received(:register_phone_number)
        expect(client).to have_received(:subscribed_to_waba?).at_least(:once)
        expect(client).not_to have_received(:subscribe_app_to_waba)
      end
    end

    it 'holds NO DB transaction/row lock while a Meta HTTP call is in progress' do
      stub_meta(connected: true)
      baseline = ActiveRecord::Base.connection.open_transactions
      observed = []
      allow(client).to receive(:phone_number_status) do
        observed << ActiveRecord::Base.connection.open_transactions
        'CONNECTED'
      end
      attempt.store_code!('OAUTH-CODE')
      run
      aggregate_failures do
        expect(observed).not_to be_empty
        expect(observed).to all(eq(baseline)) # no extra nested transaction/lock during the Meta call
      end
    end
  end

  # ---- Gap 4: persisted-but-not-finalized crash resume (BOTH outcomes) ---------------------------------
  describe 'crash boundary: persisted but not finalized (gap 4)' do
    def crashed_attempt_for(setup)
      Bloomwire::WhatsappOnboardingAttempt.create!(
        account: account, status: 'processing', waba_id: 'WABA-1', phone_number_id: 'PNID-1',
        channel_whatsapp_id: setup.channel_whatsapp_id, inbox_id: setup.inbox_id
      ) # access_token already cleared before the crash
    end

    it 'ready_for_webhook setup resumes to completed with no exchange/register/subscribe and no duplicates' do
      setup = create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                                    aligned_phone_number_id: 'PNID-1', aligned_display_phone_number: '15551230001')
      crashed = crashed_attempt_for(setup)
      stub_meta
      run(crashed)
      aggregate_failures do
        expect(Whatsapp::TokenExchangeService).not_to have_received(:new)
        expect(client).not_to have_received(:register_phone_number)
        expect(client).not_to have_received(:subscribe_app_to_waba)
        expect(Channel::Whatsapp.where(account: account).count).to eq(1)
        expect(Inbox.where(account: account).count).to eq(1)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
        expect(crashed.reload.status).to eq('completed')
      end
    end

    it 'action_required setup resumes to action_required with no exchange/register/subscribe and no duplicates' do
      setup = create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                                    aligned_phone_number_id: 'PNID-1', aligned_display_phone_number: '15551230001')
      setup.update!(setup_status: 'action_required', status_reason: 'outbound_messaging_permission_required')
      crashed = crashed_attempt_for(setup)
      stub_meta
      run(crashed)
      aggregate_failures do
        expect(Whatsapp::TokenExchangeService).not_to have_received(:new)
        expect(client).not_to have_received(:register_phone_number)
        expect(client).not_to have_received(:subscribe_app_to_waba)
        expect(Bloomwire::WhatsappSetup.where(account: account).count).to eq(1)
        expect(crashed.reload.status).to eq('action_required')
      end
    end
  end

  # ---- Existing kept cases ----------------------------------------------------------------------------
  describe 'existing reconcile + guard + error cases' do
    it 'skips /register when the phone is already CONNECTED' do
      stub_meta(connected: true)
      attempt.store_code!('OAUTH-CODE')
      run
      expect(client).not_to have_received(:register_phone_number)
    end

    it 'registers (after a status GET) when the phone is not connected' do
      stub_meta(connected: false)
      attempt.store_code!('OAUTH-CODE')
      run
      aggregate_failures do
        expect(client).to have_received(:phone_number_status).at_least(:once)
        expect(client).to have_received(:register_phone_number)
      end
    end

    it 'skips subscribe when the app is already subscribed to the WABA' do
      stub_meta(connected: true, subscribed: true)
      attempt.store_code!('OAUTH-CODE')
      run
      expect(client).not_to have_received(:subscribe_app_to_waba)
    end

    it 'does not write the credential when the worker generation is stale' do
      stub_meta
      attempt.store_code!('OAUTH-CODE')
      attempt.bump_generation! # current generation advances to 1; the worker below carries the stale generation 0
      run(as: 'stale-worker', generation: 0)
      expect(raw_col(attempt.id, 'access_token')).to be_nil
    end

    it 'records a sanitized error and RETAINS the token on a Meta timeout after the token is obtained' do
      stub_meta(connected: false)
      attempt.update!(access_token: 'long-token', token_stage: 'long_lived')
      allow(client).to receive(:register_phone_number)
        .and_raise(Whatsapp::GraphApiTimeoutError.new('Graph API POST timed out (Net::ReadTimeout)'))
      run
      aggregate_failures do
        expect(attempt.reload.safe_error_code).to be_present
        expect(attempt.safe_error_code).not_to include('long-token')
        expect(attempt.access_token).to eq('long-token') # retained for retry (transient, not terminal)
      end
    end
  end
end
