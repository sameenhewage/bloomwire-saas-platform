# Generic orchestrator for Bloomwire-managed external-channel setup
# (ADR 0005, 4.4-b-WA.2B). WhatsApp is the first adapter.
#
# Platform-context only: the actor must be a SuperAdmin acting as a Bloomwire
# operator. The orchestrator is channel-agnostic — the adapter is selected by
# app_kind, the adapter creates the provider channel + inbox and extracts the
# NON-SECRET routing metadata, and this class owns:
# - platform authorization,
# - tenant/profile resolution,
# - duplicate / routing-key safety,
# - the transaction boundary, and
# - the Bloomwire ownership row (BloomwireChannelIntegration).
#
# It is behavior-neutral for Dialog tenants: it only ADDS a platform setup path
# and changes no existing Chatwoot or tenant-admin behavior (2C deny is later).
class Bloomwire::ChannelSetup::Service
  # Adapter registry keyed by app_kind. New verticals (sms, email, instagram,
  # shopify, ...) register an adapter here without touching this orchestrator,
  # the controller, or the model.
  def self.adapter_for(app_kind)
    case app_kind.to_s
    when 'whatsapp' then Bloomwire::ChannelSetup::WhatsappAdapter.new
    end
  end

  def initialize(actor:, account:, app_kind:, params:)
    @actor = actor
    @account = account
    @app_kind = app_kind
    @params = (params || {}).symbolize_keys
  end

  def perform
    return failure(:unauthorized) unless platform_actor?

    adapter = self.class.adapter_for(@app_kind)
    return failure(:unsupported_app_kind) if adapter.nil?

    profile = BloomwireBusinessProfile.find_by(account_id: @account&.id)
    return failure(:profile_not_found) if profile.nil?

    set_up_or_resume(adapter, profile)
  rescue Bloomwire::ChannelSetup::SetupError => e
    failure(e.code)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    failure(:integration_invalid)
  end

  private

  # Platform context = a SuperAdmin actor. Dialog AccountUser admins/agents (and
  # nil) are not platform operators and are rejected here (defense in depth on top
  # of the controller's SuperAdmin authentication).
  def platform_actor?
    @actor.is_a?(SuperAdmin)
  end

  # Resolves the routing key to either a resumable PENDING row (retry of a failed
  # webhook), a genuine duplicate, or a brand-new setup. Kept separate from #perform
  # so the orchestrator's guard clauses stay flat.
  def set_up_or_resume(adapter, profile)
    existing = existing_integration(adapter.routing_key(@params))
    if existing
      # A prior attempt by THIS tenant whose provider registration failed left a PENDING
      # row; a retry RESUMES it (re-run registration, then activate) — never creating a
      # second channel/inbox/integration for the same routing key. A pending row owned by
      # ANOTHER tenant, or any active/disabled row, is a genuine duplicate this request
      # must neither mutate nor expose.
      return activate_with_provider(adapter, existing) if resumable?(existing, profile)

      return failure(:duplicate_routing_key)
    end

    activate_with_provider(adapter, create_integration(adapter, profile))
  end

  # routing_key (WhatsApp phone_number_id) is GLOBALLY unique on the ownership table, so a
  # row found for this routing key may belong to a different tenant. We may only resume a
  # row that is still PENDING and owned by the account + profile this request is scoped
  # to; otherwise that phone_number_id is already owned elsewhere and this is a duplicate.
  def resumable?(integration, profile)
    integration.status == 'pending' &&
      integration.account_id == @account&.id &&
      integration.bloomwire_business_profile_id == profile.id
  end

  # The routing key (WhatsApp phone_number_id) is globally unique on the ownership
  # table. We look the row up (not just existence) so a PENDING row left by a failed
  # webhook attempt can be resumed instead of blocking a retry as a duplicate.
  def existing_integration(routing_key)
    return nil if routing_key.blank?

    BloomwireChannelIntegration.find_by(routing_key: routing_key)
  end

  # Provider-side registration runs AFTER the transaction commits and must SURFACE
  # failure. Only a successful registration flips the row to active; on failure the
  # adapter raises a coded SetupError, the row stays pending (retryable), and setup
  # never reports success/active on a failed webhook. Used by both the create path and
  # the pending-resume (retry) path, so neither can duplicate channel/inbox rows.
  def activate_with_provider(adapter, integration)
    adapter.post_create!(integration.channelable)
    integration.update!(status: 'active')
    Bloomwire::ChannelSetup::Result.success(integration)
  end

  # Channel + inbox + ownership row are created atomically. requires_new opens a
  # real transaction (or a savepoint when nested, e.g. inside transactional
  # specs) so any failure rolls back the channel/inbox too — no partial state.
  def create_integration(adapter, profile)
    ActiveRecord::Base.transaction(requires_new: true) do
      channel = adapter.create_channel(account: @account, params: @params)
      # The freshly-created channel object does not have its has_one :inbox loaded
      # (polymorphic association, no inverse caching); reload to read the inbox the
      # service just created. Mirrors the channel_whatsapp factory's reload.inbox.
      inbox = channel.reload.inbox
      raise Bloomwire::ChannelSetup::SetupError, :duplicate_integration if integration_exists?(inbox)

      BloomwireChannelIntegration.create!(
        bloomwire_business_profile: profile,
        account: @account,
        inbox: inbox,
        channelable: channel,
        app_kind: adapter.app_kind,
        managed_by_bloomwire: true,
        # Created PENDING; only flips to active once provider registration succeeds
        # AFTER this transaction commits (see #activate_with_provider).
        status: 'pending',
        created_by_super_admin: @actor,
        **adapter.integration_attributes(channel)
      )
    end
  end

  def integration_exists?(inbox)
    inbox.present? && BloomwireChannelIntegration.exists?(inbox_id: inbox.id)
  end

  def failure(code)
    Bloomwire::ChannelSetup::Result.failure(code)
  end
end
