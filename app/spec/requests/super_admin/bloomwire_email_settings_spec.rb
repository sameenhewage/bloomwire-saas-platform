require 'rails_helper'

# Phase 15F: owner-only Bloomwire Email Settings (DB-backed SMTP config + templates + test email).
# Mode ON; fake values only; the SMTP password must never be rendered back into the page.
RSpec.describe 'SuperAdmin Bloomwire Email Settings', type: :request do
  let(:owner) do
    sa = create(:super_admin, :unapproved_platform_admin)
    Bloomwire::PlatformAdmin.grant!(user: sa, role: :owner)
    sa
  end
  # create(:super_admin) auto-grants an *admin* approval row -> approved for /super_admin, but NOT an owner.
  let(:non_owner_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:business_admin) { create(:user, password: 'Password1!', account: account, role: :administrator) }

  before do
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = true
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
    ActionMailer::Base.deliveries.clear
    Bloomwire::EmailTemplate.seed_defaults!
  end

  describe 'access control (owner-only)' do
    it 'allows the platform owner' do
      sign_in(owner, scope: :super_admin)
      get '/super_admin/bloomwire_email_settings'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Email Settings')
      expect(response.body).to include('Owner only')
    end

    it 'bounces a non-owner platform admin' do
      sign_in(non_owner_admin, scope: :super_admin)
      get '/super_admin/bloomwire_email_settings'
      expect(response).to have_http_status(:redirect)
    end

    it 'blocks a business/customer account user' do
      sign_in(business_admin, scope: :user)
      get '/super_admin/bloomwire_email_settings'
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end
  end

  describe 'tabs' do
    before { sign_in(owner, scope: :super_admin) }

    %w[overview configuration templates test_email email_logs].each do |tab|
      it "renders the #{tab} tab" do
        get "/super_admin/bloomwire_email_settings?tab=#{tab}"
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'template preview (variable interpolation)' do
    it 'renders the selected template with sample variable data, not raw placeholders' do
      sign_in(owner, scope: :super_admin)
      template = Bloomwire::EmailTemplate.find_by(key: 'new_business_invitation')
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{template.id}"
      # The preview panel interpolates the sample variables...
      expect(response.body).to include('Sameen Hewage')        # {{recipient_name}} sample
      expect(response.body).to include('Bloomwire (Pvt) Ltd')  # {{business_name}} sample
      # ...while the editor textarea still shows the raw template with {{variables}} for editing.
      expect(response.body).to include('{{recipient_name}}')
    end
  end

  describe 'PATCH config (SMTP settings)' do
    before { sign_in(owner, scope: :super_admin) }

    it 'saves the settings and records the acting owner' do
      patch '/super_admin/bloomwire_email_settings/update_settings', params: { bloomwire_email_setting: {
        smtp_address: 'smtp.example.com', smtp_port: '2525', smtp_domain: 'example.com',
        smtp_username: 'u@example.com', smtp_password: 'topsecret', from_email: 'from@example.com', enabled: '1'
      } }
      setting = Bloomwire::EmailSetting.current
      expect(setting.smtp_address).to eq('smtp.example.com')
      expect(setting.smtp_port).to eq(2525)
      expect(setting.smtp_password).to eq('topsecret')
      expect(setting.enabled).to be(true)
      expect(setting.last_updated_by_id).to eq(owner.id)
    end

    it 'keeps the existing password when the field is blank (replace-secret behaviour)' do
      Bloomwire::EmailSetting.create!(Bloomwire::EmailSetting.default_attributes.merge(smtp_password: 'keepme'))
      patch '/super_admin/bloomwire_email_settings/update_settings',
            params: { bloomwire_email_setting: { smtp_address: 'smtp.new.com', smtp_password: '' } }
      expect(Bloomwire::EmailSetting.current.smtp_password).to eq('keepme')
      expect(Bloomwire::EmailSetting.current.smtp_address).to eq('smtp.new.com')
    end

    it 'never renders the saved password back into the page' do
      Bloomwire::EmailSetting.create!(Bloomwire::EmailSetting.default_attributes.merge(smtp_password: 'sup3rsecret'))
      get '/super_admin/bloomwire_email_settings?tab=configuration'
      expect(response.body).not_to include('sup3rsecret')
      expect(response.body).to include('Configured')
    end
  end

  describe 'template CRUD (owner-only)' do
    before { sign_in(owner, scope: :super_admin) }

    it 'creates a template' do
      expect do
        post '/super_admin/bloomwire_email_templates', params: { bloomwire_email_template: {
          name: 'Custom One', category: 'Support', subject: 'Hi {{recipient_name}}', body: 'Body {{business_name}}'
        } }
      end.to change(Bloomwire::EmailTemplate, :count).by(1)
    end

    it 'updates a template' do
      template = Bloomwire::EmailTemplate.find_by(key: 'welcome_email')
      patch "/super_admin/bloomwire_email_templates/#{template.id}",
            params: { bloomwire_email_template: { subject: 'Updated subject' } }
      expect(template.reload.subject).to eq('Updated subject')
    end

    it 'duplicates a template into an inactive copy' do
      template = Bloomwire::EmailTemplate.find_by(key: 'welcome_email')
      expect do
        post "/super_admin/bloomwire_email_templates/#{template.id}/duplicate"
      end.to change(Bloomwire::EmailTemplate, :count).by(1)
    end

    it 'deactivates and reactivates a template' do
      template = Bloomwire::EmailTemplate.find_by(key: 'welcome_email')
      patch "/super_admin/bloomwire_email_templates/#{template.id}/deactivate"
      expect(template.reload.active).to be(false)
      patch "/super_admin/bloomwire_email_templates/#{template.id}/reactivate"
      expect(template.reload.active).to be(true)
    end

    it 'bounces a non-owner from creating a template' do
      sign_in(non_owner_admin, scope: :super_admin)
      expect do
        post '/super_admin/bloomwire_email_templates',
             params: { bloomwire_email_template: { name: 'X', subject: 's', body: 'b' } }
      end.not_to change(Bloomwire::EmailTemplate, :count)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'POST test_email (preflight, no fake success)' do
    before { sign_in(owner, scope: :super_admin) }

    it 'blocks and does not deliver when the SMTP password is missing' do
      Bloomwire::EmailSetting.create!(Bloomwire::EmailSetting.default_attributes.merge(
                                        smtp_password: nil, smtp_address: 'h', smtp_domain: 'd',
                                        smtp_username: 'u', from_email: 'f@x.com'
                                      ))
      post '/super_admin/bloomwire_email_settings/test_email', params: { recipient: 'to@example.com' }
      expect(Bloomwire::EmailSetting.current.last_test_status).to eq('blocked_missing_config')
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
