require "test_helper"

class AccountEventTest < ActiveSupport::TestCase
  test "recent events are newest first" do
    kinds = AccountEvent.recent_for(accounts(:acme).id).map(&:kind)
    assert_equal %w[plan_changed signed_up], kinds
  end

  test "payload is structured JSON from the events database" do
    event = AccountEvent.recent_for(accounts(:acme).id).first
    assert_equal({ "from" => "starter", "to" => "growth" }, event.payload)
  end

  test "Rails treats the events database as read-only" do
    assert_raises(ActiveRecord::ReadOnlyRecord) do
      AccountEvent.new(account_id: 1, kind: "x", payload: {}, occurred_at: Time.current).save!
    end
  end
end
