require 'rails_helper'

# Phase 17E.1 — backend contract for the Bloomwire multi-WhatsApp-inbox "category" model (ADR-0009):
#   Category = Team + Inbox. One account owns TWO WhatsApp inboxes; each category's agents are members of
#   only their own inbox (+ team). This proves, at the BACKEND (not frontend):
#     * a category agent lists/opens ONLY their own inbox's conversations (ConversationFinder + ConversationPolicy)
#     * an admin sees both inboxes
#     * team-filtered assignment keeps a conversation within its category's agents
# No real Meta/WhatsApp; fake values only. This phase does NOT touch the account-wide contacts caveat (17E.2).
RSpec.describe 'Bloomwire multi-WhatsApp-inbox category contract (Phase 17E.1)' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  # Category 1 = Team 1 + WhatsApp Inbox 1; agent1 is staff of category 1 only.
  let(:inbox1) { whatsapp_inbox(display_phone_number: '15551230001', phone_number_id: 'PNID-1') }
  let(:team1) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent1) { create(:user, account: account, role: :agent, auto_offline: false) }

  # Category 2 = Team 2 + WhatsApp Inbox 2; agent2 is staff of category 2 only.
  let(:inbox2) { whatsapp_inbox(display_phone_number: '15551230002', phone_number_id: 'PNID-2') }
  let(:team2) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent2) { create(:user, account: account, role: :agent, auto_offline: false) }

  # A managed-style whatsapp_cloud inbox (channel + its own inbox), routing identifiers aligned. Fake values.
  def whatsapp_inbox(display_phone_number:, phone_number_id:)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                        phone_number: "+#{display_phone_number}", sync_templates: false,
                                        validate_provider_config: false)
    channel.update!(provider_config: channel.provider_config.merge('phone_number_id' => phone_number_id,
                                                                   'source' => 'bloomwire_managed'))
    channel.inbox
  end

  before do
    create(:inbox_member, user: agent1, inbox: inbox1)
    create(:team_member, user: agent1, team: team1)
    create(:inbox_member, user: agent2, inbox: inbox2)
    create(:team_member, user: agent2, team: team2)
    Current.account = account
  end

  after { Current.account = nil }

  describe 'conversation visibility is backend-enforced per inbox membership' do
    let!(:convo1) { create(:conversation, account: account, inbox: inbox1) }
    let!(:convo2) { create(:conversation, account: account, inbox: inbox2) }

    it 'lets a category-1 agent list only inbox-1 conversations (ConversationFinder)' do
      ids = ConversationFinder.new(agent1, {}).perform[:conversations].map(&:id)
      aggregate_failures do
        expect(ids).to include(convo1.id)
        expect(ids).not_to include(convo2.id)
      end
    end

    it 'lets a category-2 agent list only inbox-2 conversations (ConversationFinder)' do
      ids = ConversationFinder.new(agent2, {}).perform[:conversations].map(&:id)
      aggregate_failures do
        expect(ids).to include(convo2.id)
        expect(ids).not_to include(convo1.id)
      end
    end

    it 'lets an admin list both inboxes\' conversations (ConversationFinder)' do
      ids = ConversationFinder.new(admin, {}).perform[:conversations].map(&:id)
      expect(ids).to include(convo1.id, convo2.id)
    end

    it 'enforces open-access per inbox via ConversationPolicy#show? (no cross-category open)' do
      ctx1 = { user: agent1, account: account, account_user: agent1.account_users.find_by(account: account) }
      ctx2 = { user: agent2, account: account, account_user: agent2.account_users.find_by(account: account) }
      admin_ctx = { user: admin, account: account, account_user: admin.account_users.find_by(account: account) }
      aggregate_failures do
        expect(ConversationPolicy.new(ctx1, convo1).show?).to be(true)
        expect(ConversationPolicy.new(ctx1, convo2).show?).to be(false)
        expect(ConversationPolicy.new(ctx2, convo2).show?).to be(true)
        expect(ConversationPolicy.new(ctx2, convo1).show?).to be(false)
        expect(ConversationPolicy.new(admin_ctx, convo1).show?).to be(true)
        expect(ConversationPolicy.new(admin_ctx, convo2).show?).to be(true)
      end
    end
  end

  describe 'team-filtered assignment keeps a conversation within its category' do
    # Disable per-inbox round-robin so these tests exercise ONLY the deterministic team-filter path
    # (AssignmentHandler#ensure_assignee_is_from_team), not create-time auto-assignment.
    before { inbox1.update!(enable_auto_assignment: false) }

    it 'retains a team-1 + inbox-1 agent as assignee when the conversation is moved to team-1' do
      conversation = create(:conversation, account: account, inbox: inbox1, assignee: agent1)
      Current.user = admin
      conversation.update!(team: team1)
      aggregate_failures do
        expect(conversation.reload.assignee).to eq(agent1)
        expect(team1.members).to include(conversation.assignee)
        expect(inbox1.members).to include(conversation.assignee)
      end
    ensure
      Current.user = nil
    end

    it 'auto-assigns a team-1 + inbox-1 agent when an unassigned conversation is moved to team-1 (allow_auto_assign)' do
      conversation = create(:conversation, account: account, inbox: inbox1, assignee: nil)
      Current.user = admin
      conversation.update!(team: team1)
      # team1.allow_auto_assign is true → the eligible pool is inbox1.members ∩ team1.members == [agent1].
      expect(conversation.reload.assignee).to eq(agent1)
    ensure
      Current.user = nil
    end

    it 'never keeps a team-2-only assignee on a team-1 conversation (cross-category assignee rejected)' do
      # allow_auto_assign OFF isolates the validation path: the wrong-category assignee is dropped and NOT replaced.
      team1.update!(allow_auto_assign: false)
      conversation = create(:conversation, account: account, inbox: inbox1, assignee: agent2)
      Current.user = admin
      conversation.update!(team: team1)
      aggregate_failures do
        expect(conversation.reload.assignee).to be_nil
        expect(conversation.assignee).not_to eq(agent2)
      end
    ensure
      Current.user = nil
    end
  end
end
