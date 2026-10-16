require "test_helper"

module Settlements
  class DayFileTest < ActiveSupport::TestCase
    DAY = Date.new(2024, 1, 2)

    test "parses a materialized settlement day and matches the manifest's processor totals" do
      entry = Corpus.entry_for(DAY)
      totals = DayFile.for(DAY).totals

      %i[rows charges refunds charge_cents refund_cents fee_cents].each do |key|
        assert_equal entry.fetch(key.to_s), totals[key], key
      end
      assert_operator totals[:refunds], :>, 0
    end

    test "refuses a day that is not materialized" do
      Dir.mktmpdir do |dir|
        with_corpus_dir(dir) { assert_raises(CorpusMissing) { DayFile.for(DAY) } }
      end
    end

    test "refuses a file that does not match the manifest" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, Corpus.entry_for(DAY).fetch("path"))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, DayFile::HEADER.join(",") + "\n")
        with_corpus_dir(dir) { assert_raises(CorpusMissing) { DayFile.for(DAY) } }
      end
    end

    private

    def with_corpus_dir(dir)
      previous = ENV["SETTLEMENTS_CORPUS_DIR"]
      ENV["SETTLEMENTS_CORPUS_DIR"] = dir
      yield
    ensure
      ENV["SETTLEMENTS_CORPUS_DIR"] = previous
    end
  end
end
