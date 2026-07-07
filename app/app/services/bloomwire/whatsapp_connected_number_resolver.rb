# Phase 17E.2: safe duplicate-registration resolver.
#
# Meta allows one WhatsApp display number to exist under MULTIPLE WhatsApp Business Accounts at once (migration /
# coexistence). When the WABA + phone_number_id the customer selected in the embedded-signup popup is not live
# (Meta status DISCONNECTED), the SAME number can still be CONNECTED under a different WABA the token can message.
# Onboarding must route to that live registration — otherwise both outbound (send from a DISCONNECTED pnid => Meta
# #10) and inbound (Meta delivers webhooks with the CONNECTED pnid, which will not match the persisted mapping)
# silently break.
#
# Safety contract (fail closed, never guess):
# - Only WABAs inside the exchanged token's `whatsapp_business_messaging` granular scope are considered (the token
#   already has send rights to them).
# - A match is used ONLY when EXACTLY ONE connected registration exists for the normalized number.
# - That single match must belong to the SAME owner business as the originally selected WABA — the resolver never
#   silently crosses a tenant / business boundary.
# - Zero, multiple, or cross-business matches return a safe Symbol error (no channel/inbox/setup is created).
class Bloomwire::WhatsappConnectedNumberResolver
  CONNECTED_STATUS = 'CONNECTED'.freeze

  # Safe result: `error` is a symbol NAME only (never a value/secret); ok? when a single safe match was resolved.
  Result = Struct.new(:waba_id, :phone_number_id, :display_phone_number, :error, keyword_init: true) do
    def ok?
      error.nil?
    end
  end

  def initialize(client:, input_token:, selected_waba_id:, selected_phone_number:)
    @client = client
    @input_token = input_token
    @selected_waba_id = selected_waba_id
    @selected_phone_number = selected_phone_number
  end

  def resolve
    matches = connected_matches
    return Result.new(error: :no_connected_registration) if matches.empty?
    return Result.new(error: :ambiguous_connected_registration) if matches.size > 1

    match = matches.first
    return Result.new(error: :cross_business_registration) unless same_business?(match[:waba_id])

    Result.new(waba_id: match[:waba_id], phone_number_id: match[:phone_number_id],
               display_phone_number: match[:display_phone_number])
  rescue StandardError => e
    # Sanitized (class-only) — the message/body can carry the token or PII.
    Rails.logger.error("[BLOOMWIRE CONNECTED RESOLVER] Meta lookup failed: #{e.class}")
    Result.new(error: :meta_error)
  end

  private

  # Every CONNECTED registration for the selected display number, across all WABAs this token can message.
  def connected_matches
    target = normalize(@selected_phone_number)
    @client.messaging_waba_ids(@input_token).flat_map do |waba_id|
      @client.waba_registrations(waba_id).filter_map do |registration|
        next unless registration['status'] == CONNECTED_STATUS
        next unless normalize(registration['display_phone_number']) == target

        { waba_id: waba_id, phone_number_id: registration['id'],
          display_phone_number: registration['display_phone_number'] }
      end
    end
  end

  # The match must share the originally selected WABA's owner business (or be that very WABA). If the owner is not
  # visible to this token we treat it as cross-business (fail closed) rather than assume it is safe.
  def same_business?(candidate_waba_id)
    return true if candidate_waba_id == @selected_waba_id

    selected_owner = @client.waba_owner_business_id(@selected_waba_id)
    selected_owner.present? && selected_owner == @client.waba_owner_business_id(candidate_waba_id)
  end

  def normalize(phone_number)
    phone_number.to_s.gsub(/\D/, '')
  end
end
