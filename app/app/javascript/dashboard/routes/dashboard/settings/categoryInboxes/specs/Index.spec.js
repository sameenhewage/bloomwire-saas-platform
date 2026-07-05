import { ref } from 'vue';
import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import Index from '../Index.vue';
import categoryInboxOverviewAPI from 'dashboard/api/bloomwire/categoryInboxOverview';
import { useBloomwireCapabilities } from 'dashboard/composables/useBloomwireCapabilities';
import { useAccount } from 'dashboard/composables/useAccount';

const t = (key, params = {}) => (params.teams ? `${key} ${params.teams}` : key);

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));
vi.mock('dashboard/api/bloomwire/categoryInboxOverview', () => ({
  default: { get: vi.fn() },
}));
vi.mock('dashboard/composables/useBloomwireCapabilities');
vi.mock('dashboard/composables/useAccount');

// 17F.2B launcher capability + account context. Defaults: authorized admin with managed WhatsApp on account 7.
const setCaps = ({
  canAccessCategoryAdmin = true,
  canSelfServeManagedWhatsapp = true,
} = {}) => {
  useBloomwireCapabilities.mockReturnValue({
    canAccessCategoryAdmin: ref(canAccessCategoryAdmin),
    canSelfServeManagedWhatsapp: ref(canSelfServeManagedWhatsapp),
  });
};

const setAccount = (accountId = 7) => {
  useAccount.mockReturnValue({
    accountId: ref(accountId),
    accountScopedRoute: (name, params = {}, query = {}) => ({
      name,
      params: { accountId, ...params },
      query: { ...query },
    }),
  });
};

const overview = {
  categories: [
    {
      id: 10,
      name: 'Sales',
      staff: [{ id: 1, name: 'Alice' }],
      has_inbox: true,
      derived_inboxes: [
        {
          id: 100,
          name: 'Sales WA',
          channel_type: 'Channel::Whatsapp',
          relationship_status: 'linked',
          matched_team_count: 1,
          matched_team_ids: [10],
          whatsapp: { connection_mode: 'standard', setup_status: 'configured' },
          collaborators: [{ id: 1, name: 'Alice' }],
          drift: {
            staff_missing_inbox_access: [{ id: 2, name: 'Bob' }],
            collaborators_not_in_team: [{ id: 3, name: 'Carol' }],
          },
        },
      ],
    },
    {
      id: 11,
      name: 'Support',
      staff: [],
      has_inbox: false,
      derived_inboxes: [],
    },
  ],
  ambiguous_inboxes: [
    {
      id: 150,
      name: 'Shared WA',
      channel_type: 'Channel::Whatsapp',
      relationship_status: 'ambiguous',
      matched_team_count: 2,
      matched_team_ids: [10, 11],
      matched_teams: [
        { id: 10, name: 'Sales' },
        { id: 11, name: 'Support' },
      ],
      whatsapp: {
        connection_mode: 'coexistence',
        setup_status: 'ready_for_webhook',
      },
      collaborators: [],
    },
  ],
  unlinked_inboxes: [
    {
      id: 200,
      name: 'Orphan WA',
      channel_type: 'Channel::Whatsapp',
      relationship_status: 'unlinked',
      matched_team_count: 0,
      matched_team_ids: [],
      whatsapp: {
        connection_mode: 'coexistence',
        setup_status: 'not_configured',
      },
      collaborators: [],
    },
  ],
  derivation: {
    method: 'membership_overlap',
    note: 'Derived by shared members.',
  },
};

const mountPage = () =>
  mount(Index, {
    global: {
      mocks: { $t: t },
      stubs: {
        SettingsLayout: {
          props: ['isLoading', 'noRecordsFound'],
          template:
            '<div><slot name="header" /><slot name="body" /><slot /></div>',
        },
        BaseSettingsHeader: true,
        RouterLink: RouterLinkStub,
        Label: { props: ['label'], template: '<span>{{ label }}</span>' },
        Icon: true,
        ChannelIcon: true,
        InboxSummary: {
          props: ['inbox', 'canAlign'],
          emits: ['align'],
          template:
            '<div class="inbox-summary-stub" :data-can-align="canAlign ? \'yes\' : \'no\'"><span>{{ inbox.name }} {{ inbox.relationship_status }}</span><button class="stub-align-btn" @click="$emit(\'align\')" /></div>',
        },
        MembershipAlignmentDialog: {
          props: ['category', 'inbox'],
          emits: ['close', 'aligned'],
          template:
            '<div data-testid="align-dialog"><button class="stub-dialog-aligned" @click="$emit(\'aligned\')" /><button class="stub-dialog-close" @click="$emit(\'close\')" /></div>',
        },
      },
    },
  });

describe('Categories & Inboxes overview page (17F.1)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setCaps();
    setAccount();
  });

  it('fetches the overview on mount', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    mountPage();
    await flushPromises();
    expect(categoryInboxOverviewAPI.get).toHaveBeenCalled();
  });

  it('renders each category and every derived + ambiguous + unlinked inbox', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('Sales');
    expect(wrapper.text()).toContain('Support');
    const names = wrapper.findAll('.inbox-summary-stub').map(n => n.text());
    expect(names).toEqual(
      expect.arrayContaining([
        'Sales WA linked',
        'Shared WA ambiguous',
        'Orphan WA unlinked',
      ])
    );
  });

  it('warns for a category that has no derived inbox', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="category-no-inbox"]').exists()).toBe(
      true
    );
  });

  it('renders the derivation note (honest about the derived mapping)', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="derivation-note"]').text()).toContain(
      'Derived by shared members.'
    );
  });

  it('renders an explicit ambiguous-inboxes section with matched category names', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();

    const section = wrapper.find('[data-testid="ambiguous-section"]');
    expect(section.exists()).toBe(true);
    expect(section.text()).toContain('Shared WA');
    expect(section.text()).toContain('Sales');
    expect(section.text()).toContain('Support');
  });

  it('renders an unlinked-inboxes section when present', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="unlinked-section"]').exists()).toBe(
      true
    );
  });

  it('links to the existing Agents management page', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();

    const agentsLink = wrapper
      .findAllComponents(RouterLinkStub)
      .find(link => link.props('to')?.name === 'agent_list');
    expect(agentsLink.exists()).toBe(true);
  });

  it('shows no category rows or relationship sections when the overview is empty', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({
      data: {
        categories: [],
        ambiguous_inboxes: [],
        unlinked_inboxes: [],
        derivation: { note: '' },
      },
    });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.find('[data-testid="category-row"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="ambiguous-section"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="unlinked-section"]').exists()).toBe(
      false
    );
  });

  it('shows an error state when the overview fails to load', async () => {
    categoryInboxOverviewAPI.get.mockRejectedValue(new Error('boom'));
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="overview-error"]').exists()).toBe(true);
  });

  it('retries the overview request from the error state and renders the successful response', async () => {
    categoryInboxOverviewAPI.get
      .mockRejectedValueOnce(new Error('boom'))
      .mockResolvedValueOnce({ data: overview });
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-testid="overview-retry"]').trigger('click');
    await flushPromises();

    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-testid="overview-error"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Sales');
  });

  it('keeps the error state visible when retry also fails', async () => {
    categoryInboxOverviewAPI.get
      .mockRejectedValueOnce(new Error('boom'))
      .mockRejectedValueOnce(new Error('still broken'));
    const wrapper = mountPage();
    await flushPromises();

    await wrapper.find('[data-testid="overview-retry"]').trigger('click');
    await flushPromises();

    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-testid="overview-error"]').exists()).toBe(true);
  });

  it('never renders provider secrets', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.html()).not.toMatch(/provider_config|api_key|token/i);
  });
});

describe('Add WhatsApp Inbox launcher (17F.2B)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setCaps();
    setAccount();
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
  });

  const launchers = wrapper =>
    wrapper.findAll('[data-testid="add-whatsapp-inbox"]');
  const launcherRoute = wrapper =>
    wrapper
      .findAllComponents(RouterLinkStub)
      .find(l => l.props('to')?.name === 'settings_inboxes_page_channel')
      ?.props('to');

  it('shows the launcher for an authorized administrator (category-admin + managed WhatsApp)', async () => {
    setCaps({
      canAccessCategoryAdmin: true,
      canSelfServeManagedWhatsapp: true,
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(launchers(wrapper).length).toBeGreaterThan(0);
  });

  it('hides the launcher for an agent (no category-admin, no managed WhatsApp)', async () => {
    setCaps({
      canAccessCategoryAdmin: false,
      canSelfServeManagedWhatsapp: false,
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(launchers(wrapper).length).toBe(0);
  });

  it('hides the launcher when managed WhatsApp onboarding capability is OFF', async () => {
    setCaps({
      canAccessCategoryAdmin: true,
      canSelfServeManagedWhatsapp: false,
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(launchers(wrapper).length).toBe(0);
  });

  it('hides the launcher when the category-admin capability is OFF (feature OFF)', async () => {
    setCaps({
      canAccessCategoryAdmin: false,
      canSelfServeManagedWhatsapp: true,
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(launchers(wrapper).length).toBe(0);
  });

  it('deep-links to the existing WhatsApp wizard with the correct account context', async () => {
    setAccount(7);
    const wrapper = mountPage();
    await flushPromises();
    const to = launcherRoute(wrapper);
    expect(to).toBeTruthy();
    expect(to.name).toBe('settings_inboxes_page_channel');
    expect(to.params).toMatchObject({ accountId: 7, sub_page: 'whatsapp' });
  });

  it('does not fabricate a Category↔Inbox relationship (no team/category param on the launcher route)', async () => {
    const wrapper = mountPage();
    await flushPromises();
    const to = launcherRoute(wrapper);
    expect(to.params).not.toHaveProperty('teamId');
    expect(to.params).not.toHaveProperty('categoryId');
    expect(to.params).not.toHaveProperty('category_id');
  });

  it('is declarative navigation and triggers no backend write when clicked', async () => {
    const wrapper = mountPage();
    await flushPromises();
    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(1); // mount fetch only
    await launchers(wrapper)[0].trigger('click');
    await flushPromises();
    // clicking the launcher performs no extra API/overview call (router-link only)
    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(1);
  });

  it('keeps the existing read-only overview intact (no write controls added)', async () => {
    const wrapper = mountPage();
    await flushPromises();
    const writeButtons = wrapper
      .findAll('button')
      .map(b => b.text())
      .filter(txt =>
        /save|create|delete|remove|sync|assign|connect/i.test(txt)
      );
    expect(writeButtons).toEqual([]);
  });
});

describe('17F.3 guided membership alignment wiring', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setCaps();
    setAccount();
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
  });

  const summaryFor = (wrapper, name) =>
    wrapper.findAll('.inbox-summary-stub').find(n => n.text().includes(name));

  it('offers alignment (canAlign) on a drifted derived inbox for an administrator', async () => {
    const wrapper = mountPage();
    await flushPromises();
    expect(summaryFor(wrapper, 'Sales WA').attributes('data-can-align')).toBe(
      'yes'
    );
  });

  it('does not offer alignment to an agent (capability OFF)', async () => {
    setCaps({
      canAccessCategoryAdmin: false,
      canSelfServeManagedWhatsapp: false,
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(summaryFor(wrapper, 'Sales WA').attributes('data-can-align')).toBe(
      'no'
    );
  });

  it('fails closed for ambiguous inboxes (never offers alignment)', async () => {
    const wrapper = mountPage();
    await flushPromises();
    expect(summaryFor(wrapper, 'Shared WA').attributes('data-can-align')).toBe(
      'no'
    );
  });

  it('opens the alignment dialog when a row requests alignment', async () => {
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="align-dialog"]').exists()).toBe(false);

    await summaryFor(wrapper, 'Sales WA')
      .find('.stub-align-btn')
      .trigger('click');
    expect(wrapper.find('[data-testid="align-dialog"]').exists()).toBe(true);
  });

  it('refreshes the overview from its existing data source and closes after a successful alignment', async () => {
    const wrapper = mountPage();
    await flushPromises();
    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(1);

    await summaryFor(wrapper, 'Sales WA')
      .find('.stub-align-btn')
      .trigger('click');
    await wrapper.find('.stub-dialog-aligned').trigger('click');
    await flushPromises();

    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-testid="align-dialog"]').exists()).toBe(false);
  });

  it('closes the dialog without refetching when cancelled', async () => {
    const wrapper = mountPage();
    await flushPromises();

    await summaryFor(wrapper, 'Sales WA')
      .find('.stub-align-btn')
      .trigger('click');
    await wrapper.find('.stub-dialog-close').trigger('click');
    await flushPromises();

    expect(categoryInboxOverviewAPI.get).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-testid="align-dialog"]').exists()).toBe(false);
  });
});
