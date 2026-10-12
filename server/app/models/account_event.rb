class AccountEvent < EventsRecord
  self.table_name = "account_events"

  def self.recent_for(account_id, limit: 20)
    where(account_id: account_id).order(occurred_at: :desc, id: :desc).limit(limit)
  end
end
