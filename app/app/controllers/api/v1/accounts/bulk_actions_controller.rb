class Api::V1::Accounts::BulkActionsController < Api::V1::Accounts::BaseController
  def create
    case normalized_type
    when 'Conversation'
      enqueue_conversation_job
      head :ok
    when 'Contact'
      check_authorization_for_contact_action
      enqueue_contact_job
      head :ok
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def normalized_type
    params[:type].to_s.camelize
  end

  def enqueue_conversation_job
    ::BulkActionsJob.perform_later(
      account: @current_account,
      user: current_user,
      params: conversation_params
    )
  end

  def enqueue_contact_job
    Contacts::BulkActionJob.perform_later(
      @current_account.id,
      current_user.id,
      scoped_contact_params
    )
  end

  # Phase 17E.2 (PR #114 review): a gated business agent may only bulk-act on contacts reachable through their
  # assigned inboxes. Filter the requested contact IDs through the Bloomwire contact-visibility seam BEFORE
  # enqueueing the async job, so out-of-scope IDs are never handed to the mutation (label add/remove/delete).
  # Admins and the stock (gate OFF) state pass their IDs through unchanged — no behaviour change.
  def scoped_contact_params
    permitted = contact_params
    return permitted unless Bloomwire::ContactVisibility.restricted_for?(account: @current_account, user: current_user)

    # `contact_params` is a string-keyed hash, so read/write the `ids` key with a string (works for both a
    # plain hash and ActionController::Parameters) to avoid leaving a stale, conflicting key behind.
    visible_ids = Bloomwire::ContactVisibility.scope(account: @current_account, user: current_user)
                                              .where(id: permitted['ids']).pluck(:id)
    permitted.merge('ids' => visible_ids)
  end

  def delete_contact_action?
    params[:action_name] == 'delete'
  end

  def check_authorization_for_contact_action
    authorize(Contact, :destroy?) if delete_contact_action?
  end

  def conversation_params
    # TODO: Align conversation payloads with the `{ action_name, action_attributes }`
    # and then remove this method in favor of a common params method.
    base = params.permit(
      :snoozed_until,
      fields: [:status, :assignee_id, :team_id]
    )
    append_common_bulk_attributes(base)
  end

  def contact_params
    # TODO: remove this method in favor of a common params method.
    # once legacy conversation payloads are migrated.
    append_common_bulk_attributes({})
  end

  def append_common_bulk_attributes(base_params)
    # NOTE: Conversation payloads historically diverged per action. Going forward we
    # want all objects to share a common contract: `{ action_name, action_attributes }`
    common = params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])
    base_params.merge(common)
  end
end
