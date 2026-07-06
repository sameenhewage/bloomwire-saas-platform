# Receives allow-listed, sanitized BROWSER onboarding trace events for the managed WhatsApp (Coexistence)
# flow and writes them as structured JSON to the Rails application log (via Bloomwire::OnboardingTrace).
#
# Admin-only · account-scoped · feature-gated (404 when managed WhatsApp self-serve is off) · rate-limited ·
# strict event + metadata allow-list · rejects arbitrary payloads. It NEVER accepts or logs a customer-sensitive
# value (auth code / token / phone number / phone_number_id / WABA / App ID / Config ID / Meta URL). A logging
# failure must never break onboarding, so a successfully-authorized+shaped request always returns 204 even if the
# underlying write fails.
class Api::V1::Accounts::Bloomwire::Whatsapp::OnboardingTracesController < Api::V1::Accounts::BaseController
  # Disable Rails' parameter wrapping so we can inspect the EXACT submitted body keys (no injected wrapper).
  wrap_parameters false

  before_action :ensure_managed_whatsapp_self_serve!
  before_action :check_admin_authorization?
  before_action :enforce_trace_rate_limit!
  before_action :reject_forbidden_trace_keys!

  RATE_LIMIT = 120       # max trace events ...
  RATE_PERIOD = 60       # ... per this many seconds, per (account, actor)

  # The ONLY body keys a trace may carry. Anything else — unknown OR sensitive — is rejected outright (4xx),
  # not silently dropped. Explicitly covers the forbidden classes below.
  ALLOWED_KEYS = %w[onboarding_attempt_id event result elapsed_ms http_status error_code].freeze

  # Documented, explicitly-rejected sensitive/forbidden top-level keys (already excluded by the allow-list; listed
  # here as the security contract). A request carrying any of these — or any other non-allow-listed key — is 4xx.
  FORBIDDEN_KEYS = %w[
    code auth_code access_token token phone phone_number phone_number_id waba_id business_id app_id
    configuration_id url query message metadata arbitrary
  ].freeze

  def create
    attrs = trace_params
    return render(json: { error: 'unsupported_event' }, status: :unprocessable_entity) unless
      Bloomwire::OnboardingTrace.valid_event?(attrs[:event])

    Bloomwire::OnboardingTrace.emit(
      attempt_id: attrs[:onboarding_attempt_id],
      account_id: Current.account.id,
      actor_id: Current.user&.id,
      event: attrs[:event],
      source: 'browser',
      result: attrs[:result],
      elapsed_ms: attrs[:elapsed_ms],
      http_status: attrs[:http_status],
      error_code: attrs[:error_code]
    )
    # Always 204 for an authorized, allow-listed event — a trace write failure never surfaces to onboarding.
    head :no_content
  end

  private

  # Inspect the RAW submitted body BEFORE strong-parameter filtering and reject the whole request (4xx) if it
  # carries ANY top-level key outside the strict allow-list — unknown OR sensitive (see FORBIDDEN_KEYS). This
  # closes the "silently ignore and still 204" gap. No trace is emitted for a rejected request. Only field NAMES
  # are inspected; no value is ever read or echoed.
  def reject_forbidden_trace_keys!
    extra = request.request_parameters.keys.map(&:to_s) - ALLOWED_KEYS
    render(json: { error: 'forbidden_key' }, status: :bad_request) if extra.any?
  end

  # Strong params drop every key that is not explicitly allow-listed, so arbitrary/free-text payloads and
  # sensitive fields (code, access_token, phone_number_id, waba_id, business_id, ...) can never be read.
  def trace_params
    params.permit(*ALLOWED_KEYS).to_h.symbolize_keys
  end

  def ensure_managed_whatsapp_self_serve!
    return if ::Bloomwire::Features.restrict_native_whatsapp_setup? &&
              ::Bloomwire::Features.enabled?(:managed_whatsapp_onboarding)

    head :not_found
  end

  def enforce_trace_rate_limit!
    key = "bloomwire:onboarding_trace:#{Current.account.id}:#{Current.user&.id}"
    count = Rails.cache.increment(key, 1, expires_in: RATE_PERIOD.seconds)
    # Best-effort abuse protection: on a cache store without atomic increment (returns nil) we fail OPEN — the
    # limiter must never block a legitimate trace, and it is not a security control (admin + account scope are).
    return if count.nil?

    head :too_many_requests if count.to_i > RATE_LIMIT
  end
end
