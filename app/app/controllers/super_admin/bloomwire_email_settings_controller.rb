# Phase 15F: owner-only Bloomwire Email Settings page (DB-backed SMTP config + email templates + test email).
# Inherits the SuperAdmin auth chain and ADDS the owner-only gate. The SMTP password is write-only from the
# UI's perspective: it is never rendered back, and a blank submission keeps the stored value ("replace secret").
class SuperAdmin::BloomwireEmailSettingsController < SuperAdmin::ApplicationController
  include Bloomwire::RequiresPlatformOwner

  TABS = %w[overview configuration templates test_email email_logs].freeze

  def show
    @active_tab = TABS.include?(params[:tab]) ? params[:tab] : 'overview'
    @email_setting = Bloomwire::EmailSetting.current
    @all_templates = Bloomwire::EmailTemplate.ordered.to_a
    @templates = filtered_templates(@all_templates)
    @categories = Bloomwire::EmailTemplate::CATEGORIES
    @selected_template = find_selected_template
    @new_template = params[:new].present?
    @sample_vars = Bloomwire::EmailTemplate::SAMPLE_VARS
    @compose = build_compose(@selected_template) # Phase 15F.1: "Send from Template" composer context
    # Phase 15F.3: latest per-template send result, shown in the composer-local feedback banner after a send.
    if @active_tab == 'templates' && @selected_template
      @composer_last_log = Bloomwire::EmailDeliveryLog.where(email_template_id: @selected_template.id).recent.first
    end
    @delivery_logs = Bloomwire::EmailDeliveryLog.recent.includes(:actor).limit(50) if @active_tab == 'email_logs'
  end

  # PATCH: persist SMTP/email configuration. Blank password => keep the existing secret (replace-secret UX).
  # NOTE: do not name this action `config` — that collides with the reserved Rails controller `config` method.
  def update_settings
    setting = Bloomwire::EmailSetting.current
    attrs = settings_params.to_h
    attrs.delete('smtp_password') if attrs['smtp_password'].blank?
    setting.assign_attributes(attrs)
    setting.last_updated_by = current_super_admin

    if setting.save
      redirect_to_tab('configuration', notice: I18n.t('bloomwire.email_settings.config_saved'))
    else
      redirect_to_tab('configuration', error: setting.errors.full_messages.to_sentence.presence || I18n.t('bloomwire.email_settings.config_error'))
    end
  end

  # POST: owner-initiated test email. Preflight-validated; never fakes success (see SendTestEmailService).
  def test_email
    setting = Bloomwire::EmailSetting.current
    result = Bloomwire::SendTestEmailService.new(
      setting: setting, recipient: params[:recipient], actor: current_super_admin
    ).call

    flash_key = { 'success' => :notice, 'blocked_missing_config' => :warning }.fetch(result.status, :error)
    redirect_to_tab('test_email', flash_key => result.message)
  end

  private

  def filtered_templates(list)
    result = list
    if params[:q].present?
      q = params[:q].to_s.downcase
      result = result.select { |t| t.name.to_s.downcase.include?(q) }
    end
    result = result.select { |t| t.category == params[:category] } if params[:category].present?
    result
  end

  def find_selected_template
    return Bloomwire::EmailTemplate.find_by(id: params[:template_id]) if params[:template_id].present?

    @templates.first || @all_templates.first
  end

  # Phase 15F.2: composer context for the selected template. Generates an input for EVERY variable the template
  # actually uses (incl. custom ones), and renders the "Final preview" through the template's SINGLE composition
  # resolver — the same one the send uses — so the preview equals the delivered email. Blank variables render as
  # visible {{placeholders}} and are reported in :missing for the inline "fill these in" warning + send block.
  def build_compose(template)
    return {} unless template

    submitted = compose_params
    fields = compose_field_values(template, submitted)
    recipient = submitted[:recipient].presence || current_super_admin&.email
    effective = fields.merge(
      'recipient' => recipient,
      'button_label' => (submitted[:button_label].presence || template.cta_label),
      'button_link' => (submitted[:button_link].presence || template.cta_url)
    )
    rendered = template.composition_for(effective)
    {
      recipient: recipient, fields: fields,
      button_label: effective['button_label'], button_link: effective['button_link'],
      subject: rendered[:subject], body: rendered[:body], cta_label: rendered[:cta_label],
      cta_url: rendered[:cta_url], missing: rendered[:missing_variables]
    }
  end

  # Input field values for the composer = EXACTLY what the owner submitted (blank until they fill them in).
  # Phase 15F.2 (review): SAMPLE_VARS are NEVER used as actual input values — only as placeholder/helper text in
  # the view and in the separate "Sample preview" panel. This keeps sample data out of the real send flow, so a
  # fresh composer opens with empty variables and the Send button stays disabled until every variable is filled.
  def compose_field_values(template, submitted)
    template.used_variables.index_with { |v| submitted[v].to_s }
  end

  def compose_params
    params[:compose].is_a?(ActionController::Parameters) ? params[:compose] : ActionController::Parameters.new
  end

  def redirect_to_tab(tab, flash_hash)
    redirect_to super_admin_bloomwire_email_settings_path(tab: tab), flash: flash_hash
  end

  def settings_params
    params.require(:bloomwire_email_setting).permit(
      :smtp_address, :smtp_port, :smtp_domain, :smtp_username, :smtp_password, :smtp_authentication,
      :smtp_enable_starttls_auto, :smtp_tls, :smtp_ssl, :from_name, :from_email, :reply_to_email, :enabled
    )
  end
end
