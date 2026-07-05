# Phase 17F.3: administrator-only, feature-gated endpoint that additively aligns staff between an existing Team
# (category) and an existing Inbox. Inert (404 — stock Chatwoot) unless BLOOMWIRE_CATEGORY_ADMIN_UI is enabled.
# Admin-only via check_admin_authorization? (agents get 401). Team + Inbox are scoped to Current.account, so
# cross-account ids raise RecordNotFound (404). Delegates to Bloomwire::CategoryInboxAlignment, which performs the
# additive TeamMember/InboxMember writes in ONE transaction — no schema, no persisted mapping, no Meta/external call.
class Api::V1::Accounts::Bloomwire::CategoryInboxAlignmentsController < Api::V1::Accounts::BaseController
  before_action :ensure_category_admin_ui!
  before_action :check_admin_authorization?
  before_action :set_team_and_inbox

  def create
    render json: ::Bloomwire::CategoryInboxAlignment.call(
      account: Current.account, team: @team, inbox: @inbox, user_ids: alignment_params[:user_ids]
    )
  rescue ::Bloomwire::CategoryInboxAlignment::InvalidMember => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_team_and_inbox
    @team = Current.account.teams.find(alignment_params[:team_id])
    @inbox = Current.account.inboxes.find(alignment_params[:inbox_id])
  end

  def alignment_params
    params.permit(:team_id, :inbox_id, user_ids: [])
  end

  def ensure_category_admin_ui!
    head :not_found unless ::Bloomwire::Features.enabled?(:category_admin_ui)
  end
end
