require 'rails_helper'

RSpec.describe ChatwootHub do
  describe 'installation identity and metrics' do
    it 'sync_with_hub does not POST and returns nil when isolation is enabled' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        allow(RestClient).to receive(:post)
        expect(described_class.sync_with_hub).to be_nil
        expect(RestClient).not_to have_received(:post)
      end
    end

    it 'register_instance does not POST installation metadata when isolation is enabled' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        allow(RestClient).to receive(:post)
        described_class.register_instance('Acme', 'Owner', 'owner@example.com')
        expect(RestClient).not_to have_received(:post)
      end
    end
  end

  describe 'pricing plan immutability' do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    it 'the hub response cannot set the pricing plan when isolation is enabled' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        allow(described_class).to receive(:sync_with_hub).and_return({ 'plan' => 'enterprise', 'plan_quantity' => 9 })
        Internal::CheckNewVersionsJob.perform_now
        expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')).to be_nil
        expect(InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')).to be_nil
      end
    end
  end

  describe 'OSS Chatwoot core models' do
    it 'still create and read accounts, inboxes, contacts, conversations, and messages' do
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        conversation = create(:conversation)
        message = create(:message, conversation: conversation)

        expect(Account.find(conversation.account_id)).to be_present
        expect(Inbox.find(conversation.inbox_id)).to be_present
        expect(Contact.find(conversation.contact_id)).to be_present
        expect(Conversation.find(conversation.id).messages).to include(message)
      end
    end
  end

  describe 'enterprise calling is not enabled' do
    before { allow(Rails.env).to receive(:production?).and_return(true) }

    it 'does not enable channel_voice when the daily job runs under isolation' do
      account = create(:account)
      with_modified_env BLOOMWIRE_DISABLE_CHATWOOT_HUB: 'true' do
        allow(described_class).to receive(:sync_with_hub).and_return({ 'version' => '1.2.3' })
        Internal::CheckNewVersionsJob.perform_now
      end
      expect(account.reload.feature_enabled?('channel_voice')).to be(false)
    end
  end
end
