require 'rails_helper'

# Resolution logic for the Bloomwire global Meta WhatsApp webhook router. Resolves a single, consistent,
# ready_for_webhook Bloomwire::WhatsappSetup mapping by the payload's phone_number_id. Fail-closed (nil)
# on anything ambiguous/missing. No secrets are read here. Fake values only.
RSpec.describe Bloomwire::Webhooks::WhatsappRouter do
  let(:account) { create(:account) }

  def whatsapp_channel
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                              validate_provider_config: false)
  end

  def meta_payload(phone_number_id:, display_phone_number: '15551230001')
    {
      'object' => 'whatsapp_business_account',
      'entry' => [{
        'id' => 'WABA-123',
        'changes' => [{
          'field' => 'messages',
          'value' => {
            'metadata' => { 'display_phone_number' => display_phone_number, 'phone_number_id' => phone_number_id },
            'messages' => [{ 'from' => '15559990001', 'id' => 'wamid.X', 'text' => { 'body' => 'hi' } }]
          }
        }]
      }]
    }
  end

  def ready_setup(phone_number_id:)
    channel = whatsapp_channel
    create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                      phone_number_id: phone_number_id, setup_status: 'ready_for_webhook')
  end

  # A mapping whose channel aligns with the native job resolution path: channel.phone_number is the
  # normalized display number ("+<display>") and channel.provider_config['phone_number_id'] == the setup id.
  def aligned_setup(phone_number_id: 'PNID-OK', display_phone_number: '15551230001')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display_phone_number}", sync_templates: false,
                                        validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => phone_number_id,
                                                                   'source' => 'embedded_signup'))
    setup = create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                              phone_number_id: phone_number_id, setup_status: 'ready_for_webhook')
    [setup, channel]
  end

  describe '.phone_number_id_from' do
    it 'extracts phone_number_id from a realistic Meta WhatsApp payload' do
      expect(described_class.phone_number_id_from(meta_payload(phone_number_id: 'PNID-1'))).to eq('PNID-1')
    end

    it 'returns nil when metadata is absent' do
      expect(described_class.phone_number_id_from({ 'object' => 'whatsapp_business_account', 'entry' => [] })).to be_nil
    end
  end

  describe '.resolve' do
    it 'resolves a ready_for_webhook mapping by phone_number_id' do
      setup = ready_setup(phone_number_id: 'PNID-READY')
      expect(described_class.resolve(meta_payload(phone_number_id: 'PNID-READY'))).to eq(setup)
    end

    it 'returns the correct account / inbox / channel from the mapping' do
      setup = ready_setup(phone_number_id: 'PNID-READY')
      resolved = described_class.resolve(meta_payload(phone_number_id: 'PNID-READY'))
      expect(resolved.account_id).to eq(setup.account_id)
      expect(resolved.inbox_id).to eq(setup.inbox_id)
      expect(resolved.channel_whatsapp_id).to eq(setup.channel_whatsapp_id)
    end

    it 'returns nil when no mapping matches the phone_number_id' do
      ready_setup(phone_number_id: 'PNID-READY')
      expect(described_class.resolve(meta_payload(phone_number_id: 'PNID-UNKNOWN'))).to be_nil
    end

    it 'returns nil when the mapping exists but is not ready_for_webhook' do
      channel = whatsapp_channel
      create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                        phone_number_id: 'PNID-CONFIGURED', setup_status: 'configured')
      expect(described_class.resolve(meta_payload(phone_number_id: 'PNID-CONFIGURED'))).to be_nil
    end

    it 'fails closed (nil) when a ready row is inconsistent (missing inbox/channel)' do
      setup = create(:bloomwire_whatsapp_setup, account: account, phone_number_id: 'PNID-BAD', setup_status: 'pending')
      # Force an inconsistent ready row past model validations to prove the resolver defends in depth.
      setup.update_columns(setup_status: 'ready_for_webhook', inbox_id: nil, channel_whatsapp_id: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.resolve(meta_payload(phone_number_id: 'PNID-BAD'))).to be_nil
    end

    it 'returns nil when the payload has no phone_number_id' do
      expect(described_class.resolve(meta_payload(phone_number_id: nil))).to be_nil
    end
  end

  describe '.resolve_handoff_safe_setup' do
    it 'resolves when the mapping and the native job channel-resolution path align' do
      setup, = aligned_setup(phone_number_id: 'PNID-OK')
      expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-OK'))).to eq(setup)
    end

    it 'fails closed when the channel provider_config phone_number_id does not match the setup' do
      _setup, channel = aligned_setup(phone_number_id: 'PNID-OK')
      channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => 'PNID-DIFFERENT'))
      expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-OK'))).to be_nil
    end

    it 'fails closed when the payload display_phone_number points to a different channel' do
      aligned_setup(phone_number_id: 'PNID-OK', display_phone_number: '15551230001')
      payload = meta_payload(phone_number_id: 'PNID-OK', display_phone_number: '19998887777')
      expect(described_class.resolve_handoff_safe_setup(payload)).to be_nil
    end

    it 'fails closed when the setup inbox does not match the channel inbox (forced past validations)' do
      setup, = aligned_setup(phone_number_id: 'PNID-OK')
      other_inbox = create(:inbox, account: account)
      setup.update_columns(inbox_id: other_inbox.id) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-OK'))).to be_nil
    end

    it 'fails closed when the mapped channel is missing (forced past validations)' do
      setup, = aligned_setup(phone_number_id: 'PNID-OK')
      setup.update_columns(channel_whatsapp_id: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-OK'))).to be_nil
    end

    it 'fails closed when the inbox is missing (forced past validations)' do
      setup, = aligned_setup(phone_number_id: 'PNID-OK')
      setup.update_columns(inbox_id: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-OK'))).to be_nil
    end
  end
end
