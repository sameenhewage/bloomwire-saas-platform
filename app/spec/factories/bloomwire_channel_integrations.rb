# frozen_string_literal: true

FactoryBot.define do
  factory :bloomwire_channel_integration do
    transient do
      # A WhatsApp Cloud channel automatically creates its inbox (see the
      # channel_whatsapp factory) in the same account, so the integration links a
      # tenant-consistent profile -> account -> inbox -> channel by default.
      whatsapp_channel do
        association(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                       validate_provider_config: false, sync_templates: false, strategy: :create)
      end
    end

    account { association(:account, strategy: :create) }
    bloomwire_business_profile { association(:bloomwire_business_profile, account: account, strategy: :create) }

    inbox { whatsapp_channel.reload.inbox }
    channelable { whatsapp_channel }
    app_kind { 'whatsapp' }
    provider { whatsapp_channel.provider }
    status { 'active' }
    managed_by_bloomwire { true }
    sequence(:routing_key) { |n| "routing-key-#{n}" }
    phone_number { whatsapp_channel.phone_number }
    phone_number_id { whatsapp_channel.provider_config['phone_number_id'] }
    business_account_id { whatsapp_channel.provider_config['business_account_id'] }
  end
end
