# Single source of truth for the default Meta WhatsApp Cloud / Graph API version used across the Bloomwire
# WhatsApp flows (Embedded Signup / Coexistence onboarding, WABA + phone-number queries, token exchange +
# debug, webhook subscription, and outbound message/media sends). Ops can still override per surface via the
# existing config keys (WHATSAPP_API_VERSION, WHATSAPP_CLOUD_API_VERSION); this constant only provides the
# default so no service silently inherits an older Graph API version. The approved version is v25.0.
module Whatsapp::GraphApi
  DEFAULT_VERSION = 'v25.0'.freeze
end
