# Coexistence offboarding reconciliation owner (ADR-0005 companion). Meta's AUTHORITATIVE offboarding signal is
# the account_update webhook with event=PARTNER_REMOVED — the Bloomwire Solution Partner was removed from the
# customer-owned WhatsApp Business Account. It is NOT inferred from the inverse of an onboarding-readiness GET
# (absence of is_on_biz_app+CLOUD_API does NOT prove offboarding). The signal is WABA-keyed, so this runs from the
# signed global front door (NEVER the message-only Webhooks::WhatsappEventsJob) and:
#   - resolves the WABA only from authoritative payload ids (value.waba_info.waba_id / entry.id) — fail-closed when
#     missing or ambiguous;
#   - a partner removal revokes access to the WHOLE WABA, so EVERY coexistence setup under that WABA is affected
#     (handles multiple numbers under one WABA);
#   - marks only the not-already-disconnected coexistence setups `disconnected` (idempotent), KEEPING every
#     Channel/Inbox/Setup record;
#   - NEVER touches a Standard setup, never calls Meta, never /deregister, never unsubscribes the shared webhook.
# It reads only non-secret mapping columns (waba_id) + the non-secret provider_config connection_mode marker; it
# stores nothing else and returns a Result the front door logs in sanitized form (masked WABA tail only).
class Bloomwire::Webhooks::PartnerRemovalReconciler
  ACCOUNT_UPDATE_FIELD = 'account_update'.freeze
  PARTNER_REMOVED_EVENT = 'PARTNER_REMOVED'.freeze
  COEXISTENCE_MODE = 'coexistence'.freeze

  Result = Struct.new(:disconnected_setup_ids, :waba_ids, :reasons, keyword_init: true)

  def self.reconcile(payload)
    new(payload).reconcile
  end

  def initialize(payload)
    @payload = payload
  end

  def reconcile
    ids = []
    wabas = []
    reasons = []
    partner_removed_changes.each do |entry, value|
      waba_id, skip_reason = resolve_waba_id(entry, value)
      if skip_reason
        reasons << skip_reason
        next
      end

      wabas << waba_id
      disconnected, outcome = disconnect_coexistence_under(waba_id)
      ids.concat(disconnected)
      reasons << outcome
    end
    Result.new(disconnected_setup_ids: ids.uniq, waba_ids: wabas.uniq, reasons: reasons)
  end

  private

  # [[entry, value], ...] for EVERY account_update change whose event is PARTNER_REMOVED. Defensive against a
  # non-hash / missing / non-array payload so a malformed webhook never raises (returns []).
  def partner_removed_changes
    payload_entries.flat_map do |entry|
      entry_changes(entry).filter_map { |change| [entry, change['value']] if partner_removed?(change) }
    end
  end

  def payload_entries
    entries = @payload.is_a?(Hash) ? @payload['entry'] : nil
    entries.is_a?(Array) ? entries : []
  end

  def entry_changes(entry)
    changes = entry.is_a?(Hash) ? entry['changes'] : nil
    changes.is_a?(Array) ? changes : []
  end

  def partner_removed?(change)
    return false unless change.is_a?(Hash) && change['field'] == ACCOUNT_UPDATE_FIELD

    value = change['value']
    value.is_a?(Hash) && value['event'] == PARTNER_REMOVED_EVENT
  end

  # entry.id is the WABA id for the whatsapp_business_account object; value.waba_info.waba_id repeats it. Fail
  # closed: both present but disagreeing => :ambiguous_waba (change nothing); neither present => :missing_waba.
  def resolve_waba_id(entry, value)
    entry_id = entry['id'].presence
    info_id = value.dig('waba_info', 'waba_id').presence
    return [nil, :missing_waba] if entry_id.nil? && info_id.nil?
    return [nil, :ambiguous_waba] if entry_id && info_id && entry_id != info_id

    [info_id || entry_id, nil]
  end

  # All coexistence setups under this WABA are proven affected. Mark the not-already-disconnected ones (idempotent)
  # while KEEPING every record; a Standard setup that happens to share the WABA is never modified.
  def disconnect_coexistence_under(waba_id)
    setups = Bloomwire::WhatsappSetup.where(waba_id: waba_id).to_a
    return [[], :unknown_waba] if setups.empty?

    coexistence = setups.select { |setup| coexistence?(setup) }
    return [[], :standard_only] if coexistence.empty?

    ids = coexistence.filter_map { |setup| disconnect(setup) }
    [ids, ids.empty? ? :already_disconnected : :reconciled]
  end

  def disconnect(setup)
    return if setup.setup_status == Bloomwire::WhatsappSetup::DISCONNECTED_STATUS

    setup.update!(setup_status: Bloomwire::WhatsappSetup::DISCONNECTED_STATUS, status_reason: nil)
    setup.id
  end

  # The non-secret provider_config connection_mode marker (same field the disconnect service + overview read).
  def coexistence?(setup)
    (setup.channel_whatsapp&.provider_config).to_h['connection_mode'].to_s == COEXISTENCE_MODE
  end
end
