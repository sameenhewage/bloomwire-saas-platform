# Phase 5 (resume): idempotent re-verification + ACTIVATION of an EXISTING Action-Required managed WhatsApp setup.
# Reconnecting can NOT resume it (the number is already claimed, so a fresh signup hits the duplicate guard); this
# is the supported resume path. After the account owner grants the WABA asset task in Meta Business Settings, this
# re-reads the EXACT stored-token actor's task on the EXACT WABA and, when capable, SUBSCRIBES the WABA to the
# global router (onboarding never subscribes an Action-Required inbox — BLOCKER 2) and VERIFIES the subscription
# BEFORE atomically promoting the SAME setup action_required -> ready_for_webhook (same Channel/Inbox/Setup ids,
# no duplicate, no /register, no second inbox). Still-missing/unverifiable — or a task-verified-but-subscription-
# unconfirmed attempt — stays Action-Required with a refreshed sanitized reason (never a false ready).
#
# Boundary (do not weaken):
# - Verify-only for the TASK (allow_grant: false): uses ONLY the setup's stored channel token (the partner
#   SYSTEM_USER token, which cannot self-elevate) — never a platform-admin credential, never an owner personal
#   token, never a task grant. The ONLY Meta write is the idempotent app-to-WABA subscription (global router).
# - Never re-registers the number. Reuses Bloomwire::WhatsappSetupCreator for the promotion so the ready row stays
#   router-handoff-safe and stays the SAME record (find_or_initialize by channel).
# - Never persists/echoes the token; capability failures are logged class-only inside the capability gate.
class Bloomwire::WhatsappCapabilityRecheck
  # Sanitized reason when the actor CAN send (task verified) but the app-to-WABA subscription could not be
  # confirmed this attempt — the SAME records stay Action-Required and the owner simply retries.
  ACTIVATION_INCOMPLETE_REASON = 'outbound_messaging_activation_incomplete'.freeze
  # Safe result: `error` is a symbol NAME only (never a value/secret); success? when no error.
  Result = Struct.new(:status, :setup, :error, keyword_init: true) do
    def success?
      error.nil?
    end

    def ready?
      status == :ready
    end

    def action_required?
      status == :action_required
    end
  end

  def initialize(setup:)
    @setup = setup
  end

  def perform
    guard = precheck
    return guard if guard

    client = Whatsapp::FacebookApiClient.new(@token)
    capability = verify_capability(client)
    return still_action_required(capability) unless capability.ready?

    # Capability confirmed. Onboarding NEVER subscribes an Action-Required inbox, so recheck OWNS enabling inbound:
    # subscribe the exact WABA (idempotent) with the SAME stored-token client and VERIFY it took effect BEFORE
    # promoting. A failed/unconfirmed subscription keeps the SAME records Action-Required (never a false ready).
    return activation_incomplete unless subscribe_and_verify(client)

    promote
  end

  private

  # Returns an early Result — a safe-symbol error, or the idempotent no-op success when the setup is already
  # routeable — when the setup is missing / already ready / not action-required / incomplete. Otherwise resolves
  # the stored channel token into @token and returns nil so #perform proceeds to the (verify-only) recheck.
  def precheck
    return Result.new(error: :not_found) if @setup.blank?
    return Result.new(status: :ready, setup: @setup) if routeable?
    return Result.new(error: :not_action_required) unless action_required?
    return Result.new(error: :setup_incomplete) unless complete?

    @token = channel_token(@setup.channel_whatsapp)
    @token.present? ? nil : Result.new(error: :setup_incomplete)
  end

  # An action-required setup created by onboarding always has all three; a hand-edited/partial row does not.
  def complete?
    @setup.channel_whatsapp.present? && @setup.inbox.present? && @setup.waba_id.present?
  end

  def routeable?
    @setup.setup_status == Bloomwire::WhatsappSetup::ROUTEABLE_STATUS
  end

  def action_required?
    @setup.setup_status == Bloomwire::WhatsappSetup::ACTION_REQUIRED_STATUS
  end

  # The stored per-customer token lives ONLY in the channel's encrypted provider_config (ADR-0006). Read (never
  # returned/logged) solely to re-verify the actor's task.
  def channel_token(channel)
    channel.provider_config.to_h['api_key'].presence
  end

  def verify_capability(client)
    Bloomwire::WhatsappMessagingCapability.new(
      client: client, token: @token, waba_id: @setup.waba_id, allow_grant: false
    ).ensure
  end

  # Promote the SAME setup to routeable via the creator (find_or_initialize by channel_whatsapp_id => same id, no
  # duplicate, router-handoff re-validated). Clears the sanitized reason.
  def promote
    creator = Bloomwire::WhatsappSetupCreator.call(
      account: @setup.account, inbox: @setup.inbox, channel_whatsapp: @setup.channel_whatsapp,
      phone_number_id: @setup.phone_number_id, waba_id: @setup.waba_id,
      display_phone_number: @setup.display_phone_number,
      setup_status: Bloomwire::WhatsappSetup::ROUTEABLE_STATUS, status_reason: nil
    )
    return Result.new(error: :promote_failed) unless creator.success?

    Result.new(status: :ready, setup: creator.setup)
  end

  # Onboarding never subscribes an Action-Required inbox, so recheck OWNS enabling inbound: subscribe the exact
  # WABA (idempotent) with the stored token and VERIFY it took effect. Class-only sanitized log on any failure.
  def subscribe_and_verify(client)
    client.subscribe_app_to_waba(@setup.waba_id)
    client.subscribed_to_waba?(@setup.waba_id)
  rescue StandardError => e
    Rails.logger.warn("[BLOOMWIRE WHATSAPP RECHECK] subscription failed: #{e.class}")
    false
  end

  # Still not capable: keep the inbox non-routeable and refresh the sanitized reason (verified_missing vs
  # unverifiable) so the UI can guide the owner. Never a false ready.
  def still_action_required(capability)
    reason = capability.reason
    @setup.update(status_reason: reason) if reason.present? && reason != @setup.status_reason
    Result.new(status: :action_required, setup: @setup)
  end

  # Task verified but subscription not yet confirmed: keep the SAME records Action-Required with a distinct,
  # retriable reason (permission IS present — the owner just retries to finish activation). Never a false ready.
  def activation_incomplete
    @setup.update(status_reason: ACTIVATION_INCOMPLETE_REASON) if @setup.status_reason != ACTIVATION_INCOMPLETE_REASON
    Result.new(status: :action_required, setup: @setup)
  end
end
