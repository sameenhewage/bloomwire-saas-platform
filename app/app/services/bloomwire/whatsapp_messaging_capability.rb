# Phase 5: outbound-messaging readiness for a managed WhatsApp signup — the send-side counterpart to the
# CONNECTED gate. Inbound rides the app-to-WABA subscription (no per-customer token), but OUTBOUND sending is
# authorized per-ACTOR: the stored-token actor (a partner system user) needs the WhatsApp Business Account
# ASSET task (MANAGE / MESSAGING), NOT merely the whatsapp_business_messaging OAuth scope. A token can hold the
# scope yet lack the asset task and still get Meta (#10) on /messages — so onboarding must verify the exact
# actor's task on the selected WABA before presenting the inbox as fully ready.
#
# Behavior:
# - A: the actor already holds a send-capable task -> :ready (no assignment call).
# - B: the task is absent AND the onboarding credential is authorized to grant it -> grant the minimum proven
#      task, RE-READ, and only then -> :ready.
# - C: the task is absent and cannot be established -> :action_required (the caller persists an explicit
#      Action-Required inbox, never a silently receive-only "ready" one).
#
# Boundary (do not weaken):
# - Uses ONLY the onboarding token already exchanged for this signup — never a stored platform-admin credential
#   and never an owner personal token. A view-only system-user token cannot self-elevate, so in that case the
#   grant simply fails and the gate returns :action_required (fail-safe, never a false ready).
# - Read-only apart from the single grant attempt, which is always re-verified by a fresh read.
# - Never logs the token/secret: on any Meta failure ONLY the operation + exception class name are logged.
class Bloomwire::WhatsappMessagingCapability
  # WABA asset tasks that authorize outbound Cloud API sending. MANAGE (full control) is the proven task that
  # clears Meta (#10); MESSAGING is Meta's narrower send task. Either one satisfies the outbound gate.
  SEND_TASKS = %w[MANAGE MESSAGING].freeze
  # The minimum proven task we GRANT when the onboarding credential is authorized to establish it.
  GRANT_TASKS = %w[MANAGE].freeze
  # Sanitized, stable reason code persisted on the setup + surfaced in the safe DTO (never a secret).
  REASON = 'outbound_messaging_permission_required'.freeze
  EVENT = 'bloomwire.whatsapp.messaging_capability_error'.freeze

  Result = Struct.new(:status, :actor_id, :tasks, :granted, :reason, keyword_init: true) do
    def ready?
      status == :ready
    end

    def action_required?
      status == :action_required
    end
  end

  def initialize(client:, token:, waba_id:)
    @client = client
    @token = token
    @waba_id = waba_id
  end

  def ensure
    actor_id = actor_id_safe
    return action_required(nil, nil) if actor_id.blank?

    tasks = tasks_safe(actor_id)
    return ready(actor_id, tasks) if send_capable?(tasks)

    # B: attempt to establish the task with the ONBOARDING token only, then verify with a fresh read.
    if grant_safe(actor_id)
      tasks = tasks_safe(actor_id)
      return ready(actor_id, tasks, granted: true) if send_capable?(tasks)
    end

    action_required(actor_id, tasks)
  end

  private

  def actor_id_safe
    @client.token_actor_id(@token).presence
  rescue StandardError => e
    log_failure('actor_lookup', e)
    nil
  end

  def tasks_safe(actor_id)
    Array(@client.waba_user_tasks(@waba_id, actor_id))
  rescue StandardError => e
    log_failure('tasks_lookup', e)
    []
  end

  # Grants the minimum proven task using the onboarding token. Returns true only when Meta accepts the call;
  # a view-only actor cannot self-elevate, so this returns false and the gate falls through to :action_required.
  def grant_safe(actor_id)
    @client.assign_waba_user_tasks(@waba_id, actor_id, GRANT_TASKS)
    true
  rescue StandardError => e
    log_failure('task_grant', e)
    false
  end

  def send_capable?(tasks)
    Array(tasks).map(&:to_s).intersect?(SEND_TASKS)
  end

  def ready(actor_id, tasks, granted: false)
    Result.new(status: :ready, actor_id: actor_id, tasks: tasks, granted: granted)
  end

  def action_required(actor_id, tasks)
    Result.new(status: :action_required, actor_id: actor_id, tasks: tasks, reason: REASON)
  end

  # Class-only sanitized log — never the token, message, or raw body (any of which can echo the token).
  def log_failure(operation, error)
    Rails.logger.warn(
      "[BLOOMWIRE EMBEDDED SIGNUP] #{{ event: EVENT, operation: operation, exception_class: error.class.name }.to_json}"
    )
  end
end
