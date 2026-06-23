require 'rails_helper'

# Strict, Bloomwire-ONLY phone registration/readiness check (ADR 0005, PR #23 P2 round 2).
# It runs AFTER webhook setup on the Bloomwire path because the shared
# Whatsapp::WebhookSetupService#register_phone_number swallows Meta registration errors, so a
# webhook subscribe returning does NOT prove the number is usable. This validator re-checks via
# the failure-surfacing Whatsapp::HealthService and returns a safe coded symbol (nil = ready),
# never raw provider data.
RSpec.describe Bloomwire::ChannelSetup::WhatsappReadinessValidator do
  subject(:validator) { described_class.new(channel) }

  let(:channel) { instance_double(Channel::Whatsapp) }

  def stub_health(status)
    health = instance_double(Whatsapp::HealthService)
    allow(Whatsapp::HealthService).to receive(:new).with(channel).and_return(health)
    allow(health).to receive(:fetch_health_status).and_return(status)
    health
  end

  describe '#error_code' do
    it 'returns nil when Meta reports the number verified and provisioned' do
      stub_health(code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: { 'level' => 'STANDARD' })

      expect(validator.error_code).to be_nil
    end

    it 'queries Meta health for the channel' do
      health = stub_health(code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: { 'level' => 'STANDARD' })

      validator.error_code

      expect(Whatsapp::HealthService).to have_received(:new).with(channel)
      expect(health).to have_received(:fetch_health_status)
    end

    it 'returns :phone_not_ready when the number is not yet provisioned (platform_type NOT_APPLICABLE)' do
      # This is exactly what a silently-failed Whatsapp::FacebookApiClient#register_phone_number leaves behind.
      stub_health(code_verification_status: 'VERIFIED', platform_type: 'NOT_APPLICABLE', throughput: { 'level' => 'STANDARD' })

      expect(validator.error_code).to eq(:phone_not_ready)
    end

    it 'returns :phone_not_ready when the number is not code-verified' do
      stub_health(code_verification_status: 'NOT_VERIFIED', platform_type: 'CLOUD_API', throughput: { 'level' => 'STANDARD' })

      expect(validator.error_code).to eq(:phone_not_ready)
    end

    it 'returns :phone_not_ready when platform_type is missing from Meta' do
      stub_health(code_verification_status: 'VERIFIED', platform_type: nil, throughput: { 'level' => 'STANDARD' })

      expect(validator.error_code).to eq(:phone_not_ready)
    end

    it 'returns :phone_not_ready when throughput.level is NOT_APPLICABLE (no messaging capacity assigned)' do
      # phone_number_in_pending_state? treats this exact value as still-pending registration, so a
      # number whose swallowed /register left it without throughput must NOT be reported active.
      stub_health(code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: { 'level' => 'NOT_APPLICABLE' })

      expect(validator.error_code).to eq(:phone_not_ready)
    end

    it 'returns :phone_not_ready when throughput is missing entirely' do
      stub_health(code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API')

      expect(validator.error_code).to eq(:phone_not_ready)
    end

    it 'returns :phone_not_ready when throughput is present but carries no level' do
      stub_health(code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: {})

      expect(validator.error_code).to eq(:phone_not_ready)
    end

    it 'is ready with a SYMBOL-key throughput hash (health[:throughput] / throughput[:level])' do
      stub_health(code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API', throughput: { level: 'STANDARD' })

      expect(validator.error_code).to be_nil
    end

    it 'is ready with a STRING-key throughput hash (health["throughput"] / throughput["level"])' do
      # Symbol top-level health keys (as Whatsapp::HealthService returns) but a STRING throughput
      # key + inner level, exercising health["throughput"] and throughput["level"].
      stub_health({ code_verification_status: 'VERIFIED', platform_type: 'CLOUD_API' }.merge('throughput' => { 'level' => 'STANDARD' }))

      expect(validator.error_code).to be_nil
    end

    it 'returns :phone_registration_unverifiable (never the raw error) when Meta health cannot be fetched' do
      health = instance_double(Whatsapp::HealthService)
      allow(Whatsapp::HealthService).to receive(:new).with(channel).and_return(health)
      allow(health).to receive(:fetch_health_status).and_raise(RuntimeError, 'WhatsApp API request failed: 190 - {"error":{"code":190}}')

      expect(validator.error_code).to eq(:phone_registration_unverifiable)
    end

    it 'logs the provider error server-side but never surfaces it to the caller' do
      health = instance_double(Whatsapp::HealthService)
      allow(Whatsapp::HealthService).to receive(:new).with(channel).and_return(health)
      allow(health).to receive(:fetch_health_status).and_raise(RuntimeError, 'raw provider detail 190')
      allow(Rails.logger).to receive(:error)

      code = validator.error_code

      expect(code).to eq(:phone_registration_unverifiable)
      expect(code.to_s).not_to include('190')
      expect(Rails.logger).to have_received(:error).with(/readiness verification failed/)
    end
  end
end
