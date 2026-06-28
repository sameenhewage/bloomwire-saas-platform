require 'rails_helper'

# Bloomwire ADR-0006 / Phase 13B.1 — WhatsApp provider_config secret-at-rest.
#
# Channel::Whatsapp#provider_config holds the Meta Cloud API access token (api_key) and the auto-generated
# webhook_verify_token. With encryption keys configured (Chatwoot.encryption_configured?) the jsonb column is
# encrypted at rest like every sibling channel secret; without keys (default local/CI) the `encrypts`
# declaration is skipped (OFF == stock plaintext jsonb) and the at-rest examples skip — exactly like
# spec/models/application_record_external_credentials_encryption_spec.rb (run in the run_mfa_spec workflow).
#
# The round-trip examples run in BOTH modes and prove the app can still read provider_config keys, so adding
# `encrypts` never breaks the existing plaintext behavior.
RSpec.describe Channel::Whatsapp do
  let(:account) { create(:account) }

  # Build a whatsapp_cloud channel, then set a distinctive api_key. The factory's before(:create) forces a
  # default config, so the secret is applied via update! (mirrors Whatsapp::ReauthorizationService / the 12B
  # bw_aligned_whatsapp_channel helper) to guarantee a known value for the at-rest assertions.
  def cloud_channel_with_secret(api_key: 'secret-access-token-xyz')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        validate_provider_config: false, sync_templates: false)
    channel.update!(provider_config: channel.provider_config.merge('api_key' => api_key))
    channel
  end

  describe 'provider_config round-trip (runs with or without encryption keys)' do
    it 'reads back stored keys after reload' do
      channel = cloud_channel_with_secret
      reloaded = described_class.find(channel.id)

      expect(reloaded.provider_config['api_key']).to eq('secret-access-token-xyz')
      expect(reloaded.provider_config['phone_number_id']).to eq('123456789')
      expect(reloaded.provider_config['business_account_id']).to eq('123456789')
    end

    it 'auto-generates and persists the webhook_verify_token' do
      channel = cloud_channel_with_secret
      token = channel.provider_config['webhook_verify_token']

      expect(token).to be_present
      expect(described_class.find(channel.id).provider_config['webhook_verify_token']).to eq(token)
    end

    it 'persists rotated provider_config values' do
      channel = cloud_channel_with_secret
      channel.update!(provider_config: channel.provider_config.merge('api_key' => 'rotated-token'))

      expect(described_class.find(channel.id).provider_config['api_key']).to eq('rotated-token')
    end
  end

  describe 'encryption at rest' do
    before { skip('encryption keys missing; see run_mfa_spec workflow') unless Chatwoot.encryption_configured? }

    it 'does not store the access token in plaintext' do
      channel = cloud_channel_with_secret(api_key: 'secret-access-token-xyz')
      raw = channel.reload.read_attribute_before_type_cast(:provider_config).to_s

      expect(raw).to be_present
      expect(raw).not_to include('secret-access-token-xyz')
      expect(channel.provider_config['api_key']).to eq('secret-access-token-xyz')
      expect(channel.encrypted_attribute?(:provider_config)).to be(true)
    end

    it 'does not store the auto-generated webhook_verify_token in plaintext' do
      channel = cloud_channel_with_secret
      token = channel.provider_config['webhook_verify_token']
      raw = channel.reload.read_attribute_before_type_cast(:provider_config).to_s

      expect(token).to be_present
      expect(raw).not_to include(token)
    end

    it 'reads legacy plaintext rows and re-encrypts them on update (backfill transition)' do
      channel = cloud_channel_with_secret

      # Simulate a legacy plaintext row by writing the jsonb directly, bypassing the encrypting setter.
      legacy_config = { 'api_key' => 'legacy-plain-token', 'phone_number_id' => '123456789' }
      sql = ActiveRecord::Base.send(
        :sanitize_sql_array,
        ['UPDATE channel_whatsapp SET provider_config = ? WHERE id = ?', legacy_config.to_json, channel.id]
      )
      ActiveRecord::Base.connection.execute(sql)

      legacy = described_class.find(channel.id)
      expect(legacy.provider_config['api_key']).to eq('legacy-plain-token') # support_unencrypted_data reads plaintext

      # save!(validate: false) re-encrypts without the remote credential re-check (mirrors the model's own
      # enable_voice_calling!); the point under test is the at-rest re-encryption, not provider validation.
      legacy.provider_config = legacy.provider_config.merge('api_key' => 'reencrypted-token')
      legacy.save!(validate: false)

      raw = legacy.reload.read_attribute_before_type_cast(:provider_config).to_s
      expect(raw).not_to include('reencrypted-token')
      expect(legacy.provider_config['api_key']).to eq('reencrypted-token')
    end
  end
end
