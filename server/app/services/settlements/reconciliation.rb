# Daily reconciliation: does what the ledger holds for a settlement day equal
# what the processor says it settled? Finance runs this every morning.
module Settlements
  class Reconciliation
    Result = Data.define(:settled_on, :processor_net_cents, :ledger_net_cents, :ledger_entries) do
      def matched? = processor_net_cents == ledger_net_cents
      def difference_cents = ledger_net_cents - processor_net_cents
    end

    def initialize(date)
      @date = date.is_a?(Date) ? date : Date.iso8601(date.to_s)
    end

    def call
      totals = DayFile.for(@date).totals
      Result.new(settled_on: @date, processor_net_cents: totals[:charge_cents] - totals[:refund_cents],
                 ledger_net_cents: ledger_net_cents, ledger_entries: entries.count)
    end

    private

    def entries = LedgerPoster.entries_for(@date)

    def ledger_net_cents
      entries.sum(Arel.sql(LedgerEntry::SIGNED_AMOUNT)).to_i
    end
  end
end
