require "test_helper"

# Guards setup fidelity: each logical database must be served by its intended
# PostgreSQL major, and the events schema must be the one events-svc owns.
class DatabaseVersionsTest < ActiveSupport::TestCase
  def server_major(record_class)
    record_class.connection.select_value("SHOW server_version_num").to_i / 10_000
  end

  test "primary database runs on PostgreSQL 16" do
    assert_equal 16, server_major(ApplicationRecord)
    assert_equal "server_primary_test", ApplicationRecord.connection.current_database
  end

  test "ledger database runs on PostgreSQL 14" do
    assert_equal 14, server_major(LedgerRecord)
    assert_equal "server_ledger_test", LedgerRecord.connection.current_database
  end

  test "events database runs on PostgreSQL 17" do
    assert_equal 17, server_major(EventsRecord)
    assert_equal "server_events_test", EventsRecord.connection.current_database
  end

  test "events schema version matches the events-svc migrations in this monorepo" do
    expected = Dir[Rails.root.join("../services/events-svc/migrations/*.sql")].size
    applied = EventsRecord.connection.select_value("SELECT max(version) FROM events_schema_migrations").to_i
    assert_operator expected, :>, 0
    assert_equal expected, applied
  end
end
