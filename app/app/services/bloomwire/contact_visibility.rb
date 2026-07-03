# Phase 17E.2: the single seam for Bloomwire agent contact-visibility isolation (ADR-0009 follow-up).
#
# Returns the set of contacts a given `user` may see in `account`. It is a thin wrapper around
# `account.contacts` that ONLY narrows for a business AGENT when the Bloomwire gate is ON — otherwise it
# returns the stock `account.contacts` relation unchanged. This is the one place every agent-facing contact
# read path (index / search / filter / show + sub-resources + global search) is routed through, so isolation
# is consistent and there is a single audit point.
#
# Behaviour:
#   - gate OFF (stock Chatwoot) .......... ALL account contacts (no behaviour change)
#   - administrator ...................... ALL account contacts (admin visibility never weakened)
#   - non-User principal (platform/nil) .. ALL account contacts (trusted; fail-open only in managed opt-in mode)
#   - business AGENT (gate ON) ........... only contacts reachable through the agent's assigned inboxes, i.e.
#                                          contacts having a contact_inbox in one of `user.inboxes` for this
#                                          account. Mirrors conversation/inbox visibility; a contact linked to
#                                          several inboxes (shared) is visible to agents of any of those inboxes.
#
# Uses a `where(id: <subquery>)` (not a DISTINCT join) so it composes cleanly with resolved_contacts, Sift
# sorting, `.includes`, and pagination on the caller side, and never returns duplicate rows.
module Bloomwire::ContactVisibility
  module_function

  def scope(account:, user:)
    contacts = account.contacts
    return contacts unless restricted_for?(account: account, user: user)

    reachable_ids = account.contacts
                           .joins(:contact_inboxes)
                           .where(contact_inboxes: { inbox_id: assigned_inbox_ids(account, user) })
                           .select(:id)
    contacts.where(id: reachable_ids)
  end

  # True only when we must narrow: the Bloomwire gate is ON AND the principal is a business AGENT (a User who
  # is a non-administrator member of this account). Admins, non-Users, and the gate-OFF state are never narrowed.
  def restricted_for?(account:, user:)
    return false unless user.is_a?(User)
    return false unless Bloomwire::Features.restrict_agent_contact_visibility?

    account_user = account.account_users.find_by(user_id: user.id)
    account_user.present? && !account_user.administrator?
  end

  # The agent's assigned inboxes in this account (inbox_members), as an id subquery. Admins never reach here.
  def assigned_inbox_ids(account, user)
    user.inboxes.where(account_id: account.id).select(:id)
  end
end
