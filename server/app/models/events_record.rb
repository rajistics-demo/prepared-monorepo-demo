# The events database (PostgreSQL 17) is owned by services/events-svc, which
# creates and migrates it. Rails only reads from it.
class EventsRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :events, reading: :events }

  def readonly?
    true
  end
end
