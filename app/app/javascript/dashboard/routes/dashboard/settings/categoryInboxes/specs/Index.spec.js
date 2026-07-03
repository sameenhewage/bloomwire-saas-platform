import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import Index from '../Index.vue';
import categoryInboxOverviewAPI from 'dashboard/api/bloomwire/categoryInboxOverview';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
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
  unlinked_inboxes: [
    {
      id: 200,
      name: 'Orphan WA',
      channel_type: 'Channel::Whatsapp',
      whatsapp: { connection_mode: 'coexistence', setup_status: null },
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
      mocks: { $t: key => key },
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
          template: '<div class="inbox-summary-stub">{{ inbox.name }}</div>',
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

  it('renders each category and every derived + unlinked inbox', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.text()).toContain('Sales');
    expect(wrapper.text()).toContain('Support');
    const names = wrapper.findAll('.inbox-summary-stub').map(n => n.text());
    expect(names).toContain('Sales WA');
    expect(names).toContain('Orphan WA');
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

  it('renders an unlinked-inboxes section when present', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="unlinked-section"]').exists()).toBe(
      true
    );
  });

  it('shows no category rows or unlinked section when the overview is empty', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({
      data: { categories: [], unlinked_inboxes: [], derivation: { note: '' } },
    });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.find('[data-testid="category-row"]').exists()).toBe(false);
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

  it('never renders provider secrets', async () => {
    categoryInboxOverviewAPI.get.mockResolvedValue({ data: overview });
    const wrapper = mountPage();
    await flushPromises();
    expect(wrapper.html()).not.toMatch(/provider_config|api_key|token/i);
  });
});
