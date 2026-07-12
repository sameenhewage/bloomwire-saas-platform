require 'rails_helper'

RSpec.describe Bloomwire::WhatsappInboxDeprovisionJob do
  it 'delegates to the service purge! with the passed ids' do
    expect(Bloomwire::WhatsappInboxDeprovisionService).to receive(:purge!)
      .with(account_id: 11, inbox_id: 22, actor_id: 33)
    described_class.perform_now(account_id: 11, inbox_id: 22, actor_id: 33)
  end

  it 'propagates a purge failure so the job adapter can retry' do
    allow(Bloomwire::WhatsappInboxDeprovisionService).to receive(:purge!).and_raise(StandardError, 'database failure')

    expect do
      described_class.perform_now(account_id: 11, inbox_id: 22, actor_id: 33)
    end.to raise_error(StandardError, 'database failure')
  end
end
