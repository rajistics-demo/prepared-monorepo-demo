require "test_helper"

class AccountsApiTest < ActionDispatch::IntegrationTest
  test "recently paid endpoint returns accounts newest payment first" do
    get recently_paid_accounts_path, params: { limit: 2 }
    assert_response :success
    assert_equal [accounts(:umbrella).id, accounts(:acme).id], response.parsed_body.map { |a| a["id"] }
  end

  test "ledger endpoint returns balance and running balances" do
    get ledger_account_path(accounts(:acme))
    assert_response :success
    body = response.parsed_body
    assert_equal 11_900, body["balance_cents"]
    assert_equal 3, body["entries"].size
  end

  test "activity endpoint reads from the events database" do
    get activity_account_path(accounts(:acme))
    assert_response :success
    assert_equal %w[plan_changed signed_up], response.parsed_body.map { |e| e["kind"] }
  end
end
