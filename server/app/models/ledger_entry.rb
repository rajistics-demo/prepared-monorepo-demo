class LedgerEntry < LedgerRecord
  ENTRY_TYPES = %w[credit debit].freeze

  validates :account_id, presence: true
  validates :entry_type, inclusion: { in: ENTRY_TYPES }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :posted_on, presence: true

  SIGNED_AMOUNT = "CASE entry_type WHEN 'credit' THEN amount_cents ELSE -amount_cents END".freeze

  def self.balance_for(account_id)
    where(account_id: account_id).sum(Arel.sql(SIGNED_AMOUNT)).to_i
  end

  # Running balance per entry, computed in the database with a window function.
  def self.running_balances(account_id)
    where(account_id: account_id)
      .select("ledger_entries.*, SUM(#{SIGNED_AMOUNT}) OVER (ORDER BY posted_on, id) AS running_balance_cents")
      .order(:posted_on, :id)
      .map { |e| { id: e.id, posted_on: e.posted_on, running_balance_cents: e.running_balance_cents.to_i } }
  end
end
