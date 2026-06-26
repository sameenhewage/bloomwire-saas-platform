FactoryBot.define do
  factory :bloomwire_whatsapp_setup, class: 'Bloomwire::WhatsappSetup' do
    account
    setup_status { 'pending' }
  end
end
