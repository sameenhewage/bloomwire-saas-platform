# Bloomwire global Meta WhatsApp webhook router endpoint (ADR-0005). A single endpoint that, when the
# router feature is ON, verifies the Meta signature, resolves a ready_for_webhook Bloomwire::WhatsappSetup
# by the payload's phone_number_id, and hands the raw payload to the EXISTING Webhooks::WhatsappEventsJob
# (the stock processing path — no new processing, no duplicate message/conversation storage). It fails
# closed otherwise and logs only redacted, non-secret diagnostics. With the feature OFF it is inert (404).
class Bloomwire::Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :ensure_router_enabled
  before_action :verify_meta_signature!

  def process_payload
    payload = params.to_unsafe_hash
    setup = Bloomwire::Webhooks::WhatsappRouter.resolve(payload)

    if setup
      # Hand off to the existing Chatwoot WhatsApp processing path; it re-resolves to the mapped channel.
      Webhooks::WhatsappEventsJob.perform_later(payload)
    else
      Rails.logger.info("[BLOOMWIRE ROUTER] no routeable setup for phone_number_id #{redacted_phone_number_id(payload)}")
    end

    # Always 200 so Meta does not retry; routing decision is fail-closed above.
    head :ok
  end

  private

  def ensure_router_enabled
    head :not_found unless Bloomwire::Features.enabled?(:global_webhook_router)
  end

  # Verify the Meta signature against the global embedded-signup app secret (WHATSAPP_APP_SECRET). The global
  # endpoint cannot key on a per-channel secret (no phone_number in the URL) and must verify before routing.
  def meta_app_secrets
    [GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)]
  end

  # Only a masked tail of the routing id ever reaches the log — never full ids, tokens, or message content.
  def redacted_phone_number_id(payload)
    phone_number_id = Bloomwire::Webhooks::WhatsappRouter.phone_number_id_from(payload).to_s
    phone_number_id.empty? ? '(none)' : "****#{phone_number_id.last(4)}"
  end
end
