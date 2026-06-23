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
# Lifecycle hooks (override only when needed):
# - validate_setup_metadata!(params) runs BEFORE the orchestrator creates or activates
#   the integration (outside the DB transaction). It DEFAULTS TO returning the params
#   unchanged, and is overridden by adapters that must verify provider-side metadata
#   against the provider (e.g. that a WhatsApp phone_number_id belongs to the supplied
#   WABA/token and matches the submitted phone number) so a mistyped identifier is never
#   persisted/activated. It raises a coded Bloomwire::ChannelSetup::SetupError on failure,
#   and RETURNS the params to persist — adapters may return a normalized/canonicalized copy
#   (e.g. WhatsApp swaps in Meta's canonical phone_number) which the orchestrator then uses
#   for the create/resume step.
# - post_create!(channel) runs AFTER the channel + inbox + ownership row are
#   committed. It DEFAULTS TO A NO-OP here, so a new adapter only overrides it when
#   the provider needs a post-commit step (e.g. WhatsApp webhook registration).
#   Keeping it post-commit ensures no external/provider call runs inside (or can be
#   rolled back by) the DB transaction.
# - refresh_channel!(channel, params) runs on a same-tenant RETRY of a pending setup,
#   BEFORE post_create! re-runs. It DEFAULTS TO A NO-OP returning the channel, and is
#   overridden by adapters that persist credentials/config on the channel so a retry
#   re-registers with corrected values instead of the stale ones.
class Bloomwire::ChannelSetup::BaseAdapter
  # Default: returns the params unchanged. Adapters override this to verify provider-side
  # metadata against the provider BEFORE the orchestrator creates/activates the integration,
  # and may return a normalized/canonicalized copy of the params to persist.
  def validate_setup_metadata!(params)
    params
  end

  # Default no-op. Adapters override this only when the provider requires a
  # post-commit registration step.
  def post_create!(_channel); end

  # Default no-op returning the channel unchanged. Adapters override this when the
  # provider stores credentials/config on the channel and a retry must refresh them.
  def refresh_channel!(channel, _params)
    channel
  end
end
