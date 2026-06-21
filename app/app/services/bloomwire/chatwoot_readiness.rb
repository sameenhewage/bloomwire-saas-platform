# Read-only readiness check for a Bloomwire tenant's underlying Chatwoot setup.
#
# Phase 3 — Business Onboarding / Tenant Setup (slice: Chatwoot readiness mapping).
#
# Chatwoot already owns accounts, inboxes, channels, conversations, contacts, and
# messages. This service ONLY reads existing Chatwoot state and returns a safe
# status label. It never creates or configures inboxes/channels/webhooks, and it
# never reads or exposes conversation/message/contact data (see AGENTS.md rules
# 6, 8). Readiness is computed strictly per account (tenant isolation, rule 4).
class Bloomwire::ChatwootReadiness
  READY = 'Ready'.freeze
  NEEDS_INBOX = 'Needs inbox/channel'.freeze
  NO_ACCOUNT = 'No Chatwoot account'.freeze
  NO_PROFILE = 'No Bloomwire profile'.freeze

  # The full set of safe, non-identifying labels this service may return.
  STATUSES = [READY, NEEDS_INBOX, NO_ACCOUNT, NO_PROFILE].freeze

  # account: a Chatwoot Account (or nil).
  # profile: pass the already-known BloomwireBusinessProfile to avoid a redundant
  #          lookup; defaults to resolving it from the account.
  def initialize(account, profile: :unresolved)
    @account = account
    @profile = profile
  end

  def status
    return NO_ACCOUNT if @account.nil?
    return NO_PROFILE if profile.nil?
    return NEEDS_INBOX unless usable_inbox?

    READY
  end

  private

  def profile
    @profile = @account.bloomwire_business_profile if @profile == :unresolved
    @profile
  end

  # A Chatwoot inbox always owns a channel, so "the account has at least one
  # inbox" is our readiness signal. Deeper per-channel health checks are
  # intentionally out of scope for this slice (keep it simple, no over-build).
  def usable_inbox?
    @account.inboxes.any?
  end
end
