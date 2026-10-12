require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  test "a newer payment updates the account's last payment time" do
    account = accounts(:acme)
    paid_at = Time.utc(2026, 10, 1, 9)
    account.payments.create!(amount_cents: 500, paid_at: paid_at)
    assert_equal paid_at, account.reload.last_payment_at
  end

  test "an older, backfilled payment does not move last payment time backwards" do
    account = accounts(:acme)
    before = account.last_payment_at
    account.payments.create!(amount_cents: 500, paid_at: before - 30.days)
    assert_equal before, account.reload.last_payment_at
  end

  test "amount must be positive" do
    payment = accounts(:acme).payments.build(amount_cents: 0, paid_at: Time.current)
    assert_not payment.valid?
  end
end
