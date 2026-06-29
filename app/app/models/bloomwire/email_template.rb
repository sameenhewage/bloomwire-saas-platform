# Phase 15F: a reusable, owner-managed outbound email template. Bloomwire-owned (not a Chatwoot/Enterprise
# table and NOT a conversation/message store). Template text is not a secret. Supports simple
# `{{variable}}` placeholders that are interpolated for preview and (later) sending.
# == Schema Information
#
# Table name: bloomwire_email_templates
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  body               :text
#  category           :string
#  cta_label          :string
#  cta_url            :string
#  key                :string           not null
#  name               :string           not null
#  position           :integer          default(0), not null
#  subject            :string
#  system             :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  last_updated_by_id :bigint
#
# Indexes
#
#  index_bloomwire_email_templates_on_key                 (key) UNIQUE
#  index_bloomwire_email_templates_on_last_updated_by_id  (last_updated_by_id)
#
class Bloomwire::EmailTemplate < ApplicationRecord
  self.table_name = 'bloomwire_email_templates'

  belongs_to :last_updated_by, class_name: 'User', optional: true

  # Allowed template categories (display/grouping only).
  CATEGORIES = %w[Onboarding Security Billing Support Notifications].freeze

  # Supported placeholder variables (UI "Variables" helper + preview sample data).
  VARIABLES = %w[recipient_name business_name invitation_link reset_link expiry_time support_email].freeze

  # Sample values used to render the "Preview with Sample Data" panel. Non-secret, illustrative only.
  SAMPLE_VARS = {
    'recipient_name' => 'Sameen Hewage',
    'business_name' => 'Bloomwire (Pvt) Ltd',
    'invitation_link' => 'https://app.bloomwire.lk/invitations/sample-token',
    'reset_link' => 'https://app.bloomwire.lk/password/reset/sample-token',
    'expiry_time' => '7 days',
    'support_email' => 'support@bloomwire.lk'
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :subject, presence: true
  validates :body, presence: true
  # A system template's key is immutable (future template routing depends on stable keys). Defense-in-depth
  # on top of the controller not permitting :key — holds for direct/console/service updates too.
  validate :system_key_immutable, on: :update
  # CTA URL must be a safe scheme: an http(s) URL or a {{variable}} placeholder (resolved at send/preview).
  # Blocks javascript:/data: and similar from ever reaching a rendered href.
  validate :cta_url_safe_scheme

  scope :ordered, -> { order(:position, :id) }
  scope :active, -> { where(active: true) }

  # Interpolates `{{ variable }}` placeholders. Unknown variables are left intact so the author can see
  # they are unresolved (rather than silently blanking them).
  def self.interpolate(text, vars = SAMPLE_VARS)
    text.to_s.gsub(/\{\{\s*([a-z_]+)\s*\}\}/) do
      key = Regexp.last_match(1)
      vars.key?(key) ? vars[key].to_s : "{{#{key}}}"
    end
  end

  def render_subject(vars = SAMPLE_VARS)
    self.class.interpolate(subject, vars)
  end

  def render_body(vars = SAMPLE_VARS)
    self.class.interpolate(body, vars)
  end

  def render_cta_url(vars = SAMPLE_VARS)
    self.class.interpolate(cta_url, vars)
  end

  def cta?
    cta_label.present?
  end

  # Duplicates a template into a new, inactive draft with a unique key/name.
  def duplicate!(actor: nil)
    base = key.sub(/_copy(\d+)?\z/, '')
    new_key = "#{base}_copy"
    i = 2
    new_key = "#{base}_copy#{i += 1}" while self.class.exists?(key: new_key)

    self.class.create!(
      key: new_key, name: "#{name} (Copy)", category: category, subject: subject, body: body,
      cta_label: cta_label, cta_url: cta_url, active: false, system: false,
      position: (self.class.maximum(:position).to_i + 1), last_updated_by: actor
    )
  end

  def activate!(actor: nil)
    update!(active: true, last_updated_by: actor)
  end

  def deactivate!(actor: nil)
    update!(active: false, last_updated_by: actor)
  end

  # The 6 system default templates (idempotently seeded). Bodies are plain text with {{variables}}; the
  # preview/email shell adds the Bloomwire branding + optional CTA button.
  DEFAULTS = [
    {
      key: 'new_business_invitation', name: 'New Business Invitation', category: 'Onboarding',
      subject: "You're invited to join {{business_name}} on Bloomwire",
      body: "Hi {{recipient_name}},\n\nYou have been invited to join {{business_name}} on Bloomwire. " \
            'Bloomwire is a WhatsApp-first customer engagement platform. Click the button below to accept ' \
            "the invitation and set up your account.\n\nThis invitation will expire in {{expiry_time}}.\n" \
            "If you didn't expect this email, you can safely ignore it.\n\nBest regards,\nThe Bloomwire Team",
      cta_label: 'Accept Invitation', cta_url: '{{invitation_link}}', position: 1
    },
    {
      key: 'password_reset', name: 'Password Reset', category: 'Security',
      subject: 'Reset your Bloomwire password',
      body: "Hi {{recipient_name}},\n\nWe received a request to reset your Bloomwire password. Click the " \
            "button below to choose a new password.\n\nThis link will expire in {{expiry_time}}.\n" \
            "If you didn't request this, you can safely ignore this email or contact {{support_email}}.\n\n" \
            "Best regards,\nThe Bloomwire Team",
      cta_label: 'Reset Password', cta_url: '{{reset_link}}', position: 2
    },
    {
      key: 'welcome_email', name: 'Welcome Email', category: 'Onboarding',
      subject: 'Welcome to Bloomwire, {{recipient_name}}!',
      body: "Hi {{recipient_name}},\n\nWelcome to Bloomwire! Your workspace for {{business_name}} is ready. " \
            "Bloomwire helps you talk to your customers on WhatsApp from one shared inbox.\n\n" \
            "If you need a hand getting started, reach us at {{support_email}}.\n\n" \
            "Best regards,\nThe Bloomwire Team",
      cta_label: 'Open Bloomwire', cta_url: '{{invitation_link}}', position: 3
    },
    {
      key: 'plan_change_notification', name: 'Plan Change Notification', category: 'Billing',
      subject: 'Your Bloomwire plan for {{business_name}} has changed',
      body: "Hi {{recipient_name}},\n\nThis is a confirmation that the Bloomwire plan for {{business_name}} " \
            "has been updated. The change takes effect on your next billing cycle.\n\n" \
            "Questions? Contact {{support_email}}.\n\nBest regards,\nThe Bloomwire Team",
      cta_label: 'View Billing', cta_url: '{{invitation_link}}', position: 4
    },
    {
      key: 'payment_receipt', name: 'Payment Receipt', category: 'Billing',
      subject: 'Your Bloomwire payment receipt for {{business_name}}',
      body: "Hi {{recipient_name}},\n\nThank you for your payment. This email is your receipt for the " \
            "Bloomwire subscription for {{business_name}}.\n\nA detailed invoice is available in your " \
            "billing settings. For help, contact {{support_email}}.\n\nBest regards,\nThe Bloomwire Team",
      cta_label: 'View Invoice', cta_url: '{{invitation_link}}', position: 5
    },
    {
      key: 'support_ticket_update', name: 'Support Ticket Update', category: 'Support',
      subject: 'Update on your Bloomwire support request',
      body: "Hi {{recipient_name}},\n\nThere's an update on your support request for {{business_name}}. " \
            "Our team has responded — click below to view the latest reply.\n\n" \
            "You can also reach us any time at {{support_email}}.\n\nBest regards,\nThe Bloomwire Team",
      cta_label: 'View Ticket', cta_url: '{{invitation_link}}', position: 6
    }
  ].freeze

  # Idempotently seeds the system default templates. Safe to run repeatedly (only creates missing keys).
  def self.seed_defaults!
    DEFAULTS.each do |attrs|
      next if exists?(key: attrs[:key])

      create!(attrs.merge(system: true, active: true))
    end
  end

  private

  def system_key_immutable
    return unless system? && key_changed?

    errors.add(:key, 'of a system template cannot be changed')
  end

  def cta_url_safe_scheme
    return if cta_url.blank?

    stripped = cta_url.strip
    return if stripped.start_with?('{{') # a {{variable}} placeholder, resolved to a real URL at send/preview
    return if stripped.match?(%r{\Ahttps?://}i)

    errors.add(:cta_url, 'must be an http(s) URL or a {{variable}} placeholder')
  end
end
