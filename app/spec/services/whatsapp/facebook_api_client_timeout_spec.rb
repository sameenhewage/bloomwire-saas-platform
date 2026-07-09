require 'rails_helper'

# Every Meta Graph call the client makes must have explicit HTTP timeouts so a hung Meta call can never run out
# the whole request budget. On a connection/read timeout the client raises a SANITIZED Whatsapp::GraphApiTimeoutError
# that carries ONLY the HTTP verb + the underlying timeout class — never the URL/query (which holds the token or
# App Secret), the request body (PIN), the OAuth code, or a response body.
describe Whatsapp::FacebookApiClient do
  let(:access_token) { 'SECRET-EAA-TOKEN' }
  let(:api_client) { described_class.new(access_token) }
  let(:api_version) { Whatsapp::GraphApi::DEFAULT_VERSION }

  before do
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', Whatsapp::GraphApi::DEFAULT_VERSION).and_return(api_version)
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('APP-ID')
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_SECRET', '').and_return('SECRET-APP-SECRET')
    allow(Whatsapp::GraphApiTimeouts).to receive_messages(open_seconds: 5, read_seconds: 25)
  end

  describe 'explicit Graph API HTTP timeouts' do
    it 'sends open_timeout and read_timeout on every Graph request' do
      expect(HTTParty).to receive(:get)
        .with(anything, hash_including(open_timeout: Whatsapp::GraphApiTimeouts.open_seconds,
                                       read_timeout: Whatsapp::GraphApiTimeouts.read_seconds))
        .and_return(instance_double(HTTParty::Response, success?: true, parsed_response: { 'status' => 'CONNECTED' }))
      api_client.phone_number_status('PNID-1')
    end

    it 'applies the same timeouts to assigned-user task writes' do
      response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'success' => true })
      expect(HTTParty).to receive(:post)
        .with(anything, hash_including(open_timeout: described_class::OPEN_TIMEOUT_SECONDS,
                                       read_timeout: described_class::READ_TIMEOUT_SECONDS))
        .and_return(response)

      api_client.assign_waba_user_tasks('WABA-1', 'USER-1', ['MANAGE'])
    end

    it 'raises a sanitized Whatsapp::GraphApiTimeoutError when a GET times out (read_timeout)' do
      stub_request(:get, %r{https://graph\.facebook\.com/#{api_version}/PNID-1}).to_timeout
      expect { api_client.phone_number_status('PNID-1') }.to raise_error(Whatsapp::GraphApiTimeoutError)
    end

    it 'raises a sanitized Whatsapp::GraphApiTimeoutError when a POST (register) times out' do
      stub_request(:post, %r{https://graph\.facebook\.com/#{api_version}/PNID-1/register}).to_timeout
      expect { api_client.register_phone_number('PNID-1', '123456') }.to raise_error(Whatsapp::GraphApiTimeoutError)
    end

    it 'never leaks the token, PIN, App Secret, or URL in the timeout error message' do
      stub_request(:post, %r{https://graph\.facebook\.com/#{api_version}/PNID-1/register}).to_timeout
      begin
        api_client.register_phone_number('PNID-1', '123456')
      rescue Whatsapp::GraphApiTimeoutError => e
        aggregate_failures do
          expect(e.message).not_to include(access_token)
          expect(e.message).not_to include('123456')
          expect(e.message).not_to include('SECRET-APP-SECRET')
          expect(e.message).not_to include('graph.facebook.com')
          expect(e.message).to match(/timed out/i)
        end
      else
        raise 'expected Whatsapp::GraphApiTimeoutError'
      end
    end

    it 'raises the sanitized timeout error for a subscription check timeout too' do
      stub_request(:get, %r{https://graph\.facebook\.com/#{api_version}/WABA-1/subscribed_apps}).to_timeout
      expect { api_client.subscribed_to_waba?('WABA-1') }.to raise_error(Whatsapp::GraphApiTimeoutError)
    end
  end
end
