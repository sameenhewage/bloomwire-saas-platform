# Phase 17F.3: administrator-guided, SERVER-AUTHORITATIVE staff-access alignment between an existing Team (category)
# and an existing Inbox. The caller supplies ONLY the account-scoped Team + Inbox identity — never a membership list.
# The server independently recomputes, from FRESH database state, (a) that the pair is a currently-derived,
# unambiguous, actionable pair (via the shared Bloomwire::CategoryInboxDerivation), and (b) the additive drift, then
# adds ONLY those server-computed differences. It is additive only (never removes staff), idempotent (already aligned
# ⇒ no-op), account-scoped, and makes NO Meta/WhatsApp/HTTP/email/webhook/external call.
#
# Atomicity boundary: the TeamMember + InboxMember writes run in ONE ActiveRecord::Base.transaction and are therefore
# DATABASE-atomic (a mid-write failure rolls back ALL membership rows). The stock InboxMember after_create round-robin
# (a local Redis LPUSH via AutoAssignment::InboxRoundRobinService) is NOT part of the database transaction and can
# survive a later DB rollback; it is upstream behavior and is self-reconciling from the DB source of truth
# (InboxRoundRobinService#available_agent runs reset_queue unless validate_queue?, rebuilding the queue from
# inbox.inbox_members). We deliberately do NOT modify that upstream callback.
class Bloomwire::CategoryInboxAlignment
  # Fail closed: the (team, inbox) pair is not a currently-derived, unambiguous, actionable pair — i.e. it is
  # unrelated, ambiguous, unlinked, or a stale pair that is no longer derived. Recomputed server-side; the client's
  # notion of the relationship is never trusted.
  class NotEligible < StandardError; end

  def self.call(account:, team:, inbox:)
    new(account: account, team: team, inbox: inbox).call
  end

  def initialize(account:, team:, inbox:)
    @account = account
    @team = team
    @inbox = inbox
  end

  def call
    added_to_inbox, added_to_team = apply_alignment!
    result_dto(added_to_team, added_to_inbox)
  end

  private

  attr_reader :account, :team, :inbox

  # One DATABASE transaction wraps the fresh-state eligibility recomputation AND both additive writes. Returns
  # [inbox_additions, team_additions] (the transaction block's value).
  def apply_alignment!
    ActiveRecord::Base.transaction do
      refresh_pair_members!
      raise NotEligible unless derived_pair?

      # Server-authoritative diff: recomputed from fresh membership, never from a client-supplied list.
      diff = Bloomwire::CategoryInboxDerivation.additive_drift(team, inbox)
      create_memberships!(diff)
      [diff[:inbox_additions], diff[:team_additions]]
    end
  end

  # Server-authoritative eligibility: the pair must be currently derived (linked + unambiguous + this team).
  def derived_pair?
    teams = account.teams.includes(:members).to_a
    Bloomwire::CategoryInboxDerivation.derived_pair?(team, inbox, teams)
  end

  def create_memberships!(diff)
    diff[:inbox_additions].each { |user| inbox.inbox_members.create!(user_id: user.id) }
    diff[:team_additions].each { |user| team.team_members.create!(user_id: user.id) }
  end

  # Read membership from FRESH database state so alignment reflects reality at confirmation time, even if memberships
  # changed after the UI built its preview.
  def refresh_pair_members!
    team.association(:members).reset
    inbox.association(:members).reset
  end

  def result_dto(added_to_team, added_to_inbox)
    {
      team_id: team.id,
      inbox_id: inbox.id,
      added_to_team: people(added_to_team),
      added_to_inbox: people(added_to_inbox),
      aligned: true
    }
  end

  # Safe DTO only: id + name (mirrors the 17F.1 overview people shape). Never exposes email/phone/secrets.
  def people(users)
    users.map { |user| { id: user.id, name: user.name } }
  end
end
