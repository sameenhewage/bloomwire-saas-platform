import { mount, flushPromises } from '@vue/test-utils';
import BloomwireRemoveWhatsappInbox from '../BloomwireRemoveWhatsappInbox.vue';

// Destructive "Remove WhatsApp Inbox" action + confirmation modal. All store/alert calls mocked; no real HTTP.
const dispatch = vi.fn();
const alertSpy = vi.fn();

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alertSpy(...args),
}));

const R = 'INBOX_MGMT.ADD.WHATSAPP.BLOOMWIRE_MANAGED.REMOVE';

const WootModalStub = {
  props: ['show', 'onClose'],
  template: '<div v-if="show" class="woot-modal-stub"><slot /></div>',
};
const NextButtonStub = {
  props: ['label', 'isLoading', 'disabled', 'ruby', 'solid', 'faded', 'slate'],
  emits: ['click'],
  template:
    '<button :disabled="disabled" :data-loading="isLoading" @click="$emit(\'click\')">{{ label }}</button>',
};

const standardInbox = {
  id: 42,
  name: 'Acme WhatsApp',
  phone_number: '+15551230001',
  provider_config: { source: 'bloomwire_managed' },
};
const coexistenceInbox = {
  ...standardInbox,
  id: 43,
  provider_config: {
    source: 'bloomwire_managed',
    connection_mode: 'coexistence',
  },
};

const mountComp = (inbox = standardInbox) =>
  mount(BloomwireRemoveWhatsappInbox, {
    props: { inbox },
    global: {
      mocks: { $t: key => key },
      stubs: {
        'woot-modal': WootModalStub,
        NextButton: NextButtonStub,
      },
    },
  });

const find = (wrapper, id) => wrapper.find(`[data-testid="${id}"]`);
const openModal = async wrapper => {
  await find(wrapper, 'bloomwire-remove-wa-action').trigger('click');
};

beforeEach(() => {
  dispatch.mockReset();
  alertSpy.mockReset();
});

// (case 1) the Remove Inbox option is rendered.
it('renders the "Remove inbox" action', () => {
  const wrapper = mountComp();
  expect(find(wrapper, 'bloomwire-remove-wa-action').text()).toBe(
    `${R}.ACTION`
  );
  // Modal is closed until the action is clicked.
  expect(find(wrapper, 'bloomwire-remove-wa-modal').exists()).toBe(false);
});

// (case 4) the destructive confirmation warning + details are shown.
it('opens the confirmation modal with the irreversible warning, name and mode', async () => {
  const wrapper = mountComp();
  await openModal(wrapper);
  expect(find(wrapper, 'bloomwire-remove-wa-modal').exists()).toBe(true);
  expect(find(wrapper, 'bloomwire-remove-wa-warning').text()).toBe(
    `${R}.WARNING`
  );
  expect(find(wrapper, 'bloomwire-remove-wa-name').text()).toBe(
    'Acme WhatsApp'
  );
  expect(find(wrapper, 'bloomwire-remove-wa-mode').text()).toBe(
    `${R}.MODE_STANDARD`
  );
  expect(find(wrapper, 'bloomwire-remove-wa-meta-note').text()).toBe(
    `${R}.META_NOTE`
  );
});

it('shows the Coexistence mode for a coexistence inbox', async () => {
  const wrapper = mountComp(coexistenceInbox);
  await openModal(wrapper);
  expect(find(wrapper, 'bloomwire-remove-wa-mode').text()).toBe(
    `${R}.MODE_COEXISTENCE`
  );
});

// (case 16) only the MASKED number is shown — never the full phone number.
it('shows only a masked phone number (last 4), never the full number', async () => {
  const wrapper = mountComp();
  await openModal(wrapper);
  const numberText = find(wrapper, 'bloomwire-remove-wa-number').text();
  expect(numberText).toContain('0001');
  const body = find(wrapper, 'bloomwire-remove-wa-modal').text();
  expect(body).not.toContain('15551230001');
  expect(body).not.toContain('5551230001');
});

// (case 5) cancelling performs no writes.
it('cancel closes the modal and dispatches nothing', async () => {
  const wrapper = mountComp();
  await openModal(wrapper);
  await find(wrapper, 'bloomwire-remove-wa-cancel').trigger('click');
  await flushPromises();
  expect(dispatch).not.toHaveBeenCalled();
  expect(find(wrapper, 'bloomwire-remove-wa-modal').exists()).toBe(false);
});

it('confirm dispatches the deprovision with the inbox id and emits removed on success', async () => {
  dispatch.mockResolvedValue({ success: true });
  const wrapper = mountComp();
  await openModal(wrapper);
  await find(wrapper, 'bloomwire-remove-wa-confirm').trigger('click');
  await flushPromises();
  expect(dispatch).toHaveBeenCalledWith(
    'inboxes/removeBloomwireWhatsAppInbox',
    42
  );
  expect(alertSpy).toHaveBeenCalledWith(`${R}.SUCCESS`);
  expect(wrapper.emitted('removed')).toBeTruthy();
});

it('shows a safe error alert and does not emit removed on failure', async () => {
  dispatch.mockRejectedValue({ response: { status: 422 } });
  const wrapper = mountComp();
  await openModal(wrapper);
  await find(wrapper, 'bloomwire-remove-wa-confirm').trigger('click');
  await flushPromises();
  expect(alertSpy).toHaveBeenCalledWith(`${R}.ERROR`);
  expect(wrapper.emitted('removed')).toBeFalsy();
});

it('disables repeated confirm clicks while a deletion is in flight (one dispatch)', async () => {
  let resolveDelete;
  dispatch.mockReturnValue(
    new Promise(resolve => {
      resolveDelete = resolve;
    })
  );
  const wrapper = mountComp();
  await openModal(wrapper);
  const confirm = find(wrapper, 'bloomwire-remove-wa-confirm');
  await confirm.trigger('click');
  await confirm.trigger('click');
  await confirm.trigger('click');
  expect(dispatch).toHaveBeenCalledTimes(1);
  resolveDelete({ success: true });
  await flushPromises();
});
