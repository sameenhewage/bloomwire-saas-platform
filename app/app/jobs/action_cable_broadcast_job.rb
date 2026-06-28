class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  # Bloomwire Phase 13D: `data` is the realtime DTO (for message events it carries the contact phone + name),
  # and `members` are pubsub tokens. ActiveJob's default arg logging would print them in cleartext in the
  # enqueue/perform log lines for every broadcast — PII in logs. Suppress argument logging for this job only;
  # the job still receives members/event/data and broadcasts (logging-only, no behavior change).
  self.log_arguments = false

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  def perform(members, event_name, data)
    return if members.blank?

    broadcast_data = prepare_broadcast_data(event_name, data)
    broadcast_to_members(members, event_name, broadcast_data)
  end

  private

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    conversation.push_event_data.merge(account_id: data[:account_id])
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
