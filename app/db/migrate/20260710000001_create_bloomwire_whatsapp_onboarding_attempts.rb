# Async WhatsApp onboarding attempt (ADR-0010 v3). A NON-secret, resumable record of one managed onboarding run.
#
# Security: `oauth_code` and `access_token` are TEMPORARY operational secrets, encrypted at rest (ActiveRecord
# encryption, ADR-0006) and cleared per the approved lifecycle; they are the ONLY secret-bearing columns and are
# never exposed in DTOs/logs/job-args. The full phone number is NEVER stored here — only a pre-masked value
# (`phone_number_masked`) for UI (privacy Guardrail 5). Additive table only.
class CreateBloomwireWhatsappOnboardingAttempts < ActiveRecord::Migration[7.1]
  ACTIVE_STATUSES = %w[waiting_meta queued exchanging_code processing action_required].freeze

  def change # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :bloomwire_whatsapp_onboarding_attempts do |t|
      t.references :account, null: false, foreign_key: true
      # Opaque, non-secret public id returned to the browser. Access is ALWAYS re-authorized account-scoped.
      t.string :public_uuid, null: false
      t.string :status, null: false, default: 'waiting_meta'
      t.string :step
      # Bound only when the Meta popup completes (not required at create time).
      t.string :business_id
      t.string :waba_id
      t.string :phone_number_id
      # Privacy (Guardrail 5): only a pre-masked value; the full number never lives on the attempt.
      t.string :phone_number_masked
      # Stale-job guard (Guardrail 2): bumped on each submit/restart; a job for an older generation is a no-op.
      t.integer :submission_generation, null: false, default: 0
      t.integer :retry_count, null: false, default: 0
      # Short, non-secret classifier surfaced to the UI (e.g. "meta_error", "subscription_failed", "session_expired").
      t.string :safe_error_code
      t.references :channel_whatsapp, null: true, foreign_key: { to_table: :channel_whatsapp }
      t.references :inbox, null: true, foreign_key: true
      # Temporary encrypted secrets (ADR-0006). Cleared per lifecycle; never in DTO/logs/job args.
      t.text :oauth_code
      t.text :access_token
      # Short-lease ownership (Guardrail 2): claim processing without holding a DB lock across Meta HTTP calls.
      t.string :processing_owner
      t.datetime :lease_expires_at
      # Optimistic locking (Rails uses this column automatically) to reject stale writers.
      t.integer :lock_version, null: false, default: 0
      # Lifecycle timestamps.
      t.datetime :code_received_at
      t.datetime :code_expires_at
      t.datetime :code_exchanged_at
      t.datetime :credential_persisted_at
      t.datetime :secrets_cleared_at
      t.datetime :job_enqueued_at
      t.datetime :processing_started_at

      t.timestamps
    end

    add_index :bloomwire_whatsapp_onboarding_attempts, :public_uuid, unique: true
    add_index :bloomwire_whatsapp_onboarding_attempts, %i[account_id status]
    # Recovery worker (re-enqueue) + TTL sweep scan on (status, updated_at).
    add_index :bloomwire_whatsapp_onboarding_attempts, %i[status updated_at]
    # Guardrail 1: exactly ONE active attempt per account+phone once the phone is bound — action_required is
    # ACTIVE (a persisted-but-incomplete setup must be resumed via Recheck, never onboarded in parallel).
    add_index :bloomwire_whatsapp_onboarding_attempts, %i[account_id phone_number_id],
              unique: true,
              where: "phone_number_id IS NOT NULL AND status IN (#{ACTIVE_STATUSES.map { |s| "'#{s}'" }.join(',')})",
              name: 'idx_bw_wa_onboarding_active_account_phone'
  end
end
