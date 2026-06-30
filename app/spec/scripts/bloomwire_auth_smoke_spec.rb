require 'rails_helper'
require 'open3'

# Phase 15G.3: guards the auth-smoke host ALLOWLIST (default-deny) + owner-account refusal. Runs the real
# script in SMOKE_VALIDATE_ONLY mode — no network, no login, no real secrets — and asserts exit codes.
RSpec.describe 'auth-smoke.sh host allowlist guard (Phase 15G.3)' do # rubocop:disable RSpec/DescribeClass
  let(:script) { File.expand_path('../../../.github/scripts/auth-smoke.sh', __dir__) }

  def run_guard(base_url, email: 'devtest@example.com', allowed: nil)
    env = {
      'SMOKE_VALIDATE_ONLY' => '1', 'SMOKE_BASE_URL' => base_url,
      'SMOKE_EMAIL' => email, 'SMOKE_PASSWORD' => 'dummy-not-a-secret'
    }
    env['SMOKE_ALLOWED_HOSTS'] = allowed if allowed
    out, status = Open3.capture2e(env, 'bash', script)
    [out, status.exitstatus]
  end

  it 'is present and executable' do
    expect(File.exist?(script)).to be(true)
  end

  it 'allows the known dev host (exit 0)' do
    out, code = run_guard('https://dev.unecast.com')
    expect(code).to eq(0)
    expect(out).to include('VALIDATION_OK')
  end

  it 'refuses an unknown host by default (exit 2)' do
    out, code = run_guard('https://evil.example.com')
    expect(code).to eq(2)
    expect(out).to include('not in the dev/staging allowlist')
  end

  it 'refuses a production-looking host that is not in the allowlist (exit 2)' do
    _, code = run_guard('https://app.unecast.com')
    expect(code).to eq(2)
  end

  it 'allows a staging host only when explicitly configured via SMOKE_ALLOWED_HOSTS' do
    _, denied = run_guard('https://staging.unecast.com')
    _, allowed = run_guard('https://staging.unecast.com', allowed: 'staging.unecast.com')
    expect(denied).to eq(2)
    expect(allowed).to eq(0)
  end

  it 'refuses the owner account even on an allowed host (exit 2)' do
    _, code = run_guard('https://dev.unecast.com', email: 'sameen@bloomwire.lk')
    expect(code).to eq(2)
  end
end
