require "test_helper"

class RecentlyPaidAccountsTest < ActiveSupport::TestCase
  test "lists billable accounts by most recent payment first" do
    result = RecentlyPaidAccounts.new.call.to_a
    assert_equal [accounts(:umbrella), accounts(:acme), accounts(:initech)], result
  end

  test "excludes trial and closed accounts" do
    result = RecentlyPaidAccounts.new.call
    assert_not_includes result, accounts(:globex)
    assert_not_includes result, accounts(:hooli)
  end

  test "respects the limit" do
    assert_equal [accounts(:umbrella)], RecentlyPaidAccounts.new(limit: 1).call.to_a
  end
end
