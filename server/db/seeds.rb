# Synthetic development data only. No real people, companies or payments.
accounts = [
  { name: "Acme Widgets (synthetic)", email: "billing@acme.example", status: "active" },
  { name: "Globex Trial (synthetic)", email: "ops@globex.example", status: "trial" },
  { name: "Initech (synthetic)", email: "ap@initech.example", status: "past_due" }
].map { |attrs| Account.find_or_create_by!(email: attrs[:email]) { |a| a.assign_attributes(attrs) } }

acme, _globex, initech = accounts
acme.payments.find_or_create_by!(amount_cents: 12_900, paid_at: Time.utc(2026, 9, 1, 12))
initech.payments.find_or_create_by!(amount_cents: 4_900, paid_at: Time.utc(2026, 8, 15, 9))

LedgerEntry.find_or_create_by!(account_id: acme.id, entry_type: "credit", amount_cents: 12_900, posted_on: Date.new(2026, 9, 1))
LedgerEntry.find_or_create_by!(account_id: acme.id, entry_type: "debit", amount_cents: 2_500, posted_on: Date.new(2026, 9, 3))
