require 'rails_helper'

# Endpoint-specific request timeout for the Bloomwire WhatsApp Embedded Signup endpoints ONLY. The onboarding
# request makes several sequential Meta Graph calls (register -> status re-check -> subscribe -> capability) and
# legitimately needs more than the global 15s Rack::Timeout. This middleware gives ONLY those endpoints a larger
# ceiling and marks the request so the global Rack::Timeout timer is bypassed for it — every OTHER request keeps
# the unchanged global budget. A timeout returns a sanitized JSON body (never a token/PIN/code/App Secret).
RSpec.describe Bloomwire::OnboardingRequestTimeout do
  let(:ok_app) { ->(_env) { [200, { 'Content-Type' => 'application/json' }, ['{"ok":true}']] } }

  def env_for(path, method: 'POST')
    { 'PATH_INFO' => path, 'REQUEST_METHOD' => method }
  end

  describe 'non-onboarding requests (global Rack::Timeout must stay in charge)' do
    it 'passes the request through untouched and never sets the bypass flag' do
      env = env_for('/api/v1/accounts/1/conversations', method: 'GET')
      status, = described_class.new(ok_app).call(env)
      aggregate_failures do
        expect(status).to eq(200)
        expect(env).not_to have_key(described_class::BYPASS_ENV_KEY)
      end
    end

    it 'does not treat a GET to the embedded_signup path as an onboarding POST' do
      env = env_for('/api/v1/accounts/1/bloomwire/whatsapp/embedded_signup', method: 'GET')
      described_class.new(ok_app).call(env)
      expect(env).not_to have_key(described_class::BYPASS_ENV_KEY)
    end
  end

  describe 'onboarding POST within budget' do
    it 'marks the request to bypass the global Rack::Timeout and returns the app response' do
      env = env_for('/api/v1/accounts/1/bloomwire/whatsapp/embedded_signup')
      status, = described_class.new(ok_app, timeout_seconds: 5).call(env)
      aggregate_failures do
        expect(status).to eq(200)
        expect(env[described_class::BYPASS_ENV_KEY]).to be(true)
      end
    end

    it 'also covers the coexistence embedded signup endpoint' do
      env = env_for('/api/v1/accounts/1/bloomwire/whatsapp/coexistence_embedded_signup')
      described_class.new(ok_app, timeout_seconds: 5).call(env)
      expect(env[described_class::BYPASS_ENV_KEY]).to be(true)
    end
  end

  describe 'onboarding POST exceeding the endpoint budget' do
    let(:slow_app) { ->(_env) { sleep 0.3 } }

    it 'returns a sanitized 503 timeout (no secret/PII leakage) instead of hanging' do
      env = env_for('/api/v1/accounts/1/bloomwire/whatsapp/embedded_signup')
      status, headers, body = described_class.new(slow_app, timeout_seconds: 0.05).call(env)
      payload = Array(body).join
      aggregate_failures do
        expect(status).to eq(503)
        expect(headers['Content-Type']).to match(%r{application/json})
        expect(payload).to include('onboarding_timeout')
        expect(payload).not_to match(/token|pin|secret|Bearer|EAA/i)
      end
    end
  end

  describe described_class::RackTimeoutBypass do
    # A tiny stand-in for Rack::Timeout: its #call raises unless the bypass short-circuits first.
    let(:base_class) do
      Class.new do
        def initialize(app)
          @app = app
        end

        def call(_env)
          raise 'global Rack::Timeout would run here'
        end
      end
    end

    it 'short-circuits to the downstream app when the bypass flag is set (skips the global timer)' do
      klass = base_class
      klass.prepend(described_class)
      downstream = ->(_env) { [201, {}, ['created']] }
      status, = klass.new(downstream).call(Bloomwire::OnboardingRequestTimeout::BYPASS_ENV_KEY => true)
      expect(status).to eq(201)
    end

    it 'defers to the global Rack::Timeout behaviour when the flag is absent' do
      klass = base_class
      klass.prepend(described_class)
      expect { klass.new(->(_env) {}).call({}) }.to raise_error('global Rack::Timeout would run here')
    end
  end
end
