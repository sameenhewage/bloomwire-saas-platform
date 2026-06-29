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

  # Phase 15F.1: composer context — recipient + variable values + CTA, pre-filled from sample data / the
  # template's CTA, and overridden by any submitted `compose` params (the "Update preview" round-trip).
  def build_compose(template)
    submitted = compose_params
    vars = compose_vars_with_defaults(submitted)
    {
      recipient: submitted[:recipient].presence || current_super_admin&.email,
      vars: vars,
      button_label: submitted[:button_label].presence || template&.cta_label,
      button_link: submitted[:button_link].presence || default_button_link(template, vars)
    }
  end

  def compose_params
    params[:compose].is_a?(ActionController::Parameters) ? params[:compose] : ActionController::Parameters.new
  end

  def compose_vars_with_defaults(submitted)
    Bloomwire::EmailTemplate::VARIABLES.index_with { |v| submitted[v].presence || Bloomwire::EmailTemplate::SAMPLE_VARS[v] }
  end

  def default_button_link(template, vars)
    template&.cta? ? template.render_cta_url(vars) : nil
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
