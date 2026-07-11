# Bloomwire global Meta WhatsApp webhook router endpoint (ADR-0005). A single endpoint that, when the
# router feature is ON, verifies the Meta signature, resolves a ready_for_webhook Bloomwire::WhatsappSetup
# by the payload's phone_number_id, and hands the raw payload to the EXISTING Webhooks::WhatsappEventsJob
# (the stock processing path — no new processing, no duplicate message/conversation storage). It fails
# closed otherwise and logs only redacted, non-secret diagnostics. With the feature OFF it is inert (404).
#
# GET serves Meta's webhook-callback verification handshake. Unlike the native per-channel endpoint (which
# keys on the :phone_number in the URL), this global front-door has no phone_number, so it validates a single
# global verify token (BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN). Verification needs no signature, no
# phone_number_id and no mapping; it never enqueues processing. Missing/wrong token fails closed (401).
class Bloomwire::Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :ensure_router_enabled
  before_action :verify_meta_signature!, only: :process_payload

  # GET: Meta webhook-callback verification. Echoes hub.challenge only for the configured global verify token.
  def verify
    if valid_token?(params['hub.verify_token'])
      Rails.logger.info('[BLOOMWIRE ROUTER] global webhook verification succeeded')
      render json: params['hub.challenge']
    else
      head :unauthorized
    end
  end

  def process_payload
    payload = params.to_unsafe_hash
    # Meta's Coexistence offboarding signal (account_update / PARTNER_REMOVED) is WABA-keyed (no message
    # phone_number_id), so it is reconciled here and NEVER handed to the message-only events job.
    return reconcile_account_update(payload) if account_update?(payload)

    # Only hand off when the existing job is guaranteed to re-resolve to this exact mapped channel/inbox.
    setup = Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(payload)

    if setup
      Webhooks::WhatsappEventsJob.perform_later(payload)
    else
      Rails.logger.info("[BLOOMWIRE ROUTER] no handoff-safe setup for phone_number_id #{redacted_phone_number_id(payload)}")
    end

    # Always 200 so Meta does not retry; routing decision is fail-closed above.
    head :ok
  end

  private

  # True when any change is an account_update (the Coexistence offboarding family, e.g. PARTNER_REMOVED). Safe
  # against a malformed payload (no raise) so an unexpected shape simply falls through to the message path.
  def account_update?(payload)
    entries = payload.is_a?(Hash) ? payload['entry'] : nil
    return false unless entries.is_a?(Array)

    entries.any? { |entry| account_update_entry?(entry) }
  end

  def account_update_entry?(entry)
    changes = entry.is_a?(Hash) ? entry['changes'] : nil
    changes.is_a?(Array) && changes.any? { |change| change.is_a?(Hash) && change['field'] == 'account_update' }
  end

  # Reconcile a Coexistence partner-removal (the authoritative offboarding owner) and acknowledge. The message
  # events job is NEVER enqueued here. Logs a sanitized summary only (masked WABA tail, affected count, reasons).
  def reconcile_account_update(payload)
    result = Bloomwire::Webhooks::PartnerRemovalReconciler.reconcile(payload)
    Rails.logger.info(
      "[BLOOMWIRE ROUTER] account_update reconciled affected=#{result.disconnected_setup_ids.size} " \
      "waba=#{redacted_waba_ids(result.waba_ids)} reasons=#{result.reasons.join(',').presence || '(none)'}"
    )
    head :ok
  end

  # Only a masked tail of each WABA id ever reaches the log — never the full WABA id.
  def redacted_waba_ids(waba_ids)
    return '(none)' if waba_ids.blank?

    waba_ids.map { |id| "****#{id.to_s.last(4)}" }.join(',')
  end

  def ensure_router_enabled
    head :not_found unless Bloomwire::Features.enabled?(:global_webhook_router)
  end

  # Validate Meta's hub.verify_token against the single global verify token. Fail-closed when the token is
  # not configured (blank) or blank. Constant-time compare; the token itself is never logged.
  def valid_token?(token)
    expected = GlobalConfigService.load('BLOOMWIRE_WHATSAPP_GLOBAL_VERIFY_TOKEN', nil)
    return false if expected.blank? || token.blank?

    ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected.to_s)
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
