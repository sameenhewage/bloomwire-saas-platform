# Resolution logic for the Bloomwire global Meta WhatsApp webhook router (ADR-0005). Given a Meta WhatsApp
# webhook payload, it resolves the single, consistent, ready_for_webhook Bloomwire::WhatsappSetup mapping by
# the payload's non-secret phone_number_id. Fail-closed (returns nil) on anything missing / not-ready /
# ambiguous / inconsistent. It reads ONLY the non-secret phone_number_id from the payload and non-secret
# mapping columns — it never touches provider_config secrets and stores nothing.
class Bloomwire::Webhooks::WhatsappRouter
  # phone_number_id lives at entry[0].changes[0].value.metadata.phone_number_id in the Meta payload.
  def self.phone_number_id_from(payload)
    return if payload.blank?

    payload.dig('entry', 0, 'changes', 0, 'value', 'metadata', 'phone_number_id').presence
  end

  # The ready_for_webhook mapping for this phone_number_id, or nil (fail-closed). The partial unique index on
  # phone_number_id makes >1 match impossible, but `one?` defends in depth; the inbox/channel presence check
  # rejects a row forced into an inconsistent ready state outside the model validations.
  def self.resolve(payload)
    phone_number_id = phone_number_id_from(payload)
    return if phone_number_id.blank?

    matches = Bloomwire::WhatsappSetup.ready_for_webhook.where(phone_number_id: phone_number_id).to_a
    return unless matches.one?

    setup = matches.first
    return unless setup.inbox_id.present? && setup.channel_whatsapp_id.present?

    setup
  end
end
