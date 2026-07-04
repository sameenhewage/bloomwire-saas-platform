import { mount, RouterLinkStub } from '@vue/test-utils';
import InboxSummary from '../InboxSummary.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

const LabelStub = {
  props: ['label'],
  template: '<span class="label-stub">{{ label }}</span>',
};

const baseInbox = {
  id: 42,
  name: 'Sales WhatsApp',
  channel_type: 'Channel::Whatsapp',
  relationship_status: 'linked',
  matched_team_count: 1,
  matched_team_ids: [10],
  whatsapp: {
    connection_mode: 'coexistence',
    setup_status: 'ready_for_webhook',
  },
  collaborators: [{ id: 1, name: 'Alice' }],
  drift: {
    staff_missing_inbox_access: [{ id: 2, name: 'Bob' }],
    collaborators_not_in_team: [],
  },
};

const mountRow = (inbox = baseInbox) =>
  mount(InboxSummary, {
    props: { inbox },
    global: {
      mocks: { $t: key => key },
      stubs: {
        RouterLink: RouterLinkStub,
        Label: LabelStub,
        Icon: true,
        ChannelIcon: true,
      },
    },
  });

describe('InboxSummary.vue (17F.1 read-only inbox row)', () => {
  it('renders the inbox name', () => {
    expect(mountRow().text()).toContain('Sales WhatsApp');
  });

  it('shows the Coexistence WhatsApp badge', () => {
    const labels = mountRow()
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).toMatch(/coexistence/i);
  });

  it('shows a Standard badge for a standard whatsapp inbox', () => {
    const inbox = {
      ...baseInbox,
      whatsapp: { connection_mode: 'standard', setup_status: 'not_configured' },
      drift: null,
    };
    const labels = mountRow(inbox)
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).toMatch(/standard/i);
  });

  it('shows an explicit setup fallback label when setup is missing', () => {
    const inbox = {
      ...baseInbox,
      whatsapp: { connection_mode: 'standard', setup_status: 'not_configured' },
      drift: null,
    };
    const labels = mountRow(inbox)
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).toContain(
      'CATEGORY_INBOX_OVERVIEW.SETUP_STATUS.NOT_CONFIGURED'
    );
  });

  it('shows the linked relationship label', () => {
    const labels = mountRow()
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).toContain('CATEGORY_INBOX_OVERVIEW.RELATIONSHIP.LINKED');
  });

  it('shows the ambiguous relationship label', () => {
    const labels = mountRow({
      ...baseInbox,
      relationship_status: 'ambiguous',
      matched_team_count: 2,
    })
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).toContain('CATEGORY_INBOX_OVERVIEW.RELATIONSHIP.AMBIGUOUS');
  });

  it('shows the unlinked relationship label', () => {
    const labels = mountRow({
      ...baseInbox,
      relationship_status: 'unlinked',
      matched_team_count: 0,
    })
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).toContain('CATEGORY_INBOX_OVERVIEW.RELATIONSHIP.UNLINKED');
  });

  it('renders a deep-link to the inbox settings editor', () => {
    const link = mountRow().findComponent(RouterLinkStub);
    expect(link.props('to').name).toBe('settings_inbox_show');
    expect(link.props('to').params.inboxId).toBe(42);
  });

  it('surfaces drift when team staff lack inbox access', () => {
    expect(mountRow().find('[data-testid="inbox-drift"]').exists()).toBe(true);
  });

  it('renders no drift block when there is no drift', () => {
    const inbox = {
      ...baseInbox,
      drift: { staff_missing_inbox_access: [], collaborators_not_in_team: [] },
    };
    expect(mountRow(inbox).find('[data-testid="inbox-drift"]').exists()).toBe(
      false
    );
  });

  it('renders no WhatsApp badge for a non-whatsapp inbox', () => {
    const inbox = {
      ...baseInbox,
      channel_type: 'Channel::WebWidget',
      whatsapp: null,
      drift: null,
    };
    const labels = mountRow(inbox)
      .findAll('.label-stub')
      .map(n => n.text())
      .join(' ');
    expect(labels).not.toMatch(/standard|coexistence/i);
  });

  it('never renders provider secrets', () => {
    expect(mountRow().html()).not.toMatch(/provider_config|api_key|token/i);
  });
});
