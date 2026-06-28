require 'rails_helper'

# Bloomwire Phase 13D — broadcast-DTO PII log hardening (companion to the WhatsappEventsJob fix).
#
# ActionCableBroadcastJob#perform(members, event_name, data) carries the realtime DTO as `data` — for message
# events that includes the contact phone + name. ActiveJob's default `log_arguments = true` prints that DTO
# (and the pubsub member tokens) in cleartext in the enqueue/perform log lines for EVERY realtime broadcast.
# Fix: `self.log_arguments = false` (logging-only; the job still receives members/event/data and broadcasts).
#
# These tests fail BEFORE the fix (DTO PII present in the ActiveJob log) and pass AFTER.
RSpec.describe ActionCableBroadcastJob do
  include ActiveJob::TestHelper

  let(:members) { ['fake-pubsub-token-AAA'] }
  let(:phone) { '15557770001' }                 # fake contact phone marker
  let(:name) { 'ZzContactNameMarker' }          # fake contact name marker
  let(:data) do
    { id: 6, content: 'hi there', message_type: 0, conversation_id: 4, account_id: 1, inbox_id: 1,
      sender: { id: 5, type: 'contact', name: name, phone_number: "+#{phone}" },
      conversation: { contact_inbox: { source_id: phone } } }
  end

  before { ActiveJob::Base.queue_adapter = :test }

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

  it 'does not print broadcast DTO PII (contact phone/name) in the ActiveJob enqueue log' do
    log = capture_activejob_log { described_class.perform_later(members, 'message.created', data) }

    expect(log).to include('ActionCableBroadcastJob') # lifecycle still observable
    expect(log).not_to include(phone)
    expect(log).not_to include(name)
  end

  it 'does not print broadcast DTO PII in the ActiveJob perform log' do
    allow(ActionCable.server).to receive(:broadcast)
    log = capture_activejob_log { perform_enqueued_jobs { described_class.perform_later(members, 'message.created', data) } }

    expect(log).to include('ActionCableBroadcastJob')
    expect(log).not_to include(phone)
    expect(log).not_to include(name)
  end

  it 'still records the real arguments for execution (logging change only)' do
    expect { described_class.perform_later(members, 'message.created', data) }
      .to have_enqueued_job(described_class).with(members, 'message.created', data)
  end

  it 'still performs the realtime broadcast to each member with the DTO intact' do
    allow(ActionCable.server).to receive(:broadcast)
    perform_enqueued_jobs { described_class.perform_later(members, 'message.created', data) }

    expect(ActionCable.server).to have_received(:broadcast)
      .with('fake-pubsub-token-AAA', hash_including(event: 'message.created', data: data))
  end
end
