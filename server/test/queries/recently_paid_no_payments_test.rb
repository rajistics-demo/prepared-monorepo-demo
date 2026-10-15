require "test_helper"

# Regression: billable accounts with no payments must not appear in results.
# In PostgreSQL, ORDER BY last_payment_at DESC puts NULLs first, so a comped
# (never-paid) account would appear at the top of the list if not excluded.
class RecentlyPaidNoPaymentsTest < ActiveSupport::TestCase
  test "excludes a billable account that has never made a payment" do
    comped = Account.create!(
      name: "Comped Corp",
      email: "billing@comped-corp.example",
      status: "active",
      last_payment_at: nil
    )

    result = RecentlyPaidAccounts.new.call.to_a

    assert_not_includes result, comped
  end

  test "returned accounts all have at least one payment" do
    Account.create!(
      name: "Comped Corp Two",
      email: "billing@comped-two.example",
      status: "active",
      last_payment_at: nil
    )

    result = RecentlyPaidAccounts.new.call.to_a

    result.each do |account|
      assert_not_nil account.last_payment_at,
        "#{account.name} (id=#{account.id}) has no payments but appears in recently_paid results"
    end
  end
end
