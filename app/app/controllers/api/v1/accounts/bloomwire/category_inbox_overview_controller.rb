# Phase 17F.1: administrator-only, READ-ONLY "Categories & Inboxes" overview endpoint. Inert (404 — stock
# Chatwoot, no overview) unless the BLOOMWIRE_CATEGORY_ADMIN_UI feature is enabled (master-gated). Admin-only via
# check_admin_authorization? (agents get Pundit not-authorized). Scoped to Current.account (no cross-account).
# Delegates to Bloomwire::CategoryInboxOverview, which composes existing primitives into a safe DTO only — it
# performs NO writes, adds NO schema, and NEVER exposes provider_config / tokens / secrets.
class Api::V1::Accounts::Bloomwire::CategoryInboxOverviewController < Api::V1::Accounts::BaseController
  before_action :ensure_category_admin_ui!
  before_action :check_admin_authorization?

  def show
    render json: ::Bloomwire::CategoryInboxOverview.call(account: Current.account)
  end

  private

  def ensure_category_admin_ui!
    head :not_found unless ::Bloomwire::Features.enabled?(:category_admin_ui)
  end
end
