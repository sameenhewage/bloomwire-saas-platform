require 'rails_helper'

# Edge & security coverage for the Super Admin Bloomwire businesses pages
# (onboarding step status + Chatwoot readiness mapping).
#
# Guarantees (see AGENTS.md rules 1, 6, 8 and these slices' Product Truth Gate):
# - Missing onboarding steps are handled safely (no crash, safe label).
# - Only safe summary labels are surfaced (onboarding progress + Chatwoot
#   readiness); no raw records or internal ids are exposed.
# - No Chatwoot inbox/conversation/message/contact data leaks onto the page.
RSpec.describe 'Super Admin Bloomwire businesses (edge & security)', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Globex Corp') }
  let!(:profile) { create(:bloomwire_business_profile, account: account) }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'missing / empty steps (edge)' do
    it 'renders the index safely and shows a no-steps label when a profile has no steps' do
      get '/super_admin/bloomwire/businesses'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('No onboarding steps yet')
    end

    it 'renders the show page safely with a no-steps label' do
      get "/super_admin/bloomwire/businesses/#{profile.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('No onboarding steps yet')
    end
  end

  describe 'all steps completed (edge)' do
    it 'announces completion safely' do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'completed', position: 1)

      get '/super_admin/bloomwire/businesses'

      expect(response.body).to include('2 of 2 steps completed · all done')
    end
  end

  describe 'safe DTO (security)' do
    it 'surfaces only the safe summary label, not raw onboarding-step records' do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'pending', position: 0)

      get '/super_admin/bloomwire/businesses'

      # The exact safe label from the model is what reaches the browser.
      expect(response.body).to include(profile.reload.onboarding_progress)
      # No raw internal artifacts (table/association names) are exposed.
      expect(response.body).not_to include('bloomwire_onboarding_step')
    end
  end

  describe 'no Chatwoot data leakage (security)' do
    it 'does not expose Chatwoot contact data on the Bloomwire businesses pages' do
      create(:contact, account: account, name: 'Leaky Secret Contact')

      get '/super_admin/bloomwire/businesses'
      expect(response.body).not_to include('Leaky Secret Contact')

      get "/super_admin/bloomwire/businesses/#{profile.id}"
      expect(response.body).not_to include('Leaky Secret Contact')
    end
  end

  describe 'chatwoot readiness — safe label without data leakage (security)' do
    before do
      create(:inbox, account: account, name: 'Secret Inbox Name')
      create(:contact, account: account, name: 'Leaky Readiness Contact')
      create(:message, account: account, content: 'Leaky readiness message body')
    end

    it 'shows a safe readiness label on the index without leaking Chatwoot data' do
      get '/super_admin/bloomwire/businesses'

      expect(response.body).to include('Chatwoot Readiness')
      expect(response.body).to include('Ready')
      expect(response.body).not_to include('Secret Inbox Name')
      expect(response.body).not_to include('Leaky Readiness Contact')
      expect(response.body).not_to include('Leaky readiness message body')
    end

    it 'shows a safe readiness label on the show page without leaking Chatwoot data' do
      get "/super_admin/bloomwire/businesses/#{profile.id}"

      expect(response.body.downcase).to include('chatwoot readiness')
      expect(response.body).not_to include('Secret Inbox Name')
      expect(response.body).not_to include('Leaky Readiness Contact')
      expect(response.body).not_to include('Leaky readiness message body')
    end
  end
end
