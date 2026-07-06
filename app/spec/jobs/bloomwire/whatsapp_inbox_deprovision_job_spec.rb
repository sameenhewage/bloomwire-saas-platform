require 'rails_helper'

RSpec.describe Bloomwire::WhatsappInboxDeprovisionJob do
  it 'delegates to the service purge! with the passed ids' do
    expect(Bloomwire::WhatsappInboxDeprovisionService).to receive(:purge!)
      .with(account_id: 11, inbox_id: 22, actor_id: 33)
    described_class.perform_now(account_id: 11, inbox_id: 22, actor_id: 33)
  end
end
