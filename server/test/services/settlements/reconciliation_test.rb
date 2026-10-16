require "test_helper"

module Settlements
  class ReconciliationTest < ActiveSupport::TestCase
    DAY = Date.iso8601("2025-03-14")

    setup do
      LedgerPoster.new(DayFile.for(DAY)).post!
    end

    test "reconciliation matches after a correct post (credits minus debits equals processor net)" do
      result = Reconciliation.new(DAY).call

      assert result.matched?,
        "expected MATCH but got MISMATCH: processor_net_cents=#{result.processor_net_cents} " \
        "ledger_net_cents=#{result.ledger_net_cents} difference_cents=#{result.difference_cents}"
    end
  end
end
