# Generic, channel-agnostic result for Bloomwire external-channel setup
# (ADR 0005, 4.4-b-WA.2B). Every adapter/orchestrator returns this same shape:
# a boolean outcome, a machine-readable error code (nil on success), and the
# created BloomwireChannelIntegration (nil on failure). No channel-specific fields
# live here, so the contract is reusable for WhatsApp, SMS, Email, etc.
class Bloomwire::ChannelSetup::Result
  attr_reader :error, :integration

  def self.success(integration)
    new(success: true, integration: integration)
  end

  def self.failure(error)
    new(success: false, error: error)
  end

  def initialize(success:, integration: nil, error: nil)
    @success = success
    @integration = integration
    @error = error
  end

  def success?
    @success
  end
end
