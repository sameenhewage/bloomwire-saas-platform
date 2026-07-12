require 'rails_helper'

# Coexistence offboarding reconciliation owner. Meta's authoritative offboarding signal is the
# account_update webhook with event=PARTNER_REMOVED (the Bloomwire Solution Partner was removed from the
# customer-owned WABA) — NOT the inverse of an onboarding-readiness GET. This reconciler is WABA-scoped: a
# partner removal revokes Bloomwire's access to the whole WABA, so EVERY coexistence setup under that WABA is
# proven affected. It is fail-closed (missing / ambiguous / unknown WABA change nothing), idempotent, never
# calls Meta, never /deregister, preserves the Channel/Inbox/Setup records, and never touches a Standard setup.
RSpec.describe Bloomwire::Webhooks::PartnerRemovalReconciler do
  let(:account) { create(:account) }

  def build_setup(waba_id:, phone_number_id:, connection_mode: 'coexistence',
                  status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS, display: '15551230001')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display}", sync_templates: false,
                                        validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge(
      'phone_number_id' => phone_number_id, 'business_account_id' => waba_id,
      'connection_mode' => connection_mode, 'source' => 'bloomwire_managed', 'api_key' => 'FAKE-STORED-TOKEN'
    ))
    create(:bloomwire_whatsapp_setup, account: account, inbox: channel.inbox, channel_whatsapp: channel,
                                      phone_number_id: phone_number_id, waba_id: waba_id,
                                      display_phone_number: "+#{display}", setup_status: status)
  end

  # entry.id is the WABA id for the whatsapp_business_account webhook object; value.waba_info.waba_id repeats it.
  # Pass entry_id/info_id explicitly to build the missing/ambiguous variants.
  def account_update_payload(entry_id: 'WABA-1', info_id: :same, event: 'PARTNER_REMOVED')
    resolved_info = info_id == :same ? entry_id : info_id
    value = { 'event' => event }
    value['waba_info'] = { 'waba_id' => resolved_info, 'owner_business_id' => 'BIZ-1' } unless resolved_info.nil?
    { 'object' => 'whatsapp_business_account',
      'entry' => [{ 'id' => entry_id, 'time' => 1_700_000_000,
                    'changes' => [{ 'field' => 'account_update', 'value' => value }] }] }
  end

  it 'marks the coexistence setup disconnected on PARTNER_REMOVED without any Meta call' do
    expect(Whatsapp::FacebookApiClient).not_to receive(:new)
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-1'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to contain_exactly(setup.id)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
    end
  end

  it 'marks ALL coexistence setups under one WABA (multiple numbers under the removed partner)' do
    a = build_setup(waba_id: 'WABA-M', phone_number_id: 'PNID-A', display: '15551230001')
    b = build_setup(waba_id: 'WABA-M', phone_number_id: 'PNID-B', display: '15551230002')

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-M'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to contain_exactly(a.id, b.id)
      expect(a.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
      expect(b.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
    end
  end

  it 'never modifies a Standard setup that happens to share the WABA' do
    standard = build_setup(waba_id: 'WABA-S', phone_number_id: 'PNID-STD', connection_mode: 'standard',
                           display: '15551230003')
    coexistence = build_setup(waba_id: 'WABA-S', phone_number_id: 'PNID-CO', display: '15551230004')

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-S'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to contain_exactly(coexistence.id)
      expect(standard.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
      expect(coexistence.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
    end
  end

  it 'changes nothing for an unrelated account_update event (not PARTNER_REMOVED)' do
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-1', event: 'ACCOUNT_VERIFIED'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to be_empty
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    end
  end

  it 'changes nothing when the WABA is ambiguous (entry.id and waba_info.waba_id disagree)' do
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-1', info_id: 'WABA-OTHER'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to be_empty
      expect(result.reasons).to include(:ambiguous_waba)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    end
  end

  it 'changes nothing when no WABA id can be resolved (missing identifiers)' do
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')

    result = described_class.reconcile(account_update_payload(entry_id: nil, info_id: nil))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to be_empty
      expect(result.reasons).to include(:missing_waba)
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    end
  end

  it 'changes nothing for an unknown WABA (no mapped setup)' do
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-UNKNOWN'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to be_empty
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::ROUTEABLE_STATUS)
    end
  end

  it 'is idempotent across duplicate deliveries (second delivery marks nothing, no error)' do
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')
    described_class.reconcile(account_update_payload(entry_id: 'WABA-1'))

    result = described_class.reconcile(account_update_payload(entry_id: 'WABA-1'))

    aggregate_failures do
      expect(result.disconnected_setup_ids).to be_empty
      expect(setup.reload.setup_status).to eq(Bloomwire::WhatsappSetup::DISCONNECTED_STATUS)
    end
  end

  it 'preserves the Channel / Inbox / Setup records (only the status changes)' do
    setup = build_setup(waba_id: 'WABA-1', phone_number_id: 'PNID-1')
    channel_id = setup.channel_whatsapp_id
    inbox_id = setup.inbox_id

    expect { described_class.reconcile(account_update_payload(entry_id: 'WABA-1')) }
      .to not_change(Bloomwire::WhatsappSetup, :count)
      .and not_change(Channel::Whatsapp, :count)
      .and not_change(Inbox, :count)

    aggregate_failures do
      expect(Channel::Whatsapp.exists?(channel_id)).to be(true)
      expect(Inbox.exists?(inbox_id)).to be(true)
      expect(Bloomwire::WhatsappSetup.exists?(setup.id)).to be(true)
    end
  end

  it 'does not raise for a malformed payload and returns an empty result' do
    aggregate_failures do
      expect { described_class.reconcile(nil) }.not_to raise_error
      expect(described_class.reconcile({}).disconnected_setup_ids).to be_empty
      expect(described_class.reconcile('entry' => 'not-an-array').disconnected_setup_ids).to be_empty
    end
  end
end
