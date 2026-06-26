require 'rails_helper'

# Phase 11A: Bloomwire-managed WhatsApp setup REQUEST (Ops intake). A separate, non-secret record that tracks
# the business request lifecycle (pending -> ... -> completed/blocked), kept distinct from the router/readiness
# Bloomwire::WhatsappSetup mapping (it may optionally link to one). One ACTIVE request per account. Fake data only.
RSpec.describe Bloomwire::WhatsappSetupRequest do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'statuses' do
    it 'exposes the exact intake statuses' do
      expect(described_class::STATUSES).to eq(%w[pending in_progress waiting_for_client ready_for_setup blocked completed])
    end

    it 'treats completed and blocked as closed (not active)' do
      expect(described_class::ACTIVE_STATUSES).not_to include('completed', 'blocked')
      expect(described_class::ACTIVE_STATUSES).to include('pending', 'in_progress', 'waiting_for_client', 'ready_for_setup')
    end

    it 'validates the status against the allowed set' do
      req = described_class.new(account: account, status: 'not_a_status')
      expect(req).not_to be_valid
      expect(req.errors[:status]).to be_present
    end
  end

  describe '.request_for (idempotent intake)' do
    it 'creates a pending request for the account' do
      req = described_class.request_for(account: account, requested_by: user)
      expect(req).to be_persisted
      expect(req.account_id).to eq(account.id)
      expect(req.requested_by_id).to eq(user.id)
      expect(req.status).to eq('pending')
    end

    it 'returns the existing active request instead of creating a duplicate' do
      first = described_class.request_for(account: account, requested_by: user)
      second = nil
      expect { second = described_class.request_for(account: account, requested_by: user) }.not_to change(described_class, :count)
      expect(second.id).to eq(first.id)
    end

    it 'allows a brand-new request once the previous one is completed' do
      first = described_class.request_for(account: account, requested_by: user)
      first.update!(status: 'completed')
      second = described_class.request_for(account: account, requested_by: user)
      expect(second.id).not_to eq(first.id)
      expect(second.status).to eq('pending')
    end

    it 'allows a brand-new request once the previous one is blocked' do
      first = described_class.request_for(account: account, requested_by: user)
      first.update!(status: 'blocked')
      second = described_class.request_for(account: account, requested_by: user)
      expect(second.id).not_to eq(first.id)
    end
  end

  describe 'one active request per account (DB partial unique index)' do
    it 'rejects a second active row for the same account at the database level (validation bypassed)' do
      described_class.create!(account: account, status: 'pending')
      duplicate = described_class.new(account: account, status: 'in_progress')
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'permits multiple closed (completed/blocked) rows for the same account' do
      described_class.create!(account: account, status: 'completed')
      expect { described_class.create!(account: account, status: 'blocked') }.not_to raise_error
    end
  end

  describe 'one active request per account (model validation, before DB)' do
    it 'allows a closed (completed) request to coexist with an active request' do
      described_class.create!(account: account, status: 'pending')
      coexisting = described_class.new(account: account, status: 'completed')
      expect(coexisting).to be_valid
    end

    it 'is invalid to reopen a closed request to an active status while another active request exists' do
      described_class.create!(account: account, status: 'pending')
      closed = described_class.create!(account: account, status: 'completed')
      closed.status = 'in_progress'
      expect(closed).not_to be_valid
      expect(closed.errors[:status]).to be_present
    end

    it 'allows reopening a closed request when no other active request exists' do
      closed = described_class.create!(account: account, status: 'completed')
      closed.status = 'in_progress'
      expect(closed).to be_valid
    end
  end

  describe 'status_reason + completed_at' do
    it 'persists an optional status reason' do
      req = described_class.create!(account: account, status: 'waiting_for_client', status_reason: 'awaiting Meta WABA from client')
      expect(req.reload.status_reason).to eq('awaiting Meta WABA from client')
    end

    it 'is valid without a status reason' do
      expect(described_class.new(account: account, status: 'pending')).to be_valid
    end

    it 'stamps completed_at when completed and clears it otherwise' do
      req = described_class.create!(account: account, status: 'pending')
      expect(req.completed_at).to be_nil
      req.update!(status: 'completed')
      expect(req.completed_at).to be_present
      req.update!(status: 'in_progress')
      expect(req.completed_at).to be_nil
    end
  end

  describe 'associations + no-secret storage' do
    it 'optionally links to a Bloomwire::WhatsappSetup mapping' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      req = described_class.create!(account: account, status: 'ready_for_setup', bloomwire_whatsapp_setup: setup)
      expect(req.reload.bloomwire_whatsapp_setup).to eq(setup)
    end

    it 'allows linking a setup mapping from the same account' do
      setup = create(:bloomwire_whatsapp_setup, account: account, setup_status: 'pending')
      req = described_class.new(account: account, status: 'ready_for_setup', bloomwire_whatsapp_setup: setup)
      expect(req).to be_valid
    end

    it 'rejects linking a setup mapping that belongs to another account' do
      other_account = create(:account)
      other_setup = create(:bloomwire_whatsapp_setup, account: other_account, setup_status: 'pending')
      req = described_class.new(account: account, status: 'ready_for_setup', bloomwire_whatsapp_setup: other_setup)
      expect(req).not_to be_valid
      expect(req.errors[:bloomwire_whatsapp_setup_id]).to include('must belong to the same account as the request')
    end

    it 'stores no secret columns' do
      secretish = described_class.column_names.grep(/api_key|token|secret|password|provider_config/i)
      expect(secretish).to be_empty
    end
  end
end
