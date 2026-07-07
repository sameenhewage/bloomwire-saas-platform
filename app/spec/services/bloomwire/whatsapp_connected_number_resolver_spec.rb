require 'rails_helper'

# Phase 17E.2: the safe duplicate-registration resolver. All Meta access is stubbed via an instance_double of the
# FacebookApiClient (no real Graph calls). Fake values only.
RSpec.describe Bloomwire::WhatsappConnectedNumberResolver do
  let(:client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:token) { 'FAKE-TOKEN' }
  let(:selected_waba_id) { 'WABA-SELECTED' }
  let(:selected_phone_number) { '+94771713273' }

  subject(:result) do
    described_class.new(client: client, input_token: token,
                        selected_waba_id: selected_waba_id, selected_phone_number: selected_phone_number).resolve
  end

  # A phone registration row as Meta returns it (string keys); CONNECTED unless a status is passed.
  def reg(id, display, status = 'CONNECTED')
    { 'id' => id, 'display_phone_number' => display, 'status' => status }
  end

  describe 'exactly one CONNECTED same-business registration (the safe happy path)' do
    before do
      allow(client).to receive(:messaging_waba_ids).with(token).and_return(%w[WABA-SELECTED WABA-CONNECTED])
      allow(client).to receive(:waba_registrations).with('WABA-SELECTED')
                                                   .and_return([reg('PNID-DISC', '+94771713273', 'DISCONNECTED')])
      # Deliberately different formatting on the connected row to prove normalized matching.
      allow(client).to receive(:waba_registrations).with('WABA-CONNECTED')
                                                   .and_return([reg('PNID-CONN', '+94 77 171 3273')])
      allow(client).to receive(:waba_owner_business_id).with('WABA-SELECTED').and_return('BIZ-1')
      allow(client).to receive(:waba_owner_business_id).with('WABA-CONNECTED').and_return('BIZ-1')
    end

    it 'resolves to the CONNECTED WABA + phone_number_id (normalized match across formatting)' do
      aggregate_failures do
        expect(result).to be_ok
        expect(result.waba_id).to eq('WABA-CONNECTED')
        expect(result.phone_number_id).to eq('PNID-CONN')
        expect(result.error).to be_nil
      end
    end
  end

  describe 'a connected duplicate on the SAME selected WABA' do
    it 'resolves without an owner lookup (the same WABA is trivially the same business)' do
      allow(client).to receive(:messaging_waba_ids).with(token).and_return(%w[WABA-SELECTED])
      allow(client).to receive(:waba_registrations).with('WABA-SELECTED')
                                                   .and_return([reg('PNID-DISC', '+94771713273', 'DISCONNECTED'),
                                                                reg('PNID-CONN', '+94771713273')])
      expect(client).not_to receive(:waba_owner_business_id)
      aggregate_failures do
        expect(result).to be_ok
        expect(result.phone_number_id).to eq('PNID-CONN')
      end
    end
  end

  describe 'zero CONNECTED registrations (fail closed)' do
    it 'returns :no_connected_registration' do
      allow(client).to receive(:messaging_waba_ids).with(token).and_return(%w[WABA-SELECTED])
      allow(client).to receive(:waba_registrations).with('WABA-SELECTED')
                                                   .and_return([reg('PNID-DISC', '+94771713273', 'DISCONNECTED')])
      expect(result.error).to eq(:no_connected_registration)
    end
  end

  describe 'multiple CONNECTED registrations (ambiguous -> fail closed, never guess)' do
    it 'returns :ambiguous_connected_registration' do
      allow(client).to receive(:messaging_waba_ids).with(token).and_return(%w[WABA-A WABA-B])
      allow(client).to receive(:waba_registrations).with('WABA-A').and_return([reg('PNID-A', '+94771713273')])
      allow(client).to receive(:waba_registrations).with('WABA-B').and_return([reg('PNID-B', '+94771713273')])
      expect(result.error).to eq(:ambiguous_connected_registration)
    end
  end

  describe 'the only CONNECTED match is in a DIFFERENT business (never cross a tenant boundary)' do
    it 'returns :cross_business_registration' do
      allow(client).to receive(:messaging_waba_ids).with(token).and_return(%w[WABA-SELECTED WABA-OTHERBIZ])
      allow(client).to receive(:waba_registrations).with('WABA-SELECTED')
                                                   .and_return([reg('PNID-DISC', '+94771713273', 'DISCONNECTED')])
      allow(client).to receive(:waba_registrations).with('WABA-OTHERBIZ').and_return([reg('PNID-X', '+94771713273')])
      allow(client).to receive(:waba_owner_business_id).with('WABA-SELECTED').and_return('BIZ-1')
      allow(client).to receive(:waba_owner_business_id).with('WABA-OTHERBIZ').and_return('BIZ-2')
      expect(result.error).to eq(:cross_business_registration)
    end
  end

  describe 'a CONNECTED registration for a different display number is ignored' do
    it 'returns :no_connected_registration (only the selected number counts)' do
      allow(client).to receive(:messaging_waba_ids).with(token).and_return(%w[WABA-SELECTED])
      allow(client).to receive(:waba_registrations).with('WABA-SELECTED')
                                                   .and_return([reg('PNID-OTHER', '+15551230000'),
                                                                reg('PNID-DISC', '+94771713273', 'DISCONNECTED')])
      expect(result.error).to eq(:no_connected_registration)
    end
  end

  describe 'a Meta lookup failure fails closed (sanitized)' do
    it 'returns :meta_error when a client call raises' do
      allow(client).to receive(:messaging_waba_ids).with(token).and_raise(StandardError, 'boom RAW')
      expect(result.error).to eq(:meta_error)
    end
  end
end
