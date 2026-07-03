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

  # Phase 17D.2 — WhatsApp Business App Coexistence webhook proof. A coexistence-created channel is a normal
  # whatsapp_cloud channel marked provider_config[source]=bloomwire_managed + [connection_mode]=coexistence.
  # The router keys ONLY on phone_number_id + channel alignment, so connection_mode never changes routing.
  describe 'coexistence routing (connection_mode=coexistence)' do
    def aligned_coexistence_setup(account:, phone_number_id:, display_phone_number:)
      channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          phone_number: "+#{display_phone_number}", sync_templates: false,
                                          validate_provider_config: false)
      channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => phone_number_id,
                                                                     'source' => 'bloomwire_managed',
                                                                     'connection_mode' => 'coexistence'))
      setup = create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                                phone_number_id: phone_number_id, setup_status: 'ready_for_webhook')
      [setup, channel]
    end

    it 'routes a coexistence channel by phone_number_id (connection_mode does not affect routing)' do
      setup, channel = aligned_coexistence_setup(account: account, phone_number_id: 'PNID-COEX',
                                                 display_phone_number: '15551230009')
      payload = meta_payload(phone_number_id: 'PNID-COEX', display_phone_number: '15551230009')
      aggregate_failures do
        expect(channel.provider_config['connection_mode']).to eq('coexistence')
        expect(described_class.resolve_handoff_safe_setup(payload)).to eq(setup)
      end
    end

    it 'routes a coexistence smb_message_echoes payload the same way (keys on metadata phone_number_id)' do
      setup, = aligned_coexistence_setup(account: account, phone_number_id: 'PNID-COEX',
                                         display_phone_number: '15551230009')
      echo = bw_echo_payload(phone_number_id: 'PNID-COEX', display_phone_number: '15551230009')
      expect(described_class.resolve_handoff_safe_setup(echo)).to eq(setup)
    end

    it 'does not route when the phone_number_id does not match the coexistence mapping' do
      aligned_coexistence_setup(account: account, phone_number_id: 'PNID-COEX', display_phone_number: '15551230009')
      payload = meta_payload(phone_number_id: 'PNID-WRONG', display_phone_number: '15551230009')
      expect(described_class.resolve_handoff_safe_setup(payload)).to be_nil
    end

    it 'is account-scoped: each coexistence payload resolves only to its own account mapping' do
      account_b = create(:account)
      setup_a, = aligned_coexistence_setup(account: account, phone_number_id: 'PNID-A', display_phone_number: '15551230001')
      setup_b, = aligned_coexistence_setup(account: account_b, phone_number_id: 'PNID-B', display_phone_number: '15551230002')

      resolved_a = described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-A', display_phone_number: '15551230001'))
      resolved_b = described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-B', display_phone_number: '15551230002'))

      aggregate_failures do
        expect(resolved_a).to eq(setup_a)
        expect(resolved_a.account_id).to eq(account.id)
        expect(resolved_b).to eq(setup_b)
        expect(resolved_b.account_id).to eq(account_b.id)
        expect(resolved_a.account_id).not_to eq(resolved_b.account_id)
      end
    end
  end

  # Phase 17E.1 — multiple WhatsApp inboxes within ONE account (ADR-0009). Each phone_number_id resolves to its
  # own inbox/channel; unknown pnid and crossed (pnid vs display) payloads fail closed; routing is
  # connection_mode-agnostic (a Standard and a Coexistence inbox coexist and each resolves correctly).
  describe 'multiple inboxes within a single account (Phase 17E.1 contract)' do
    it 'routes each phone_number_id to its own inbox/channel in the same account' do
      setup1, channel1 = aligned_setup(phone_number_id: 'PNID-1', display_phone_number: '15551230001')
      setup2, channel2 = aligned_setup(phone_number_id: 'PNID-2', display_phone_number: '15551230002')

      resolved1 = described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-1', display_phone_number: '15551230001'))
      resolved2 = described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-2', display_phone_number: '15551230002'))

      aggregate_failures do
        expect(resolved1).to eq(setup1)
        expect(resolved1.inbox_id).to eq(channel1.inbox.id)
        expect(resolved2).to eq(setup2)
        expect(resolved2.inbox_id).to eq(channel2.inbox.id)
        expect(resolved1.account_id).to eq(account.id)
        expect(resolved2.account_id).to eq(account.id)
        expect(resolved1.inbox_id).not_to eq(resolved2.inbox_id)
      end
    end

    it 'returns nil for an unknown phone_number_id even when the account already has other inboxes' do
      aligned_setup(phone_number_id: 'PNID-1', display_phone_number: '15551230001')
      aligned_setup(phone_number_id: 'PNID-2', display_phone_number: '15551230002')
      expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-UNKNOWN'))).to be_nil
    end

    it 'fails closed on a crossed payload (inbox-1 phone_number_id with inbox-2 display_phone_number)' do
      aligned_setup(phone_number_id: 'PNID-1', display_phone_number: '15551230001')
      aligned_setup(phone_number_id: 'PNID-2', display_phone_number: '15551230002')
      crossed = meta_payload(phone_number_id: 'PNID-1', display_phone_number: '15551230002')
      expect(described_class.resolve_handoff_safe_setup(crossed)).to be_nil
    end

    it 'routes a mix of Standard and Coexistence inboxes in one account (connection_mode does not affect routing)' do
      standard_setup, = aligned_setup(phone_number_id: 'PNID-STD', display_phone_number: '15551230003')
      # A coexistence inbox in the SAME account (source=bloomwire_managed + connection_mode=coexistence).
      coex_channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                               phone_number: '+15551230004', sync_templates: false,
                                               validate_provider_config: false)
      coex_channel.update!(provider_config: coex_channel.provider_config.merge('phone_number_id' => 'PNID-COEX',
                                                                               'source' => 'bloomwire_managed',
                                                                               'connection_mode' => 'coexistence'))
      coexistence_setup = create(:bloomwire_whatsapp_setup, account: account, inbox: coex_channel.inbox,
                                                            channel_whatsapp: coex_channel, phone_number_id: 'PNID-COEX',
                                                            setup_status: 'ready_for_webhook')
      aggregate_failures do
        expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-STD',
                                                                       display_phone_number: '15551230003'))).to eq(standard_setup)
        expect(described_class.resolve_handoff_safe_setup(meta_payload(phone_number_id: 'PNID-COEX',
                                                                       display_phone_number: '15551230004'))).to eq(coexistence_setup)
      end
    end
  end
end
