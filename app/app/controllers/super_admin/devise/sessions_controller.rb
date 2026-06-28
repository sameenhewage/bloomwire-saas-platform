# frozen_string_literal: true

class SuperAdmin::Devise::SessionsController < Devise::SessionsController
  def new
    self.resource = resource_class.new(sign_in_params)
  end

  def create
    redirect_to(super_admin_session_path, flash: { error: @error_message }) && return unless valid_credentials?

    # Phase 15A (ADR-0007): when Bloomwire Mode is ON, a SuperAdmin must also be an approved Bloomwire platform
    # admin. Refuse login (no session established) otherwise, with a non-secret message. Mode OFF => stock.
    if Bloomwire::Features.master_enabled? && !Bloomwire::PlatformAdmin.approved?(@super_admin)
      redirect_to(super_admin_session_path, flash: { error: I18n.t('bloomwire.platform_admin_required') }) && return
    end

    sign_in(:super_admin, @super_admin)
    flash.discard
    redirect_to super_admin_users_path
  end

  def destroy
    sign_out
    flash.discard
    redirect_to '/'
  end

  private

  def valid_credentials?
    @super_admin = SuperAdmin.find_by!(email: params[:super_admin][:email])
    raise StandardError, 'Invalid Password' unless @super_admin.valid_password?(params[:super_admin][:password])

    true
  rescue StandardError => e
    Rails.logger.error e.message
    @error_message = 'Invalid credentials. Please try again.'
    false
  end
end
