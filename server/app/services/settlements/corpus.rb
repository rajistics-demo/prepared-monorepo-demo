# The processor settlement corpus: one CSV per settlement day.
#
# The manifest is committed with the code, so a checkout always knows exactly
# which bytes each day must contain. The files themselves are materialized by
# tools/settlements-corpus/materialize.py and are not in Git. Point
# SETTLEMENTS_CORPUS_DIR at a shared verified copy to avoid a second
# materialization; every file is still checked against this checkout's manifest.
module Settlements
  module Corpus
    module_function

    def manifest_path = Rails.root.join("data/settlements/manifest.json")

    def data_root = Pathname(ENV.fetch("SETTLEMENTS_CORPUS_DIR", Rails.root.join("data/settlements").to_s))

    def manifest
      @manifest ||= JSON.parse(File.read(manifest_path))
    end

    def entry_for(date)
      files_by_day.fetch(date.iso8601) { raise ArgumentError, "no settlement file for #{date}" }
    end

    def files_by_day
      @files_by_day ||= manifest.fetch("files").index_by { |f| f.fetch("settled_on") }
    end
  end
end
