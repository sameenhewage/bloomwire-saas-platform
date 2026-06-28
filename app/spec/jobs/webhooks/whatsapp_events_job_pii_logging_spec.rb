require 'rails_helper'

# Bloomwire Phase 13D — WhatsApp webhook PII log hardening.
#
# Root cause (found in Phase 13C live cert): ActiveJob's default `log_arguments = true` makes the
# enqueue/perform log lines for Webhooks::WhatsappEventsJob print the FULL Meta webhook payload in
# cleartext — including the customer wa_id/phone, profile name, and routing phone_number_id. That is PII in
# logs (not a secret leak). The fix sets `self.log_arguments = false` on the job (logging-only; the job still
# receives + processes the full payload, so behavior + `have_enqueued_job.with(...)` are unchanged).
#
# These tests fail BEFORE the fix (payload PII present in the ActiveJob log) and pass AFTER.
RSpec.describe Webhooks::WhatsappEventsJob do
  include ActiveJob::TestHelper

  let!(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:wa_id) { '15557770001' }              # customer phone / wa_id (distinctive marker)
  let(:profile_name) { 'ZzCustomerProfileMarker' } # customer profile name (distinctive marker)
  let(:pnid) { channel.provider_config['phone_number_id'] }

  let(:inbound_payload) do
    {
      'object' => 'whatsapp_business_account',
      'entry' => [{ 'id' => 'WABA-FAKE', 'changes' => [{ 'field' => 'messages', 'value' => {
        'metadata' => { 'display_phone_number' => channel.phone_number.delete('+'), 'phone_number_id' => pnid },
        'contacts' => [{ 'profile' => { 'name' => profile_name }, 'wa_id' => wa_id }],
        'messages' => [{ 'from' => wa_id, 'id' => 'wamid.PII-TEST-1', 'timestamp' => '1700000000',
                         'text' => { 'body' => 'hi' }, 'type' => 'text' }]
      } }] }]
    }
  end

  let(:status_payload) do
    {
      'object' => 'whatsapp_business_account',
      'entry' => [{ 'id' => 'WABA-FAKE', 'changes' => [{ 'field' => 'messages', 'value' => {
        'metadata' => { 'display_phone_number' => channel.phone_number.delete('+'), 'phone_number_id' => pnid },
        'statuses' => [{ 'id' => 'wamid.PII-TEST-1', 'status' => 'delivered', 'timestamp' => '1700000300',
                         'recipient_id' => wa_id }]
      } }] }]
    }
  end

  before { ActiveJob::Base.queue_adapter = :test }

  # Capture only ActiveJob's own lifecycle logs (enqueue/perform), isolated from Rails.logger.
  def capture_activejob_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    logger.level = Logger::DEBUG
    original = ActiveJob::Base.logger
    ActiveJob::Base.logger = logger
    begin
      yield
    ensure
      ActiveJob::Base.logger = original
    end
    io.string
  end

  it 'does not print inbound webhook payload PII in the ActiveJob enqueue log' do
    log = capture_activejob_log { described_class.perform_later(inbound_payload) }

    expect(log).to include('Webhooks::WhatsappEventsJob') # lifecycle still observable
    expect(log).not_to include(wa_id)
    expect(log).not_to include(profile_name)
    expect(log).not_to include(pnid)
  end

  it 'does not print inbound webhook payload PII in the ActiveJob perform log' do
    # Stub the incoming service so perform logs its "Performing ... " line without cascading downstream jobs.
    allow(Whatsapp::IncomingMessageWhatsappCloudService).to receive(:new)
      .and_return(instance_double(Whatsapp::IncomingMessageWhatsappCloudService, perform: nil))

    log = capture_activejob_log { perform_enqueued_jobs { described_class.perform_later(inbound_payload) } }

    expect(log).to include('Webhooks::WhatsappEventsJob')
    expect(log).not_to include(wa_id)
    expect(log).not_to include(profile_name)
  end

  it 'does not print status webhook payload PII (recipient/wa_id) in the ActiveJob log' do
    log = capture_activejob_log { described_class.perform_later(status_payload) }

    expect(log).to include('Webhooks::WhatsappEventsJob')
    expect(log).not_to include(wa_id)
  end

  it 'still records the real job arguments for execution (logging change only, not behavior)' do
    expect { described_class.perform_later(inbound_payload) }
      .to have_enqueued_job(described_class).with(inbound_payload)
  end
end
