require "fileutils"
require "json"

# Writes machine-readable test evidence when EVIDENCE_JSON is set.
# Classification separates assertion failures (a real red) from environment
# failures (missing database, pending schema, missing gems), so an
# environment problem can never be mistaken for a reproduced bug.
module Minitest
  class EvidenceReporter < AbstractReporter
    ENV_ERROR_CLASSES = %w[
      PG::ConnectionBad
      PG::UndefinedTable
      ActiveRecord::ConnectionNotEstablished
      ActiveRecord::DatabaseConnectionError
      ActiveRecord::NoDatabaseError
      ActiveRecord::PendingMigrationError
      LoadError
      Bundler::GemNotFound
    ].freeze

    def initialize(path)
      super()
      @path = path
      @results = []
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def record(result)
      file, line = result.source_location
      entry = { test: "#{result.klass}##{result.name}", file: file && relative(file), line: line,
                status: status_for(result), time: result.time.round(4) }
      if (failure = result.failure)
        entry[:failure_class] = failure.is_a?(Minitest::UnexpectedError) ? failure.error.class.name : failure.class.name
        entry[:message] = failure.message.to_s[0, 2000]
        if failure.is_a?(Minitest::UnexpectedError)
          causes = cause_chain(failure.error)
          entry[:cause_classes] = causes
          entry[:env_error] = causes.any? { |c| ENV_ERROR_CLASSES.include?(c) }
        end
      end
      @results << entry
    end

    def report
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(
        classification: classification, counts: counts, wall_seconds: wall_seconds,
        generated_at: Time.now.utc.iso8601, results: @results
      ))
    end

    private

    def status_for(result)
      return "pass" if result.passed?
      return "skip" if result.skipped?

      result.failure.is_a?(Minitest::UnexpectedError) ? "error" : "failure"
    end

    def cause_chain(error)
      chain = []
      while error && chain.size < 5
        chain << error.class.name
        error = error.cause
      end
      chain
    end

    def counts = @results.group_by { |r| r[:status] }.transform_values(&:size)

    def wall_seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started).round(3)

    def relative(path) = path.sub("#{Rails.root}/", "")

    def classification
      return "NO_TESTS" if @results.empty?
      return "ENV_ERROR" if @results.any? { |r| r[:env_error] }
      return "ASSERTION_RED" if @results.any? { |r| r[:status] == "failure" }
      return "CODE_ERROR" if @results.any? { |r| r[:status] == "error" }

      "GREEN"
    end
  end

  def self.plugin_evidence_init(_options)
    reporter << EvidenceReporter.new(ENV["EVIDENCE_JSON"]) if ENV["EVIDENCE_JSON"].to_s != ""
  end
end

Minitest.extensions << "evidence" unless Minitest.extensions.include?("evidence")
