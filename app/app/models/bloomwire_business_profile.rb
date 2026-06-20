# == Schema Information
#
# Table name: bloomwire_business_profiles
#
#  id                :bigint           not null, primary key
#  industry          :string
#  onboarding_status :string           default("not_started"), not null
#  plan_name         :string
#  status            :string           default("setup_pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_bloomwire_business_profiles_on_account_id         (account_id) UNIQUE
#  index_bloomwire_business_profiles_on_onboarding_status  (onboarding_status)
#  index_bloomwire_business_profiles_on_status             (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class BloomwireBusinessProfile < ApplicationRecord
  STATUSES = %w[setup_pending active paused cancelled].freeze
  ONBOARDING_STATUSES = %w[not_started in_progress completed].freeze

  belongs_to :account

  validates :account_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :onboarding_status, presence: true, inclusion: { in: ONBOARDING_STATUSES }

  scope :active, -> { where(status: 'active') }
  scope :setup_pending, -> { where(status: 'setup_pending') }
end
