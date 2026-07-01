require 'rails_helper'

# Phase 17A: the SuperAdmin manual WhatsApp "provision customer" flow, the standalone "new setup mapping" CRUD,
# and the 16C owner-activation action are REMOVED. Onboarding now happens customer-side (Settings -> Inboxes ->
# Add Inbox); SuperAdmin WhatsApp is a read-only surface (transitional; rebuilt into Global WhatsApp Config in
# PR B). The router mapping (Bloomwire::WhatsappSetup) stays, created by the wizard, not manual Ops UI.
RSpec.describe 'Phase 17A removed SuperAdmin WhatsApp routes', type: :routing do
  it 'no longer routes SuperAdmin customer provisioning' do
    expect(get: '/super_admin/bloomwire_customer_provisionings').not_to be_routable
    expect(get: '/super_admin/bloomwire_customer_provisionings/new').not_to be_routable
    expect(post: '/super_admin/bloomwire_customer_provisionings').not_to be_routable
  end

  it 'no longer routes the standalone manual setup-mapping CRUD (new/create/edit/update)' do
    # The `new` ACTION is gone; the /new path is now absorbed by the show :id route (and 404s at find),
    # so there is no separate "new mapping" form.
    expect(get: '/super_admin/bloomwire_whatsapp_setups/new')
      .to route_to('super_admin/bloomwire_whatsapp_setups#show', id: 'new')
    expect(post: '/super_admin/bloomwire_whatsapp_setups').not_to be_routable          # create
    expect(get: '/super_admin/bloomwire_whatsapp_setups/1/edit').not_to be_routable    # edit
    expect(patch: '/super_admin/bloomwire_whatsapp_setups/1').not_to be_routable       # update
    expect(put: '/super_admin/bloomwire_whatsapp_setups/1').not_to be_routable         # update
  end

  it 'no longer routes the 16C owner-activation action' do
    expect(post: '/super_admin/bloomwire_whatsapp_setups/1/send_owner_activation').not_to be_routable
  end

  it 'still routes the read-only observability + credentials surfaces' do
    expect(get: '/super_admin/bloomwire_whatsapp_setups').to be_routable
    expect(get: '/super_admin/bloomwire_whatsapp_setups/1').to be_routable
    expect(get: '/super_admin/bloomwire_whatsapp_setups/1/readiness').to be_routable
    expect(get: '/super_admin/bloomwire_whatsapp_setups/1/credentials').to be_routable
    expect(patch: '/super_admin/bloomwire_whatsapp_setups/1/update_credentials').to be_routable
  end

  it 'still routes the parked setup-requests intake queue (deprecated, not removed in 17A)' do
    expect(get: '/super_admin/bloomwire_whatsapp_setup_requests').to be_routable
    expect(get: '/super_admin/bloomwire_whatsapp_setup_requests/1').to be_routable
    expect(patch: '/super_admin/bloomwire_whatsapp_setup_requests/1').to be_routable
  end
end
