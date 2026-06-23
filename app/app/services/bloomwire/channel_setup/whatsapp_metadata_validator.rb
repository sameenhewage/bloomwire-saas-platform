# Verifies operator-supplied WhatsApp phone metadata against Meta BEFORE the
# orchestrator creates or activates an integration (ADR 0005, PR #23 P2).
#
# This closes a source-of-truth gap: Whatsapp::ChannelCreationService trusts the
# supplied phone_number_id / phone_number verbatim, Channel::Whatsapp#validate_provider_config
# only checks the WABA *templates* endpoint, and Whatsapp::WebhookSetupService rescues
# phone registration/verification errors before subscribing the WABA webhook. So none
# of them prove the supplied phone_number_id actually belongs to the supplied WABA/token
# or matches the submitted phone number. Without this, a mistyped id/number could be
# persisted as the Bloomwire routing source-of-truth and still be reported active, while
# outgoing sends use a bad identifier.
#
# It reuses the existing Whatsapp::FacebookApiClient (the shared Meta Graph client) — no
# new HTTP plumbing — and returns a machine-readable error symbol (nil when valid). On
# success it also exposes #canonical_phone_number: Meta's number for the validated id,
# normalized to Chatwoot's '+<digits>' convention, so the caller persists the canonical
# value (not the raw submitted string) and inbound webhook routing can resolve the channel.
# It never persists anything and never surfaces raw provider data: the access token stays in
# the caller's params (and, after creation, only in Channel::Whatsapp#provider_config),
# and provider errors are logged server-side, never returned. The Meta lookup is memoized
# so error_code + canonical_phone_number share a single HTTP call.
class Bloomwire::ChannelSetup::WhatsappMetadataValidator
  def initialize(params)
    @business_account_id = params[:business_account_id]
    @phone_number_id = params[:phone_number_id]
    @phone_number = params[:phone_number]
    @api_key = params[:api_key]
  end

  # nil  -> the supplied phone metadata is valid for this WABA/token.
  # else -> a coded error symbol the adapter turns into a Bloomwire::ChannelSetup::SetupError:
  #   :phone_metadata_unverifiable -> Meta could not be queried for the WABA/token at all
  #   :phone_number_id_mismatch    -> the WABA does not expose the supplied phone_number_id
  #   :phone_number_mismatch       -> the id is valid but its number != the submitted number
  def error_code
    return :phone_metadata_unverifiable if waba_phone_numbers.nil?
    return :phone_number_id_mismatch if matched_phone.nil?
    return :phone_number_mismatch unless number_matches?(matched_phone['display_phone_number'])

    nil
  end

  # Meta's number for the validated phone_number_id, normalized to Chatwoot's '+<digits>'
  # convention (mirroring Whatsapp::PhoneInfoService) so the persisted Channel::Whatsapp
  # #phone_number matches what inbound WhatsApp webhook routing looks up — both
  # Webhooks::WhatsappEventsJob and Webhooks::WhatsappController resolve the channel by
  # '+<display_phone_number>'. Returns nil unless the metadata is valid (error_code.nil?),
  # so callers must guard on error_code first.
  def canonical_phone_number
    return nil unless error_code.nil?

    "+#{digits(matched_phone['display_phone_number'])}"
  end

  private

  # The phone entry in the WABA whose id matches the submitted phone_number_id, or nil.
  # Memoized; nil when the WABA list could not be fetched or has no such id.
  def matched_phone
    return @matched_phone if defined?(@matched_phone)

    @matched_phone = waba_phone_numbers&.find { |entry| entry['id'].to_s == @phone_number_id.to_s }
  end

  # The supplied token's view of the supplied WABA's phone numbers (memoized so error_code
  # and canonical_phone_number share one HTTP call). Returns nil when Meta rejects the
  # request (bad/inaccessible token or WABA, or a transport error): the FacebookApiClient
  # raises on a non-success response, which we treat as "cannot verify" and never leak the
  # raw provider error into the response.
  def waba_phone_numbers
    return @waba_phone_numbers if defined?(@waba_phone_numbers)

    @waba_phone_numbers = Whatsapp::FacebookApiClient.new(@api_key).fetch_phone_numbers(@business_account_id)['data']
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE] WhatsApp phone metadata verification failed: #{e.message}")
    @waba_phone_numbers = nil
  end

  # Compare Meta's canonical display_phone_number to the submitted number on digits only,
  # so equivalent formats (spaces, dashes, parentheses, leading +) are treated as equal.
  def number_matches?(display_phone_number)
    submitted = digits(@phone_number)
    submitted.present? && digits(display_phone_number) == submitted
  end

  def digits(value)
    value.to_s.gsub(/\D/, '')
  end
end
