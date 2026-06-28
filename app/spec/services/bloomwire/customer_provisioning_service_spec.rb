require 'rails_helper'

# Phase 14 S3 — Ops customer provisioning orchestration. Creates Account + Business Owner (admin) + optional
# agents + a credential-less WhatsApp shell channel + inbox + Bloomwire::WhatsappSetup mapping, in one
# transaction, with NO Meta calls, NO access token, and NO invitation emails. Fake values only.
RSpec.describe Bloomwire::CustomerProvisioningService do
  include ActiveJob::TestHelper

  # Counts only the mail jobs enqueued by the given block (clears the queue first so fixture-created
  # unconfirmed users' confirmation mails don't leak into the count).
  def mail_jobs_enqueued_by
    clear_enqueued_jobs
    yield
    enqueued_jobs.count { |job| job[:job].to_s.include?('Mail') }
  end

  let(:base_attrs) do
    {
      account_name: 'Aroma Flora',
      owner_email: 'owner@example.com',
      owner_name: 'Flora Owner',
      display_phone_number: '15551239999',
      phone_number_id: 'PNID-S3-1',
      business_account_id: 'WABA-S3-1'
    }
  end

  def provision(attrs = {})
    described_class.new(base_attrs.merge(attrs)).perform
  end

  describe 'happy path' do
    it 'creates account + confirmed admin owner with no invitation email' do
      result = nil
      mail_count = mail_jobs_enqueued_by { result = provision }
      owner_au = AccountUser.find_by(account: result[:account], user: result[:owner])
      expect(result[:account]).to be_persisted
      expect(owner_au.role).to eq('administrator')
      expect(result[:owner].confirmed?).to be(true) # confirmed => Devise sends nothing
      expect(mail_count).to eq(0)
    end

    it 'creates a credential-less whatsapp_cloud shell channel (no api_key)' do
      channel = provision[:channel]
      expect(channel.provider).to eq('whatsapp_cloud')
      expect(channel.phone_number).to eq('+15551239999')
      expect(channel.provider_config['phone_number_id']).to eq('PNID-S3-1')
      expect(channel.provider_config['business_account_id']).to eq('WABA-S3-1')
      expect(channel.provider_config['source']).to eq('bloomwire_managed')
      expect(channel.provider_config).not_to have_key('api_key')
    end

    it 'creates the inbox linked to the shell channel + account' do
      result = provision
      expect(result[:inbox].channel).to eq(result[:channel])
      expect(result[:inbox].account).to eq(result[:account])
    end

    it 'creates a configured setup mapping aligned with the channel' do
      result = provision
      setup = result[:setup]
      expect(setup.setup_status).to eq('configured')
      expect(setup.account).to eq(result[:account])
      expect(setup.inbox).to eq(result[:inbox])
      expect(setup.channel_whatsapp).to eq(result[:channel])
      expect(setup.phone_number_id).to eq(result[:channel].provider_config['phone_number_id'])
      expect(result[:channel].phone_number).to eq("+#{setup.display_phone_number}")
    end

    it 'makes NO call to graph.facebook.com' do
      provision
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'agents' do
    it 'creates confirmed agents (no email), links them as agents, and adds them to the inbox' do
      result = nil
      mail_count = mail_jobs_enqueued_by { result = provision(agent_emails: 'a1@example.com, a2@example.com') }
      expect(result[:agents].map(&:email)).to contain_exactly('a1@example.com', 'a2@example.com')
      result[:agents].each do |agent|
        expect(agent.confirmed?).to be(true)
        expect(AccountUser.find_by(account: result[:account], user: agent).role).to eq('agent')
        expect(InboxMember.exists?(inbox: result[:inbox], user: agent)).to be(true)
      end
      expect(mail_count).to eq(0)
    end

    it 'skips an agent email that duplicates the owner' do
      result = provision(agent_emails: 'owner@example.com')
      expect(result[:agents]).to be_empty
    end
  end

  describe 'existing users (confirm in place, never email)' do
    it 'confirms an existing unconfirmed agent, links them, and adds them to the inbox' do
      agent = create(:user, skip_confirmation: false, email: 'existing-agent@example.com')
      expect(agent.confirmed?).to be(false)

      result = provision(agent_emails: agent.email)

      expect(agent.reload.confirmed?).to be(true)
      expect(AccountUser.find_by(account: result[:account], user: agent).role).to eq('agent')
      expect(InboxMember.exists?(inbox: result[:inbox], user: agent)).to be(true)
    end

    it 'confirms an existing unconfirmed owner and links them as administrator' do
      owner = create(:user, skip_confirmation: false, email: 'existing-owner@example.com')
      expect(owner.confirmed?).to be(false)

      result = provision(owner_email: owner.email)

      expect(owner.reload.confirmed?).to be(true)
      expect(AccountUser.find_by(account: result[:account], user: owner).role).to eq('administrator')
    end

    it 'sends no email when confirming existing unconfirmed owner + agent' do
      owner = create(:user, skip_confirmation: false, email: 'existing-owner@example.com')
      agent = create(:user, skip_confirmation: false, email: 'existing-agent@example.com')

      expect(mail_jobs_enqueued_by { provision(owner_email: owner.email, agent_emails: agent.email) }).to eq(0)
    end

    it 'leaves an existing confirmed user confirmed (no change, no email)' do
      user = create(:user, email: 'already-confirmed@example.com') # factory confirms by default
      original_confirmed_at = user.confirmed_at

      expect(mail_jobs_enqueued_by { provision(agent_emails: user.email) }).to eq(0)
      expect(user.reload.confirmed?).to be(true)
      expect(user.confirmed_at).to be_within(1.second).of(original_confirmed_at)
    end

    it 'makes no graph.facebook.com call when linking existing users' do
      agent = create(:user, skip_confirmation: false, email: 'existing-agent@example.com')
      provision(agent_emails: agent.email)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'stores no api_key/token on the shell channel when linking existing users' do
      agent = create(:user, skip_confirmation: false, email: 'existing-agent@example.com')
      result = provision(agent_emails: agent.email)
      expect(result[:channel].provider_config).not_to have_key('api_key')
    end
  end

  describe 'validation + uniqueness (fail closed, no partial records)' do
    it 'raises when a required field is missing and creates nothing' do
      expect { described_class.new(base_attrs.merge(account_name: '')).perform }
        .to raise_error(described_class::ProvisioningError, /Account name/)
      expect(Account.where(name: '').count).to eq(0)
    end

    it 'raises when the channel phone number already exists' do
      create(:channel_whatsapp, phone_number: '+15551239999', provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
      expect { provision }.to raise_error(described_class::ProvisioningError, /phone number already exists/)
    end

    it 'raises when the phone_number_id is already mapped' do
      account = create(:account)
      create(:bloomwire_whatsapp_setup, account: account, phone_number_id: 'PNID-S3-1', setup_status: 'pending')
      expect { provision }.to raise_error(described_class::ProvisioningError, /Phone Number ID already exists/)
    end

    it 'rolls back fully on a mid-transaction failure (no orphan account)' do
      allow(Bloomwire::WhatsappSetup).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Bloomwire::WhatsappSetup.new))
      expect { provision }.to raise_error(described_class::ProvisioningError)
      expect(Account.exists?(name: 'Aroma Flora')).to be(false)
      expect(Channel::Whatsapp.exists?(phone_number: '+15551239999')).to be(false)
      expect(User.exists?(email: 'owner@example.com')).to be(false)
    end
  end
end
