import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import Index from '../Index.vue';
import categoryInboxOverviewAPI from 'dashboard/api/bloomwire/categoryInboxOverview';

const t = (key, params = {}) => (params.teams ? `${key} ${params.teams}` : key);

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t }) }));
vi.mock('dashboard/api/bloomwire/categoryInboxOverview', () => ({
  default: { get: vi.fn() },
}));

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
            staff_missing_inbox_access: [],
            collaborators_not_in_team: [],
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
          props: ['inbox'],
          template:
            '<div class="inbox-summary-stub">{{ inbox.name }} {{ inbox.relationship_status }}</div>',
        },
      },
    },
  });

describe('Categories & Inboxes overview page (17F.1)', () => {
  beforeEach(() => vi.clearAllMocks());

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
