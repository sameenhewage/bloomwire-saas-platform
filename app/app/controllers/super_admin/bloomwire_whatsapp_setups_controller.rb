class SuperAdmin::BloomwireWhatsappSetupsController < SuperAdmin::ApplicationController
  before_action :ensure_bloomwire_mode_enabled
  before_action :set_setup, only: [:show, :edit, :update, :readiness]

  def index
    @setups = Bloomwire::WhatsappSetup.includes(:account, :inbox, :channel_whatsapp).order(created_at: :desc)
  end

  def show; end

  # Read-only real-hop readiness console (Phase 10A.1). Computes a secret-free checklist; never calls Meta.
  def readiness
    @readiness = Bloomwire::WhatsappRealHopReadiness.new(@setup).result
  end

  def new
    @setup = Bloomwire::WhatsappSetup.new
  end

  def edit; end

  def create
    @setup = Bloomwire::WhatsappSetup.new(setup_params)
    if @setup.save
      redirect_to super_admin_bloomwire_whatsapp_setup_path(@setup), flash: created_flash
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @setup.update(setup_params)
      redirect_to super_admin_bloomwire_whatsapp_setup_path(@setup), flash: updated_flash
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_setup
    @setup = Bloomwire::WhatsappSetup.find(params[:id])
  end

  # Non-secret fields only. Secrets (api_key, webhook_verify_token) live in Channel::Whatsapp#provider_config
  # and are intentionally NOT permitted here, so this surface can never store or echo credentials.
  def setup_params
    params.require(:bloomwire_whatsapp_setup).permit(
      :account_id, :inbox_id, :channel_whatsapp_id,
      :setup_status, :status_reason,
      :waba_id, :phone_number_id, :display_phone_number
    )
  end

  # Bloomwire WhatsApp Setup Mapping is a Bloomwire-mode surface: when the master toggle is OFF the console
  # behaves like stock Chatwoot and this surface is unavailable.
  def ensure_bloomwire_mode_enabled
    return if Bloomwire::Features.master_enabled?

    redirect_to super_admin_root_path, flash: disabled_flash
  end

  def created_flash
    { notice: 'WhatsApp setup mapping created.' }
  end

  def updated_flash
    { notice: 'WhatsApp setup mapping updated.' }
  end

  def disabled_flash
    { error: 'Bloomwire mode is disabled.' }
  end
end
