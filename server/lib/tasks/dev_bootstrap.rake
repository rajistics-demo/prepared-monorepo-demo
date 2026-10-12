# Custom bootstrap that replaces `db:setup` for this monorepo.
#
# Order matters and every step fails closed:
#   1. auth gate (bin/auth-check, AUTH_MODE must be explicit)
#   2. each database server answers with the expected PostgreSQL major
#   3. services/events-svc is healthy and has migrated the events databases
#   4. primary (PG16) and ledger (PG14) schemas are loaded per environment
#   5. development seeds
require "json"
require "net/http"
require "open3"

module DevBootstrap
  SERVERS = [
    { label: "ledger", port_env: "PG14_PORT", default_port: 54314, major: 14 },
    { label: "primary", port_env: "PG16_PORT", default_port: 54316, major: 16 },
    { label: "events", port_env: "PG17_PORT", default_port: 54317, major: 17 }
  ].freeze

  module_function

  def root = File.expand_path("../..", __dir__)

  def events_migrations_dir = File.expand_path("../services/events-svc/migrations", root)

  def expected_events_schema_version = Dir[File.join(events_migrations_dir, "*.sql")].size

  def step(state, name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    state[:steps] << { name: name, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3) }
    result
  end

  def fail!(message, code: 1)
    warn "dev:bootstrap FAILED: #{message}"
    exit code
  end

  def auth_gate!
    system(File.join(root, "bin/auth-check"))
    status = $?.exitstatus
    fail!("auth gate refused (bin/auth-check exit #{status})", code: status.to_i.zero? ? 78 : status) unless status&.zero?
  end

  def check_servers!(timeout: Integer(ENV.fetch("BOOTSTRAP_DB_TIMEOUT", "60")))
    require "pg"
    SERVERS.map do |s|
      port = Integer(ENV.fetch(s[:port_env], s[:default_port].to_s))
      deadline = Time.now + timeout
      begin
        conn = PG.connect(host: ENV.fetch("PGHOST", "127.0.0.1"), port: port,
                          user: ENV.fetch("PGUSER", "postgres"), dbname: "postgres", connect_timeout: 3)
        version = conn.server_version
        conn.close
      rescue PG::Error => e
        retry if Time.now < deadline && sleep(1)
        fail!("#{s[:label]} database on port #{port} unreachable: #{e.message.lines.first&.strip}")
      end
      major = version / 10_000
      fail!("#{s[:label]} expected PostgreSQL #{s[:major]}, got #{major}") unless major == s[:major]
      { label: s[:label], port: port, server_version_num: version }
    end
  end

  def check_events_service!(envs, timeout: Integer(ENV.fetch("BOOTSTRAP_EVENTS_TIMEOUT", "120")))
    uri = URI("http://127.0.0.1:#{ENV.fetch('EVENTS_SVC_PORT', '18080')}/healthz")
    expected = expected_events_schema_version
    wanted = envs.map { |e| "server_events_#{e}" }
    deadline = Time.now + timeout
    last = nil
    loop do
      begin
        res = Net::HTTP.get_response(uri)
        if res.is_a?(Net::HTTPSuccess)
          body = JSON.parse(res.body)
          last = body
          return body if body["schema_version"] == expected && (wanted - body.fetch("databases", [])).empty?
        end
      rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
        last = e.class.name
      end
      fail!("events-svc not ready with schema_version=#{expected} for #{wanted.join(',')} (last: #{last.inspect})") if Time.now > deadline
      sleep 1
    end
  end

  def rails!(env, *tasks)
    vars = { "RAILS_ENV" => env, "SKIP_TEST_DATABASE" => "true" }
    out, status = Open3.capture2e(vars, File.join(root, "bin/rails"), *tasks, chdir: root)
    fail!("bin/rails #{tasks.join(' ')} (#{env}) failed:\n#{out}") unless status.success?
  end

  def run(envs)
    state = { started_at: Time.now.utc.iso8601, envs: envs, auth_mode: ENV["AUTH_MODE"], steps: [] }
    step(state, "auth_gate") { auth_gate! }
    state[:servers] = step(state, "server_versions") { check_servers! }
    state[:events_service] = step(state, "events_service") { check_events_service!(envs) }
    envs.each do |env|
      step(state, "schema_load:#{env}") { rails!(env, "db:create", "db:schema:load") }
    end
    step(state, "seed:development") { rails!("development", "db:seed") } if envs.include?("development")
    state[:finished_at] = Time.now.utc.iso8601
    path = File.join(root, "tmp", "bootstrap-state.json")
    File.write(path, JSON.pretty_generate(state))
    puts "dev:bootstrap OK (#{envs.join(',')}); state written to tmp/bootstrap-state.json"
  end
end

namespace :dev do
  desc "Bootstrap databases for BOOTSTRAP_ENVS (default development,test). Replaces db:setup."
  task :bootstrap do
    envs = ENV.fetch("BOOTSTRAP_ENVS", "development,test").split(",").map(&:strip).reject(&:empty?)
    unknown = envs - %w[development test]
    DevBootstrap.fail!("unknown BOOTSTRAP_ENVS: #{unknown.join(',')}") unless unknown.empty?
    DevBootstrap.run(envs)
  end
end
