require "test_helper"

# Reference regression test (CI proof only; not part of the agent's seed).
class RecentlyPaidAccountsRegressionTest < ActiveSupport::TestCase
  test "billable accounts that have never paid are not listed, and do not sort first" do
    Account.create!(name: "Comped Co", email: "owner@comped.example", status: "active")

    assert_equal [accounts(:umbrella), accounts(:acme), accounts(:initech)], RecentlyPaidAccounts.new.call.to_a
  end
end
