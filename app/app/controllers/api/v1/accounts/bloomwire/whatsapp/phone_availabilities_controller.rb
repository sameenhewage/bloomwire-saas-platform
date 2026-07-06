# Advisory duplicate-number preflight for the managed WhatsApp onboarding wizard. Admin-only; inert (404) unless
# managed WhatsApp self-serve is active; account-scoped auth. Returns ONLY { status: "available" | "already_connected" }
# — never the owning account/inbox/channel id or name, phone_number_id, WABA id, or any credential (no tenant leak).
# Advisory only: the authoritative global duplicate guard still runs after the Meta callback in the signup service.
class Api::V1::Accounts::Bloomwire::Whatsapp::PhoneAvailabilitiesController < Api::V1::Accounts::BaseController
  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?

  def create
    render json: { status: ::Bloomwire::WhatsappPhoneAvailability.status_for(params[:phone_number]) }
  end

  private

  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end
end
