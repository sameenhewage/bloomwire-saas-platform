# Phase 17D.1: dedicated Coexistence backend service for "Connect Existing WhatsApp Business App".
#
# This intentionally reuses the safe 17C.2 managed-signup seam but marks the created channel explicitly as
# `connection_mode: coexistence` so Standard number-registration and WhatsApp Business App coexistence are not
# indistinguishable in provider_config / safe DTOs.
#
# Boundary (do not weaken):
# - No native /whatsapp/authorization path.
# - No per-channel callback override / native webhook registration.
# - App-to-WABA subscription only through the global router path inherited from the 17C.2 service.
# - Token still goes only through Bloomwire::WhatsappCredentialWriter.
# - No Standard Cloud API /register: coexistence numbers are already registered on the WhatsApp Business App.
# - Response remains safe: no token, api_key, provider_config, app secret, verify token, or raw Meta payload.
class Bloomwire::WhatsappCoexistenceEmbeddedSignupService < Bloomwire::WhatsappEmbeddedSignupService
  CONNECTION_MODE = 'coexistence'.freeze
  SOURCE = 'bloomwire_managed'.freeze

  private

  # Coexistence numbers are already registered on the WhatsApp Business App, so the Standard Cloud API
  # `POST /{phone_number_id}/register` path does not apply to them. Meta rejects it and the parent swallows that
  # failure as non-fatal, which made onboarding return success while the number stayed DISCONNECTED (a false
  # success). Coexistence therefore skips /register entirely: inbound still works through the parent's app-to-WABA
  # subscription (global router) and outbound uses the already-registered number's Cloud API credentials.
  def register_number(_client, _phone_number_id)
    nil
  end

  def create_channel_shell(phone_info)
    channel = Channel::Whatsapp.new(
      account: @account,
      phone_number: phone_info[:phone_number],
      provider: 'whatsapp_cloud',
      provider_config: {
        'phone_number_id' => phone_info[:phone_number_id],
        'business_account_id' => @waba_id,
        'source' => SOURCE,
        'connection_mode' => CONNECTION_MODE
      }
    )
    channel.save!(validate: false)
    channel
  end

  def dto_for(setup)
    dto = super
    dto[:channel][:connection_mode] = CONNECTION_MODE
    dto[:setup][:connection_mode] = CONNECTION_MODE
    dto
  end
end
