require 'rails_helper'

# Bloomwire Phase 13D.2 — controller request-param PII filtering.
#
# Root cause (found in the Phase 13D post-deploy check): the WhatsApp webhook controllers log the request
# `Parameters:` line (ActionController, INFO) with the full raw Meta payload — customer wa_id/phone, profile
# name, routing phone_number_id, message `from`, status `recipient_id`. ActiveJob log_arguments (Phase 13D)
# does not cover this controller layer; `config.filter_parameters` only filtered *token-style keys.
#
# Fix: add `:entry` to config.filter_parameters. All Meta webhook PII is nested under the `entry` container,
# so deep-filtering `entry` redacts the whole payload in logs without filtering generic inner keys
# (from/name/id) globally. Logging-only: `params[:entry]` used for processing is unaffected.
#
# `request.filtered_parameters` is exactly what the `Parameters:` log prints, so it is the faithful assertion.
RSpec.describe 'Bloomwire WhatsApp webhook request-param PII filtering', type: :request do
  include ActiveJob::TestHelper

  let(:phone_number_id) { 'PNID-LOGTEST-1' }
  let(:wa_id) { '15557779999' }                 # customer phone marker
  let(:profile_name) { 'ZzWebhookProfileMarker' } # customer profile name marker
  let(:payload) { bw_inbound_text_payload(phone_number_id: phone_number_id, from: wa_id, name: profile_name) }

  before do
    ActiveJob::Base.queue_adapter = :test
    bw_enable_all
  end

  describe 'controller request log (filtered_parameters == what Parameters: prints)' do
    it 'redacts the Meta webhook payload (no customer PII) from the request log' do
      bw_post_router(payload)

      fp = request.filtered_parameters
      expect(fp['entry']).to eq('[FILTERED]')
      dump = fp.inspect
      expect(dump).not_to include(wa_id)
      expect(dump).not_to include(profile_name)
      expect(dump).not_to include(phone_number_id)
    end
  end

  describe 'config.filter_parameters (applies to every webhook controller, incl. native path)' do
    it 'deep-filters the entry payload regardless of controller' do
      raw = { 'object' => 'whatsapp_business_account', 'entry' => payload['entry'] }
      filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(raw)

      expect(filtered['entry']).to eq('[FILTERED]')
      expect(filtered.inspect).not_to include(wa_id)
      expect(filtered.inspect).not_to include(profile_name)
    end
  end

  describe 'webhook behavior unchanged' do
    it 'accepts a validly-signed webhook (200)' do
      bw_post_router(payload)
      expect(response).to have_http_status(:ok)
    end

    it 'rejects an invalid signature (401)' do
      bw_post_router(payload, signature: 'sha256=deadbeefdeadbeef')
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
