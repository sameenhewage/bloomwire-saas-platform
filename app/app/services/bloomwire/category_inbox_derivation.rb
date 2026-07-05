# Phase 17F.3: the SINGLE authoritative Category↔Inbox derivation algorithm, shared by the read-only overview
# (Bloomwire::CategoryInboxOverview) and the guided alignment (Bloomwire::CategoryInboxAlignment) so the two can
# never diverge. The relationship is DERIVED by membership overlap (no persisted Inbox↔Team link):
#   - matched teams for an inbox = account teams whose member set intersects the inbox's member set;
#   - a (team, inbox) pair is "derived" (linked + unambiguous + this team) iff the inbox matches EXACTLY that team.
# Pure functions over already-loaded records — callers pass fresh records so eligibility/drift reflect current state.
module Bloomwire::CategoryInboxDerivation
  module_function

  # Teams (from the supplied preloaded `teams`) whose member set overlaps the inbox's member set.
  def matched_teams(inbox, teams)
    inbox_ids = member_ids(inbox)
    return [] if inbox_ids.empty?

    inbox_set = inbox_ids.to_set
    teams.select { |team| member_ids(team).any? { |id| inbox_set.include?(id) } }
  end

  # linked (exactly one matched team) / ambiguous (many) / unlinked (none).
  def relationship_status(inbox, teams)
    matches = matched_teams(inbox, teams)
    return :unlinked if matches.empty?
    return :ambiguous if matches.length > 1

    :linked
  end

  # True only for the unambiguous derived pair: the inbox is matched by exactly one team AND it is this team.
  # Fails closed for unlinked, ambiguous, or a pair whose inbox is derived to a different team.
  def derived_pair?(team, inbox, teams)
    matches = matched_teams(inbox, teams)
    matches.one? && matches.first.id == team.id
  end

  # Additive-only diff (no removals): team members lacking inbox access, and inbox members lacking team access.
  # Returns user records (callers map to a safe DTO or create memberships).
  def additive_drift(team, inbox)
    team_member_ids = member_ids(team).to_set
    inbox_member_ids = member_ids(inbox).to_set
    {
      inbox_additions: team.members.reject { |user| inbox_member_ids.include?(user.id) },
      team_additions: inbox.members.reject { |user| team_member_ids.include?(user.id) }
    }
  end

  def member_ids(record)
    record.members.map(&:id)
  end
end
