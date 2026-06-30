# Phase 15F: owner-only CRUD for Bloomwire email templates (create / update / duplicate / deactivate /
# reactivate). All actions redirect back to the Email Settings "Email Templates" tab with the affected
# template selected. Template text is not a secret; no SMTP secrets are handled here.
class SuperAdmin::BloomwireEmailTemplatesController < SuperAdmin::ApplicationController
  include Bloomwire::RequiresPlatformOwner

  def create
    template = Bloomwire::EmailTemplate.new(template_params)
    template.key = unique_key_for(template.name) if template.key.blank?
    template.last_updated_by = current_super_admin

    if template.save
      redirect_to_template(template, notice: I18n.t('bloomwire.email_settings.template_created'))
    else
      redirect_to_template(nil, error: template.errors.full_messages.to_sentence)
    end
  end

  def update
    template = find_template
    if template.update(template_params.merge(last_updated_by: current_super_admin))
      redirect_to_template(template, notice: I18n.t('bloomwire.email_settings.template_saved'))
    else
      redirect_to_template(template, error: template.errors.full_messages.to_sentence)
    end
  end

  def duplicate
    copy = find_template.duplicate!(actor: current_super_admin)
    redirect_to_template(copy, notice: I18n.t('bloomwire.email_settings.template_duplicated'))
  end

  def deactivate
    template = find_template
    template.deactivate!(actor: current_super_admin)
    redirect_to_template(template, notice: I18n.t('bloomwire.email_settings.template_deactivated'))
  end

  def reactivate
    template = find_template
    template.activate!(actor: current_super_admin)
    redirect_to_template(template, notice: I18n.t('bloomwire.email_settings.template_reactivated'))
  end

  # Phase 15F.1: send a REAL HTML email rendered from the selected template + owner-supplied variable values.
  # Goes through SendTemplateEmailService (preflight + enabled-gate + per-send Email Log); the HTML body uses
  # the same shared partial as the composer preview, so the delivered email matches the preview. Never fakes
  # success; the SMTP password is never leaked.
  def send_email
    template = find_template
    # Phase 15F.2: render via the template's SINGLE composition resolver — the exact same one the live "Final
    # preview" uses — so the delivered email matches the preview. Blank/unfilled variables stay as
    # {{placeholders}} and are blocked by SendTemplateEmailService preflight (never half-rendered).
    rendered = template.composition_for(compose_params)
    composition = Bloomwire::SendTemplateEmailService::Composition.new(
      template: template, recipient: compose_field(:recipient),
      subject: rendered[:subject], body: rendered[:body],
      cta_label: rendered[:cta_label], cta_url: rendered[:cta_url]
    )
    result = Bloomwire::SendTemplateEmailService.new(
      setting: Bloomwire::EmailSetting.current, composition: composition, actor: current_super_admin
    ).call

    flash_key = { 'success' => :notice, 'blocked' => :warning }.fetch(result.status, :error)
    redirect_to_template(template, flash_key => result.message)
  end

  private

  def find_template
    Bloomwire::EmailTemplate.find(params[:id])
  end

  def compose_field(name)
    params.dig(:compose, name).to_s
  end

  # The raw submitted composer params (variable values + recipient + button overrides). Passed to the
  # template's composition resolver so preview and send resolve identically (Phase 15F.2).
  def compose_params
    params[:compose].is_a?(ActionController::Parameters) ? params[:compose] : ActionController::Parameters.new
  end

  def redirect_to_template(template, flash_hash)
    redirect_to super_admin_bloomwire_email_settings_path(tab: 'templates', template_id: template&.id), flash: flash_hash
  end

  # NOTE: `:key` is intentionally NOT permitted. Keys are auto-generated on create and are immutable
  # afterwards (system templates depend on stable keys for future routing). See Bloomwire::EmailTemplate.
  def template_params
    params.require(:bloomwire_email_template).permit(:name, :category, :subject, :body, :cta_label, :cta_url)
  end

  def unique_key_for(name)
    base = name.to_s.parameterize(separator: '_').presence || 'template'
    key = base
    i = 1
    key = "#{base}_#{i += 1}" while Bloomwire::EmailTemplate.exists?(key: key)
    key
  end
end
