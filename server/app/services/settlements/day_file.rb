# One processor settlement file. The processor's format is fixed: comma
# separated, no quoting, header on the first line, amounts in integer cents.
module Settlements
  class DayFile
    HEADER = %w[batch_id processor_ref account_id policy_ref txn_type card_brand card_last4 auth_code
                amount_cents fee_cents net_cents currency captured_at settled_on descriptor].freeze

    Row = Data.define(:processor_ref, :account_id, :txn_type, :amount_cents, :fee_cents, :net_cents,
                      :captured_at, :settled_on) do
      def refund? = txn_type == "refund"
    end

    attr_reader :date, :entry, :path

    def self.for(date) = new(date.is_a?(Date) ? date : Date.iso8601(date.to_s))

    def initialize(date)
      @date = date
      @entry = Corpus.entry_for(date)
      @path = Corpus.data_root.join(entry.fetch("path"))
      verify!
    end

    def each_row
      return enum_for(:each_row) unless block_given?

      File.open(path, "r") do |f|
        header = f.gets&.chomp&.split(",")
        raise CorpusMissing, "#{path}: unexpected header" unless header == HEADER

        f.each_line do |line|
          c = line.chomp.split(",", -1)
          yield Row.new(processor_ref: c[1], account_id: Integer(c[2], 10), txn_type: c[4],
                        amount_cents: Integer(c[8], 10), fee_cents: Integer(c[9], 10), net_cents: Integer(c[10], 10),
                        captured_at: c[12], settled_on: Date.iso8601(c[13]))
        end
      end
    end

    # Processor-side totals, computed from the file itself.
    def totals
      t = { rows: 0, charges: 0, refunds: 0, charge_cents: 0, refund_cents: 0, fee_cents: 0 }
      each_row do |r|
        t[:rows] += 1
        t[:fee_cents] += r.fee_cents
        if r.refund?
          t[:refunds] += 1
          t[:refund_cents] += r.amount_cents
        else
          t[:charges] += 1
          t[:charge_cents] += r.amount_cents
        end
      end
      t
    end

    private

    def verify!
      unless path.file?
        raise CorpusMissing, "#{path} is not materialized; run tools/settlements-corpus/materialize.py"
      end
      raise CorpusMissing, "#{path}: size does not match the manifest" unless path.size == entry.fetch("bytes")
      raise CorpusMissing, "#{path}: sha256 does not match the manifest" unless
        Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
    end
  end
end
