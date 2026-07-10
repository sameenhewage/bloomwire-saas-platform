# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :password, :secret, :_key, :auth, :crypt, :salt, :certificate, :otp, :access, :private, :protected, :ssn,
  :otp_secret, :otp_code, :backup_code, :mfa_token, :otp_backup_codes
]

# Bloomwire Phase 13D.2: Meta webhook (WhatsApp/Facebook/Instagram) request payloads carry customer PII
# (wa_id/phone, profile name, routing phone_number_id, message `from`, status `recipient_id`) — all nested
# under the `entry` container. Deep-filtering `entry` redacts the whole payload from the controller
# `Parameters:` log without filtering generic inner keys (from/name/id) globally. Logging-only: `params[:entry]`
# used by the webhook processing path is unaffected.
Rails.application.config.filter_parameters += [:entry]

# Bloomwire Phase 14 S2d: WhatsApp provider credentials are submitted/handled under a `provider_config` key
# (Ops credential-capture surface + the inbox provider-config update path). `api_key` is already covered by the
# `:_key` filter, but deep-filtering the whole `provider_config` container redacts the entire credential blob
# (token + routing ids) from request-parameter logs. Logging-only: controllers still read params[:provider_config].
Rails.application.config.filter_parameters += [:provider_config]

# Bloomwire Phase 15F: the Email Settings page accepts an SMTP password (DB-backed, plaintext until the
# encryption-hardening follow-up). The generic `:password` filter already redacts the `smtp_password` key
# (substring match); this explicit entry documents the intent and is defense-in-depth. The secret must never
# appear in request-parameter logs.
Rails.application.config.filter_parameters += [:smtp_password]

# Regex to filter all occurrences of 'token' in keys except for 'website_token'
filter_regex = /\A(?!.*\bwebsite_token\b).*token/i

# Apply the regex for filtering
Rails.application.config.filter_parameters += [filter_regex]

# Bloomwire (managed WhatsApp onboarding): the Meta Embedded Signup endpoints and the phone-availability preflight
# receive the Meta authorization `code` (single-use secret, exchanges for an access token) plus WhatsApp routing
# identifiers and the customer phone number. None of these may appear in request-parameter logs.
#
# Symbol filters use SUBSTRING matching, so a bare `:code` would also redact unrelated keys like `error_code`,
# `country_code`, and `status_code`. To filter EXACTLY these keys (and nothing else), use anchored regexes. The
# existing token regex still filters `token`/`access_token` while preserving `website_token`; the anchored
# `access_token` here is explicit defense-in-depth. Logging-only: controllers still read these params normally.
Rails.application.config.filter_parameters += [
  /\Acode\z/i,
  /\Aauth_code\z/i,
  /\Abusiness_id\z/i,
  /\Awaba_id\z/i,
  /\Aphone_number_id\z/i,
  /\Adisplay_phone_number\z/i,
  /\Aaccess_token\z/i,
  /\Aphone_number\z/i
]

# Bloomwire (managed WhatsApp onboarding): the Cloud API /register two-step-verification PIN is a secret resolved
# SERVER-SIDE only (stored encrypted in provider_config; already covered there by the :provider_config deep filter).
# It is never a request parameter, but these anchored filters are defense-in-depth so a `pin` / `verification_pin`
# key can never surface in request-parameter logs. Anchored so unrelated keys (e.g. `spin`) are untouched.
Rails.application.config.filter_parameters += [
  /\Apin\z/i,
  /\Averification_pin\z/i
]
