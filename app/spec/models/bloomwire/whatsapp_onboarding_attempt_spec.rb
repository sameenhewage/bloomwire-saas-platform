require 'rails_helper'

# Resumable async onboarding attempt (ADR-0010 v3), Slice 1 + correction pass. Proves: statuses incl. cancelled +
# action_required-as-ACTIVE (Guardrail 1); DB status CHECK constraint; encrypted secret lifecycle that FAILS CLOSED
# when AR encryption is unavailable; stale-worker credential protection (Guardrail 2); phone privacy — masked only
# (Guardrail 5); no secret in inspect/DTO. Fake values only; no Meta calls.
RSpec.describe Bloomwire::WhatsappOnboardingAttempt do
  subject(:attempt) { described_class.create!(account: account) }

  let(:account) { create(:account) }

  def raw_row(id, *cols)
    ActiveRecord::Base.connection.select_one(
      "SELECT #{cols.join(', ')} FROM bloomwire_whatsapp_onboarding_attempts WHERE id = #{id}"
    )
  end

  # -- Encryption-agnostic behaviour (runs in both key modes) ---------------------------------------------------

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

  describe 'status DB CHECK constraint (Fix 5)' do
    it 'rejects an unknown status at the DB level even when model validation is bypassed' do
      id = attempt.id
      expect do
        ActiveRecord::Base.connection.execute(
          "UPDATE bloomwire_whatsapp_onboarding_attempts SET status = 'bogus_status' WHERE id = #{id}"
        )
      end.to raise_error(ActiveRecord::StatementInvalid, /bw_wa_onboarding_status_check|check constraint/i)
    end
  end

  describe 'phone privacy (Guardrail 5)' do
    it 'bind_target! stores ONLY a masked number, never the full number' do
      attempt.bind_target!(waba_id: 'WABA-1', phone_number_id: 'PNID-1', phone_number: '+15551230001')
      raw = raw_row(attempt.id, '*')
      aggregate_failures do
        expect(attempt.masked_phone).to eq('****0001')
        expect(raw.values.map(&:to_s).join(' ')).not_to include('15551230001')
        expect(raw).not_to have_key('phone_number')
      end
    end

    it 'rejects a direct full-number assignment to phone_number_masked (Fix 3)' do
      attempt.phone_number_masked = '+15551230001'
      aggregate_failures do
        expect(attempt).not_to be_valid
        expect(attempt.errors[:phone_number_masked]).to be_present
      end
      expect { attempt.update!(phone_number_masked: '15551230001') }.to raise_error(ActiveRecord::RecordInvalid)
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
      attempt.bump_generation!
      expect(attempt.claim_lease!(owner: 'worker-a', expected_generation: 0)).to be(false)
    end

    it 'is not claimable in a terminal state' do
      attempt.update!(status: 'completed')
      expect(attempt.claim_lease!(owner: 'worker-a')).to be(false)
    end
  end

  # -- Fail-closed encryption (Fix 1): only meaningful WITHOUT AR encryption keys ------------------------------

  context 'when AR encryption is NOT configured (fail-closed / Fix 1)' do
    before { skip 'AR encryption IS configured in this env' if Chatwoot.encryption_configured? }

    it 'store_code! raises SecretStorageUnavailableError and leaves oauth_code NULL' do
      expect { attempt.store_code!('CODE-SECRET') }.to raise_error(described_class::SecretStorageUnavailableError)
      expect(raw_row(attempt.id, 'oauth_code')['oauth_code']).to be_nil
    end

    it 'store_access_token! raises SecretStorageUnavailableError and leaves access_token NULL' do
      expect do
        attempt.store_access_token!('TOKEN-SECRET', owner: 'w1', expected_generation: attempt.submission_generation)
      end.to raise_error(described_class::SecretStorageUnavailableError)
      expect(raw_row(attempt.id, 'access_token')['access_token']).to be_nil
    end

    it 'blocks even a raw update! that would persist a plaintext secret (before_save backstop)' do
      expect { attempt.update!(oauth_code: 'RAW-SECRET') }.to raise_error(described_class::SecretStorageUnavailableError)
      expect(raw_row(attempt.id, 'oauth_code')['oauth_code']).to be_nil
    end

    it 'does not leak the attempted secret in the exception message or #inspect' do
      error = nil
      begin
        attempt.store_code!('SUPER-SECRET-CODE')
      rescue described_class::SecretStorageUnavailableError => e
        error = e
      end
      aggregate_failures do
        expect(error).to be_present
        expect(error.message).not_to include('SUPER-SECRET-CODE')
        expect(attempt.inspect).not_to include('SUPER-SECRET-CODE')
      end
    end
  end

  # -- Encrypted lifecycle + stale-worker protection: require AR encryption keys -------------------------------

  context 'when AR encryption is configured' do
    before { skip 'AR encryption keys not configured in this env' unless Chatwoot.encryption_configured? }

    describe 'temporary secret lifecycle' do
      it 'store_code! records the code + code_received_at' do
        attempt.store_code!('CODE-1')
        aggregate_failures do
          expect(attempt.oauth_code).to eq('CODE-1')
          expect(attempt.code_received_at).to be_present
        end
      end

      it 'store_access_token! (current owner) stores token, CLEARS code, sets code_exchanged_at' do
        attempt.store_code!('CODE-1')
        gen = attempt.submission_generation
        attempt.claim_lease!(owner: 'w1', expected_generation: gen)
        attempt.store_access_token!('TOKEN-1', owner: 'w1', expected_generation: gen)
        aggregate_failures do
          expect(attempt.reload.access_token).to eq('TOKEN-1')
          expect(attempt.oauth_code).to be_nil
          expect(attempt.code_exchanged_at).to be_present
        end
      end

      it 'mark_credential_persisted! (current owner) clears token + sets timestamps' do
        gen = attempt.submission_generation
        attempt.claim_lease!(owner: 'w1', expected_generation: gen)
        attempt.store_access_token!('TOKEN-1', owner: 'w1', expected_generation: gen)
        attempt.mark_credential_persisted!(owner: 'w1', expected_generation: gen)
        aggregate_failures do
          expect(attempt.reload.access_token).to be_nil
          expect(attempt.credential_persisted_at).to be_present
          expect(attempt.secrets_cleared_at).to be_present
          expect(attempt.secrets_present?).to be(false)
        end
      end

      it 'clear_secrets! drops both secrets on terminal cleanup' do
        attempt.store_code!('CODE-1')
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
        attempt.store_code!('CODE-SECRET')
        gen = attempt.submission_generation
        attempt.claim_lease!(owner: 'w1', expected_generation: gen)
        attempt.store_access_token!('TOKEN-SECRET', owner: 'w1', expected_generation: gen)
        raw = raw_row(attempt.id, 'oauth_code', 'access_token')
        aggregate_failures do
          expect(raw['oauth_code'].to_s).not_to include('CODE-SECRET')
          expect(raw['access_token'].to_s).not_to include('TOKEN-SECRET')
        end
      end

      it 'never exposes the plaintext code/token via #inspect' do
        attempt.store_code!('CODE-SECRET')
        dump = attempt.inspect
        aggregate_failures do
          expect(dump).not_to include('CODE-SECRET')
          expect(dump).to include('[FILTERED]')
        end
      end
    end

    describe 'stale-worker credential protection (Guardrail 2 / Fix 4)' do
      it 'a worker with an OLDER submission_generation cannot store the token' do
        attempt.claim_lease!(owner: 'w1', expected_generation: 0)
        attempt.bump_generation! # generation is now 1; w1 is stale
        expect do
          attempt.store_access_token!('TOKEN', owner: 'w1', expected_generation: 0)
        end.to raise_error(described_class::StaleWorkerError)
        expect(raw_row(attempt.id, 'access_token')['access_token']).to be_nil
      end

      it 'a worker that no longer owns the lease cannot write credentials' do
        attempt.claim_lease!(owner: 'w1', expected_generation: 0)
        attempt.update!(lease_expires_at: 1.minute.ago)
        attempt.reload.claim_lease!(owner: 'w2', expected_generation: 0)
        stale = described_class.find(attempt.id)
        expect do
          stale.store_access_token!('TOKEN', owner: 'w1', expected_generation: 0)
        end.to raise_error(described_class::StaleWorkerError)
      end

      it 'a failed stale write does not clear or overwrite the newer credential' do
        gen0 = attempt.submission_generation
        attempt.claim_lease!(owner: 'w1', expected_generation: gen0)
        attempt.store_access_token!('TOKEN-GOOD', owner: 'w1', expected_generation: gen0)
        attempt.bump_generation! # w1 is now stale

        stale = described_class.find(attempt.id)
        expect do
          stale.store_access_token!('TOKEN-STALE', owner: 'w1', expected_generation: gen0)
        end.to raise_error(described_class::StaleWorkerError)
        expect(described_class.find(attempt.id).access_token).to eq('TOKEN-GOOD')
      end

      it 'mark_credential_persisted! rejects a stale worker (cannot clear a newer credential)' do
        gen0 = attempt.submission_generation
        attempt.claim_lease!(owner: 'w1', expected_generation: gen0)
        attempt.store_access_token!('TOKEN-GOOD', owner: 'w1', expected_generation: gen0)
        attempt.bump_generation!

        stale = described_class.find(attempt.id)
        expect do
          stale.mark_credential_persisted!(owner: 'w1', expected_generation: gen0)
        end.to raise_error(described_class::StaleWorkerError)
        expect(described_class.find(attempt.id).access_token).to eq('TOKEN-GOOD')
      end
    end

    describe '#to_status_dto' do
      it 'exposes safe fields only — never a secret' do
        attempt.bind_target!(waba_id: 'WABA-1', phone_number_id: 'PNID-1', phone_number: '+15551230001')
        attempt.store_code!('CODE-SECRET')
        gen = attempt.submission_generation
        attempt.claim_lease!(owner: 'w1', expected_generation: gen)
        attempt.store_access_token!('TOKEN-SECRET', owner: 'w1', expected_generation: gen)
        attempt.update!(status: 'processing', step: 'registering')
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

  # -- Slice 3 dependency (Fix 6): recovery/TTL is NOT implemented in Slice 1; these are executable reminders ---
  #
  # Temporary credentials in abandoned attempts MUST be cleared by the Slice 3 recovery/TTL worker. Pending specs
  # (no block) keep this obligation visible and un-droppable until Slice 3 implements it.
  describe 'Slice 3 dependency: abandoned-attempt cleanup (NOT implemented in Slice 1)' do
    it 'clears secrets for abandoned waiting_meta attempts past their TTL (Slice 3)'
    it 'recovers queued-but-never-enqueued attempts (Slice 3)'
    it 'recovers stale processing attempts whose lease expired with no live worker (Slice 3)'
    it 'sweeps terminal secret cleanup so no credential lingers (Slice 3)'
  end
end
