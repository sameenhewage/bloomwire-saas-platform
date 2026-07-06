# Advisory duplicate-number preflight for the managed WhatsApp onboarding wizard. Admin-only; inert (404) unless
# managed WhatsApp self-serve is active; account-scoped auth. Returns ONLY { status: "available" | "already_connected" }
# — never the owning account/inbox/channel id or name, phone_number_id, WABA id, or any credential (no tenant leak).
# Advisory only: the authoritative global duplicate guard still runs after the Meta callback in the signup service.
class Api::V1::Accounts::Bloomwire::Whatsapp::PhoneAvailabilitiesController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?
  before_action :enforce_rate_limit!

  # The endpoint answers a GLOBAL "is this number connected?" question, so — even though it returns only a safe
  # enum — it is throttled per (account, actor) to prevent an administrator enumerating arbitrary numbers. 429 on excess.
  RATE_LIMIT = 20
  RATE_PERIOD = 60 # seconds

  def create
    # `params[:phone_number]` is filtered from request logs (config.filter_parameters); the service never logs it.
    render json: { status: ::Bloomwire::WhatsappPhoneAvailability.status_for(params[:phone_number]) }
  end

  private

  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end

  def enforce_rate_limit!
    key = "bloomwire:phone_availability:#{Current.account.id}:#{Current.user&.id}"
    count = Rails.cache.increment(key, 1, expires_in: RATE_PERIOD.seconds)
    # Best-effort abuse protection: a cache store without atomic increment (returns nil) fails OPEN — the limiter
    # must not block a legitimate check, and it is not a security control (admin + account scope are).
    return if count.nil?

    head :too_many_requests if count.to_i > RATE_LIMIT
  end
end
