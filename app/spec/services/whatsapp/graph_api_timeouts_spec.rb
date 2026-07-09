require 'rails_helper'

# Slice 5 (ADR-0010 v3): the single, config-driven source of truth for the Meta Graph open/read timeouts. The
# async onboarding lease budget derives from this same provider (see the model spec), so a change here moves the
# lease. Runtime validation clamps non-positive/blank config to the safe default.
RSpec.describe Whatsapp::GraphApiTimeouts do
  it 'defaults to the safe open/read seconds when unconfigured' do
    allow(GlobalConfigService).to receive(:load).with(described_class::OPEN_TIMEOUT_KEY, described_class::DEFAULT_OPEN_SECONDS)
                                                .and_return(described_class::DEFAULT_OPEN_SECONDS)
    allow(GlobalConfigService).to receive(:load).with(described_class::READ_TIMEOUT_KEY, described_class::DEFAULT_READ_SECONDS)
                                                .and_return(described_class::DEFAULT_READ_SECONDS)
    aggregate_failures do
      expect(described_class.open_seconds).to eq(described_class::DEFAULT_OPEN_SECONDS)
      expect(described_class.read_seconds).to eq(described_class::DEFAULT_READ_SECONDS)
      expect(described_class.max_call_seconds).to eq(described_class::DEFAULT_OPEN_SECONDS + described_class::DEFAULT_READ_SECONDS)
    end
  end

  it 'reads configured open/read timeouts (single source the lease derives from)' do
    allow(GlobalConfigService).to receive(:load).with(described_class::OPEN_TIMEOUT_KEY, described_class::DEFAULT_OPEN_SECONDS).and_return('8')
    allow(GlobalConfigService).to receive(:load).with(described_class::READ_TIMEOUT_KEY, described_class::DEFAULT_READ_SECONDS).and_return('40')
    aggregate_failures do
      expect(described_class.open_seconds).to eq(8)
      expect(described_class.read_seconds).to eq(40)
      expect(described_class.max_call_seconds).to eq(48)
    end
  end

  it 'clamps a non-positive or blank config to the safe default (runtime validation)' do
    allow(GlobalConfigService).to receive(:load).with(described_class::OPEN_TIMEOUT_KEY, described_class::DEFAULT_OPEN_SECONDS).and_return('0')
    allow(GlobalConfigService).to receive(:load).with(described_class::READ_TIMEOUT_KEY, described_class::DEFAULT_READ_SECONDS).and_return('')
    aggregate_failures do
      expect(described_class.open_seconds).to eq(described_class::DEFAULT_OPEN_SECONDS)
      expect(described_class.read_seconds).to eq(described_class::DEFAULT_READ_SECONDS)
    end
  end
end
