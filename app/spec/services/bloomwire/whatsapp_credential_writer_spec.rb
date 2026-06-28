require 'rails_helper'

# Phase 14 S2a — Ops credential writer. Merges WhatsApp provider credentials into an EXISTING
# Channel::Whatsapp#provider_config: write-only api_key (blank => keep), non-secret routing ids updated only
# when provided, never replacing the config, and saved with validate: false so NO live Meta call is made.
RSpec.describe Bloomwire::WhatsappCredentialWriter do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              validate_provider_config: false, sync_templates: false)
  end

  before do
    channel.update!(provider_config: channel.provider_config.merge(
      'api_key' => 'old-token', 'phone_number_id' => 'PNID-OLD', 'business_account_id' => 'WABA-OLD'
    ))
  end

  def write(attrs)
    described_class.new(channel: channel, attributes: attrs).perform
    channel.reload
  end

  it 'sets/rotates the api_key when provided' do
    write('api_key' => 'new-token')
    expect(channel.provider_config['api_key']).to eq('new-token')
  end

  it 'keeps the existing api_key when the submitted value is blank (no-wipe, write-only)' do
    write('api_key' => '')
    expect(channel.provider_config['api_key']).to eq('old-token')
  end

  it 'keeps the existing api_key when the key is absent entirely' do
    write('phone_number_id' => 'PNID-NEW')
    expect(channel.provider_config['api_key']).to eq('old-token')
  end

  it 'updates non-secret routing ids when provided' do
    write('phone_number_id' => 'PNID-NEW', 'business_account_id' => 'WABA-NEW')
    expect(channel.provider_config['phone_number_id']).to eq('PNID-NEW')
    expect(channel.provider_config['business_account_id']).to eq('WABA-NEW')
  end

  it 'keeps existing non-secret ids when their fields are blank' do
    write('phone_number_id' => '', 'business_account_id' => '   ')
    expect(channel.provider_config['phone_number_id']).to eq('PNID-OLD')
    expect(channel.provider_config['business_account_id']).to eq('WABA-OLD')
  end

  it 'merges (does not replace) — preserves the auto-generated webhook_verify_token and source' do
    token = channel.provider_config['webhook_verify_token']
    expect(token).to be_present
    write('api_key' => 'new-token')
    expect(channel.provider_config['webhook_verify_token']).to eq(token)
    expect(channel.provider_config['source']).to eq('embedded_signup')
  end

  it 'does not write webhook_verify_token or verification_pin even if submitted' do
    token = channel.provider_config['webhook_verify_token']
    write('api_key' => 'new-token', 'webhook_verify_token' => 'attacker', 'verification_pin' => '000000')
    expect(channel.provider_config['webhook_verify_token']).to eq(token)
    expect(channel.provider_config['verification_pin']).to be_nil
  end

  it 'makes NO call to graph.facebook.com (validate: false; no create-only callbacks on update)' do
    write('api_key' => 'new-token', 'phone_number_id' => 'PNID-NEW')
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'strips surrounding whitespace from submitted values' do
    write('api_key' => '  spaced-token  ')
    expect(channel.provider_config['api_key']).to eq('spaced-token')
  end

  describe 'encryption at rest (skips unless encryption keys are configured)' do
    before { skip('encryption keys missing') unless Chatwoot.encryption_configured? }

    it 'does not persist the token in plaintext' do
      write('api_key' => 'super-secret-token')
      raw = channel.reload.read_attribute_before_type_cast(:provider_config).to_s
      expect(raw).not_to include('super-secret-token')
      expect(channel.provider_config['api_key']).to eq('super-secret-token')
    end
  end
end
