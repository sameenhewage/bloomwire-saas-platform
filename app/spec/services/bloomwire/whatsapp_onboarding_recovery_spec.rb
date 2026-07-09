require 'rails_helper'

# Slice 3 (ADR-0010 v3): recovery + TTL sweep. Proves enqueue-gap recovery, dead-worker (stale processing)
# recovery, generous abandoned-attempt expiry (waiting_meta never swept short), action_required is NEVER
# auto-expired, and terminal secret cleanup. Fake values only; no Meta calls.
RSpec.describe Bloomwire::WhatsappOnboardingRecovery do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }

  def build_attempt(status:, idle_for:, lease_expires_at: nil, owner: nil, phone_number_id: nil)
    attempt = Bloomwire::WhatsappOnboardingAttempt.create!(
      account: account, status: status, phone_number_id: phone_number_id,
      processing_owner: owner, lease_expires_at: lease_expires_at
    )
    attempt.update_columns(updated_at: idle_for.ago) # rubocop:disable Rails/SkipsModelValidations
    attempt
  end

  describe '#redrive_stalled!' do
    it 're-enqueues a queued attempt that was never picked up (no lease, idle past grace)' do
      attempt = build_attempt(status: 'queued', idle_for: 5.minutes)
      expect { described_class.new.redrive_stalled! }
        .to have_enqueued_job(Bloomwire::WhatsappOnboardingJob).with(attempt.id, attempt.submission_generation)
    end

    it 're-enqueues a processing attempt whose lease expired (dead worker)' do
      attempt = build_attempt(status: 'processing', idle_for: 5.minutes, lease_expires_at: 2.minutes.ago, owner: 'dead')
      expect { described_class.new.redrive_stalled! }
        .to have_enqueued_job(Bloomwire::WhatsappOnboardingJob).with(attempt.id, attempt.submission_generation)
    end

    it 'does NOT re-enqueue a live-leased or freshly-updated attempt' do
      build_attempt(status: 'processing', idle_for: 5.minutes, lease_expires_at: 5.minutes.from_now, owner: 'alive')
      build_attempt(status: 'queued', idle_for: 2.seconds) # within grace
      expect { described_class.new.redrive_stalled! }.not_to have_enqueued_job(Bloomwire::WhatsappOnboardingJob)
    end
  end

  describe '#expire_abandoned!' do
    it 'expires an abandoned waiting_meta attempt past the generous TTL' do
      attempt = build_attempt(status: 'waiting_meta', idle_for: 31.minutes)
      described_class.new.expire_abandoned!
      aggregate_failures do
        expect(attempt.reload.status).to eq('expired')
        expect(attempt.safe_error_code).to eq('onboarding_abandoned')
      end
    end

    it 'does NOT expire a waiting_meta attempt within the TTL (never short)' do
      attempt = build_attempt(status: 'waiting_meta', idle_for: 5.minutes)
      described_class.new.expire_abandoned!
      expect(attempt.reload.status).to eq('waiting_meta')
    end

    it 'does NOT auto-expire an action_required attempt (awaits owner Recheck)' do
      attempt = build_attempt(status: 'action_required', idle_for: 2.hours)
      described_class.new.expire_abandoned!
      expect(attempt.reload.status).to eq('action_required')
    end
  end

  describe '#clear_terminal_secrets!' do
    before { skip 'AR encryption keys not configured in this env' unless Chatwoot.encryption_configured? }

    it 'clears a secret still held by a terminal attempt' do
      attempt = Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'queued')
      attempt.store_code!('LINGERING-CODE')
      attempt.update!(status: 'failed') # terminal but still holding the code
      described_class.new.clear_terminal_secrets!
      expect(attempt.reload.oauth_code).to be_nil
    end
  end

  describe '.sweep!' do
    it 'expires past-TTL before redriving: an ancient queued attempt is expired, not re-enqueued' do
      attempt = build_attempt(status: 'queued', idle_for: 40.minutes)
      expect { described_class.sweep! }.not_to have_enqueued_job(Bloomwire::WhatsappOnboardingJob)
      expect(attempt.reload.status).to eq('expired')
    end
  end
end
