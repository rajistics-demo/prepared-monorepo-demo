# Raised when a settlement file is absent or does not match the committed manifest.
# This is an environment failure, never a behavior failure.
module Settlements
  class CorpusMissing < StandardError; end
end
