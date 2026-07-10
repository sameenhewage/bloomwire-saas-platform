require 'rails_helper'

# Slice 3 (ADR-0010 v3): the per-attempt onboarding job. High priority; delegates to the resumable processor;
# no-ops for a missing/terminal attempt (idempotent, retry-safe). No Meta calls (processor is stubbed).
RSpec.describe Bloomwire::WhatsappOnboardingJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:attempt) { Bloomwire::WhatsappOnboardingAttempt.create!(account: account, status: 'queued') }

  it 'enqueues on the high-priority queue' do
    expect { described_class.perform_later(attempt.id, 0) }
      .to have_enqueued_job(described_class).on_queue('high')
  end

  it 'serializes only the attempt id and non-secret submission generation' do
    described_class.perform_later(attempt.id, attempt.submission_generation)
    payload = enqueued_jobs.last

    aggregate_failures do
      expect(payload[:args]).to eq([attempt.id, attempt.submission_generation])
      expect(payload[:args]).to all(be_a(Integer))
      expect(payload.to_json).not_to include('oauth_code', 'access_token', 'verification_pin', 'phone_number', 'provider_config')
    end
  end

  it 'runs the processor for the attempt with the current enqueued generation' do
    processor = instance_double(Bloomwire::WhatsappOnboardingProcessor, process: nil)
    allow(Bloomwire::WhatsappOnboardingProcessor).to receive(:new).and_return(processor)
    described_class.perform_now(attempt.id, attempt.submission_generation)
    aggregate_failures do
      expect(Bloomwire::WhatsappOnboardingProcessor).to have_received(:new)
        .with(hash_including(attempt: attempt, generation: attempt.submission_generation))
      expect(processor).to have_received(:process)
    end
  end

  it 'no-ops before processor construction when the enqueued generation is stale' do
    attempt.bump_generation!
    allow(Bloomwire::WhatsappOnboardingProcessor).to receive(:new)

    described_class.perform_now(attempt.id, 0)

    expect(Bloomwire::WhatsappOnboardingProcessor).not_to have_received(:new)
  end

  it 'no-ops for a missing attempt' do
    allow(Bloomwire::WhatsappOnboardingProcessor).to receive(:new)
    described_class.perform_now(-1, 0)
    expect(Bloomwire::WhatsappOnboardingProcessor).not_to have_received(:new)
  end

  it 'no-ops for an already-terminal attempt' do
    attempt.update!(status: 'completed')
    allow(Bloomwire::WhatsappOnboardingProcessor).to receive(:new)
    described_class.perform_now(attempt.id, 0)
    expect(Bloomwire::WhatsappOnboardingProcessor).not_to have_received(:new)
  end

  # In-flight attempts must continue even if the emergency kill switch is later flipped: the worker never gates on
  # the flag (the flag only affects whether NEW async attempts are created at the controller).
  it 'still processes an in-flight attempt even when the emergency kill switch is set' do
    allow(Bloomwire::Features).to receive(:async_whatsapp_onboarding_disabled?).and_return(true)
    processor = instance_double(Bloomwire::WhatsappOnboardingProcessor, process: nil)
    allow(Bloomwire::WhatsappOnboardingProcessor).to receive(:new).and_return(processor)
    described_class.perform_now(attempt.id, attempt.submission_generation)
    expect(processor).to have_received(:process)
  end
end
