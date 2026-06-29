require 'rails_helper'

# Phase 15F.1: owner-only "Send from Template" composer — renders a template with owner-supplied variable
# values and sends a REAL email via the DB-backed SMTP settings. Mode ON; fake values only.
# The mailer is stubbed for the happy paths so no real SMTP connection is attempted in the test suite
# (the mailer forces :smtp delivery on the message; see Bloomwire::EmailTestMailer).
RSpec.describe 'SuperAdmin Bloomwire Send-from-Template', type: :request do
  let(:owner) do
    sa = create(:super_admin, :unapproved_platform_admin)
    Bloomwire::PlatformAdmin.grant!(user: sa, role: :owner)
    sa
  end
  let(:non_owner_admin) { create(:super_admin) }
  let(:template) { Bloomwire::EmailTemplate.find_by(key: 'new_business_invitation') }
  let(:delivery) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }
  let(:smtp_password) { 'sup3rsecret-pw-9' }

  def configure_smtp!(enabled: true, password: smtp_password)
    Bloomwire::EmailSetting.create!(
      Bloomwire::EmailSetting.default_attributes.merge(
        smtp_address: 'smtp.example.com', smtp_domain: 'example.com', smtp_username: 'u@example.com',
        smtp_password: password, from_email: 'from@example.com', enabled: enabled
      )
    )
  end

  def send_path(tpl = template)
    "/super_admin/bloomwire_email_templates/#{tpl.id}/send_email"
  end

  before do
    config = InstallationConfig.where(name: 'BLOOMWIRE_MODE_ENABLED').first_or_initialize
    config.value = true
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
    ActionMailer::Base.deliveries.clear
    Bloomwire::EmailTemplate.seed_defaults!
  end

  describe 'owner can send a real email from a template' do
    before { sign_in(owner, scope: :super_admin) }

    it 'sends via the DB SMTP settings and records success' do
      configure_smtp!
      sent = nil
      allow(Bloomwire::EmailTestMailer).to receive(:test_email) do |*args, **kwargs|
        sent = kwargs.any? ? kwargs : args.first
        delivery
      end

      post send_path, params: { compose: {
        recipient: 'jane@example.com', recipient_name: 'Jane Doe', business_name: 'Acme Co',
        invitation_link: 'https://app.bloomwire.lk/i/abc'
      } }

      expect(sent[:to]).to eq('jane@example.com')
      expect(sent[:setting]).to be_a(Bloomwire::EmailSetting)
      expect(delivery).to have_received(:deliver_now)
      expect(Bloomwire::EmailSetting.current.last_test_status).to eq('success')
      expect(response).to have_http_status(:redirect)
    end

    it 'replaces {{placeholders}} in the rendered subject/body before sending' do
      configure_smtp!
      sent = nil
      allow(Bloomwire::EmailTestMailer).to receive(:test_email) do |*args, **kwargs|
        sent = kwargs.any? ? kwargs : args.first
        delivery
      end

      post send_path, params: { compose: {
        recipient: 'jane@example.com', recipient_name: 'Jane Doe', business_name: 'Acme Co',
        invitation_link: 'https://app.bloomwire.lk/i/abc', button_label: 'Accept', button_link: '{{invitation_link}}'
      } }

      expect(sent[:body]).to include('Jane Doe')
      expect(sent[:body]).to include('Acme Co')
      expect(sent[:body]).not_to include('{{recipient_name}}')
      expect(sent[:body]).not_to include('{{business_name}}')
      # CTA line uses the composer button + the resolved {{invitation_link}}
      expect(sent[:body]).to include('Accept: https://app.bloomwire.lk/i/abc')
    end
  end

  describe 'honest blocking (never fakes success, no real send)' do
    before { sign_in(owner, scope: :super_admin) }

    it 'blocks when the recipient is missing (never attempts a send)' do
      configure_smtp!
      post send_path, params: { compose: { recipient: '', recipient_name: 'Jane' } }
      # Blank recipient is rejected at the first gate (before SMTP is touched), so status is never marked success.
      expect(Bloomwire::EmailSetting.current.last_test_status).not_to eq('success')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'blocks when SMTP is incomplete (missing password)' do
      configure_smtp!(password: nil)
      post send_path, params: { compose: { recipient: 'jane@example.com' } }
      expect(Bloomwire::EmailSetting.current.last_test_status).to eq('blocked_missing_config')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'blocks when outbound email is disabled' do
      configure_smtp!(enabled: false)
      post send_path, params: { compose: { recipient: 'jane@example.com' } }
      expect(Bloomwire::EmailSetting.current.last_test_status).to eq('blocked_missing_config')
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe 'final preview (Update preview round-trip)' do
    before { sign_in(owner, scope: :super_admin) }

    it 'renders the final preview using the owner-entered values, not the sample data' do
      configure_smtp!
      get '/super_admin/bloomwire_email_settings', params: {
        tab: 'templates', template_id: template.id,
        compose: { recipient: 'rita@example.com', recipient_name: 'Rita Roe', business_name: 'Globex LLC' }
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Rita Roe')        # {{recipient_name}} rendered with the entered value
      expect(response.body).to include('Globex LLC')       # {{business_name}} rendered with the entered value
      expect(response.body).to include('rita@example.com') # pre-filled recipient + "Will send to"
    end
  end

  describe 'access control + secret safety' do
    it 'bounces a non-owner and does not deliver' do
      configure_smtp!
      sign_in(non_owner_admin, scope: :super_admin)
      post send_path, params: { compose: { recipient: 'jane@example.com' } }
      expect(response).to have_http_status(:redirect)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'never renders the saved SMTP password in the composer page' do
      configure_smtp!
      sign_in(owner, scope: :super_admin)
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{template.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Send from Template')
      expect(response.body).to include('Send to email')
      expect(response.body).not_to include(smtp_password)
    end
  end
end
