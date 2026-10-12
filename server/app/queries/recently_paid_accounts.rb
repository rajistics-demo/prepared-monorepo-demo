# Accounts that have made a payment, most recent payment first.
# Powers the "Recently paid" panel used by the collections team.
class RecentlyPaidAccounts
  DEFAULT_LIMIT = 10

  def initialize(scope: Account.all, limit: DEFAULT_LIMIT)
    @scope = scope
    @limit = limit
  end

  def call
    @scope
      .billable
      .paying
      .order(last_payment_at: :desc, id: :asc)
      .limit(@limit)
  end
end
