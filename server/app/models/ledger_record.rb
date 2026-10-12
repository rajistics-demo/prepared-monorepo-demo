# Ledger data lives in a separate, older PostgreSQL 14 cluster.
class LedgerRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :ledger, reading: :ledger }
end
