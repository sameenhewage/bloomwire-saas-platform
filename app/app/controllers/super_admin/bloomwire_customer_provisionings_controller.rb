class SuperAdmin::BloomwireCustomerProvisioningsController < SuperAdmin::ApplicationController
  before_action :ensure_bloomwire_mode_enabled

  # There is no provisioning list; the collection path simply leads to the form (the route exists so the
  # SuperAdmin layout can resolve the resource's collection path).
  def index
    redirect_to new_super_admin_bloomwire_customer_provisioning_path
  end

  # Phase 14 S3: Ops-only form to provision a new managed customer (account + owner + optional agents +
  # credential-less WhatsApp shell + setup mapping). No access token is entered here.
  def new
    @provisioning = {}
  end

  # Runs the provisioning orchestration in one transaction (no Meta calls, no token, no invite emails) and
  # sends Ops to the new setup so they can enter the access token via the Channel credentials page (S2).
  def create
    result = Bloomwire::CustomerProvisioningService.new(provisioning_params.to_h).perform
    redirect_to super_admin_bloomwire_whatsapp_setup_path(result[:setup]), flash: provisioned_flash(result)
  rescue Bloomwire::CustomerProvisioningService::ProvisioningError => e
    # Re-render with the operator's inputs preserved (this form carries no secret — credentials are S2-only).
    @provisioning = provisioning_params.to_h
    @provisioning_error = e.message
    render :new, status: :unprocessable_entity
  end

  private

  # No api_key / secret field is permitted here — credentials are handled only by the S2 credential page.
  def provisioning_params
    params.require(:provisioning).permit(:account_name, :owner_email, :owner_name, :agent_emails,
                                         :display_phone_number, :phone_number_id, :business_account_id)
  end

  # Bloomwire-mode surface: when the master toggle is OFF the console behaves like stock Chatwoot and this
  # surface is unavailable.
  def ensure_bloomwire_mode_enabled
    return if Bloomwire::Features.master_enabled?

    redirect_to super_admin_root_path, flash: { error: 'Bloomwire mode is disabled.' }
  end

  def provisioned_flash(result)
    { notice: "Provisioned account ##{result[:account].id} with a WhatsApp shell. " \
              'Enter the access token next via Channel credentials.' }
  end
end
