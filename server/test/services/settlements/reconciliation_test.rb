require "test_helper"

module Settlements
  class ReconciliationTest < ActiveSupport::TestCase
    # 2025-03-14: the day cited in the bug report (charge_cents=2106014781, refund_cents=38661548)
    DAY = Date.iso8601("2025-03-14")

    setup { LedgerPoster.new(DayFile.for(DAY)).post! }

    test "reports MATCH when the posted ledger equals the processor net" do
      result = Reconciliation.new(DAY).call

      assert result.matched?, "expected matched? to be true but difference_cents=#{result.difference_cents}"
      assert_equal 0, result.difference_cents
    end

    test "ledger_net_cents equals charge_cents minus refund_cents" do
      entry = Corpus.entry_for(DAY)
      result = Reconciliation.new(DAY).call

      assert_equal entry.fetch("charge_cents") - entry.fetch("refund_cents"), result.ledger_net_cents
    end

    test "reports MISMATCH when a ledger entry is altered" do
      # Corrupt one debit to make the ledger differ from the processor file.
      scope = LedgerPoster.entries_for(DAY)
      scope.where(entry_type: "debit").first.update!(amount_cents: 1)

      result = Reconciliation.new(DAY).call

      assert_not result.matched?
      assert_not_equal 0, result.difference_cents
    end
  end
end
