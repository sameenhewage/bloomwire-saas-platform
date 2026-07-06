require 'rails_helper'

# Advisory duplicate-number preflight. Returns ONLY the safe enum; mirrors the authoritative global uniqueness
# guard (Channel::Whatsapp#phone_number) and never mutates data.
RSpec.describe Bloomwire::WhatsappPhoneAvailability do
  let(:account) { create(:account) }

  def connect_number(phone_number, on: account)
    create(:channel_whatsapp, account: on, phone_number: phone_number,
                              sync_templates: false, validate_provider_config: false)
  end

  describe '.normalize' do
    it 'normalizes to +<digits>, consistent with Channel::Whatsapp / PhoneInfoService storage' do
      aggregate_failures do
        expect(described_class.normalize('+1 (555) 123-0001')).to eq('+15551230001')
        expect(described_class.normalize('15551230001')).to eq('+15551230001')
        expect(described_class.normalize('  +1.555.123.0001 ')).to eq('+15551230001')
        expect(described_class.normalize('')).to eq('')
        expect(described_class.normalize(nil)).to eq('')
      end
    end
  end

  describe '.status_for' do
    it 'returns "available" for a blank/nil number' do
      expect(described_class.status_for('')).to eq('available')
      expect(described_class.status_for(nil)).to eq('available')
    end

    it 'returns "available" when no channel has the number' do
      expect(described_class.status_for('+15551239999')).to eq('available')
    end

    it 'returns "already_connected" when a channel already has the number (any formatting)' do
      connect_number('+15551230001')
      aggregate_failures do
        expect(described_class.status_for('+1 555 123 0001')).to eq('already_connected')
        expect(described_class.status_for('15551230001')).to eq('already_connected')
        expect(described_class.status_for('+15551230001')).to eq('already_connected')
      end
    end

    # The check is GLOBAL (matches the authoritative guard) — a number connected on ANOTHER account is taken.
    it 'detects a number connected on a different account (global uniqueness)' do
      other = create(:account)
      connect_number('+15551230001', on: other)
      expect(described_class.status_for('+15551230001')).to eq('already_connected')
    end

    it 'is READ-ONLY — creates/modifies no records' do
      connect_number('+15551230001')
      expect { described_class.status_for('+15551230001') }
        .not_to(change { [Channel::Whatsapp.count, Inbox.count] })
    end

    it 'only ever returns the two safe enum values' do
      connect_number('+15551230001')
      expect(described_class.status_for('+15551230001')).to be_in(%w[available already_connected])
      expect(described_class.status_for('+15551239999')).to be_in(%w[available already_connected])
    end
  end
end
