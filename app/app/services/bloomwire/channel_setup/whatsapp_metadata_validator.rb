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
# new HTTP plumbing — and returns a machine-readable error symbol (nil when valid). It
# never persists anything and never surfaces raw provider data: the access token stays in
# the caller's params (and, after creation, only in Channel::Whatsapp#provider_config),
# and provider errors are logged server-side, never returned.
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
    phone_numbers = waba_phone_numbers
    return :phone_metadata_unverifiable if phone_numbers.nil?

    phone = phone_numbers.find { |entry| entry['id'].to_s == @phone_number_id.to_s }
    return :phone_number_id_mismatch if phone.nil?
    return :phone_number_mismatch unless number_matches?(phone['display_phone_number'])

    nil
  end

  private

  # The supplied token's view of the supplied WABA's phone numbers. Returns nil when Meta
  # rejects the request (bad/inaccessible token or WABA, or a transport error): the
  # FacebookApiClient raises on a non-success response, which we treat as "cannot verify"
  # and never leak the raw provider error into the response.
  def waba_phone_numbers
    Whatsapp::FacebookApiClient.new(@api_key).fetch_phone_numbers(@business_account_id)['data']
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE] WhatsApp phone metadata verification failed: #{e.message}")
    nil
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
