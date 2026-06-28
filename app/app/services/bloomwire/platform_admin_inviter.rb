# Phase 15A.1 (ADR-0007): owner-only "add platform admin" flow (create + grant by email).
#
# Rules (see the platform-admin ADR):
# - Only an active OWNER may invite/grant.
# - New email      => create a fresh SuperAdmin + active approval row + send a safe reset-password email so they
#                     set their own password (no raw password is created in/returned to the UI).
# - Existing SuperAdmin => (re)grant/reactivate the approval row + set role (refuses demoting the last owner).
# - Existing BUSINESS/customer user (users.type = nil) => REFUSE. Never converts a business user into a
#                     SuperAdmin; business roles stay in account_users.role.
# No secrets/tokens/provider_config/full phone numbers are read or returned.
class Bloomwire::PlatformAdminInviter
  class Error < StandardError; end
  class NotAuthorizedError < Error; end
  class BusinessUserError < Error; end
  class InvalidInputError < Error; end

  def self.call(actor:, email:, name:, role:, reason:)
    new(actor: actor, email: email, name: name, role: role, reason: reason).call
  end

  def initialize(actor:, email:, name:, role:, reason:)
    @actor = actor
    @email = email.to_s.strip.downcase
    @name = name.to_s.strip
    @role = role.to_s
    @reason = reason.to_s.strip
  end

  def call
    authorize_actor!
    validate_input!

    existing = User.from_email(@email)
    if existing.nil?
      grant_new_super_admin!
    elsif existing.type == 'SuperAdmin'
      grant_existing_super_admin!(existing)
    else
      raise BusinessUserError, I18n.t('bloomwire.platform_admin.business_email_refused')
    end
  end

  private

  def authorize_actor!
    raise NotAuthorizedError, I18n.t('bloomwire.platform_admin.owner_only') unless owner_actor?
  end

  def owner_actor?
    @actor.present? && Bloomwire::PlatformAdmin.active_owners.exists?(user_id: @actor.id)
  end

  def validate_input!
    raise InvalidInputError, I18n.t('bloomwire.platform_admin.fields_required') if @name.blank? || @email.blank? || @reason.blank?
    raise InvalidInputError, I18n.t('bloomwire.platform_admin.invalid_role') unless Bloomwire::PlatformAdmin.roles.key?(@role)
    raise InvalidInputError, I18n.t('bloomwire.platform_admin.invalid_email') unless @email.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def grant_new_super_admin!
    user = create_super_admin!
    record = Bloomwire::PlatformAdmin.grant!(user: user, approved_by: @actor, role: @role, reason: @reason)
    send_password_setup(user)
    { created_user: true, user_id: user.id, role: record.role }
  end

  def grant_existing_super_admin!(user)
    refuse_demoting_last_owner!(user)
    record = Bloomwire::PlatformAdmin.grant!(user: user, approved_by: @actor, role: @role, reason: @reason)
    { created_user: false, user_id: user.id, role: record.role }
  end

  # Block changing the role of the last active owner to a non-owner role (would leave zero owners).
  def refuse_demoting_last_owner!(user)
    record = Bloomwire::PlatformAdmin.find_by(user_id: user.id)
    return if record.nil? || @role == 'owner'

    raise Error, I18n.t('bloomwire.platform_admin.last_owner_protected') if record.last_active_owner?
  end

  # Create a confirmed SuperAdmin with a throwaway password (never displayed). The new admin sets their own
  # password via the reset-password email below (or the "Forgot password?" link).
  def create_super_admin!
    password = "1!aA#{SecureRandom.alphanumeric(24)}"
    user = SuperAdmin.new(email: @email, name: @name, password: password, password_confirmation: password)
    user.skip_confirmation!
    user.save!
    user
  end

  # Best-effort: enqueue Devise reset-password instructions so the new admin can set a password. Email
  # delivery depends on the install's SMTP config; a failure here must not abort the grant.
  def send_password_setup(user)
    user.send_reset_password_instructions
  rescue StandardError => e
    Rails.logger.warn("[bloomwire] platform-admin reset-password enqueue failed: #{e.class}")
  end
end
