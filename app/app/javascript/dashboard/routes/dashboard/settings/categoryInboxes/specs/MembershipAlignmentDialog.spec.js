import { flushPromises, mount } from '@vue/test-utils';
import MembershipAlignmentDialog from '../MembershipAlignmentDialog.vue';
import categoryInboxAlignmentAPI from 'dashboard/api/bloomwire/categoryInboxAlignment';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/bloomwire/categoryInboxAlignment', () => ({
  default: { create: vi.fn() },
}));

const category = {
  id: 10,
  name: 'Sales',
  staff: [
    { id: 1, name: 'Alice' },
    { id: 2, name: 'Bob' },
  ],
};

const inbox = {
  id: 100,
  name: 'Sales WA',
  collaborators: [
    { id: 1, name: 'Alice' },
    { id: 3, name: 'Carol' },
  ],
  drift: {
    staff_missing_inbox_access: [{ id: 2, name: 'Bob' }],
    collaborators_not_in_team: [{ id: 3, name: 'Carol' }],
  },
};

const mountDialog = (props = {}) =>
  mount(MembershipAlignmentDialog, {
    props: { category, inbox, ...props },
    global: { mocks: { $t: key => key }, stubs: { Icon: true } },
  });

describe('MembershipAlignmentDialog.vue (17F.3 guided alignment preview)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows the selected category/team and inbox', () => {
    const text = mountDialog().text();
    expect(text).toContain('Sales');
    expect(text).toContain('Sales WA');
  });

  it('previews the current team staff and current inbox collaborators', () => {
    const team = mountDialog()
      .find('[data-testid="current-team-staff"]')
      .text();
    const inb = mountDialog()
      .find('[data-testid="current-inbox-staff"]')
      .text();
    expect(team).toContain('Alice');
    expect(team).toContain('Bob');
    expect(inb).toContain('Alice');
    expect(inb).toContain('Carol');
  });

  it('previews the additive diff: who will be added to the inbox and to the team', () => {
    const wrapper = mountDialog();
    expect(wrapper.find('[data-testid="will-add-to-inbox"]').text()).toContain(
      'Bob'
    );
    expect(wrapper.find('[data-testid="will-add-to-team"]').text()).toContain(
      'Carol'
    );
  });

  it('states explicitly that no staff will be removed (additive only)', () => {
    expect(mountDialog().find('[data-testid="no-removal-note"]').exists()).toBe(
      true
    );
  });

  it('cancel emits close and performs no write', async () => {
    const wrapper = mountDialog();
    await wrapper.find('[data-testid="align-cancel"]').trigger('click');
    expect(categoryInboxAlignmentAPI.create).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toBeTruthy();
  });

  it('confirm sends ONLY Team + Inbox identity (no client user_ids) and emits aligned on success', async () => {
    categoryInboxAlignmentAPI.create.mockResolvedValue({
      data: { aligned: true },
    });
    const wrapper = mountDialog();
    await wrapper.find('[data-testid="align-confirm"]').trigger('click');
    await flushPromises();

    expect(categoryInboxAlignmentAPI.create).toHaveBeenCalledTimes(1);
    expect(categoryInboxAlignmentAPI.create).toHaveBeenCalledWith({
      team_id: 10,
      inbox_id: 100,
    });
    // the request payload must NOT carry a client-controlled membership list
    expect(
      categoryInboxAlignmentAPI.create.mock.calls[0][0]
    ).not.toHaveProperty('user_ids');
    expect(wrapper.emitted('aligned')).toBeTruthy();
  });

  it('issues only one request on double-submit (isSubmitting guard)', async () => {
    let resolvePromise;
    categoryInboxAlignmentAPI.create.mockReturnValue(
      new Promise(resolve => {
        resolvePromise = resolve;
      })
    );
    const wrapper = mountDialog();
    const confirmButton = wrapper.find('[data-testid="align-confirm"]');

    await confirmButton.trigger('click');
    await confirmButton.trigger('click'); // second click while the first request is still in-flight

    expect(categoryInboxAlignmentAPI.create).toHaveBeenCalledTimes(1);

    resolvePromise({ data: { aligned: true } });
    await flushPromises();
  });

  it('shows a safe error and does NOT emit aligned when the alignment fails', async () => {
    categoryInboxAlignmentAPI.create.mockRejectedValue(new Error('boom'));
    const wrapper = mountDialog();
    await wrapper.find('[data-testid="align-confirm"]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-testid="align-error"]').exists()).toBe(true);
    expect(wrapper.emitted('aligned')).toBeFalsy();
  });

  it('never renders provider secrets', () => {
    expect(mountDialog().html()).not.toMatch(/provider_config|api_key|token/i);
  });
});
