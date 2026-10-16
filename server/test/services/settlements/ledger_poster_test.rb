require "test_helper"

module Settlements
  class LedgerPosterTest < ActiveSupport::TestCase
    DAY = Date.new(2024, 1, 2)

    test "posts every row of a settlement day into the ledger database" do
      entry = Corpus.entry_for(DAY)

      assert_equal entry.fetch("rows"), LedgerPoster.new(DayFile.for(DAY)).post!

      scope = LedgerPoster.entries_for(DAY)
      assert_equal({ "credit" => entry.fetch("charges"), "debit" => entry.fetch("refunds") },
                   scope.group(:entry_type).count)
      assert_equal entry.fetch("charge_cents"), scope.where(entry_type: "credit").sum(:amount_cents)
      assert_equal entry.fetch("refund_cents"), scope.where(entry_type: "debit").sum(:amount_cents)
    end

    test "refuses to post the same settlement day twice" do
      LedgerPoster.new(DayFile.for(DAY)).post!

      assert_raises(LedgerPoster::AlreadyPosted) { LedgerPoster.new(DayFile.for(DAY)).post! }
    end
  end
end
