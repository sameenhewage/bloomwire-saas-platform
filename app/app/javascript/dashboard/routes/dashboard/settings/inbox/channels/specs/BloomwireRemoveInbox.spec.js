import { mount, flushPromises } from '@vue/test-utils';
import BloomwireRemoveInbox from '../BloomwireRemoveInbox.vue';
import inboxMgmt from 'dashboard/i18n/locale/en/inboxMgmt.json';

// Universal, destructive "Remove inbox" action + confirmation modal. All store/alert/router calls mocked; no real HTTP.
const dispatch = vi.fn();
const alertSpy = vi.fn();

// Capture the registered route-leave guard so we can simulate leaving the page mid-request.
let routeLeaveGuard = null;

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alertSpy(...args),
}));
vi.mock('vue-router', () => ({
  onBeforeRouteLeave: cb => {
    routeLeaveGuard = cb;
  },
}));

const R = 'INBOX_MGMT.BLOOMWIRE_REMOVE';

const WootModalStub = {
  props: ['show'],
  template: '<div v-if="show"><slot /></div>',
};
const NextButtonStub = {
  props: ['label', 'disabled', 'isLoading'],
  template:
    '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};
const ChannelNameStub = {
  props: ['channelType', 'medium'],
  template: '<span>{{ channelType }}</span>',
};

const waInbox = {
  id: 42,
  name: 'Bloomwire WA Dev',
  channel_type: 'Channel::Whatsapp',
  phone_number: '+94771234567',
};
const emailInbox = {
  id: 7,
  name: 'Support Email',
  channel_type: 'Channel::Email',
  email: 'support@bloomwire.lk',
};
const apiInbox = { id: 9, name: 'API Bot', channel_type: 'Channel::Api' };

const find = (wrapper, testid) => wrapper.find(`[data-testid="${testid}"]`);

const mountComp = (inbox = waInbox) =>
  mount(BloomwireRemoveInbox, {
    props: { inbox },
    global: {
      stubs: {
        'woot-modal': WootModalStub,
        NextButton: NextButtonStub,
        ChannelName: ChannelNameStub,
      },
    },
  });

const openModal = async wrapper => {
  await find(wrapper, 'bloomwire-remove-inbox-action').trigger('click');
  await flushPromises();
};

beforeEach(() => {
  dispatch.mockReset();
  dispatch.mockResolvedValue();
  alertSpy.mockReset();
  routeLeaveGuard = null;
});

describe('BloomwireRemoveInbox.vue', () => {
  it('renders the Remove inbox action and hides the modal until clicked', () => {
    const wrapper = mountComp();
    expect(find(wrapper, 'bloomwire-remove-inbox-action').exists()).toBe(true);
    expect(find(wrapper, 'bloomwire-remove-inbox-modal').exists()).toBe(false);
  });

  it('opens the confirmation modal with the inbox name and channel type', async () => {
    const wrapper = mountComp();
    await openModal(wrapper);
    expect(find(wrapper, 'bloomwire-remove-inbox-modal').exists()).toBe(true);
    expect(find(wrapper, 'bloomwire-remove-inbox-name').text()).toBe(
      'Bloomwire WA Dev'
    );
    expect(find(wrapper, 'bloomwire-remove-inbox-type').text()).toContain(
      'Channel::Whatsapp'
    );
  });

  it('masks the WhatsApp phone number and truthfully labels removal local-only with Meta access potentially active', async () => {
    const wrapper = mountComp(waInbox);
    await openModal(wrapper);
    const identifier = find(
      wrapper,
      'bloomwire-remove-inbox-identifier'
    ).text();
    expect(identifier).toContain('4567');
    expect(identifier).not.toContain('94771234567');
    expect(find(wrapper, 'bloomwire-remove-inbox-meta-note').exists()).toBe(
      true
    );

    const copy = inboxMgmt.INBOX_MGMT.BLOOMWIRE_REMOVE.META_NOTE;
    expect(copy).toMatch(/local-only/i);
    expect(copy).toMatch(/makes no Meta call/i);
    expect(copy).toMatch(/remain registered.*connected at Meta/i);
    expect(copy).toMatch(/provider access.*remain active/i);
    expect(copy).toMatch(/does not delete.*phone number.*WABA/i);
  });

  it('masks the Email address local-part and shows no Meta note', async () => {
    const wrapper = mountComp(emailInbox);
    await openModal(wrapper);
    const identifier = find(
      wrapper,
      'bloomwire-remove-inbox-identifier'
    ).text();
    expect(identifier).toContain('@bloomwire.lk');
    expect(identifier).not.toContain('support@');
    expect(find(wrapper, 'bloomwire-remove-inbox-meta-note').exists()).toBe(
      false
    );
  });

  it('shows no identifier row and no Meta note for a non-WhatsApp/non-email inbox', async () => {
    const wrapper = mountComp(apiInbox);
    await openModal(wrapper);
    expect(find(wrapper, 'bloomwire-remove-inbox-identifier').exists()).toBe(
      false
    );
    expect(find(wrapper, 'bloomwire-remove-inbox-meta-note').exists()).toBe(
      false
    );
  });

  it('Cancel performs no request and closes the modal', async () => {
    const wrapper = mountComp();
    await openModal(wrapper);
    await find(wrapper, 'bloomwire-remove-inbox-cancel').trigger('click');
    await flushPromises();
    expect(dispatch).not.toHaveBeenCalled();
    expect(find(wrapper, 'bloomwire-remove-inbox-modal').exists()).toBe(false);
  });

  it('dispatches the stock inbox delete, alerts, and emits removed on confirm', async () => {
    const wrapper = mountComp();
    await openModal(wrapper);
    await find(wrapper, 'bloomwire-remove-inbox-confirm').trigger('click');
    await flushPromises();
    expect(dispatch).toHaveBeenCalledWith('inboxes/delete', 42);
    expect(alertSpy).toHaveBeenCalledWith(`${R}.STARTED`);
    expect(wrapper.emitted('removed')).toBeTruthy();
    expect(wrapper.emitted('removed')[0]).toEqual([42]);
  });

  it('reports accepted removal as pending without emitting removed', async () => {
    dispatch.mockResolvedValue({ status: 'pending' });
    const wrapper = mountComp();
    await openModal(wrapper);
    await find(wrapper, 'bloomwire-remove-inbox-confirm').trigger('click');
    await flushPromises();

    expect(alertSpy).toHaveBeenCalledWith(`${R}.STARTED`);
    expect(wrapper.emitted('removed')).toBeFalsy();
  });

  it('blocks repeated confirm clicks (one dispatch only)', async () => {
    let resolveDelete;
    dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveDelete = resolve;
        })
    );
    const wrapper = mountComp();
    await openModal(wrapper);
    await find(wrapper, 'bloomwire-remove-inbox-confirm').trigger('click');
    await find(wrapper, 'bloomwire-remove-inbox-confirm').trigger('click');
    resolveDelete();
    await flushPromises();
    expect(dispatch).toHaveBeenCalledTimes(1);
  });

  it('shows a safe error alert and does not emit removed on failure', async () => {
    dispatch.mockRejectedValue(new Error('boom'));
    const wrapper = mountComp();
    await openModal(wrapper);
    await find(wrapper, 'bloomwire-remove-inbox-confirm').trigger('click');
    await flushPromises();
    expect(alertSpy).toHaveBeenCalledWith(`${R}.ERROR`);
    expect(wrapper.emitted('removed')).toBeFalsy();
  });

  it('route-leave safety: no late alert/emit if the flow is left mid-request', async () => {
    let resolveDelete;
    dispatch.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveDelete = resolve;
        })
    );
    const wrapper = mountComp();
    await openModal(wrapper);
    await find(wrapper, 'bloomwire-remove-inbox-confirm').trigger('click');
    // Simulate leaving the page before the request resolves.
    expect(routeLeaveGuard).toBeTypeOf('function');
    routeLeaveGuard();
    resolveDelete();
    await flushPromises();
    expect(alertSpy).not.toHaveBeenCalled();
    expect(wrapper.emitted('removed')).toBeFalsy();
  });
});
