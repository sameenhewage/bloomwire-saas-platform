# Phase 10A.2: control-plane guard that blocks native (account-level) WhatsApp channel
# setup/configuration for business users when Bloomwire restriction mode is ON
# (BLOOMWIRE_MODE_ENABLED + BLOOMWIRE_RESTRICT_NATIVE_WHATSAPP_SETUP). WhatsApp setup is then handled only by
# Bloomwire Ops/SuperAdmin (setup mapping + readiness). OFF => stock Chatwoot.
#
# The guard fires only for native WhatsApp setup actions (`native_whatsapp_setup_request?`, overridable per
# controller), never for webhooks/jobs/read paths/non-WhatsApp channels/the SuperAdmin surfaces. It returns a
# 403 with a non-secret message and never reads or echoes provider_config / secrets.
module Bloomwire::RestrictsNativeWhatsappSetup
  extend ActiveSupport::Concern

  private

  def restrict_native_whatsapp_setup!
    return unless Bloomwire::Features.restrict_native_whatsapp_setup?
    return unless native_whatsapp_setup_request?

    # Phase 11A: point the client toward the managed request path (no secrets; message text unchanged).
    render json: { error: I18n.t('bloomwire.native_whatsapp_setup_restricted'), managed_request: true }, status: :forbidden
  end

  # Default: the including controller is a WhatsApp-only setup surface. Controllers that also serve
  # non-WhatsApp channels (e.g. inboxes) override this to scope the guard to WhatsApp setup actions only.
  def native_whatsapp_setup_request?
    true
  end
end
