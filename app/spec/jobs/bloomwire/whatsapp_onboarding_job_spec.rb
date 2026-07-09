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

  it 'runs the processor for the attempt with the enqueued generation' do
    processor = instance_double(Bloomwire::WhatsappOnboardingProcessor, process: nil)
    allow(Bloomwire::WhatsappOnboardingProcessor).to receive(:new).and_return(processor)
    described_class.perform_now(attempt.id, attempt.submission_generation)
    aggregate_failures do
      expect(Bloomwire::WhatsappOnboardingProcessor).to have_received(:new)
        .with(hash_including(attempt: attempt, generation: attempt.submission_generation))
      expect(processor).to have_received(:process)
    end
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
end
