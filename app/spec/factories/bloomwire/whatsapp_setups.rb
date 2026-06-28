FactoryBot.define do
  factory :bloomwire_whatsapp_setup, class: 'Bloomwire::WhatsappSetup' do
    account
    setup_status { 'pending' }

    # Phase 12B — a fully-aligned, routeable mapping for the WhatsApp E2E harness. Creates a whatsapp_cloud
    # Channel::Whatsapp (+ its inbox) in the setup's account whose phone_number == "+<display_phone_number>"
    # and provider_config['phone_number_id'] == the setup's phone_number_id, so both
    # Bloomwire::Webhooks::WhatsappRouter (handoff-safe) and Bloomwire::WhatsappRealHopReadiness resolve it.
    # Override the aligned_* transients to vary the routing identifiers. Fake values only.
    trait :ready_for_webhook do
      transient do
        aligned_phone_number_id { 'PNID-READY-1' }
        aligned_display_phone_number { '15551230001' }
        aligned_api_key { 'FAKE-PROVIDER-API-KEY' }
      end

      setup_status { 'ready_for_webhook' }

      after(:build) do |setup, evaluator|
        channel = create(:channel_whatsapp, account: setup.account, provider: 'whatsapp_cloud',
                                            phone_number: "+#{evaluator.aligned_display_phone_number}",
                                            sync_templates: false, validate_provider_config: false)
        channel.update!(
          provider_config: channel.provider_config.merge(
            'phone_number_id' => evaluator.aligned_phone_number_id,
            'source' => 'embedded_signup',
            'api_key' => evaluator.aligned_api_key
          )
        )
        setup.channel_whatsapp = channel
        setup.inbox = channel.inbox
        setup.phone_number_id = evaluator.aligned_phone_number_id
        setup.display_phone_number = evaluator.aligned_display_phone_number
      end
    end
  end
end
