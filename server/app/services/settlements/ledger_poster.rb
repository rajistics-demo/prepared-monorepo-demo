# Posts one settlement day into the ledger: a credit per charge and a debit
# per refund, dated on the settlement day.
module Settlements
  class LedgerPoster
    BATCH_SIZE = 2_000
    MEMO_PREFIX = "settlement:".freeze

    class AlreadyPosted < StandardError; end

    def self.entries_for(date) = LedgerEntry.where(posted_on: date).where("memo LIKE ?", "#{MEMO_PREFIX}%")

    def initialize(day_file)
      @day_file = day_file
    end

    def post!
      date = @day_file.date
      raise AlreadyPosted, "settlement #{date} is already posted" if self.class.entries_for(date).exists?

      now = Time.current
      posted = 0
      LedgerEntry.transaction do
        @day_file.each_row.each_slice(BATCH_SIZE) do |rows|
          LedgerEntry.insert_all!(rows.map { |r| attributes(r, now) })
          posted += rows.size
        end
      end
      posted
    end

    private

    def attributes(row, now)
      { account_id: row.account_id, entry_type: row.refund? ? "debit" : "credit", amount_cents: row.amount_cents,
        posted_on: row.settled_on, memo: "#{MEMO_PREFIX}#{row.processor_ref}", created_at: now, updated_at: now }
    end
  end
end
