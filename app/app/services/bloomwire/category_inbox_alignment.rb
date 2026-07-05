# Phase 17F.3: administrator-guided, LOCAL-ONLY staff-access alignment between an existing Team (category) and an
# existing Inbox. It ADDITIVELY ensures every given account user is a member of BOTH the Team and the Inbox, in a
# single ActiveRecord transaction (atomic; rolls back fully on any failure; idempotent — re-running adds nobody).
# It NEVER removes staff, NEVER creates a persisted Team<->Inbox mapping/schema, and makes NO Meta/WhatsApp/external
# call. Callers must have already validated (admin + feature gate) and scoped Team/Inbox to Current.account.
class Bloomwire::CategoryInboxAlignment
  # Raised when a requested user does not belong to the account (rejected before any write).
  class InvalidMember < StandardError; end

  def self.call(account:, team:, inbox:, user_ids:)
    new(account: account, team: team, inbox: inbox, user_ids: user_ids).call
  end

  def initialize(account:, team:, inbox:, user_ids:)
    @account = account
    @team = team
    @inbox = inbox
    @user_ids = Array(user_ids).map(&:to_i).uniq
  end

  def call
    validate_members!

    added_to_team = []
    added_to_inbox = []
    # One transaction wraps BOTH additive membership writes so a partial pair can never be committed.
    ActiveRecord::Base.transaction do
      added_to_team = add_missing(team.team_members, existing_team_user_ids)
      added_to_inbox = add_missing(inbox.inbox_members, existing_inbox_user_ids)
    end

    result_dto(added_to_team, added_to_inbox)
  end

  private

  attr_reader :account, :team, :inbox, :user_ids

  def existing_team_user_ids
    @existing_team_user_ids ||= team.team_members.pluck(:user_id)
  end

  def existing_inbox_user_ids
    @existing_inbox_user_ids ||= inbox.inbox_members.pluck(:user_id)
  end

  # Additive + idempotent: only creates join rows for users not already present. Uses create! so any failure
  # raises and rolls back the enclosing transaction. Returns the user_ids that were newly added.
  def add_missing(association, existing_ids)
    missing = user_ids - existing_ids
    missing.each { |user_id| association.create!(user_id: user_id) }
    missing
  end

  # Account-scoped validation: every requested user must belong to this account. Rejects cross-account/unknown ids
  # before any write occurs.
  def validate_members!
    known_ids = account.users.where(id: user_ids).pluck(:id)
    unknown = user_ids - known_ids
    raise InvalidMember, 'One or more users do not belong to this account' if unknown.any?
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
  def people(ids)
    account.users.where(id: ids).order(:id).map { |user| { id: user.id, name: user.name } }
  end
end
