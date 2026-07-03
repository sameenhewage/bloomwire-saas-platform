class Api::V1::Accounts::Actions::ContactMergesController < Api::V1::Accounts::BaseController
  before_action :set_base_contact, only: [:create]
  before_action :set_mergee_contact, only: [:create]

  def create
    contact_merge_action = ContactMergeAction.new(
      account: Current.account,
      base_contact: @base_contact,
      mergee_contact: @mergee_contact
    )
    contact_merge_action.perform
  end

  private

  def set_base_contact
    @base_contact = contacts.find(params[:base_contact_id])
  end

  def set_mergee_contact
    @mergee_contact = contacts.find(params[:mergee_contact_id])
  end

  def contacts
    # Phase 17E.4: scope by Bloomwire contact visibility so a gated agent cannot merge (base or mergee) a contact
    # outside their assigned-inbox visibility (out-of-scope => RecordNotFound => 404). Admin / stock (gate OFF) =>
    # account.contacts, unchanged.
    @contacts ||= Bloomwire::ContactVisibility.scope(account: Current.account, user: Current.user)
  end
end
