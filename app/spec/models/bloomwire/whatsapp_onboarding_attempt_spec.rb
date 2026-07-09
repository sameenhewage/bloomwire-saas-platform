require 'rails_helper'

# Resumable async onboarding attempt (ADR-0010 v3). Proves: statuses incl. cancelled + action_required-as-ACTIVE
# (Guardrail 1); temporary encrypted secret lifecycle; phone privacy — masked only (Guardrail 5); short lease +
# stale-generation rejection (Guardrail 2); no secret in inspect/DTO. Fake values only; no Meta calls.
RSpec.describe Bloomwire::WhatsappOnboardingAttempt do
  subject(:attempt) { described_class.create!(account: account) }

  let(:account) { create(:account) }

  describe 'identity' do
    it 'assigns a public_uuid and starts in waiting_meta' do
      aggregate_failures do
        expect(attempt.public_uuid).to be_present
        expect(attempt.status).to eq('waiting_meta')
        expect(attempt.submission_generation).to eq(0)
      end
    end

    it 'enforces a unique public_uuid' do
      dup = described_class.new(account: account, public_uuid: attempt.public_uuid)
      expect(dup).not_to be_valid
    end
  end

  describe 'status sets' do
    it 'treats action_required as ACTIVE (Guardrail 1), not terminal' do
      attempt.update!(status: 'action_required')
      aggregate_failures do
        expect(attempt.active?).to be(true)
        expect(attempt.terminal?).to be(false)
        expect(described_class::ACTIVE_STATUSES).to include('action_required')
      end
    end

    it 'marks completed/expired/failed/cancelled terminal' do
      %w[completed expired failed cancelled].each do |s|
        attempt.update!(status: s)
        expect(attempt.terminal?).to be(true), "expected #{s} terminal"
      end
    end
  end

  describe 'phone privacy (Guardrail 5)' do
    it 'stores ONLY a masked number on bind_target!, never the full number' do
      attempt.bind_target!(waba_id: 'WABA-1', phone_number_id: 'PNID-1', phone_number: '+15551230001')
      raw = ActiveRecord::Base.connection.select_one(
        "SELECT * FROM bloomwire_whatsapp_onboarding_attempts WHERE id = #{attempt.id}"
      )
      aggregate_failures do
        expect(attempt.masked_phone).to eq('****0001')
        expect(raw.values.map(&:to_s).join(' ')).not_to include('15551230001')
        expect(raw).not_to have_key('phone_number') # no full-number column exists at all
      end
    end
  end

  describe 'temporary secret lifecycle' do
    it 'store_code! records the code + code_received_at' do
      attempt.store_code!('CODE-1')
      aggregate_failures do
        expect(attempt.oauth_code).to eq('CODE-1')
        expect(attempt.code_received_at).to be_present
      end
    end

    it 'store_access_token! stores the token, CLEARS the code, sets code_exchanged_at' do
      attempt.store_code!('CODE-1')
      attempt.store_access_token!('TOKEN-1')
      aggregate_failures do
        expect(attempt.access_token).to eq('TOKEN-1')
        expect(attempt.oauth_code).to be_nil
        expect(attempt.code_exchanged_at).to be_present
      end
    end

    it 'mark_credential_persisted! clears the token + sets credential_persisted_at + secrets_cleared_at' do
      attempt.store_access_token!('TOKEN-1')
      attempt.mark_credential_persisted!
      aggregate_failures do
        expect(attempt.access_token).to be_nil
        expect(attempt.credential_persisted_at).to be_present
        expect(attempt.secrets_cleared_at).to be_present
        expect(attempt.secrets_present?).to be(false)
      end
    end

    it 'clear_secrets! drops both secrets on terminal cleanup' do
      attempt.store_code!('CODE-1')
      attempt.update!(access_token: 'TOKEN-1')
      attempt.clear_secrets!
      aggregate_failures do
        expect(attempt.reload.oauth_code).to be_nil
        expect(attempt.access_token).to be_nil
        expect(attempt.secrets_cleared_at).to be_present
      end
    end
  end

  describe 'secret at-rest + inspect redaction' do
    it 'encrypts oauth_code and access_token at rest (ciphertext in the DB columns)' do
      skip 'AR encryption keys not configured in this env' unless Chatwoot.encryption_configured?
      attempt.store_code!('CODE-SECRET')
      attempt.update!(access_token: 'TOKEN-SECRET')
      raw = ActiveRecord::Base.connection.select_one(
        "SELECT oauth_code, access_token FROM bloomwire_whatsapp_onboarding_attempts WHERE id = #{attempt.id}"
      )
      aggregate_failures do
        expect(raw['oauth_code'].to_s).not_to include('CODE-SECRET')
        expect(raw['access_token'].to_s).not_to include('TOKEN-SECRET')
      end
    end

    it 'never exposes the plaintext code/token via #inspect' do
      attempt.store_code!('CODE-SECRET')
      attempt.update!(access_token: 'TOKEN-SECRET')
      dump = attempt.inspect
      aggregate_failures do
        expect(dump).not_to include('CODE-SECRET')
        expect(dump).not_to include('TOKEN-SECRET')
        expect(dump).to include('[FILTERED]')
      end
    end
  end

  describe 'short ownership lease (Guardrail 2)' do
    it 'grants ownership to the first claimer' do
      aggregate_failures do
        expect(attempt.claim_lease!(owner: 'worker-a', ttl_seconds: 60)).to be(true)
        expect(attempt.reload.lease_held_by?('worker-a')).to be(true)
      end
    end

    it 'refuses a second owner while the lease is unexpired' do
      attempt.claim_lease!(owner: 'worker-a', ttl_seconds: 60)
      expect(attempt.claim_lease!(owner: 'worker-b', ttl_seconds: 60)).to be(false)
    end

    it 'allows reclaim once the lease has expired' do
      attempt.claim_lease!(owner: 'worker-a', ttl_seconds: 60)
      attempt.update!(lease_expires_at: 1.minute.ago)
      expect(attempt.reload.claim_lease!(owner: 'worker-b', ttl_seconds: 60)).to be(true)
    end

    it 'rejects a claim for a stale submission_generation' do
      attempt.bump_generation! # now generation 1
      expect(attempt.claim_lease!(owner: 'worker-a', expected_generation: 0)).to be(false)
    end

    it 'is not claimable in a terminal state' do
      attempt.update!(status: 'completed')
      expect(attempt.claim_lease!(owner: 'worker-a')).to be(false)
    end
  end

  describe '#to_status_dto' do
    it 'exposes safe fields only — never a secret' do
      attempt.bind_target!(waba_id: 'WABA-1', phone_number_id: 'PNID-1', phone_number: '+15551230001')
      attempt.store_code!('CODE-SECRET')
      attempt.update!(access_token: 'TOKEN-SECRET', status: 'processing', step: 'registering')
      dto = attempt.to_status_dto
      json = dto.to_json
      aggregate_failures do
        expect(dto[:attempt_id]).to eq(attempt.public_uuid)
        expect(dto[:status]).to eq('processing')
        expect(dto[:phone]).to eq('****0001')
        expect(json).not_to include('CODE-SECRET')
        expect(json).not_to include('TOKEN-SECRET')
        expect(json).not_to include('15551230001')
      end
    end
  end
end
