class Account < ApplicationRecord
  STATUSES = %w[trial active past_due closed].freeze

  has_many :payments, dependent: :destroy

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :billable, -> { where(status: %w[active past_due]) }
  scope :paying, -> { where.not(last_payment_at: nil) }

  def ledger_entries
    LedgerEntry.where(account_id: id)
  end

  def events
    AccountEvent.where(account_id: id)
  end
end
