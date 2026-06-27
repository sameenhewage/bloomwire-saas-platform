class Api::V1::Accounts::InboxesController < Api::V1::Accounts::BaseController
  include Api::V1::InboxesHelper
  include Bloomwire::RestrictsNativeWhatsappSetup
  include Bloomwire::RestrictsProviderSetup
  before_action :fetch_inbox, except: [:index, :create]
  # Bloomwire: block native WhatsApp channel create / provider-config update for business users when the
  # restriction toggle is ON. Scoped to WhatsApp via native_whatsapp_setup_request?; non-WhatsApp is untouched.
  before_action :restrict_native_whatsapp_setup!, only: [:create, :update]
  # Bloomwire (Phase 11B.4B): block business admins from creating/updating EXTERNAL-credential channel inboxes
  # (email/sms/line/telegram/voice) when BLOOMWIRE_RESTRICT_PROVIDER_SETUP is ON. Scoped via
  # external_provider_channel_setup_request?; web_widget/api/WhatsApp/core paths untouched. OFF => stock.
  before_action :restrict_external_provider_channel_setup!, only: [:create, :update]
  before_action :fetch_agent_bot, only: [:set_agent_bot]
  before_action :validate_limit, only: [:create]
  # we are already handling the authorization in fetch inbox
  before_action :check_authorization, except: [:show]

  include Api::V1::Accounts::Concerns::WhatsappHealthManagement

  def index
    @inboxes = policy_scope(Current.account.inboxes)
               .includes(:channel, :portal, :working_hours, { avatar_attachment: :blob })
               .order_by_name
  end

  def show; end

  # Deprecated: This API will be removed in 2.7.0
  def assignable_agents
    @assignable_agents = @inbox.assignable_agents
  end

  def campaigns
    @campaigns = @inbox.campaigns
  end

  def avatar
    @inbox.avatar.attachment.destroy! if @inbox.avatar.attached?
    head :ok
  end

  def create
    ActiveRecord::Base.transaction do
      channel = create_channel
      @inbox = Current.account.inboxes.build(
        {
          name: inbox_name(channel),
          channel: channel
        }.merge(
          permitted_params.except(:channel)
        )
      )
      @inbox.save!
    end
  end

  def update
    inbox_params = permitted_params.except(:channel, :csat_config)
    inbox_params[:csat_config] = format_csat_config(permitted_params[:csat_config]) if permitted_params[:csat_config].present?
    @inbox.update!(inbox_params)
    update_inbox_working_hours
    update_channel if channel_update_required?
  end

  def agent_bot
    @agent_bot = @inbox.agent_bot
  end

  def set_agent_bot
    if @agent_bot
      agent_bot_inbox = @inbox.agent_bot_inbox || AgentBotInbox.new(inbox: @inbox)
      agent_bot_inbox.agent_bot = @agent_bot
      agent_bot_inbox.save!
    elsif @inbox.agent_bot_inbox.present?
      @inbox.agent_bot_inbox.destroy!
    end
    head :ok
  end

  def reset_secret
    return head :not_found unless @inbox.api?

    @inbox.channel.reset_secret!
  end

  def destroy
    ::DeleteObjectJob.perform_later(@inbox, Current.user, request.ip) if @inbox.present?
    render status: :ok, json: { message: I18n.t('messages.inbox_deletetion_response') }
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    authorize @inbox, :show?
  end

  # Bloomwire guard scope: only a WhatsApp channel CREATE (channel.type == 'whatsapp') or a WhatsApp channel
  # provider-config UPDATE (existing WhatsApp inbox + channel params present) counts as native WhatsApp setup.
  # Non-WhatsApp channels and inbox-only updates (name/working hours) are never restricted.
  def native_whatsapp_setup_request?
    if action_name == 'create'
      params.dig(:channel, :type).to_s == 'whatsapp'
    else
      @inbox&.channel.is_a?(Channel::Whatsapp) && params[:channel].present?
    end
  end

  # External-credential channel types creatable via inboxes#create (voice = enterprise Twilio voice). Note
  # 'sms' is Channel::Sms (e.g. Bandwidth); Twilio SMS/voice is Channel::TwilioSms.
  EXTERNAL_CREDENTIAL_CHANNEL_TYPES = %w[email sms line telegram voice].freeze
  EXTERNAL_CREDENTIAL_CHANNEL_CLASSES = %w[Channel::Email Channel::Sms Channel::Line Channel::Telegram Channel::TwilioSms].freeze

  # Bloomwire (Phase 11B.4B) guard scope: a CREATE of an external-credential channel type, or an UPDATE whose
  # existing channel is one of those types with channel params present (a credential / provider-config change).
  # Inbox-only updates (name/working hours), web_widget, api, and WhatsApp (its own native guard) never match.
  def external_provider_channel_setup_request?
    if action_name == 'create'
      EXTERNAL_CREDENTIAL_CHANNEL_TYPES.include?(params.dig(:channel, :type).to_s)
    else
      params[:channel].present? && EXTERNAL_CREDENTIAL_CHANNEL_CLASSES.include?(@inbox&.channel_type)
    end
  end

  def fetch_agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:agent_bot]) if params[:agent_bot]
  end

  def create_channel
    return unless allowed_channel_types.include?(permitted_params[:channel][:type])

    account_channels_method.create!(permitted_params(channel_type_from_params::EDITABLE_ATTRS)[:channel].except(:type))
  end

  def allowed_channel_types
    %w[web_widget api email line telegram whatsapp sms]
  end

  def update_inbox_working_hours
    @inbox.update_working_hours(params.permit(working_hours: Inbox::OFFISABLE_ATTRS)[:working_hours]) if params[:working_hours]
  end

  def update_channel
    channel_attributes = get_channel_attributes(@inbox.channel_type)
    return if permitted_params(channel_attributes)[:channel].blank?

    validate_and_update_email_channel(channel_attributes) if @inbox.inbox_type == 'Email'

    reauthorize_and_update_channel(channel_attributes)
    update_channel_feature_flags
  end

  def channel_update_required?
    permitted_params(get_channel_attributes(@inbox.channel_type))[:channel].present?
  end

  def validate_and_update_email_channel(channel_attributes)
    validate_email_channel(channel_attributes)
  rescue StandardError => e
    render json: { message: e }, status: :unprocessable_entity and return
  end

  def reauthorize_and_update_channel(channel_attributes)
    @inbox.channel.reauthorized! if @inbox.channel.respond_to?(:reauthorized!)
    @inbox.channel.update!(permitted_params(channel_attributes)[:channel])
  end

  def update_channel_feature_flags
    return unless @inbox.web_widget?
    return unless permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel].key? :selected_feature_flags

    @inbox.channel.selected_feature_flags = permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel][:selected_feature_flags]
    @inbox.channel.save!
  end

  def format_csat_config(config)
    formatted = {
      'display_type' => config['display_type'] || 'emoji',
      'message' => config['message'] || '',
      :survey_rules => {
        'operator' => config.dig('survey_rules', 'operator') || 'contains',
        'values' => config.dig('survey_rules', 'values') || []
      },
      'button_text' => config['button_text'] || 'Please rate us',
      'language' => config['language'] || 'en'
    }
    format_template_config(config, formatted)
    formatted
  end

  def format_template_config(config, formatted)
    formatted['template'] = config['template'] if config['template'].present?
  end

  def inbox_attributes
    [:name, :avatar, :greeting_enabled, :greeting_message, :enable_email_collect, :csat_survey_enabled,
     :enable_auto_assignment, :working_hours_enabled, :out_of_office_message, :timezone, :allow_messages_after_resolved,
     :lock_to_single_conversation, :portal_id, :sender_name_type, :business_name,
     { csat_config: [:display_type, :message, :button_text, :language,
                     { survey_rules: [:operator, { values: [] }],
                       template: [:name, :template_id, :friendly_name, :content_sid, :approval_sid, :created_at, :language, :status] }] }]
  end

  def permitted_params(channel_attributes = [])
    # We will remove this line after fixing https://linear.app/chatwoot/issue/CW-1567/null-value-passed-as-null-string-to-backend
    params.each { |k, v| params[k] = params[k] == 'null' ? nil : v }
    params.permit(*inbox_attributes, channel: [:type, *channel_attributes])
  end

  def channel_type_from_params
    {
      'web_widget' => Channel::WebWidget,
      'api' => Channel::Api,
      'email' => Channel::Email,
      'line' => Channel::Line,
      'telegram' => Channel::Telegram,
      'whatsapp' => Channel::Whatsapp,
      'sms' => Channel::Sms
    }[permitted_params[:channel][:type]]
  end

  def get_channel_attributes(channel_type)
    channel_type.constantize.const_defined?(:EDITABLE_ATTRS) ? channel_type.constantize::EDITABLE_ATTRS.presence : []
  end
end

Api::V1::Accounts::InboxesController.prepend_mod_with('Api::V1::Accounts::InboxesController')
