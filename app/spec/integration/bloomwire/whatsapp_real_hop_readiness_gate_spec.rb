require 'rails_helper'

# Phase 12B — WhatsApp real-hop readiness GATE (NO real Meta).
#
# Drives Bloomwire::WhatsappRealHopReadiness from one aligned fixture and proves it is the machine-checkable
# pre-flight gate for a real inbound hop: fully aligned => ready; each missing/broken precondition => blocked
# with the exact failing check key; and the result never leaks secret values. It never calls Meta.
#
# (Complements the granular service spec; this version exercises the gate through the shared E2E harness
# fixture so the harness's aligned mapping stays trustworthy.)
RSpec.describe 'Bloomwire WhatsApp real-hop readiness gate', type: :request do
  let(:account) { create(:account) }
  let(:pnid) { 'PNID-READY-GATE-1' }
  let(:display) { '15551230055' }
  let(:api_key) { 'FAKE-PROVIDER-API-KEY' }

  let(:setup) do
    create(:bloomwire_whatsapp_setup, :ready_for_webhook, account: account,
                                                          aligned_phone_number_id: pnid,
                                                          aligned_display_phone_number: display,
                                                          aligned_api_key: api_key)
  end

  def result_for(setup_record = setup)
    Bloomwire::WhatsappRealHopReadiness.new(setup_record).result
  end

  def check(result, key)
    result[:checks].find { |c| c[:key] == key.to_s }
  end

  before { GlobalConfig.clear_cache }

  context 'when fully aligned and configured' do
    before { bw_enable_all }

    it 'is ready with all sub-summaries true and the global callback path' do
      result = result_for
      expect(result[:status]).to eq('ready')
      expect(result[:ready_for_inbound_mapping]).to be(true)
      expect(result[:ready_for_get_verification_config]).to be(true)
      expect(result[:callback_path]).to eq('/bloomwire/webhooks/whatsapp')
      expect(result[:checks].map { |c| c[:status] }.uniq).to eq(['pass'])
    end
  end

  context 'when a precondition is missing or broken' do
    it 'blocks when Bloomwire mode is OFF' do
      bw_enable_all
      record = setup
      bw_set_config('BLOOMWIRE_MODE_ENABLED', false)
      result = result_for(record)
      expect(result[:status]).to eq('blocked')
      expect(check(result, :bloomwire_mode_enabled)[:status]).to eq('blocked')
    end

    it 'blocks when WHATSAPP_APP_SECRET is missing' do
      bw_enable_all
      record = setup
      bw_set_config('WHATSAPP_APP_SECRET', nil)
      result = result_for(record)
      expect(result[:status]).to eq('blocked')
      expect(check(result, :app_secret_configured)[:status]).to eq('blocked')
      expect(result[:ready_for_inbound_mapping]).to be(false)
    end

    it 'blocks when the mapping is not ready_for_webhook (bad mapping)' do
      bw_enable_all
      record = setup
      record.update_column(:setup_status, 'configured') # rubocop:disable Rails/SkipsModelValidations
      result = result_for(record)
      expect(result[:status]).to eq('blocked')
      expect(check(result, :setup_ready_for_webhook)[:status]).to eq('blocked')
    end

    it 'blocks when the channel provider_config phone_number_id mismatches (bad alignment)' do
      bw_enable_all
      record = setup
      record.channel_whatsapp.update!(
        provider_config: record.channel_whatsapp.provider_config.merge('phone_number_id' => 'OTHER-PNID')
      )
      result = result_for(record.reload)
      expect(result[:status]).to eq('blocked')
      expect(check(result, :channel_provider_config_phone_number_id_matches)[:status]).to eq('blocked')
      expect(check(result, :router_handoff_safe)[:status]).to eq('blocked')
    end
  end

  context 'without exposing secrets' do
    before { bw_enable_all }

    it 'never includes secret values or full routing identifiers in the result' do
      dump = result_for.inspect
      expect(dump).not_to include(bw_app_secret)
      expect(dump).not_to include(bw_verify_token)
      expect(dump).not_to include(api_key)
      expect(dump).not_to include(pnid)
      expect(dump).not_to include("+#{display}")
      expect(result_for[:masked][:phone_number_id]).to include('****')
    end
  end

  context 'without any real Meta network egress' do
    it 'computes readiness without contacting graph.facebook.com' do
      bw_enable_all
      result_for
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end
end
