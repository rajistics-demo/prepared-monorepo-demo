class Payment < ApplicationRecord
  belongs_to :account

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :paid_at, presence: true

  after_create :touch_account_last_payment

  private

  def touch_account_last_payment
    return if account.last_payment_at && account.last_payment_at >= paid_at

    account.update_column(:last_payment_at, paid_at)
  end
end
