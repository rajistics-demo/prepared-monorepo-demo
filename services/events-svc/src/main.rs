//! events-svc: owns the PostgreSQL 17 events schema.
//!
//! Commands:
//!   serve        create + migrate EVENTS_DATABASES, then serve /healthz and /version
//!   migrate      create + migrate, then exit
//!   healthcheck  exit 0 if the local /healthz answers 200 (used by Compose)

mod migrations;

use std::env;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::process::ExitCode;
use std::thread;
use std::time::{Duration, Instant};

use postgres::{Client, NoTls};
use tiny_http::{Header, Response, Server};

const REQUIRED_MAJOR: i32 = 17;
const MIGRATION_LOCK_KEY: i64 = 7_272_740_017;

struct Config {
    admin_url: String,
    databases: Vec<String>,
    listen: String,
}

struct Status {
    server_version: String,
    schema_version: i32,
    databases: Vec<String>,
}

fn main() -> ExitCode {
    let command = env::args().nth(1).unwrap_or_else(|| "serve".to_string());
    let result = match command.as_str() {
        "serve" => config().and_then(|c| serve(&c)),
        "migrate" => config().and_then(|c| migrate_all(&c).map(|_| ())),
        "healthcheck" => healthcheck(),
        other => Err(format!("unknown command '{other}' (expected serve, migrate or healthcheck)")),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("events-svc: {e}");
            ExitCode::FAILURE
        }
    }
}

fn config() -> Result<Config, String> {
    let admin_url = env::var("EVENTS_ADMIN_URL").map_err(|_| "EVENTS_ADMIN_URL is required".to_string())?;
    let raw = env::var("EVENTS_DATABASES").map_err(|_| "EVENTS_DATABASES is required".to_string())?;
    let databases: Vec<String> = raw.split(',').map(str::trim).filter(|s| !s.is_empty()).map(String::from).collect();
    if databases.is_empty() {
        return Err("EVENTS_DATABASES is empty".into());
    }
    for db in &databases {
        if !valid_db_name(db) {
            return Err(format!("invalid database name '{db}'"));
        }
    }
    Ok(Config { admin_url, databases, listen: listen_addr() })
}

fn listen_addr() -> String {
    env::var("EVENTS_LISTEN").unwrap_or_else(|_| "0.0.0.0:8080".to_string())
}

fn valid_db_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 63 && name.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

fn db_url(admin_url: &str, db: &str) -> Result<String, String> {
    let (base, _) = admin_url.rsplit_once('/').ok_or("EVENTS_ADMIN_URL must end with /<database>")?;
    Ok(format!("{base}/{db}"))
}

fn connect_with_retry(url: &str, timeout: Duration) -> Result<Client, String> {
    let deadline = Instant::now() + timeout;
    loop {
        match Client::connect(url, NoTls) {
            Ok(client) => return Ok(client),
            Err(e) if Instant::now() < deadline => {
                eprintln!("events-svc: waiting for database: {e}");
                thread::sleep(Duration::from_secs(1));
            }
            Err(e) => return Err(format!("could not connect to database: {e}")),
        }
    }
}

fn ensure_database(admin: &mut Client, db: &str) -> Result<(), String> {
    let exists = admin
        .query_opt("SELECT 1 FROM pg_database WHERE datname = $1", &[&db])
        .map_err(|e| e.to_string())?
        .is_some();
    if exists {
        return Ok(());
    }
    match admin.batch_execute(&format!("CREATE DATABASE \"{db}\"")) {
        Ok(()) => Ok(()),
        Err(e) if e.code().map(|c| c.code()) == Some("42P04") => Ok(()),
        Err(e) => Err(format!("create database {db}: {e}")),
    }
}

fn migrate(client: &mut Client) -> Result<i32, String> {
    client
        .batch_execute(
            "CREATE TABLE IF NOT EXISTS events_schema_migrations (
                version integer PRIMARY KEY,
                name text NOT NULL,
                applied_at timestamptz NOT NULL DEFAULT now()
            )",
        )
        .map_err(|e| e.to_string())?;
    client.execute("SELECT pg_advisory_lock($1)", &[&MIGRATION_LOCK_KEY]).map_err(|e| e.to_string())?;
    let result = (|| {
        let current: i32 = client
            .query_one("SELECT COALESCE(max(version), 0) FROM events_schema_migrations", &[])
            .map_err(|e| e.to_string())?
            .get(0);
        for m in migrations::MIGRATIONS.iter().filter(|m| m.version > current) {
            let mut tx = client.transaction().map_err(|e| e.to_string())?;
            tx.batch_execute(m.sql).map_err(|e| format!("migration {}: {e}", m.name))?;
            tx.execute("INSERT INTO events_schema_migrations (version, name) VALUES ($1, $2)", &[&m.version, &m.name])
                .map_err(|e| e.to_string())?;
            tx.commit().map_err(|e| e.to_string())?;
            eprintln!("events-svc: applied {}", m.name);
        }
        let applied: i32 = client
            .query_one("SELECT COALESCE(max(version), 0) FROM events_schema_migrations", &[])
            .map_err(|e| e.to_string())?
            .get(0);
        Ok(applied)
    })();
    let _ = client.execute("SELECT pg_advisory_unlock($1)", &[&MIGRATION_LOCK_KEY]);
    result
}

fn migrate_all(cfg: &Config) -> Result<Status, String> {
    let mut admin = connect_with_retry(&cfg.admin_url, Duration::from_secs(60))?;
    let version_num: i32 = admin
        .query_one("SHOW server_version_num", &[])
        .map_err(|e| e.to_string())?
        .get::<_, String>(0)
        .parse()
        .map_err(|e| format!("bad server_version_num: {e}"))?;
    if version_num / 10_000 != REQUIRED_MAJOR {
        return Err(format!("requires PostgreSQL {REQUIRED_MAJOR}, server reports {version_num}"));
    }
    let server_version: String = admin.query_one("SHOW server_version", &[]).map_err(|e| e.to_string())?.get(0);
    let latest = migrations::latest_version();
    for db in &cfg.databases {
        ensure_database(&mut admin, db)?;
        let mut client = connect_with_retry(&db_url(&cfg.admin_url, db)?, Duration::from_secs(10))?;
        let applied = migrate(&mut client)?;
        if applied != latest {
            return Err(format!("{db}: schema version {applied}, expected {latest}"));
        }
    }
    Ok(Status { server_version, schema_version: latest, databases: cfg.databases.clone() })
}

fn json_escape(s: &str) -> String {
    s.chars()
        .flat_map(|c| match c {
            '"' => "\\\"".chars().collect::<Vec<_>>(),
            '\\' => "\\\\".chars().collect(),
            c if c.is_control() => format!("\\u{:04x}", c as u32).chars().collect(),
            c => vec![c],
        })
        .collect()
}

fn health_json(status: &Status) -> String {
    let dbs: Vec<String> = status.databases.iter().map(|d| format!("\"{}\"", json_escape(d))).collect();
    format!(
        "{{\"status\":\"ok\",\"schema_version\":{},\"server_version\":\"{}\",\"databases\":[{}]}}",
        status.schema_version,
        json_escape(&status.server_version),
        dbs.join(",")
    )
}

fn serve(cfg: &Config) -> Result<(), String> {
    let status = migrate_all(cfg)?;
    let health = health_json(&status);
    let version = format!("{{\"name\":\"events-svc\",\"version\":\"{}\"}}", env!("CARGO_PKG_VERSION"));
    let server = Server::http(&cfg.listen).map_err(|e| format!("listen {}: {e}", cfg.listen))?;
    eprintln!("events-svc: ready on {} ({})", cfg.listen, health);
    let json = Header::from_bytes(&b"Content-Type"[..], &b"application/json"[..]).expect("static header");
    for request in server.incoming_requests() {
        let (code, body) = match request.url() {
            "/healthz" => (200, health.clone()),
            "/version" => (200, version.clone()),
            _ => (404, "{\"error\":\"not found\"}".to_string()),
        };
        let _ = request.respond(Response::from_string(body).with_status_code(code).with_header(json.clone()));
    }
    Ok(())
}

fn healthcheck() -> Result<(), String> {
    let port = listen_addr().rsplit_once(':').map(|(_, p)| p.to_string()).unwrap_or_else(|| "8080".into());
    let addr: SocketAddr = format!("127.0.0.1:{port}").parse().map_err(|e| format!("bad address: {e}"))?;
    let mut stream = TcpStream::connect_timeout(&addr, Duration::from_secs(2)).map_err(|e| e.to_string())?;
    stream.set_read_timeout(Some(Duration::from_secs(2))).map_err(|e| e.to_string())?;
    stream
        .write_all(b"GET /healthz HTTP/1.0\r\nHost: localhost\r\n\r\n")
        .map_err(|e| e.to_string())?;
    let mut response = String::new();
    stream.read_to_string(&mut response).map_err(|e| e.to_string())?;
    let status_line = response.lines().next().unwrap_or_default();
    if status_line.split_whitespace().nth(1) == Some("200") {
        Ok(())
    } else {
        Err(format!("unhealthy: {status_line}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn db_url_replaces_database() {
        assert_eq!(
            db_url("postgres://postgres@pg17:5432/postgres", "server_events_test").unwrap(),
            "postgres://postgres@pg17:5432/server_events_test"
        );
    }

    #[test]
    fn rejects_unsafe_database_names() {
        assert!(valid_db_name("server_events_test"));
        assert!(!valid_db_name("Bad\";DROP"));
        assert!(!valid_db_name(""));
    }

    #[test]
    fn health_json_is_escaped() {
        let s = Status { server_version: "17.11 \"x\"".into(), schema_version: 2, databases: vec!["a".into()] };
        assert_eq!(
            health_json(&s),
            "{\"status\":\"ok\",\"schema_version\":2,\"server_version\":\"17.11 \\\"x\\\"\",\"databases\":[\"a\"]}"
        );
    }

    /// Runs against a real PostgreSQL 17 when EVENTS_TEST_ADMIN_URL is set (CI does this).
    #[test]
    fn migrates_idempotently_against_postgres_17() {
        let Ok(admin_url) = env::var("EVENTS_TEST_ADMIN_URL") else {
            eprintln!("skipping: EVENTS_TEST_ADMIN_URL not set");
            return;
        };
        let cfg = Config {
            admin_url,
            databases: vec!["events_svc_selftest".into()],
            listen: "127.0.0.1:0".into(),
        };
        let first = migrate_all(&cfg).expect("first migration run");
        let second = migrate_all(&cfg).expect("second migration run is a no-op");
        assert_eq!(first.schema_version, migrations::latest_version());
        assert_eq!(second.schema_version, first.schema_version);
        assert!(first.server_version.starts_with("17."));
    }
}
