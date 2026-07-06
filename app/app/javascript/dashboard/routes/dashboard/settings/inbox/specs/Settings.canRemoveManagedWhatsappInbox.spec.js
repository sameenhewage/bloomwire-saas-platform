import Settings from '../Settings.vue';

// The "Remove WhatsApp Inbox" action in the inbox settings page is rendered with
// `v-if="canRemoveManagedWhatsappInbox"`. This exercises that exact computed from Settings.vue with a controlled
// component context, proving the capability gate: feature OFF hides the action; feature ON + admin + managed
// WhatsApp Cloud inbox shows it. (`canSelfServeManagedWhatsapp` is the SAME server-derived capability onboarding
// uses; the backend endpoint remains the enforcement boundary.)
const gate = Settings.computed.canRemoveManagedWhatsappInbox;

const ctx = ({
  capability,
  whatsappCloud = true,
  source = 'bloomwire_managed',
}) => ({
  canSelfServeManagedWhatsapp: capability,
  isAWhatsAppCloudChannel: whatsappCloud,
  inbox: { provider_config: { source } },
});

describe('Settings.vue — canRemoveManagedWhatsappInbox gate', () => {
  it('HIDES the Remove action when the managed WhatsApp self-serve capability is OFF', () => {
    expect(gate.call(ctx({ capability: false }))).toBe(false);
  });

  it('SHOWS the Remove action for a capability-ON admin on a managed WhatsApp Cloud inbox', () => {
    expect(gate.call(ctx({ capability: true }))).toBe(true);
  });

  it('HIDES the action for a non-WhatsApp-Cloud inbox even when the capability is ON', () => {
    expect(gate.call(ctx({ capability: true, whatsappCloud: false }))).toBe(
      false
    );
  });

  it('HIDES the action for a non-managed (e.g. embedded_signup) WhatsApp inbox even when the capability is ON', () => {
    expect(
      gate.call(ctx({ capability: true, source: 'embedded_signup' }))
    ).toBe(false);
  });
});
