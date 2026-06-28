module SuperAdmin::BloomwireUiHelper
  # Whether the Bloomwire managed-mode master toggle is ON (drives the header badge + Bloomwire nav section).
  def bw_bloomwire_mode_on?
    Bloomwire::Features.master_enabled?
  rescue StandardError
    false
  end

  # Whether the sidebar "WhatsApp Setups" group should render expanded (on any WhatsApp surface).
  def bw_whatsapp_section_open?
    %w[bloomwire_whatsapp_setups bloomwire_customer_provisionings
       bloomwire_whatsapp_setup_requests].include?(controller_name)
  end

  # Whether the current SuperAdmin is an active platform OWNER (drives owner-only nav: Platform Admins).
  def bw_platform_owner?
    admin = current_super_admin if respond_to?(:current_super_admin)
    return false if admin.blank?

    Bloomwire::PlatformAdmin.active_owners.exists?(user_id: admin.id)
  rescue StandardError
    false
  end

  # Environment label for the header/footer. Prefers an explicit BLOOMWIRE_ENV label (optional, read-only)
  # and falls back to Rails.env. Reading an optional env var does not change any toggle/behavior.
  def bw_environment_label
    (ENV['BLOOMWIRE_ENV'].presence || Rails.env).to_s
  end

  # Short release identifier for the footer (build SHA; not a secret). Nil when unknown.
  def bw_release_sha
    sha = defined?(GIT_HASH) ? GIT_HASH.to_s : ''
    return if sha.blank? || sha == 'unknown'

    sha.first(7)
  end

  # Initials for the SuperAdmin avatar. Never renders the full email/name, only up to 2 initials.
  def bw_admin_initials(admin = (current_super_admin if respond_to?(:current_super_admin)))
    source = admin.try(:name).presence || admin.try(:email).to_s
    return 'SA' if source.blank?

    parts = source.split(/[\s@._-]+/).reject(&:blank?)
    (parts.first(2).pluck(0).join.presence || source[0, 2]).upcase
  end

  # Renders a breadcrumb trail. Each crumb is a String, or a [label, path] pair (linked unless it is last).
  def bw_crumbs(*crumbs)
    safe_join(crumbs.each_with_index.map do |crumb, index|
      label, path = crumb.is_a?(Array) ? crumb : [crumb, nil]
      last = index == crumbs.length - 1
      node = if path && !last
               link_to(label, path, class: 'bw-breadcrumb__link')
             else
               content_tag(:span, label, class: (last ? 'bw-breadcrumb__current' : nil))
             end
      last ? node : safe_join([node, content_tag(:span, '/', class: 'bw-breadcrumb__sep')])
    end)
  end

  # Renders a status string as a semantic pill. Status keeps its own semantic color regardless of the
  # customer accent (success/warning/danger/info/neutral) — accent never overrides status colors.
  def bw_status_badge(status, label: nil, variant: nil)
    status_str = status.to_s
    css_variant = variant || bw_status_variant(status_str)
    content_tag(:span, (label || status_str.titleize),
                class: "bw-badge bw-badge--#{css_variant}", data: { status: status_str })
  end

  # Central mapping of operational statuses -> semantic badge variant (was duplicated inline across views).
  def bw_status_variant(status)
    case status.to_s
    when 'ready_for_webhook', 'ready', 'pass', 'completed', 'linked', 'approved', 'active'
      'success'
    when 'blocked', 'failed', 'rejected', 'error', 'suspended'
      'danger'
    when 'pending', 'in_progress', 'awaiting', 'requested', 'received'
      'warning'
    when 'configured', 'ready_for_credentials'
      'info'
    else
      'neutral'
    end
  end
end
