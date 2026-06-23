require 'rails_helper'

# Verifies operator-supplied WhatsApp phone metadata against Meta BEFORE the orchestrator
# creates/activates an integration. It must prove the supplied phone_number_id is exposed
# by the supplied WABA/token and that the submitted phone number matches Meta's canonical
# number — returning a coded symbol (never raw provider data).
RSpec.describe Bloomwire::ChannelSetup::WhatsappMetadataValidator do
  let(:params) do
    {
      business_account_id: 'waba-001',
      phone_number_id: 'pnid-001',
      phone_number: '+15551234567',
      api_key: 'token-001'
    }
  end

  let(:api_client) { instance_double(Whatsapp::FacebookApiClient) }

  before { allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(api_client) }

  def stub_phone_numbers(data)
    allow(api_client).to receive(:fetch_phone_numbers).and_return('data' => data)
  end

  describe '#error_code' do
    it 'returns nil when the WABA exposes the phone_number_id and the number matches' do
      stub_phone_numbers([{ 'id' => 'pnid-001', 'display_phone_number' => '+1 555-123-4567' }])
      expect(described_class.new(params).error_code).to be_nil
    end

    it 'queries Meta with the supplied token and WABA' do
      stub_phone_numbers([{ 'id' => 'pnid-001', 'display_phone_number' => '15551234567' }])

      described_class.new(params).error_code

      expect(Whatsapp::FacebookApiClient).to have_received(:new).with('token-001')
      expect(api_client).to have_received(:fetch_phone_numbers).with('waba-001')
    end

    it 'matches the correct phone among several in the WABA (not just the first)' do
      stub_phone_numbers([
                           { 'id' => 'other-pnid', 'display_phone_number' => '+19998887777' },
                           { 'id' => 'pnid-001', 'display_phone_number' => '15551234567' }
                         ])
      expect(described_class.new(params).error_code).to be_nil
    end

    it 'returns :phone_number_id_mismatch when the WABA does not expose the phone_number_id' do
      stub_phone_numbers([{ 'id' => 'a-different-pnid', 'display_phone_number' => '15551234567' }])
      expect(described_class.new(params).error_code).to eq(:phone_number_id_mismatch)
    end

    it 'returns :phone_number_mismatch when the id matches but the number does not' do
      stub_phone_numbers([{ 'id' => 'pnid-001', 'display_phone_number' => '+15559999999' }])
      expect(described_class.new(params).error_code).to eq(:phone_number_mismatch)
    end

    it 'returns :phone_metadata_unverifiable when Meta raises (bad/inaccessible WABA or token)' do
      allow(api_client).to receive(:fetch_phone_numbers).and_raise(RuntimeError, 'WABA phone numbers fetch failed: 190')
      expect(described_class.new(params).error_code).to eq(:phone_metadata_unverifiable)
    end

    it 'returns :phone_metadata_unverifiable when the provider response carries no phone list' do
      allow(api_client).to receive(:fetch_phone_numbers).and_return('error' => { 'code' => 100 })
      expect(described_class.new(params).error_code).to eq(:phone_metadata_unverifiable)
    end
  end
end
