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
end
