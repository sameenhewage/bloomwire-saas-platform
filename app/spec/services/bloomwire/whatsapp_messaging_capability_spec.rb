require 'rails_helper'

# Phase 5: the outbound-messaging capability gate. Unit-tested against a stubbed Meta client (no real Meta).
# Proves TRI-STATE verification (verified_capable / verified_missing / unverifiable), that a lookup/verification
# ERROR never triggers an assignment POST, that a grant is attempted ONLY when the caller is authorized AND the
# token is a USER token (a SYSTEM_USER / unknown token never self-elevates), that only the proven MANAGE task
# marks an inbox ready, and that no secret is ever logged. Fake values only.
RSpec.describe Bloomwire::WhatsappMessagingCapability do
  let(:client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:token) { 'FAKE-CUSTOMER-TOKEN' }
  let(:waba_id) { 'WABA-X' }
  let(:actor_id) { 'ACTOR-Y' }

  before do
    allow(client).to receive(:token_actor_id).with(token).and_return(actor_id)
    allow(client).to receive(:token_actor_type).with(token).and_return('USER')
    allow(client).to receive(:waba_user_tasks)
    allow(client).to receive(:assign_waba_user_tasks)
  end

  def run(allow_grant: false)
    described_class.new(client: client, token: token, waba_id: waba_id, allow_grant: allow_grant).ensure
  end

  # A — actor already holds the proven send task: :ready, no assignment call.
  describe 'A: actor already has the proven send task (MANAGE)' do
    it 'is :ready and issues NO assignment call' do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id).and_return(%w[MANAGE VIEW_TEMPLATES])
      result = run
      aggregate_failures do
        expect(result.status).to eq(:ready)
        expect(result.verification).to eq(:verified_capable)
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end

    # BLOCKER 5: MANAGE is the only task PROVEN to clear Meta (#10); the narrower MESSAGING must NOT mark ready.
    it 'does NOT treat the unproven MESSAGING task as send-capable (stays action_required, no grant)' do
      allow(client).to receive(:waba_user_tasks).and_return(%w[MESSAGING])
      result = run
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end
  end

  # The authorized owner-USER path (allow_grant: true + USER token): grant the minimum proven task, re-read, ready.
  describe 'authorized USER credential establishes the task, then re-verifies' do
    it 'grants MANAGE on the EXACT waba+actor, re-reads, and becomes :ready (granted)' do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id)
                                                .and_return(%w[VIEW_TEMPLATES VIEW_PHONE_ASSETS], %w[MANAGE])
      result = run(allow_grant: true)
      aggregate_failures do
        expect(result.status).to eq(:ready)
        expect(result.granted).to be(true)
        expect(client).to have_received(:assign_waba_user_tasks).with(waba_id, actor_id, %w[MANAGE]).once
        expect(client).to have_received(:waba_user_tasks).with(waba_id, actor_id).twice
      end
    end

    it 'is :action_required (never a false ready) when the grant returns but re-read still lacks the task' do
      allow(client).to receive(:waba_user_tasks).and_return(%w[VIEW_TEMPLATES], %w[VIEW_TEMPLATES])
      expect(run(allow_grant: true).status).to eq(:action_required)
    end

    it 'is :action_required/unverifiable when the grant call itself raises' do
      allow(client).to receive(:waba_user_tasks).and_return(%w[VIEW_TEMPLATES])
      allow(client).to receive(:assign_waba_user_tasks).and_raise(StandardError, 'RAW (#200) cannot self-assign')
      result = run(allow_grant: true)
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(result.verification).to eq(:unverifiable)
      end
    end
  end

  # BLOCKER 3 — a verification ERROR (lookup raised) must NOT collapse into "missing" and must NEVER POST a grant.
  describe 'unverifiable (lookup error) never mutates' do
    it 'is unverifiable and issues NO assignment POST when reading tasks raises (even if authorized)' do
      allow(client).to receive(:waba_user_tasks).and_raise(StandardError, 'RAW meta 500')
      result = run(allow_grant: true)
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(result.verification).to eq(:unverifiable)
        expect(result.reason).to eq('outbound_messaging_permission_unverifiable')
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end

    it 'is unverifiable and reads NO tasks when the actor cannot be identified' do
      allow(client).to receive(:token_actor_id).and_return(nil)
      result = run
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(result.verification).to eq(:unverifiable)
        expect(client).not_to have_received(:waba_user_tasks)
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end

    # BLOCKER 4: an actor ABSENT from a successful assigned_users read (client returns nil) is NOT proof of
    # missing (Business-scope visibility / pagination) -> unverifiable, and never a grant even if authorized.
    it 'is unverifiable (never verified_missing / never a grant) when the actor is ABSENT from the read (nil)' do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id).and_return(nil)
      result = run(allow_grant: true)
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(result.verification).to eq(:unverifiable)
        expect(result.reason).to eq('outbound_messaging_permission_unverifiable')
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end
  end

  # BLOCKER 4 — never blindly self-elevate. Onboarding/recheck pass allow_grant:false; a SYSTEM_USER / unknown
  # token is never used to self-grant even if a grant were mistakenly authorized.
  describe 'grant policy (never self-elevate a SYSTEM_USER / unknown token)' do
    before { allow(client).to receive(:waba_user_tasks).and_return(%w[VIEW_TEMPLATES VIEW_PHONE_ASSETS]) }

    it 'issues NO assignment POST for the verify-only path (allow_grant: false) and is verified_missing' do
      result = run(allow_grant: false)
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(result.verification).to eq(:verified_missing)
        expect(result.reason).to eq('outbound_messaging_permission_required')
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end

    it 'issues NO assignment POST when the token is a SYSTEM_USER, even if the caller allows a grant' do
      allow(client).to receive(:token_actor_type).and_return('SYSTEM_USER')
      run(allow_grant: true)
      expect(client).not_to have_received(:assign_waba_user_tasks)
    end

    it 'issues NO assignment POST when the token identity is unknown/unintrospectable' do
      allow(client).to receive(:token_actor_type).and_return(nil)
      run(allow_grant: true)
      expect(client).not_to have_received(:assign_waba_user_tasks)
    end
  end

  # The gate must act on the EXACT selected WABA + the EXACT stored-token actor — no substitution.
  describe 'exact-actor / exact-WABA (no substitution)' do
    it 'introspects the EXACT stored token and checks the EXACT selected WABA + actor' do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id).and_return(%w[MANAGE])
      run
      aggregate_failures do
        expect(client).to have_received(:token_actor_id).with(token)
        expect(client).to have_received(:waba_user_tasks).with(waba_id, actor_id)
      end
    end
  end

  describe 'no secret leakage on failure' do
    it 'logs only a sanitized capability-error event (class name, never the token/body) when a Meta call raises' do
      logs = []
      allow(Rails.logger).to receive(:warn) { |message| logs << message }
      allow(client).to receive(:waba_user_tasks).and_raise(StandardError, "boom #{token}")
      run
      event = logs.find { |message| message.include?('bloomwire.whatsapp.messaging_capability_error') }
      aggregate_failures do
        expect(event).to be_present
        expect(event).not_to include(token)
      end
    end
  end
end
