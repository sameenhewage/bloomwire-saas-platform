class SuperAdmin::BloomwireWhatsappSetupsController < SuperAdmin::ApplicationController
  before_action :ensure_bloomwire_mode_enabled
  before_action :set_setup, only: [:show, :edit, :update, :readiness, :credentials, :update_credentials]
  before_action :set_credential_channel, only: [:credentials, :update_credentials]

  def index
    @setups = Bloomwire::WhatsappSetup.includes(:account, :inbox, :channel_whatsapp).order(created_at: :desc)
    # Phase 12E: per-setup non-secret operational observability (reuses the readiness calculator; never Meta).
    @readiness = @setups.index_with { |setup| Bloomwire::WhatsappRealHopReadiness.new(setup).result }
    @linked_setup_ids = Bloomwire::WhatsappSetupRequest.where.not(bloomwire_whatsapp_setup_id: nil)
                                                       .distinct.pluck(:bloomwire_whatsapp_setup_id).to_set
  end

  def show
    # Phase 12E: surface the same non-secret operational state (masked ids + readiness) on the detail page.
    @readiness = Bloomwire::WhatsappRealHopReadiness.new(@setup).result
    @request_linked = Bloomwire::WhatsappSetupRequest.exists?(bloomwire_whatsapp_setup_id: @setup.id)
  end

  # Read-only real-hop readiness console (Phase 10A.1). Computes a secret-free checklist; never calls Meta.
  def readiness
    @readiness = Bloomwire::WhatsappRealHopReadiness.new(@setup).result
  end

  # Phase 14 S2a: Ops-only credential-capture form for the linked channel's provider_config. The api_key is
  # WRITE-ONLY — the stored token is never rendered (only its presence). Non-secret routing ids are shown masked.
  def credentials; end

  # Phase 14 S2a: merge submitted credentials into the channel's provider_config via the writer service. The
  # writer keeps a blank api_key (no-wipe) and saves with validate: false, so no live Meta call is made.
  def update_credentials
    Bloomwire::WhatsappCredentialWriter.new(channel: @channel, attributes: credential_params.to_h).perform
    redirect_to super_admin_bloomwire_whatsapp_setup_path(@setup), flash: credentials_updated_flash
  rescue StandardError => e
    Rails.logger.error("[BLOOMWIRE CREDENTIALS] update failed: #{e.class}")
    @credential_error = 'Could not update credentials. Please check the values and try again.'
    render :credentials, status: :unprocessable_entity
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

  # The credential surface writes to the setup's linked WhatsApp channel. It is intentionally edit-only:
  # a setup with no linked channel has nothing to credential, so redirect (S2 never creates channels).
  def set_credential_channel
    @channel = @setup.channel_whatsapp
    return if @channel.present?

    redirect_to super_admin_bloomwire_whatsapp_setup_path(@setup), flash: no_channel_flash
  end

  # Only the channel provider_config fields this Ops surface is allowed to write (api_key is the write-only
  # secret). webhook_verify_token / verification_pin are intentionally NOT permitted here.
  def credential_params
    params.require(:provider_config).permit(:api_key, :phone_number_id, :business_account_id)
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

  def credentials_updated_flash
    { notice: 'WhatsApp channel credentials updated.' }
  end

  def no_channel_flash
    { error: 'Link a WhatsApp channel to this setup before entering credentials.' }
  end

  def disabled_flash
    { error: 'Bloomwire mode is disabled.' }
  end
end
