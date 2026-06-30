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

  # Phase 15F.2: every variable the new_business_invitation template uses must be filled, otherwise the send is
  # blocked (no half-rendered emails). Used by the success/placeholder/failure paths.
  def full_invitation_vars
    { recipient_name: 'Jane Doe', business_name: 'Acme Co',
      invitation_link: 'https://app.bloomwire.lk/i/abc', expiry_time: '7 days' }
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
        post send_path, params: { compose: { recipient: 'jane@example.com', **full_invitation_vars } }
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
        recipient: 'jane@example.com', **full_invitation_vars, button_label: 'Accept', button_link: '{{invitation_link}}'
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

      post send_path, params: { compose: { recipient: 'jane@example.com', **full_invitation_vars } }

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

  describe 'Phase 15F.2 — dynamic variables, validation, and preview/send consistency' do
    before { sign_in(owner, scope: :super_admin) }

    it 'blocks the send when a required variable is left blank — never half-renders' do
      configure_smtp!
      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      expect do
        post send_path, params: { compose: {
          recipient: 'jane@example.com', recipient_name: 'Jane', business_name: 'Acme',
          invitation_link: 'https://x.test/i' # expiry_time intentionally omitted
        } }
      end.to change { Bloomwire::EmailDeliveryLog.where(status: 'blocked').count }.by(1)
      expect(Bloomwire::EmailDeliveryLog.last.error_message).to match(/variable|placeholder/i)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'blocks an invalid recipient email before any SMTP send' do
      configure_smtp!
      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      post send_path, params: { compose: { recipient: 'not-an-email', **full_invitation_vars } }
      log = Bloomwire::EmailDeliveryLog.last
      expect(log.status).to eq('blocked')
      expect(log.error_message).to match(/valid/i)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'delivers EXACTLY what composition_for renders (preview and send share one resolver)' do
      configure_smtp!
      sent = nil
      allow(Bloomwire::EmailTestMailer).to receive(:template_email) do |**kwargs|
        sent = kwargs
        delivery
      end
      submitted = { recipient: 'jane@example.com', **full_invitation_vars }
      post send_path, params: { compose: submitted }

      expected = template.composition_for(ActionController::Parameters.new(submitted).permit!)
      expect(sent[:subject]).to eq(expected[:subject])
      expect(sent[:body]).to eq(expected[:body])
      expect(sent[:cta_url]).to eq(expected[:cta_url])
      expect(sent[:body]).not_to match(/\{\{.*?\}\}/)
    end

    it 'generates a composer input for a CUSTOM variable, then previews and sends it' do
      configure_smtp!
      custom = Bloomwire::EmailTemplate.create!(
        key: 'qa_custom', name: 'QA Custom', subject: 'Order {{custom_order_id}}',
        body: 'Hi {{recipient_name}}, order {{custom_order_id}} is ready.', cta_label: 'View', cta_url: 'https://x.test/o'
      )
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{custom.id}"
      expect(response.body).to include('compose[custom_order_id]') # generated input field
      expect(response.body).to include('Custom order id')          # humanized label

      allow(Bloomwire::EmailTestMailer).to receive(:template_email).and_return(delivery)
      expect do
        post send_path(custom), params: { compose: {
          recipient: 'cory@example.com', recipient_name: 'Cory', custom_order_id: 'ORD-42'
        } }
      end.to change { Bloomwire::EmailDeliveryLog.where(status: 'success').count }.by(1)
      expect(Bloomwire::EmailDeliveryLog.last.subject).to eq('Order ORD-42') # custom var resolved
    end

    it 'shows the literal sent subject in the Email Logs tab' do
      configure_smtp!
      Bloomwire::EmailDeliveryLog.create!(
        email_template: template, template_key: template.key, template_name: template.name,
        recipient_email: 'logged@example.com', subject: 'Welcome ORD-99', status: 'success',
        actor_id: owner.id, sent_at: Time.current
      )
      get '/super_admin/bloomwire_email_settings?tab=email_logs'
      expect(response.body).to include('Welcome ORD-99')
    end

    it 'opens the composer with BLANK variable inputs on first load — sample data is placeholder-only' do
      configure_smtp!
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{template.id}"
      expect(response).to have_http_status(:success)
      # SAMPLE_VARS appear only as placeholder hints, NEVER as actual prefilled input values
      expect(response.body).to include('placeholder="Sameen Hewage"')   # SAMPLE_VARS['recipient_name'] as hint
      expect(response.body).not_to include('value="Sameen Hewage"')     # not prefilled as a real value
      expect(response.body).not_to include('value="Bloomwire (Pvt) Ltd"')
    end

    it 'keeps Send disabled on first load when the template has required variables' do
      configure_smtp!
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{template.id}"
      expect(response.body).to include('Fill in all variables before sending')         # inline missing-var warning
      expect(response.body).to include('The send button is disabled until every variable is filled')
      # the submit button is rendered in a disabled state (no intentional fill yet)
      expect(response.body).to match(/<input[^>]*value="Send Email"[^>]*disabled|<input[^>]*disabled[^>]*value="Send Email"/)
    end

    it 'blocks a first-load send (all variables blank) — never sends sample data' do
      configure_smtp!
      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      post send_path, params: { compose: { recipient: 'jane@example.com' } } # no variable values at all
      expect(Bloomwire::EmailDeliveryLog.last.status).to eq('blocked')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'detects a variable used ONLY in the CTA label: generates its input and blocks a blank send (review fix)' do
      configure_smtp!
      cta_tpl = Bloomwire::EmailTemplate.create!(
        key: 'qa_cta', name: 'QA CTA', subject: 'Hello there', body: 'Static body, no vars.',
        cta_label: 'Open {{business_name}}', cta_url: 'https://x.test/o'
      )
      get "/super_admin/bloomwire_email_settings?tab=templates&template_id=#{cta_tpl.id}"
      expect(response.body).to include('compose[business_name]') # input generated for a CTA-only variable
      expect(response.body).to include('Business name')

      expect(Bloomwire::EmailTestMailer).not_to receive(:template_email)
      post send_path(cta_tpl), params: { compose: { recipient: 'cta@example.com' } } # business_name blank
      expect(Bloomwire::EmailDeliveryLog.last.status).to eq('blocked')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'renders a filled CTA-label variable in the delivered email (preview == send for CTA label, review fix)' do
      configure_smtp!
      cta_tpl = Bloomwire::EmailTemplate.create!(
        key: 'qa_cta2', name: 'QA CTA 2', subject: 'Hello', body: 'Static body.',
        cta_label: 'Open {{business_name}}', cta_url: 'https://x.test/o'
      )
      sent = nil
      allow(Bloomwire::EmailTestMailer).to receive(:template_email) do |**kwargs|
        sent = kwargs
        delivery
      end
      submitted = { recipient: 'cta@example.com', business_name: 'Globex' }
      post send_path(cta_tpl), params: { compose: submitted }

      expected = cta_tpl.composition_for(ActionController::Parameters.new(submitted).permit!)
      expect(sent[:cta_label]).to eq('Open Globex')
      expect(sent[:cta_label]).to eq(expected[:cta_label])
      expect(sent[:cta_label]).not_to match(/\{\{.*?\}\}/)
    end
  end

  describe 'Phase 15F.3 — send feedback UX (visible result near composer)' do
    before { sign_in(owner, scope: :super_admin) }

    it 'success: redirects to the composer anchor with the template selected + visible success near composer' do
      configure_smtp!
      allow(Bloomwire::EmailTestMailer).to receive(:template_email).and_return(delivery)

      post send_path, params: { compose: { recipient: 'jane@example.com', **full_invitation_vars } }
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include("template_id=#{template.id}") # template stays selected
      expect(response.redirect_url).to include('#bw-composer')               # lands on the composer

      follow_redirect!
      expect(response.body).to include('id="bw-send-result"')                # composer-local result banner
      expect(response.body).to include('Email sent successfully to jane@example.com')
      expect(response.body).to include('View Email Logs')
      expect(Bloomwire::EmailDeliveryLog.where(status: 'success').count).to be >= 1
    end

    it 'blocked (missing variable): shows a visible "was not sent" message near the composer' do
      configure_smtp!
      expect do
        post send_path, params: { compose: { recipient: 'jane@example.com', recipient_name: 'Jane' } } # vars missing
      end.to change { Bloomwire::EmailDeliveryLog.where(status: 'blocked').count }.by(1)
      expect(response.redirect_url).to include('#bw-composer')
      follow_redirect!
      expect(response.body).to include('id="bw-send-result"')
      expect(response.body).to include('Email was not sent:')
    end

    it 'invalid email: shows a visible validation message near the composer' do
      configure_smtp!
      post send_path, params: { compose: { recipient: 'not-an-email', **full_invitation_vars } }
      expect(response.redirect_url).to include('#bw-composer')
      follow_redirect!
      expect(response.body).to include('id="bw-send-result"')
      expect(response.body).to match(/Email was not sent:.*valid/i)
    end

    it 'does not expose the SMTP password in the send-result response body' do
      configure_smtp!
      allow(Bloomwire::EmailTestMailer).to receive(:template_email).and_return(delivery)
      post send_path, params: { compose: { recipient: 'jane@example.com', **full_invitation_vars } }
      follow_redirect!
      expect(response.body).not_to include(smtp_password)
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
