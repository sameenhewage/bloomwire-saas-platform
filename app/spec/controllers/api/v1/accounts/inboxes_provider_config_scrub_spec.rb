require 'rails_helper'

# Bloomwire Phase 2B: when privacy hardening is ON (master AND-gated), the inbox/channel API DTO must not
# expose sensitive provider_config values (api_key, webhook_verify_token, ...). OFF or master-OFF => stock
# Chatwoot. Output-only scrub: stored provider_config is never mutated. Fake secrets only.
RSpec.describe 'Bloomwire provider_config DTO scrub (Phase 2B)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:fake_api_key) { 'FAKE-WA-APIKEY-do-not-use' }
  let(:fake_verify_token) { 'FAKE-WA-VERIFY-do-not-use' }
  let(:whatsapp_channel) do
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false)
    # Set provider_config deterministically (validation/webhook callbacks are neutered by the factory) so
    # the assertions are stable; 'source' => 'embedded_signup' keeps the setup-webhook callback skipped.
    channel.update!(provider_config: {
                      'api_key' => fake_api_key,
                      'webhook_verify_token' => fake_verify_token,
                      'phone_number_id' => 'PNID-KEEP',
                      'business_account_id' => 'WABA-KEEP',
                      'source' => 'embedded_signup'
                    })
    channel
  end
  let!(:whatsapp_inbox) { create(:inbox, channel: whatsapp_channel, account: account) }

  before { GlobalConfig.clear_cache }

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  def show_inbox
    get "/api/v1/accounts/#{account.id}/inboxes/#{whatsapp_inbox.id}",
        headers: admin.create_new_auth_token, as: :json
  end

  def provider_config_json
    response.parsed_body['provider_config']
  end

  context 'when privacy hardening is OFF (stock Chatwoot)' do
    it 'returns the full provider_config including secrets to an admin' do
      show_inbox
      expect(response).to have_http_status(:success)
      expect(provider_config_json).to include('api_key' => fake_api_key)
      expect(response.body).to include(fake_api_key)
    end
  end

  context 'when Bloomwire master ON and privacy hardening ON' do
    before do
      set_toggle('BLOOMWIRE_MODE_ENABLED', true)
      set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true)
    end

    it 'does not expose sensitive provider_config values in the inbox show response' do
      show_inbox
      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(fake_api_key)
      expect(response.body).not_to include(fake_verify_token)
      pc = provider_config_json
      expect(pc).not_to have_key('api_key')
      expect(pc).not_to have_key('webhook_verify_token')
    end

    it 'does not expose sensitive provider_config values in the inbox index response' do
      get "/api/v1/accounts/#{account.id}/inboxes", headers: admin.create_new_auth_token, as: :json
      expect(response.body).not_to include(fake_api_key)
      expect(response.body).not_to include(fake_verify_token)
    end

    it 'still returns non-secret provider_config fields and required UI fields (regression)' do
      show_inbox
      pc = provider_config_json
      expect(pc).to include('phone_number_id')
      expect(pc).to include('source')
      body = response.parsed_body
      expect(body['name']).to eq(whatsapp_inbox.name)
      expect(body).to have_key('reauthorization_required')
    end

    it 'does not mutate the stored provider_config (output-only scrub, no DB change)' do
      show_inbox
      expect(whatsapp_channel.reload.provider_config['api_key']).to eq(fake_api_key)
      expect(whatsapp_channel.reload.provider_config['webhook_verify_token']).to eq(fake_verify_token)
    end
  end

  context 'when BLOOMWIRE_PRIVACY_HARDENING is stored ON but master is OFF (AND-gate keeps it stock)' do
    before { set_toggle('BLOOMWIRE_PRIVACY_HARDENING', true) } # master stays OFF

    it 'returns the full provider_config because the master AND-gate forces the feature OFF' do
      show_inbox
      expect(response.body).to include(fake_api_key)
      expect(provider_config_json).to include('api_key' => fake_api_key)
    end
  end
end
