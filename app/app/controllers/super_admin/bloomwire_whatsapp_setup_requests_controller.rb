class SuperAdmin::BloomwireWhatsappSetupRequestsController < SuperAdmin::ApplicationController
  before_action :ensure_bloomwire_mode_enabled
  before_action :set_request, only: [:show, :update]

  def index
    @requests = Bloomwire::WhatsappSetupRequest
                .includes(:account, :requested_by, :bloomwire_whatsapp_setup)
                .order(created_at: :desc)
  end

  def show; end

  def update
    if @request.update(request_params)
      redirect_to super_admin_bloomwire_whatsapp_setup_request_path(@request), flash: updated_flash
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_request
    @request = Bloomwire::WhatsappSetupRequest.find(params[:id])
  end

  # Ops controls status/reason and (optionally) the link to an existing setup mapping. No secret fields exist
  # on this model, so nothing sensitive can be set or echoed here.
  def request_params
    params.require(:bloomwire_whatsapp_setup_request).permit(:status, :status_reason, :bloomwire_whatsapp_setup_id)
  end

  # Managed WhatsApp setup intake is a Bloomwire-mode surface: when the master toggle is OFF the console behaves
  # like stock Chatwoot and this surface is unavailable.
  def ensure_bloomwire_mode_enabled
    return if Bloomwire::Features.master_enabled?

    redirect_to super_admin_root_path, flash: disabled_flash
  end

  def updated_flash
    { notice: 'WhatsApp setup request updated.' }
  end

  def disabled_flash
    { error: 'Bloomwire mode is disabled.' }
  end
end
