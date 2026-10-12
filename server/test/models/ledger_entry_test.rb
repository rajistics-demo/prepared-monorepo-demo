require "test_helper"

class LedgerEntryTest < ActiveSupport::TestCase
  test "balance is credits minus debits" do
    assert_equal 12_900 - 2_500 + 1_500, LedgerEntry.balance_for(accounts(:acme).id)
  end

  test "running balances are computed in date order by the ledger database" do
    balances = LedgerEntry.running_balances(accounts(:acme).id).map { |e| e[:running_balance_cents] }
    assert_equal [12_900, 10_400, 11_900], balances
  end

  test "an account with no entries has a zero balance" do
    assert_equal 0, LedgerEntry.balance_for(accounts(:globex).id)
  end
end
