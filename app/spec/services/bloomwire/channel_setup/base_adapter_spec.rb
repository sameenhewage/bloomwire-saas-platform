require 'rails_helper'

# Base class for the generic Bloomwire channel-setup adapters (ADR 0005). It carries
# the adapter contract and a DEFAULT NO-OP post_create! lifecycle hook, so a future
# adapter (SMS / Email / Instagram / Shopify) that needs no provider-side
# registration step inherits safe behavior without implementing the hook.
RSpec.describe Bloomwire::ChannelSetup::BaseAdapter do
  subject(:adapter) { described_class.new }

  describe '#post_create!' do
    it 'defaults to a no-op (no provider-side call) for adapters that need none' do
      channel = instance_spy(Channel::Whatsapp)

      expect { adapter.post_create!(channel) }.not_to raise_error
      expect(channel).not_to have_received(:setup_webhooks)
    end
  end
end
