require 'rails_helper'

# The Bloomwire platform channel-setup endpoint is a SINGLE create-only POST action.
# It must NOT expose a GET index/show route: the Administrate Super Admin sidebar
# enumerates every super_admin controller, so a routable GET index would surface as a
# dead sidebar link (the resource is also skip-listed in the nav partial). These specs
# pin the POST-only contract so the create-only endpoint can never regrow a dead GET path.
RSpec.describe 'SuperAdmin Bloomwire channel-integration setup routing', type: :routing do
  it 'routes POST /super_admin/bloomwire/channel_integrations to the create action' do
    expect(post: '/super_admin/bloomwire/channel_integrations')
      .to route_to('super_admin/bloomwire_channel_integrations#create')
  end

  it 'exposes no GET index or show path (so the Super Admin nav has no dead link)' do
    expect(get: '/super_admin/bloomwire/channel_integrations').not_to be_routable
    expect(get: '/super_admin/bloomwire/channel_integrations/1').not_to be_routable
  end
end
