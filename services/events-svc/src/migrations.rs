/// Embedded, ordered schema migrations for the events database.
/// The Rails app counts `migrations/*.sql` to know which version to expect,
/// so every file here must be listed exactly once, in order.
pub struct Migration {
    pub version: i32,
    pub name: &'static str,
    pub sql: &'static str,
}

pub const MIGRATIONS: &[Migration] = &[
    Migration {
        version: 1,
        name: "0001_create_account_events",
        sql: include_str!("../migrations/0001_create_account_events.sql"),
    },
    Migration {
        version: 2,
        name: "0002_require_event_kind",
        sql: include_str!("../migrations/0002_require_event_kind.sql"),
    },
];

pub fn latest_version() -> i32 {
    MIGRATIONS.last().map(|m| m.version).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions_are_contiguous_from_one() {
        for (i, m) in MIGRATIONS.iter().enumerate() {
            assert_eq!(m.version, i as i32 + 1, "migration {} out of order", m.name);
            assert!(m.name.starts_with(&format!("{:04}_", m.version)));
        }
    }

    #[test]
    fn every_sql_file_is_embedded() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/migrations");
        let files = std::fs::read_dir(dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.path().extension().is_some_and(|x| x == "sql"))
            .count();
        assert_eq!(files, MIGRATIONS.len());
    }
}
