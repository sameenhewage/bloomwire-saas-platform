# Bloomwire global Meta WhatsApp webhook router endpoint (ADR-0005). When the router feature is ON, it verifies
# the Meta signature, splits each batched entry/change exactly once, and separately owns two handoffs: authoritative
# account_update/PARTNER_REMOVED changes go to PartnerRemovalReconciler; every other handoff-safe single-change
# payload goes to the EXISTING Webhooks::WhatsappEventsJob (stock processing, no duplicate message/conversation
# storage). It fails closed otherwise and logs only redacted, non-secret diagnostics. Feature OFF is inert (404).
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
    # The native job reads only entry[0].changes[0], so route each non-account_update change as its own payload.
    # Route before reconciliation: PARTNER_REMOVED can make the same setup non-routeable within this batch.
    message_event_payloads(payload).each { |event_payload| handoff_message_event(event_payload) }

    removal_payload = partner_removed_payload(payload)
    reconcile_partner_removals(removal_payload) if removal_payload

    # Always 200 so Meta does not retry; each routing decision is fail-closed above.
    head :ok
  end

  private

  def message_event_payloads(payload)
    payload_entries(payload).flat_map do |entry|
      entry_changes(entry).filter_map do |change|
        next if change['field'] == 'account_update'

        single_change_payload(payload, entry, change)
      end
    end
  end

  def partner_removed_payload(payload)
    entries = payload_entries(payload).filter_map do |entry|
      changes = entry_changes(entry).select { |change| partner_removed?(change) }
      entry.merge('changes' => changes) if changes.any?
    end
    payload.merge('entry' => entries) if entries.any?
  end

  def partner_removed?(change)
    value = change['value']
    change['field'] == 'account_update' && value.is_a?(Hash) && value['event'] == 'PARTNER_REMOVED'
  end

  def payload_entries(payload)
    entries = payload.is_a?(Hash) ? payload['entry'] : nil
    entries.is_a?(Array) ? entries.select { |entry| entry.is_a?(Hash) } : []
  end

  def entry_changes(entry)
    changes = entry['changes']
    changes.is_a?(Array) ? changes.select { |change| change.is_a?(Hash) } : []
  end

  def single_change_payload(payload, entry, change)
    payload.merge('entry' => [entry.merge('changes' => [change])])
  end

  # Only hand off when the existing job is guaranteed to re-resolve to this exact mapped channel/inbox.
  def handoff_message_event(event_payload)
    setup = Bloomwire::Webhooks::WhatsappRouter.resolve_handoff_safe_setup(event_payload)
    return Webhooks::WhatsappEventsJob.perform_later(event_payload) if setup

    Rails.logger.info(
      "[BLOOMWIRE ROUTER] no handoff-safe setup for phone_number_id #{redacted_phone_number_id(event_payload)}"
    )
  end

  # Reconcile Coexistence partner removals from the account_update-only slice. The message events job never receives
  # this slice. Logs a sanitized summary only (masked WABA tail, affected count, reasons).
  def reconcile_partner_removals(payload)
    result = Bloomwire::Webhooks::PartnerRemovalReconciler.reconcile(payload)
    Rails.logger.info(
      "[BLOOMWIRE ROUTER] account_update reconciled affected=#{result.disconnected_setup_ids.size} " \
      "waba=#{redacted_waba_ids(result.waba_ids)} reasons=#{result.reasons.join(',').presence || '(none)'}"
    )
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
