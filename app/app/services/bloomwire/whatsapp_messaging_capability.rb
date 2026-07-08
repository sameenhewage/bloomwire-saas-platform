# Phase 5: outbound-messaging readiness for a managed WhatsApp signup — the send-side counterpart to the
# CONNECTED gate. Inbound rides the app-to-WABA subscription (no per-customer token), but OUTBOUND sending is
# authorized per-ACTOR: the stored-token actor (a partner system user) needs the WhatsApp Business Account
# ASSET task (MANAGE), NOT merely the whatsapp_business_messaging OAuth scope. A token can hold the scope yet
# lack the asset task and still get Meta (#10) on /messages — so onboarding must verify the exact actor's task
# on the selected WABA before presenting the inbox as fully ready.
#
# Verification is TRI-STATE (a successful "missing" must never be confused with an error):
# - verified_capable  -> the actor holds a send task              -> :ready (no assignment call).
# - verified_missing  -> the read SUCCEEDED and the task is absent -> may grant ONLY when explicitly authorized.
# - unverifiable      -> a lookup RAISED (network/auth/visibility) -> NEVER grant; :action_required (retriable).
#
# Grant policy (never blindly self-elevate):
# - Attempted ONLY when the CALLER declares the credential is independently authorized (allow_grant: true) AND
#   the token introspects as a real USER token. Managed onboarding + recheck pass allow_grant: false — their
#   stored credential is the partner SYSTEM_USER token, which provably cannot self-elevate — so they NEVER POST
#   an assignment; they resolve to :ready (A) or :action_required (C).
# - Uses ONLY the supplied token — never a stored platform-admin credential and never an owner personal token.
# - Never logs the token/secret: on any Meta failure ONLY the operation + exception class name are logged.
class Bloomwire::WhatsappMessagingCapability
  # WABA asset task proven (live) to clear Meta (#10) on /messages. Meta's narrower MESSAGING task is NOT yet
  # proven sufficient in our stack, so we do NOT mark an inbox ready on it (evidence-based).
  SEND_TASKS = %w[MANAGE].freeze
  # The minimum proven task we GRANT when (and only when) the credential is authorized to establish it.
  GRANT_TASKS = %w[MANAGE].freeze
  # debug_token actor type that MAY be trusted to assign a task; a view-only SYSTEM_USER cannot self-elevate.
  USER_TOKEN_TYPE = 'USER'.freeze
  # Sanitized, stable reason codes (never a secret) persisted on the setup + surfaced in the safe DTO.
  MISSING_REASON = 'outbound_messaging_permission_required'.freeze
  UNVERIFIABLE_REASON = 'outbound_messaging_permission_unverifiable'.freeze
  EVENT = 'bloomwire.whatsapp.messaging_capability_error'.freeze

  Result = Struct.new(:status, :verification, :actor_id, :tasks, :granted, :reason, keyword_init: true) do
    def ready?
      status == :ready
    end

    def action_required?
      status == :action_required
    end
  end

  # allow_grant: the CALLER declares the supplied credential is independently authorized to ASSIGN the task
  # (e.g. an owner-admin USER token from an explicit owner-authorized flow). Onboarding + recheck pass false.
  def initialize(client:, token:, waba_id:, allow_grant: false)
    @client = client
    @token = token
    @waba_id = waba_id
    @allow_grant = allow_grant
  end

  def ensure
    actor_id = actor_id_safe
    return unverifiable(nil, nil) if actor_id.blank? # lookup failed -> NO mutation

    verification, tasks = verify(actor_id)
    return ready(actor_id, tasks) if verification == :verified_capable
    return unverifiable(actor_id, tasks) if verification == :unverifiable # error -> NEVER a grant POST

    # verified_missing: establish the task ONLY with an authorized USER credential, then re-verify by a read.
    return granted_ready_or_action_required(actor_id) if grant_allowed?

    action_required(actor_id, tasks)
  end

  private

  def actor_id_safe
    @client.token_actor_id(@token).presence
  rescue StandardError => e
    log_failure('actor_lookup', e)
    nil
  end

  # Tri-state: a SUCCESSFUL read lacking the task is :verified_missing (real, actionable); a read that RAISES is
  # :unverifiable (transient/visibility/auth). They must NOT collapse — only a verified-missing state may (when
  # authorized) attempt a grant; an unverifiable one never mutates.
  def verify(actor_id)
    tasks = Array(@client.waba_user_tasks(@waba_id, actor_id))
    [send_capable?(tasks) ? :verified_capable : :verified_missing, tasks]
  rescue StandardError => e
    log_failure('tasks_lookup', e)
    [:unverifiable, []]
  end

  # Grant ONLY when the caller declared authorization AND the token introspects as a real USER token (never a
  # SYSTEM_USER, never an unknown/unintrospectable identity).
  def grant_allowed?
    return false unless @allow_grant

    token_type_safe == USER_TOKEN_TYPE
  end

  def token_type_safe
    @client.token_actor_type(@token)
  rescue StandardError => e
    log_failure('actor_type_lookup', e)
    nil
  end

  # Assign the minimum proven task with the authorized credential, then RE-READ to verify. A grant that raises
  # (or still verifies missing) never yields a false ready — it falls through to a safe non-routeable state.
  def granted_ready_or_action_required(actor_id)
    @client.assign_waba_user_tasks(@waba_id, actor_id, GRANT_TASKS)
    verification, tasks = verify(actor_id)
    return ready(actor_id, tasks, granted: true) if verification == :verified_capable

    action_required(actor_id, tasks)
  rescue StandardError => e
    log_failure('task_grant', e)
    unverifiable(actor_id, nil)
  end

  def send_capable?(tasks)
    Array(tasks).map(&:to_s).intersect?(SEND_TASKS)
  end

  def ready(actor_id, tasks, granted: false)
    Result.new(status: :ready, verification: :verified_capable, actor_id: actor_id, tasks: tasks, granted: granted)
  end

  # verified_missing -> the owner must grant the task (then Recheck). Non-routeable, resumable.
  def action_required(actor_id, tasks)
    Result.new(status: :action_required, verification: :verified_missing, actor_id: actor_id, tasks: tasks,
               reason: MISSING_REASON)
  end

  # unverifiable -> we could not confirm the task (lookup/grant raised). Non-routeable, retriable via Recheck.
  def unverifiable(actor_id, tasks)
    Result.new(status: :action_required, verification: :unverifiable, actor_id: actor_id, tasks: tasks,
               reason: UNVERIFIABLE_REASON)
  end

  # Class-only sanitized log — never the token, message, or raw body (any of which can echo the token).
  def log_failure(operation, error)
    Rails.logger.warn(
      "[BLOOMWIRE EMBEDDED SIGNUP] #{{ event: EVENT, operation: operation, exception_class: error.class.name }.to_json}"
    )
  end
end
