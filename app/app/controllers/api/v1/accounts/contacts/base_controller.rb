class Api::V1::Accounts::Contacts::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_contact

  private

  def ensure_contact
    # Phase 17E.2: sub-resources (notes/labels/attachments/conversations/contact_inboxes) load the contact
    # through the Bloomwire contact-visibility seam, so an agent cannot reach a contact outside their assigned
    # inboxes (gate ON) → RecordNotFound (404). Admins/stock are unchanged.
    @contact = Bloomwire::ContactVisibility.scope(account: Current.account, user: Current.user).find(params[:contact_id])
  end
end
