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

  def member_ids(record)
    record.members.map(&:id)
  end

  def derived_inboxes_for(team)
    team_set = member_ids(team).to_set
    inboxes.select { |inbox| member_ids(inbox).to_set.intersect?(team_set) }
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

  # Inboxes with no membership overlap with ANY team => cannot derive a category. Shown explicitly (not guessed).
  def unlinked_inboxes
    @unlinked_inboxes ||= inboxes - teams.flat_map { |team| derived_inboxes_for(team) }.uniq
  end

  def inbox_dto(inbox)
    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      whatsapp: whatsapp_summary(inbox),
      collaborators: people(inbox.members)
    }
  end

  def whatsapp_summary(inbox)
    return nil unless inbox.channel.is_a?(Channel::Whatsapp)

    { connection_mode: connection_mode(inbox.channel), setup_status: setup_status_by_inbox[inbox.id] }
  end

  # Only the non-secret 'connection_mode' badge value is read from provider_config; the config is NEVER exposed.
  def connection_mode(channel)
    channel.provider_config.to_h['connection_mode'].to_s == 'coexistence' ? 'coexistence' : 'standard'
  end

  def drift(team, inbox)
    team_set = member_ids(team).to_set
    inbox_set = member_ids(inbox).to_set
    {
      staff_missing_inbox_access: people(team.members.reject { |user| inbox_set.include?(user.id) }),
      collaborators_not_in_team: people(inbox.members.reject { |user| team_set.include?(user.id) })
    }
  end

  def people(users)
    users.map { |user| { id: user.id, name: user.name } }
  end
end
