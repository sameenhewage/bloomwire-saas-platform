# Bloomwire-owned ownership/routing record for an external-app channel (ADR 0005).
#
# Records WHICH Chatwoot inbox/channel Bloomwire configured for WHICH tenant, plus
# the NON-SECRET routing identifiers a future global webhook router (ADR 0004) will
# use. WhatsApp is the first vertical.
#
# Source-of-truth rule (see projects/bloomwire-chatwoot-platform/CONTEXT.md):
# Chatwoot remains the owner of inboxes, channels, conversations, messages, and
# contacts. This table never duplicates conversation data and never stores provider
# secrets (api_key/access tokens, webhook_verify_token, raw provider_config) — those
# stay in Channel::Whatsapp#provider_config. It only mirrors non-secret ownership and
# routing metadata. Creating a row changes no Chatwoot behavior and no policy decision.
#
# == Schema Information
#
# Table name: bloomwire_channel_integrations
#
#  id                            :bigint           not null, primary key
#  app_kind                      :string           not null
#  business_account_id           :string
#  channelable_type              :string           not null
#  managed_by_bloomwire          :boolean          default(TRUE), not null
#  phone_number                  :string
#  phone_number_id               :string
#  provider                      :string           not null
#  routing_key                   :string
#  status                        :string           default("pending"), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  bloomwire_business_profile_id :bigint           not null
#  channelable_id                :bigint           not null
#  created_by_super_admin_id     :bigint
#  inbox_id                      :bigint           not null
#
# Indexes
#
#  index_bloomwire_channel_integrations_on_account_id             (account_id)
#  index_bloomwire_channel_integrations_on_app_kind_and_provider  (app_kind,provider)
#  index_bloomwire_channel_integrations_on_channelable            (channelable_type,channelable_id)
#  index_bloomwire_channel_integrations_on_inbox_id               (inbox_id) UNIQUE
#  index_bloomwire_channel_integrations_on_status                 (status)
#  index_bw_channel_integrations_on_business_account_id           (business_account_id) WHERE (business_account_id IS NOT NULL)
#  index_bw_channel_integrations_on_created_by_sa_id              (created_by_super_admin_id)
#  index_bw_channel_integrations_on_phone_number_id               (phone_number_id) WHERE (phone_number_id IS NOT NULL)
#  index_bw_channel_integrations_on_profile_id                    (bloomwire_business_profile_id)
#  index_bw_channel_integrations_on_routing_key                   (routing_key) UNIQUE WHERE (routing_key IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (bloomwire_business_profile_id => bloomwire_business_profiles.id)
#  fk_rails_...  (created_by_super_admin_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class BloomwireChannelIntegration < ApplicationRecord
  STATUSES = %w[pending active disabled].freeze
  APP_KINDS = %w[whatsapp sms email instagram facebook shopify].freeze

  belongs_to :bloomwire_business_profile
  belongs_to :account
  belongs_to :inbox
  belongs_to :channelable, polymorphic: true
  belongs_to :created_by_super_admin, class_name: 'SuperAdmin', optional: true

  validates :bloomwire_business_profile, presence: true
  validates :account, presence: true
  validates :inbox, presence: true
  validates :channelable, presence: true
  validates :app_kind, presence: true, inclusion: { in: APP_KINDS }
  validates :provider, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :inbox_id, uniqueness: true, allow_nil: true
  validates :routing_key, uniqueness: true, allow_nil: true

  # Tenant consistency (ADR 0005): a row must never span two tenants/accounts.
  # Each check fails safely so an invalid combination is rejected (nothing persisted)
  # rather than stored as a mixed-tenant row.
  validate :profile_within_account
  validate :inbox_within_account
  validate :channelable_is_inbox_channel
  validate :channelable_within_account

  scope :managed, -> { where(managed_by_bloomwire: true) }
  scope :for_app_kind, ->(kind) { where(app_kind: kind) }

  private

  def profile_within_account
    return if bloomwire_business_profile.nil? || account_id.nil?
    return if bloomwire_business_profile.account_id == account_id

    errors.add(:bloomwire_business_profile, 'must belong to the same account')
  end

  def inbox_within_account
    return if inbox.nil? || account_id.nil?
    return if inbox.account_id == account_id

    errors.add(:inbox, 'must belong to the same account')
  end

  def channelable_is_inbox_channel
    return if inbox.nil? || channelable.nil?
    return if inbox.channel_id == channelable_id && inbox.channel_type == channelable_type

    errors.add(:channelable, 'must be the channel of the linked inbox')
  end

  def channelable_within_account
    return if channelable.nil? || account_id.nil?
    return unless channelable.respond_to?(:account_id)
    return if channelable.account_id == account_id

    errors.add(:channelable, 'must belong to the same account')
  end
end
