require 'rails_helper'

# Phase 15F.1: owner-only "Send from Template" — fill variables, preview the branded email, send a REAL
# multipart email via the DB-backed SMTP settings, and record a per-send Email Log. Mode ON; fake values only.
# The mailer is stubbed on the delivery paths so no real SMTP connection is opened in the suite.
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

    it 'sends via the DB SMTP settings and records a SUCCESS delivery log' do
      configure_smtp!
      allow(Bloomwire::EmailTestMailer).to receive(:template_email).and_return(delivery)

      expect do
        post send_path, params: { compose: {
          recipient: 'jane@example.com', recipient_name: 'Jane Doe', business_name: 'Acme Co',
          invitation_link: 'https://app.bloomwire.lk/i/abc'
        } }
      end.to change(Bloomwire::EmailDeliveryLog, :count).by(1)

      expect(delivery).to have_received(:deliver_now)
      log = Bloomwire::EmailDeliveryLog.last
      expect(log.status).to eq('success')
      expect(log.recipient_email).to eq('jane@example.com')
      expect(log.template_name).to eq(template.name)
      expect(log.actor_id).to eq(owner.id)
      expect(response).to have_http_status(:redirect)
    end

    it 'replaces {{placeholders}} in the rendered subject/body/CTA before sending' do
      configure_smtp!
      sent = nil
      allow(Bloomwire::EmailTestMailer).to receive(:template_email) do |*args, **kwargs|
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
      expect(sent[:subject]).not_to include('{{')
      expect(sent[:cta_label]).to eq('Accept')
      expect(sent[:cta_url]).to eq('https://app.bloomwire.lk/i/abc') # {{invitation_link}} resolved
    end

    it 'records a FAILED log with a sanitized error and never leaks the password' do
      configure_smtp!
      allow(Bloomwire::EmailTestMailer).to receive(:template_email)
        .and_raise(StandardError.new("auth failed for #{smtp_password}"))

      post send_path, params: { compose: { recipient: 'jane@example.com', recipient_name: 'Jane' } }

      log = Bloomwire::EmailDeliveryLog.last
      expect(log.status).to eq('failed')
      expect(log.error_message).to include('[FILTERED]')
      expect(log.error_message).not_to include(smtp_password)
      expect(response.body).not_to include(smtp_password)
    end
  end

  describe 'honest blocking — creates a blocked log, never delivers' do
    before { sign_in(owner, scope: :super_admin) }

    it 'blocks a missing recipient' do
      configure_smtp!
      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      expect do
        post send_path, params: { compose: { recipient: '', recipient_name: 'Jane' } }
      end.to change { Bloomwire::EmailDeliveryLog.where(status: 'blocked').count }.by(1)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'blocks incomplete SMTP (missing password)' do
      configure_smtp!(password: nil)
      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      post send_path, params: { compose: { recipient: 'jane@example.com' } }
      expect(Bloomwire::EmailDeliveryLog.last.status).to eq('blocked')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'blocks disabled outbound email' do
      configure_smtp!(enabled: false)
      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      post send_path, params: { compose: { recipient: 'jane@example.com' } }
      log = Bloomwire::EmailDeliveryLog.last
      expect(log.status).to eq('blocked')
      expect(log.error_message).to match(/disabled/i)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe 'Email Logs tab' do
    before { sign_in(owner, scope: :super_admin) }

    it 'renders per-send rows with recipient, template name, and status' do
      configure_smtp!
      Bloomwire::EmailDeliveryLog.create!(
        email_template: template, template_key: template.key, template_name: template.name,
        recipient_email: 'logged@example.com', subject: 'Hi', status: 'success', actor_id: owner.id, sent_at: Time.current
      )
      get '/super_admin/bloomwire_email_settings?tab=email_logs'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('logged@example.com')
      expect(response.body).to include(template.name)
      expect(response.body).to include('Success')
    end
  end

  describe 'final preview (Update preview round-trip) matches the delivered shell' do
    before { sign_in(owner, scope: :super_admin) }

    it 'renders the branded preview using the owner-entered values' do
      configure_smtp!
      get '/super_admin/bloomwire_email_settings', params: {
        tab: 'templates', template_id: template.id,
        compose: { recipient: 'rita@example.com', recipient_name: 'Rita Roe', business_name: 'Globex LLC' }
      }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Rita Roe')          # entered {{recipient_name}}
      expect(response.body).to include('Globex LLC')         # entered {{business_name}}
      expect(response.body).to include('rita@example.com')   # pre-filled recipient + "Will send to"
      expect(response.body).to include('All rights reserved') # shared branded shell (same partial the mailer uses)
    end
  end

  describe 'access control + secret safety' do
    it 'bounces a non-owner, sends nothing, and writes no log' do
      configure_smtp!
      sign_in(non_owner_admin, scope: :super_admin)
      expect do
        post send_path, params: { compose: { recipient: 'jane@example.com' } }
      end.not_to change(Bloomwire::EmailDeliveryLog, :count)
      expect(response).to have_http_status(:redirect)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'bounces a non-owner from the Email Logs tab' do
      sign_in(non_owner_admin, scope: :super_admin)
      get '/super_admin/bloomwire_email_settings?tab=email_logs'
      expect(response).to have_http_status(:redirect)
    end

    it 'never renders the saved SMTP password in the composer or logs pages' do
      configure_smtp!
      sign_in(owner, scope: :super_admin)
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{template.id}"
      expect(response.body).to include('Send from Template')
      expect(response.body).not_to include(smtp_password)
      get '/super_admin/bloomwire_email_settings?tab=email_logs'
      expect(response.body).not_to include(smtp_password)
    end
  end
end
