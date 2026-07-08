require 'rails_helper'

# Phase 5: the outbound-messaging capability gate. Unit-tested against a stubbed Meta client (no real Meta).
# Proves it verifies the EXACT stored-token actor's WABA asset task, establishes it ONLY via the onboarding
# token when authorized (then re-verifies), and otherwise reports :action_required — never a false ready, and
# never a secret in logs. Fake values only.
RSpec.describe Bloomwire::WhatsappMessagingCapability do
  subject(:capability) { described_class.new(client: client, token: token, waba_id: waba_id).ensure }

  let(:client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:token) { 'FAKE-CUSTOMER-TOKEN' }
  let(:waba_id) { 'WABA-X' }
  let(:actor_id) { 'ACTOR-Y' }

  before do
    allow(client).to receive(:token_actor_id).with(token).and_return(actor_id)
    allow(client).to receive(:waba_user_tasks)
    allow(client).to receive(:assign_waba_user_tasks)
  end

  # A — the actor already holds a send-capable task: continue, issue NO assignment call.
  describe 'A: actor already has a send-capable task' do
    it 'is :ready and issues NO assignment call when the actor already has MANAGE' do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id).and_return(%w[MANAGE VIEW_TEMPLATES])
      aggregate_failures do
        expect(capability.status).to eq(:ready)
        expect(client).not_to have_received(:assign_waba_user_tasks)
      end
    end

    it 'is :ready when the actor holds the narrower MESSAGING task' do
      allow(client).to receive(:waba_user_tasks).and_return(%w[MESSAGING])
      expect(capability.status).to eq(:ready)
    end
  end

  # B — task absent, but the onboarding token is authorized to grant it: grant the minimum proven task,
  # re-read, and only then become ready.
  describe 'B: absent task established via the onboarding token, then re-verified' do
    before do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id)
                                                .and_return(%w[VIEW_TEMPLATES VIEW_PHONE_ASSETS], %w[MANAGE])
    end

    it 'grants MANAGE on the EXACT waba+actor, re-verifies, and becomes :ready (granted)' do
      result = capability
      aggregate_failures do
        expect(result.status).to eq(:ready)
        expect(result.granted).to be(true)
        expect(client).to have_received(:assign_waba_user_tasks).with(waba_id, actor_id, %w[MANAGE]).once
        expect(client).to have_received(:waba_user_tasks).with(waba_id, actor_id).twice
      end
    end
  end

  # C — task absent and cannot be established: :action_required (the caller persists an explicit Action-Required
  # inbox, never a silently receive-only "ready" one).
  describe 'C: task absent and cannot be established' do
    it 'is :action_required with a sanitized reason when the actor is view-only and the grant is rejected' do
      allow(client).to receive(:waba_user_tasks).and_return(%w[VIEW_TEMPLATES VIEW_PHONE_ASSETS])
      allow(client).to receive(:assign_waba_user_tasks).and_raise(StandardError, 'RAW (#200) cannot self-assign')
      result = capability
      aggregate_failures do
        expect(result.status).to eq(:action_required)
        expect(result.reason).to eq('outbound_messaging_permission_required')
      end
    end

    it 'is :action_required when a grant returns but re-verification still shows no send task (no false ready)' do
      allow(client).to receive(:waba_user_tasks).and_return(%w[VIEW_TEMPLATES], %w[VIEW_TEMPLATES])
      expect(capability.status).to eq(:action_required)
    end

    it 'is :action_required (never a false ready) when the token actor cannot be identified' do
      allow(client).to receive(:token_actor_id).and_return(nil)
      aggregate_failures do
        expect(capability.status).to eq(:action_required)
        expect(client).not_to have_received(:waba_user_tasks)
      end
    end

    it 'is :action_required when reading the WABA tasks raises (never a false ready)' do
      allow(client).to receive(:waba_user_tasks).and_raise(StandardError, 'RAW meta error')
      expect(capability.status).to eq(:action_required)
    end
  end

  # The gate must act on the EXACT selected WABA + the EXACT stored-token actor — no substitution.
  describe 'exact-actor / exact-WABA (no substitution)' do
    it 'introspects the EXACT stored token and checks the EXACT selected WABA + actor' do
      allow(client).to receive(:waba_user_tasks).with(waba_id, actor_id).and_return(%w[MANAGE])
      capability
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
      capability
      event = logs.find { |message| message.include?('bloomwire.whatsapp.messaging_capability_error') }
      aggregate_failures do
        expect(event).to be_present
        expect(event).not_to include(token)
      end
    end
  end
end
