class AddUniqueManagedWhatsappPhoneNumberIdIndexToBloomwireChannelIntegrations < ActiveRecord::Migration[7.1]
  # 4.4-b-WA.3 (ADR 0004 router foundation). The future Meta/WhatsApp webhook
  # router resolves the destination Chatwoot account+inbox by the Meta
  # phone_number_id. A phone_number_id identifies exactly one WhatsApp number, so
  # two managed WhatsApp integrations claiming the same one would make routing
  # ambiguous. This was only enforced INDIRECTLY (routing_key == phone_number_id is
  # UNIQUE); make it explicit and robust by replacing the non-unique lookup index
  # with a partial UNIQUE index scoped to Bloomwire-managed rows. We scope by
  # managed_by_bloomwire (not app_kind) because phone_number_id is only ever set for
  # WhatsApp (NULL for other kinds, and NULLs are distinct in a UNIQUE index), so
  # this enforces deterministic routing for managed WhatsApp numbers while leaving
  # non-WhatsApp managed rows unconstrained.
  #
  # Safe for existing data: every Bloomwire-created managed WhatsApp row already has
  # routing_key == phone_number_id with routing_key UNIQUE, so phone_number_id is
  # already unique among those rows.
  def up
    remove_index :bloomwire_channel_integrations,
                 name: 'index_bw_channel_integrations_on_phone_number_id'
    add_index :bloomwire_channel_integrations, :phone_number_id,
              unique: true,
              where: 'managed_by_bloomwire',
              name: 'index_bw_channel_integrations_on_managed_phone_number_id'
  end

  def down
    remove_index :bloomwire_channel_integrations,
                 name: 'index_bw_channel_integrations_on_managed_phone_number_id'
    add_index :bloomwire_channel_integrations, :phone_number_id,
              where: 'phone_number_id IS NOT NULL',
              name: 'index_bw_channel_integrations_on_phone_number_id'
  end
end
