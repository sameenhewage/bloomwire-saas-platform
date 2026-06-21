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

  # Read-only, safe summary of a profile's onboarding step progress. Carries only
  # aggregate counts plus the current (next pending) step key — no raw step
  # records, no internal ids, and no Chatwoot data.
  OnboardingStepSummary = Struct.new(:total, :completed, :pending, :current_step, :all_completed, keyword_init: true)

  belongs_to :account
  has_many :onboarding_steps, class_name: 'BloomwireOnboardingStep', dependent: :destroy

  validates :account_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :onboarding_status, presence: true, inclusion: { in: ONBOARDING_STATUSES }

  scope :active, -> { where(status: 'active') }
  scope :setup_pending, -> { where(status: 'setup_pending') }

  # Safe, read-only progress summary computed from the (preloaded) onboarding
  # steps. Does not mutate: seeding/advancing steps is owned by
  # Bloomwire::OnboardingStepTracker (see AGENTS.md rule 4 — single owner).
  def onboarding_step_summary
    steps = onboarding_steps.to_a.sort_by { |step| [step.position, step.id] }
    completed = steps.count(&:completed?)
    current = steps.find { |step| !step.completed? }

    OnboardingStepSummary.new(
      total: steps.size,
      completed: completed,
      pending: steps.size - completed,
      current_step: current&.step_key,
      all_completed: steps.any? && current.nil?
    )
  end

  # Human-readable, safe label for Super Admin UI surfaces. Encodes total,
  # completed, and the current step (or completion) without leaking ids/records.
  def onboarding_progress
    summary = onboarding_step_summary
    return 'No onboarding steps yet' if summary.total.zero?

    state = summary.all_completed ? 'all done' : "current: #{summary.current_step.to_s.humanize}"
    "#{summary.completed} of #{summary.total} steps completed · #{state}"
  end
end
