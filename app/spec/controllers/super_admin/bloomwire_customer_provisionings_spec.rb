require 'rails_helper'

# Phase 14 S3 — SuperAdmin/Ops-only customer provisioning surface. This spec covers the THIN controller
# (access control, OFF == stock, param plumbing, response). The real orchestration (account + owner + agents +
# shell channel + setup) is covered by Bloomwire::CustomerProvisioningService's own spec, so the service is
# stubbed here to keep the controller spec focused and side-effect-free. Fake values only.
RSpec.describe 'SuperAdmin Bloomwire Customer Provisioning', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:setup) { create(:bloomwire_whatsapp_setup, account: create(:account), setup_status: 'pending') }
  let(:service) { instance_double(Bloomwire::CustomerProvisioningService) }

  let(:valid_provisioning) do
    { account_name: 'Aroma Flora', owner_email: 'owner@example.com', owner_name: 'Flora Owner',
      display_phone_number: '15551239999', phone_number_id: 'PNID-S3-1', business_account_id: 'WABA-S3-1' }
  end

  def set_toggle(key, value)
    config = InstallationConfig.where(name: key).first_or_initialize
    config.value = value
    config.locked = false
    config.save!
    GlobalConfig.clear_cache
  end

  before { GlobalConfig.clear_cache }

  context 'when not authenticated as a super admin (business owner/staff have no access)' do
    before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

    it 'redirects the new form to the super admin login' do
      get new_super_admin_bloomwire_customer_provisioning_path
      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('/super_admin/sign_in')
    end

    it 'does not run provisioning on create' do
      expect(Bloomwire::CustomerProvisioningService).not_to receive(:new)
      post super_admin_bloomwire_customer_provisionings_path, params: { provisioning: valid_provisioning }
      expect(response).to have_http_status(:redirect)
    end
  end

  context 'when authenticated as a super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    context 'when Bloomwire master mode is OFF (stock - surface inert)' do
      it 'does not expose the new form' do
        get new_super_admin_bloomwire_customer_provisioning_path
        expect(response).to have_http_status(:redirect)
        expect(response.redirect_url).not_to include('customer_provisioning')
      end

      it 'does not run provisioning on create' do
        expect(Bloomwire::CustomerProvisioningService).not_to receive(:new)
        post super_admin_bloomwire_customer_provisionings_path, params: { provisioning: valid_provisioning }
      end
    end

    context 'when Bloomwire master mode is ON' do
      before { set_toggle('BLOOMWIRE_MODE_ENABLED', true) }

      it 'renders the new form' do
        get new_super_admin_bloomwire_customer_provisioning_path
        expect(response).to have_http_status(:success)
      end

      it 'runs provisioning and redirects to the new setup' do
        allow(Bloomwire::CustomerProvisioningService).to receive(:new).and_return(service)
        allow(service).to receive(:perform).and_return({ account: setup.account, setup: setup })

        post super_admin_bloomwire_customer_provisionings_path, params: { provisioning: valid_provisioning }
        expect(response).to redirect_to(super_admin_bloomwire_whatsapp_setup_path(setup))
      end

      it 'never passes an api_key to the provisioning service (no token field)' do
        captured = nil
        allow(Bloomwire::CustomerProvisioningService).to receive(:new) do |attrs|
          captured = attrs
          service
        end
        allow(service).to receive(:perform).and_return({ account: setup.account, setup: setup })

        post super_admin_bloomwire_customer_provisionings_path,
             params: { provisioning: valid_provisioning.merge(api_key: 'SHOULD-BE-IGNORED') }
        expect(captured.keys.map(&:to_s)).not_to include('api_key')
      end

      it 're-renders unprocessable_entity when provisioning raises a ProvisioningError' do
        allow(Bloomwire::CustomerProvisioningService).to receive(:new).and_return(service)
        allow(service).to receive(:perform).and_raise(Bloomwire::CustomerProvisioningService::ProvisioningError, 'bad input')

        post super_admin_bloomwire_customer_provisionings_path, params: { provisioning: valid_provisioning }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
