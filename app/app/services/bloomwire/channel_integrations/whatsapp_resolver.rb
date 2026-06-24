# Resolves the BloomwireChannelIntegration that owns a set of NON-SECRET WhatsApp
# routing identifiers (ADR 0004 router foundation, 4.4-b-WA.3).
#
# This is the lookup foundation the future Bloomwire Global Meta/WhatsApp webhook
# router (ADR 0004, Phase 8) will use to map an inbound Meta event to the correct
# Chatwoot account + inbox. It is FOUNDATION ONLY: it does not expose a webhook
# endpoint, it processes no Meta payloads, and it is not the Phase 8 router.
#
# Source-of-truth rule (see projects/bloomwire-chatwoot-platform/CONTEXT.md):
# Chatwoot remains the owner of inboxes, channels, conversations, messages, and
# contacts. This resolver is READ-ONLY and queries ONLY the Bloomwire-owned
# ownership table; it never reads Channel::Whatsapp#provider_config, never touches
# provider secrets (api_key/access tokens, webhook_verify_token, raw provider_config),
# and never copies or mutates Chatwoot conversation data.
#
# Contract:
# - Scope is always managed WhatsApp integrations only (non-managed and non-WhatsApp
#   rows are ignored), so a routing match can never point at a row Bloomwire does
#   not own.
# - All supplied identifiers must match the SAME row (AND), so a mix of identifiers
#   from two different integrations resolves to nil instead of the wrong tenant.
# - Deterministic + ambiguity-safe: returns the single matching row, or nil when
#   there is no match OR more than one row matches (e.g. a business_account_id alone,
#   which can cover many numbers in one WABA). It never picks a row arbitrarily.
class Bloomwire::ChannelIntegrations::WhatsappResolver
  APP_KIND = 'whatsapp'.freeze

  def self.resolve(provider: nil, phone_number_id: nil, business_account_id: nil, routing_key: nil)
    new(provider: provider, phone_number_id: phone_number_id,
        business_account_id: business_account_id, routing_key: routing_key).resolve
  end

  def initialize(provider: nil, phone_number_id: nil, business_account_id: nil, routing_key: nil)
    @provider = provider.presence
    @phone_number_id = phone_number_id.presence
    @business_account_id = business_account_id.presence
    @routing_key = routing_key.presence
  end

  # Returns the matching BloomwireChannelIntegration, or nil when there is no
  # unambiguous match. Never raises on missing/blank identifiers.
  def resolve
    return nil unless identifiers?

    unique_or_nil(scope)
  end

  private

  def scope
    relation = BloomwireChannelIntegration.managed.for_app_kind(APP_KIND)
    relation = relation.where(provider: @provider) if @provider
    relation = relation.where(routing_key: @routing_key) if @routing_key
    relation = relation.where(phone_number_id: @phone_number_id) if @phone_number_id
    relation = relation.where(business_account_id: @business_account_id) if @business_account_id
    relation
  end

  # Deterministic: load at most two rows and return the row only when exactly one
  # matches, so ambiguous routing data resolves to nil rather than an arbitrary row.
  def unique_or_nil(relation)
    rows = relation.limit(2).to_a
    rows.one? ? rows.first : nil
  end

  def identifiers?
    [@provider, @phone_number_id, @business_account_id, @routing_key].any?(&:present?)
  end
end
