# Internal, channel-agnostic error raised by channel adapters to signal a setup
# failure with a machine-readable code (e.g. :invalid_channel_params,
# :duplicate_phone_number). The orchestrator rescues it and converts it into a
# failed Result, so callers never see raw provider/channel exceptions.
class Bloomwire::ChannelSetup::SetupError < StandardError
  attr_reader :code

  def initialize(code, message = nil)
    @code = code
    super(message || code.to_s)
  end
end
