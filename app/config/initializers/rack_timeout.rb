require 'rack-timeout'

# Endpoint-specific request timeout for the Bloomwire WhatsApp Embedded Signup endpoints. Those onboarding POSTs
# make several SEQUENTIAL Meta Graph calls (register -> status re-check -> subscribe -> capability) and legitimately
# need more than the GLOBAL 15s Rack::Timeout (whose default is left untouched here — every other request keeps it).
# The real middleware Bloomwire::OnboardingRequestTimeout gives ONLY the onboarding endpoints a bounded 75s ceiling
# and marks the request so the prepended RackTimeoutBypass lets that single request skip the global timer.
#
# That middleware is autoloaded from lib/ and CANNOT be referenced while the middleware stack is built during
# initialize! (autoload is unavailable then, and Rails 7.1 rejects a String middleware). This tiny top-level shim
# IS a plain class available at build time; on the FIRST request (autoload-safe, post-boot) it lazily loads the
# real middleware and prepends the bypass onto Rack::Timeout, then delegates. Inserted at the TOP of the stack so
# it always runs ABOVE the global Rack::Timeout wherever/whenever that is inserted.
class BloomwireOnboardingTimeoutShim
  def initialize(app)
    @app = app
    @delegate = nil
  end

  def call(env)
    (@delegate ||= build_delegate).call(env)
  end

  private

  def build_delegate
    Rack::Timeout.prepend(Bloomwire::OnboardingRequestTimeout::RackTimeoutBypass) if defined?(Rack::Timeout)
    Bloomwire::OnboardingRequestTimeout.new(@app)
  end
end

Rails.application.config.middleware.insert(0, BloomwireOnboardingTimeoutShim)

Rails.application.config.after_initialize do
  # Reduce noise by filtering state=ready and state=completed which are logged at INFO level
  Rack::Timeout::Logger.level = Logger::ERROR
end
