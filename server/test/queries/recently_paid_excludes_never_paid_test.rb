require "test_helper"

class RecentlyPaidExcludesNeverPaidTest < ActiveSupport::TestCase
  test "excludes accounts that have never made a payment" do
    comped = Account.create!(
      name:   "Comped Corp",
      email:  "billing@comped.example",
      status: "active"
      # last_payment_at intentionally absent (nil)
    )

    result = RecentlyPaidAccounts.new.call.to_a

    assert_not_includes result, comped,
      "expected never-paid account to be excluded from recently_paid, but it appeared"
  end
end
