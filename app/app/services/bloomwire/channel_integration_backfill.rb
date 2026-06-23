# Backfills a BloomwireChannelIntegration for every existing WhatsApp inbox that
# belongs to a Bloomwire tenant (an account with a BloomwireBusinessProfile), so
# Bloomwire has an ownership/routing record for channels configured before this
# foundation existed (ADR 0005, slice 4.4-b-WA.2A).
#
# Source-of-truth rule (see projects/bloomwire-chatwoot-platform/CONTEXT.md):
# Chatwoot remains the owner of inboxes, channels, conversations, messages, and
# contacts. This backfill is read-only against Chatwoot data: it only mirrors
# NON-SECRET routing metadata (phone_number, phone_number_id, business_account_id)
# into the Bloomwire-owned table. It never copies provider secrets
# (api_key/access tokens, webhook_verify_token, raw provider_config) and never
# changes any Chatwoot behavior.
#
# It is idempotent (one integration per inbox) and fails safely: any tenant
# mismatch or routing-key collision is skipped, never persisted, and never raised.
class Bloomwire::ChannelIntegrationBackfill
  # Safe summary for callers/operators — numeric counts only, no tenant data.
  Result = Struct.new(:created, :skipped, :total, keyword_init: true)

  def perform
    created = 0
    skipped = 0

    Channel::Whatsapp.find_each do |channel|
      if integration_created_for?(channel)
        created += 1
      else
        skipped += 1
      end
    end

    Result.new(created: created, skipped: skipped, total: created + skipped)
  end

  private

  # Returns true only when a new integration row was persisted for the channel.
  def integration_created_for?(channel)
    inbox = channel.inbox
    return false if inbox.nil?

    profile = channel.account&.bloomwire_business_profile
    return false if profile.nil?
    return false if BloomwireChannelIntegration.exists?(inbox_id: inbox.id)

    integration = build_integration(profile, inbox, channel)
    return false unless integration.valid?

    integration.save!
    true
  rescue ActiveRecord::RecordNotUnique
    # Concurrent/duplicate routing identifier — fail safe, never raise.
    false
  end

  def build_integration(profile, inbox, channel)
    config = channel.provider_config || {}

    BloomwireChannelIntegration.new(
      bloomwire_business_profile: profile,
      account_id: channel.account_id,
      inbox: inbox,
      channelable: channel,
      app_kind: 'whatsapp',
      provider: channel.provider,
      status: 'active',
      managed_by_bloomwire: true,
      routing_key: config['phone_number_id'],
      phone_number: channel.phone_number,
      phone_number_id: config['phone_number_id'],
      business_account_id: config['business_account_id']
    )
  end
end
