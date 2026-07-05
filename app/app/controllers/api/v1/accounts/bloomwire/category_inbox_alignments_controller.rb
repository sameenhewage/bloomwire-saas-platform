# Phase 17F.3: administrator-only, feature-gated endpoint that additively aligns staff between an existing Team
# (category) and an existing Inbox. Inert (404 — stock Chatwoot) unless BLOOMWIRE_CATEGORY_ADMIN_UI is enabled.
# Admin-only via check_admin_authorization? (agents get 401). The request carries ONLY the account-scoped Team +
# Inbox identity (no membership list); cross-account ids raise RecordNotFound (404). Bloomwire::CategoryInboxAlignment
# is SERVER-AUTHORITATIVE: it recomputes eligibility (currently-derived, unambiguous pair) and the additive drift from
# fresh DB state, then adds only those server-computed differences in ONE database transaction. An ineligible pair
# (unrelated / ambiguous / unlinked / stale) fails closed with 422. No schema, no persisted mapping, no external call.
class Api::V1::Accounts::Bloomwire::CategoryInboxAlignmentsController < Api::V1::Accounts::BaseController
  before_action :ensure_category_admin_ui!
  before_action :check_admin_authorization?
  before_action :set_team_and_inbox

  def create
    render json: ::Bloomwire::CategoryInboxAlignment.call(
      account: Current.account, team: @team, inbox: @inbox
    )
  rescue ::Bloomwire::CategoryInboxAlignment::NotEligible
    render json: { error: 'not_eligible' }, status: :unprocessable_entity
  end

  private

  def set_team_and_inbox
    @team = Current.account.teams.find(alignment_params[:team_id])
    @inbox = Current.account.inboxes.find(alignment_params[:inbox_id])
  end

  # Identity only — deliberately NO user_ids. Membership to add is computed server-side, never client-supplied.
  def alignment_params
    params.permit(:team_id, :inbox_id)
  end

  def ensure_category_admin_ui!
    head :not_found unless ::Bloomwire::Features.enabled?(:category_admin_ui)
  end
end
