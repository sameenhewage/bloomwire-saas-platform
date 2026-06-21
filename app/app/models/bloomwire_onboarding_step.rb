# A single onboarding/readiness step for a Bloomwire tenant (business profile).
#
# This is control-plane / readiness metadata ONLY. It tracks *where a tenant is*
# in its Bloomwire setup process. It does not represent or build any Chatwoot
# functionality (accounts, users, inboxes, channels, conversations, contacts,
# messages remain owned by Chatwoot) and never copies Chatwoot data.
#
# == Schema Information
#
# Table name: bloomwire_onboarding_steps
#
#  id                            :bigint           not null, primary key
#  position                      :integer          default(0), not null
#  status                        :string           default("pending"), not null
#  step_key                      :string           not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  bloomwire_business_profile_id :bigint           not null
#
# Indexes
#
#  idx_on_bloomwire_business_profile_id_5927964855      (bloomwire_business_profile_id)
#  index_bloomwire_onboarding_steps_on_profile_and_key  (bloomwire_business_profile_id,step_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (bloomwire_business_profile_id => bloomwire_business_profiles.id)
#
class BloomwireOnboardingStep < ApplicationRecord
  STATUSES = %w[pending in_progress completed].freeze

  # The ordered, default readiness checkpoints tracked for every tenant. These
  # are deliberately generic control-plane steps, not Chatwoot feature setup.
  DEFAULT_STEPS = %w[business_profile business_details setup_review].freeze

  belongs_to :bloomwire_business_profile

  validates :step_key, presence: true,
                       uniqueness: { scope: :bloomwire_business_profile_id }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position, :id) }
  scope :completed, -> { where(status: 'completed') }
  scope :pending, -> { where(status: 'pending') }

  def completed?
    status == 'completed'
  end
end
