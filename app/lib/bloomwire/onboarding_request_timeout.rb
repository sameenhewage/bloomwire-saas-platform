require 'timeout'

# Endpoint-specific request timeout for the Bloomwire WhatsApp Embedded Signup endpoints ONLY.
#
# Why: a Standard/Coexistence onboarding request makes several SEQUENTIAL Meta Graph calls (register -> status
# re-check -> subscribe -> capability) and legitimately needs more than the GLOBAL 15s Rack::Timeout. When the
# global timer fired mid-`/register`, Meta connected the number but Rails returned 500 and persisted nothing
# (a split state). We do NOT weaken the global Rack::Timeout: this middleware gives ONLY the two onboarding POST
# endpoints a larger, bounded ceiling and marks the request (BYPASS_ENV_KEY) so the prepended RackTimeoutBypass
# lets it skip the global timer. Every other request keeps the unchanged global budget. A timeout returns a
# sanitized JSON body (never a token/PIN/OAuth code/App Secret/URL). It is the immediate safety layer; the durable
# fix is idempotent onboarding (safe retry) + per-call Graph HTTP timeouts (see the resilience ADR).
class Bloomwire::OnboardingRequestTimeout
  ONBOARDING_PATH = %r{/bloomwire/whatsapp/(?:coexistence_)?embedded_signup\z}
  DEFAULT_TIMEOUT_SECONDS = 75
  BYPASS_ENV_KEY = 'bloomwire.onboarding_bypass'.freeze

  # Inherits from Exception (like Rack::Timeout's own) so an app-level `rescue StandardError` cannot swallow the
  # endpoint deadline; we catch it here and render a sanitized response.
  class RequestTimeout < Exception; end # rubocop:disable Lint/InheritException,Style/OneClassPerFile

  def initialize(app, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
    @app = app
    @timeout_seconds = timeout_seconds
  end

  def call(env)
    return @app.call(env) unless onboarding_request?(env)

    env[BYPASS_ENV_KEY] = true
    Timeout.timeout(@timeout_seconds, RequestTimeout) { @app.call(env) }
  rescue RequestTimeout
    timeout_response
  end

  private

  def onboarding_request?(env)
    env['REQUEST_METHOD'] == 'POST' && env['PATH_INFO'].to_s.match?(ONBOARDING_PATH)
  end

  def timeout_response
    body = { error: 'WhatsApp setup is taking longer than expected. Please try again in a moment.',
             code: 'onboarding_timeout' }.to_json
    [503, { 'Content-Type' => 'application/json' }, [body]]
  end

  # Prepended onto Rack::Timeout so the GLOBAL request timer is skipped ONLY for a request this middleware has
  # marked as an onboarding POST. Reads env only (no shared mutable state) so it is thread-safe under Puma.
  # Every non-onboarding request falls through to Rack::Timeout's unchanged behaviour via `super`.
  module RackTimeoutBypass
    def call(env)
      return @app.call(env) if env[BYPASS_ENV_KEY]

      super
    end
  end
end
