# Backfills a BloomwireBusinessProfile for every Chatwoot account that is
# missing one, so the Bloomwire Super Admin business views can represent all
# tenants.
#
# Source-of-truth rule (see projects/bloomwire-chatwoot-platform/CONTEXT.md):
# Chatwoot remains the owner of conversations, messages, and contacts. This
# service only creates Bloomwire SaaS metadata rows; it never reads or copies
# Chatwoot conversation/message/contact data.
#
# The backfill is idempotent: it only creates profiles for accounts that do not
# already have one, so it is safe to run repeatedly.
class Bloomwire::BusinessProfileBackfill
  # Small, safe summary returned to callers/operators. Only numeric counts are
  # exposed — never account names, ids, or any raw tenant data.
  Result = Struct.new(:created, :skipped, :total, keyword_init: true)

  def perform
    created = 0

    accounts_missing_profile.find_each do |account|
      account.create_bloomwire_business_profile!
      created += 1
    end

    total = Account.count
    Result.new(created: created, skipped: total - created, total: total)
  end

  private

  def accounts_missing_profile
    Account.where.missing(:bloomwire_business_profile)
  end
end
