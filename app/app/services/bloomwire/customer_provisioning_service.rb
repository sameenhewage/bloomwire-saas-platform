# Bloomwire Phase 14 S3: Ops/SuperAdmin customer provisioning orchestration. Creates, in one transaction, the
# technical records an Ops operator otherwise hand-builds for a new managed customer:
#   Account + Business Owner (administrator) + optional Staff/Agents + a credential-less WhatsApp CHANNEL SHELL
#   (+ its inbox) + a Bloomwire::WhatsappSetup mapping (status: configured).
#
# Deliberately out of scope (kept where they belong):
# - NO access token / secret is entered or stored here. The shell channel has no api_key; credentials are
#   entered afterwards via the SuperAdmin credential page (Phase 14 S2).
# - NO Meta calls: the shell uses save(validate: false) (skips the credential re-check) and source
#   'bloomwire_managed' + a blank api_key (Channel::Whatsapp guards skip template sync + native webhook setup),
#   so creation makes zero graph.facebook.com calls. Inbound stays on the global router.
# - NO invitation emails: the owner is created confirmed (AccountBuilder confirmed: true) and agents with
#   skip_confirmation!, so Devise sends nothing. Operators share access out-of-band / via password reset.
class Bloomwire::CustomerProvisioningService
  class ProvisioningError < StandardError; end

  # source marker so Channel::Whatsapp#should_auto_setup_webhooks? skips the native per-channel webhook.
  MANAGED_SOURCE = 'bloomwire_managed'.freeze

  def initialize(attributes = {})
    @attrs = (attributes || {}).to_h.symbolize_keys
  end

  def perform
    normalize!
    validate!

    ActiveRecord::Base.transaction do
      create_account_and_owner
      create_agents
      create_channel_shell
      create_inbox
      attach_agents_to_inbox
      create_setup_mapping
    end

    { account: @account, owner: @owner, agents: @agents, channel: @channel, inbox: @inbox, setup: @setup }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, CustomExceptions::Account::UserExists,
         CustomExceptions::Account::InvalidEmail => e
    raise ProvisioningError, e.message
  end

  private

  def normalize!
    @account_name = @attrs[:account_name].to_s.strip
    @owner_email = @attrs[:owner_email].to_s.strip.downcase
    @owner_name = @attrs[:owner_name].to_s.strip.presence
    @phone_number_id = @attrs[:phone_number_id].to_s.strip
    @business_account_id = @attrs[:business_account_id].to_s.strip
    # Keep digits only; channel.phone_number is "+<display>" and the setup stores the bare display number.
    @display_digits = @attrs[:display_phone_number].to_s.gsub(/\D/, '')
    @agent_email_list = parse_agent_emails(@attrs[:agent_emails])
    @agents = []
  end

  def parse_agent_emails(raw)
    raw.to_s.split(/[\s,;]+/).map { |email| email.strip.downcase }.reject(&:blank?).uniq
  end

  def validate!
    {
      'Account name' => @account_name, 'Business owner email' => @owner_email,
      'Display phone number' => @display_digits, 'Phone Number ID' => @phone_number_id,
      'Business Account ID (WABA ID)' => @business_account_id
    }.each { |label, value| raise ProvisioningError, "#{label} is required" if value.blank? }

    raise ProvisioningError, 'A WhatsApp channel with this phone number already exists' if channel_phone_taken?
    raise ProvisioningError, 'A WhatsApp setup with this Phone Number ID already exists' if phone_number_id_taken?
  end

  def channel_phone_taken?
    Channel::Whatsapp.exists?(phone_number: channel_phone_number)
  end

  def phone_number_id_taken?
    Bloomwire::WhatsappSetup.exists?(phone_number_id: @phone_number_id)
  end

  def channel_phone_number
    "+#{@display_digits}"
  end

  def create_account_and_owner
    @owner, @account = AccountBuilder.new(
      account_name: @account_name,
      email: @owner_email,
      user_full_name: @owner_name,
      user_password: temp_password,
      confirmed: true # confirmed => no Devise confirmation email; AccountUser is administrator, no inviter
    ).perform
  end

  def create_agents
    @agent_email_list.each do |email|
      next if email == @owner_email

      user = find_or_create_confirmed_user(email)
      unless AccountUser.exists?(account_id: @account.id, user_id: user.id)
        AccountUser.create!(account_id: @account.id, user_id: user.id, role: AccountUser.roles['agent'])
      end
      @agents << user
    end
  end

  # Mirrors AgentBuilder/Seeders::AccountSeeder but with skip_confirmation! so no invitation email is sent.
  def find_or_create_confirmed_user(email)
    existing = User.from_email(email)
    return existing if existing

    password = temp_password
    user = User.new(email: email, name: email.split('@').first, password: password, password_confirmation: password)
    user.skip_confirmation!
    user.save!
    user
  end

  # Credential-less shell: no api_key (entered later via the S2 credential page). validate: false skips the
  # Meta credential re-check; source 'bloomwire_managed' + blank api_key skip native webhook + template sync.
  def create_channel_shell
    @channel = Channel::Whatsapp.new(
      account: @account,
      phone_number: channel_phone_number,
      provider: 'whatsapp_cloud',
      provider_config: { 'phone_number_id' => @phone_number_id, 'business_account_id' => @business_account_id,
                         'source' => MANAGED_SOURCE }
    )
    @channel.save!(validate: false)
  end

  def create_inbox
    @inbox = Inbox.create!(account: @account, name: "#{@account_name} WhatsApp", channel: @channel)
  end

  def attach_agents_to_inbox
    @agents.each do |user|
      InboxMember.create!(inbox: @inbox, user: user) unless InboxMember.exists?(inbox_id: @inbox.id, user_id: user.id)
    end
  end

  def create_setup_mapping
    @setup = Bloomwire::WhatsappSetup.create!(
      account: @account, inbox: @inbox, channel_whatsapp: @channel,
      phone_number_id: @phone_number_id, waba_id: @business_account_id,
      display_phone_number: @display_digits, setup_status: 'configured'
    )
  end

  # Strong throwaway password meeting User password-content rules; never displayed. Owner/agents set their own
  # via the standard password-reset flow (no invite email is sent by this Ops flow).
  def temp_password
    "1!aA#{SecureRandom.alphanumeric(20)}"
  end
end
