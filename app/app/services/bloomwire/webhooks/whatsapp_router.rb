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

  # Returns a setup ONLY when the existing Webhooks::WhatsappEventsJob (get_channel_from_wb_payload) is
  # guaranteed to re-resolve to this exact mapped channel/inbox from the same payload — otherwise nil
  # (fail-closed). This prevents enqueueing a payload that the native job would route to a different (or no)
  # channel. Mirrors the native resolution: channel.phone_number == "+<display>" AND
  # channel.provider_config['phone_number_id'] == payload phone_number_id, with the channel's own inbox.
  def self.resolve_handoff_safe_setup(payload)
    setup = resolve(payload)
    return unless setup && channel_aligned_with_payload?(setup, payload)

    setup
  end

  # True only when the native job (get_channel_from_wb_payload) would re-resolve to this exact mapped
  # channel/inbox: the channel exists with the setup's own inbox, its provider_config phone_number_id equals
  # the payload's phone_number_id, and its phone_number equals the normalized display number.
  def self.channel_aligned_with_payload?(setup, payload)
    channel = setup.channel_whatsapp
    return false unless channel && setup.inbox
    return false unless channel.inbox&.id == setup.inbox_id
    return false unless channel.provider_config.to_h['phone_number_id'] == phone_number_id_from(payload)

    channel.phone_number == normalized_display_phone_number(payload)
  end

  # Mirrors Webhooks::WhatsappEventsJob#get_channel_from_wb_payload, which finds the channel by "+<display>".
  def self.normalized_display_phone_number(payload)
    display_phone_number = payload.dig('entry', 0, 'changes', 0, 'value', 'metadata', 'display_phone_number')
    return if display_phone_number.blank?

    "+#{display_phone_number}"
  end
end
