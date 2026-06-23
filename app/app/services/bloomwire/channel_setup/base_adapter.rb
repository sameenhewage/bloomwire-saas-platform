# Base class for Bloomwire channel-setup adapters (ADR 0005, 4.4-b-WA.2B). Each
# external-channel vertical (WhatsApp first; SMS / Email / Instagram / Shopify
# later) subclasses this and implements the channel-specific contract below, so the
# orchestrator (Bloomwire::ChannelSetup::Service) stays channel-agnostic and talks
# only to this interface.
#
# Contract a subclass must implement:
# - app_kind                          -> String identifier (Service.adapter_for key)
# - permitted_params                  -> Array<Symbol> strong-params allowlist
# - routing_key(params)               -> dedupe key derived from RAW request params
# - create_channel(account:, params:) -> the provider channel (with its inbox)
# - integration_attributes(channel)   -> Hash of NON-SECRET routing columns
#
# Lifecycle hook (override only when needed):
# - post_create!(channel) runs AFTER the channel + inbox + ownership row are
#   committed. It DEFAULTS TO A NO-OP here, so a new adapter only overrides it when
#   the provider needs a post-commit step (e.g. WhatsApp webhook registration).
#   Keeping it post-commit ensures no external/provider call runs inside (or can be
#   rolled back by) the DB transaction.
class Bloomwire::ChannelSetup::BaseAdapter
  # Default no-op. Adapters override this only when the provider requires a
  # post-commit registration step.
  def post_create!(_channel); end
end
