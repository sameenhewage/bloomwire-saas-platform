# Phase 17F.1: read-only, safe-DTO builder for the administrator-only "Categories & Inboxes" overview.
# Composes EXISTING Chatwoot primitives only (Team, Inbox, InboxMember, TeamMember, Bloomwire::WhatsappSetup).
# There is NO persisted Inbox<->Team relationship; the category<->inbox association is DERIVED by member overlap
# and clearly labelled (ambiguous / unlinked / drifted records are shown explicitly, never guessed). This service
# performs NO writes and NEVER exposes provider_config / access tokens / secrets / encrypted values.
class Bloomwire::CategoryInboxOverview
  DERIVATION_NOTE = 'Category↔Inbox is derived by shared members (no persisted Inbox↔Team link). ' \
                    'Ambiguous, unlinked, or drifted records are shown explicitly, not guessed.'.freeze

  def self.call(account:)
    new(account: account).build
  end

  def initialize(account:)
    @account = account
  end

  def build
    {
      categories: teams.map { |team| category_dto(team) },
      ambiguous_inboxes: ambiguous_inboxes.map { |inbox| inbox_dto(inbox) },
      unlinked_inboxes: unlinked_inboxes.map { |inbox| inbox_dto(inbox) },
      derivation: { method: 'membership_overlap', note: DERIVATION_NOTE }
    }
  end

  private

  attr_reader :account

  def teams
    @teams ||= account.teams.includes(:members).order(:name).to_a
  end

  def inboxes
    @inboxes ||= account.inboxes.includes(:channel, :members).order(:name).to_a
  end

  # inbox_id => setup_status ('pending'/'configured'/'ready_for_webhook'/'blocked'), in one query. Non-secret.
  def setup_status_by_inbox
    @setup_status_by_inbox ||= Bloomwire::WhatsappSetup.where(account: account).where.not(inbox_id: nil)
                                                       .pluck(:inbox_id, :setup_status).to_h
  end

  def team_matches_for(inbox)
    team_matches_by_inbox[inbox.id] || []
  end

  # Delegates to the SINGLE shared derivation algorithm (also used by Bloomwire::CategoryInboxAlignment) so the
  # read-only overview and the write-side alignment can never diverge on what "linked / ambiguous / unlinked" means.
  def team_matches_by_inbox
    @team_matches_by_inbox ||= inboxes.to_h do |inbox|
      [inbox.id, Bloomwire::CategoryInboxDerivation.matched_teams(inbox, teams)]
    end
  end

  def derived_inboxes_for(team)
    inboxes.select do |inbox|
      matches = team_matches_for(inbox)
      matches.one? && matches.first.id == team.id
    end
  end

  def category_dto(team)
    derived = derived_inboxes_for(team)
    {
      id: team.id,
      name: team.name,
      staff: people(team.members),
      has_inbox: derived.any?,
      derived_inboxes: derived.map { |inbox| inbox_dto(inbox).merge(drift: drift(team, inbox)) }
    }
  end

  def ambiguous_inboxes
    @ambiguous_inboxes ||= inboxes.select { |inbox| team_matches_for(inbox).many? }
  end

  # Inboxes with no membership overlap with ANY team => cannot derive a category. Shown explicitly (not guessed).
  def unlinked_inboxes
    @unlinked_inboxes ||= inboxes.select { |inbox| team_matches_for(inbox).empty? }
  end

  def inbox_dto(inbox)
    matches = team_matches_for(inbox)
    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      relationship_status: relationship_status(matches),
      derivation_method: 'membership_overlap',
      matched_team_count: matches.length,
      matched_team_ids: matches.map(&:id),
      matched_teams: people(matches),
      whatsapp: whatsapp_summary(inbox),
      collaborators: people(inbox.members)
    }
  end

  def relationship_status(matches)
    return 'unlinked' if matches.empty?
    return 'linked' if matches.one?

    'ambiguous'
  end

  def whatsapp_summary(inbox)
    return nil unless inbox.channel.is_a?(Channel::Whatsapp)

    { connection_mode: connection_mode(inbox.channel), setup_status: setup_status_by_inbox.fetch(inbox.id, 'not_configured') }
  end

  # Only the non-secret 'connection_mode' badge value is read from provider_config; the config is NEVER exposed.
  def connection_mode(channel)
    channel.provider_config.to_h['connection_mode'].to_s == 'coexistence' ? 'coexistence' : 'standard'
  end

  # Reuses the shared additive-drift primitive (same one the alignment applies) so what the overview SHOWS as drift
  # is exactly what the alignment would ADD. inbox_additions = team members missing inbox access;
  # team_additions = inbox collaborators not on the team.
  def drift(team, inbox)
    diff = Bloomwire::CategoryInboxDerivation.additive_drift(team, inbox)
    {
      staff_missing_inbox_access: people(diff[:inbox_additions]),
      collaborators_not_in_team: people(diff[:team_additions])
    }
  end

  def people(users)
    users.map { |user| { id: user.id, name: user.name } }
  end
end
