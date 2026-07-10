# Sanitized error raised when a Meta WhatsApp Graph API call exceeds its connection (open) or read timeout.
#
# It deliberately carries NO url/query (which hold the access token or App Secret), NO request body (the 2SV PIN),
# NO OAuth code, and NO response body — only the HTTP verb plus the underlying timeout class name — so a timed-out
# onboarding step is diagnosable (and retriable) without ever leaking a secret. It is a StandardError so the
# managed-signup caller's existing `rescue StandardError` fails closed / re-checks Meta state on a retry.
class Whatsapp::GraphApiTimeoutError < StandardError; end
