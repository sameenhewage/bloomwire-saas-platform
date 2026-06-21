require 'rails_helper'

RSpec.describe 'Super Admin Bloomwire Businesses', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Globex Corp') }
  let!(:profile) do
    create(:bloomwire_business_profile,
           account: account,
           industry: 'Retail / E-commerce',
           plan_name: 'Pro',
           status: 'active',
           onboarding_status: 'completed')
  end

  describe 'GET /super_admin/bloomwire/businesses' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get '/super_admin/bloomwire/businesses'
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'lists business profiles with account name and metadata' do
        get '/super_admin/bloomwire/businesses'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Globex Corp')
        expect(response.body).to include('Retail / E-commerce')
        expect(response.body).to include('Pro')
      end
    end
  end

  describe 'GET /super_admin/bloomwire/businesses/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/super_admin/bloomwire/businesses/#{profile.id}"
        expect(response).to have_http_status(:redirect)
      end
    end

    context 'when it is an authenticated super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'renders the business profile show page' do
        get "/super_admin/bloomwire/businesses/#{profile.id}"
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Globex Corp')
      end
    end
  end

  describe 'onboarding step progress visibility' do
    before do
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_profile', status: 'completed', position: 0)
      create(:bloomwire_onboarding_step, bloomwire_business_profile: profile,
                                         step_key: 'business_details', status: 'pending', position: 1)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'shows the onboarding progress column and value on the index' do
      get '/super_admin/bloomwire/businesses'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Onboarding Progress')
      expect(response.body).to include('1 of 2 steps completed')
      expect(response.body).to include('current: Business details')
    end

    it 'shows the onboarding progress on the show page' do
      get "/super_admin/bloomwire/businesses/#{profile.id}"

      expect(response).to have_http_status(:success)
      expect(response.body.downcase).to include('onboarding progress')
      expect(response.body).to include('1 of 2 steps completed')
    end
  end

  describe 'chatwoot readiness visibility' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'shows the chatwoot readiness column and "Needs inbox/channel" when there is no inbox' do
      get '/super_admin/bloomwire/businesses'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Chatwoot Readiness')
      expect(response.body).to include('Needs inbox/channel')
    end

    it 'shows "Ready" when the account has an inbox' do
      create(:inbox, account: account)

      get '/super_admin/bloomwire/businesses'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Chatwoot Readiness')
      expect(response.body).to include('Ready')
    end

    it 'shows the chatwoot readiness on the show page' do
      get "/super_admin/bloomwire/businesses/#{profile.id}"

      expect(response).to have_http_status(:success)
      expect(response.body.downcase).to include('chatwoot readiness')
      expect(response.body).to include('Needs inbox/channel')
    end
  end

  describe 'manual tenant activation' do
    let!(:pending_account) { create(:account, name: 'Pending Co') }
    let!(:pending_profile) do
      create(:bloomwire_business_profile, account: pending_account,
                                          status: 'setup_pending', onboarding_status: 'in_progress')
    end

    def make_ready(target)
      create(:inbox, account: target.account)
      BloomwireOnboardingStep::DEFAULT_STEPS.each_with_index do |key, index|
        create(:bloomwire_onboarding_step, bloomwire_business_profile: target,
                                           step_key: key, status: 'completed', position: index)
      end
    end

    context 'when it is an unauthenticated user' do
      it 'does not activate the tenant' do
        post "/super_admin/bloomwire/businesses/#{pending_profile.id}/activate"

        expect(response).to have_http_status(:redirect)
        expect(pending_profile.reload.status).to eq('setup_pending')
      end
    end

    context 'when it is an authenticated super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'shows the activation action on the show page for a pending tenant' do
        get "/super_admin/bloomwire/businesses/#{pending_profile.id}"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Activate tenant')
      end

      it 'activates a ready tenant and reports success' do
        make_ready(pending_profile)

        post "/super_admin/bloomwire/businesses/#{pending_profile.id}/activate"

        expect(response).to have_http_status(:redirect)
        expect(pending_profile.reload.status).to eq('active')
        expect(pending_profile.onboarding_status).to eq('completed')

        follow_redirect!
        expect(response.body).to include('Tenant activated')
      end

      it 'shows a safe failure and does not activate a not-ready tenant' do
        post "/super_admin/bloomwire/businesses/#{pending_profile.id}/activate"

        expect(response).to have_http_status(:redirect)
        expect(pending_profile.reload.status).to eq('setup_pending')
        expect(pending_profile.onboarding_status).to eq('in_progress')

        follow_redirect!
        expect(response.body).to include('Cannot activate')
      end

      it 'is idempotent for an already-active tenant' do
        active_account = create(:account, name: 'Already Active Co')
        active_profile = create(:bloomwire_business_profile, account: active_account,
                                                             status: 'active', onboarding_status: 'completed')

        post "/super_admin/bloomwire/businesses/#{active_profile.id}/activate"

        expect(response).to have_http_status(:redirect)
        expect(active_profile.reload.status).to eq('active')

        follow_redirect!
        expect(response.body).to include('already active')
      end
    end
  end
end
