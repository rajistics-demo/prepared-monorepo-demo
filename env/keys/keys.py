#!/usr/bin/env python3
"""Compute the prepared-environment cache keys.

bundle   key for the prebuilt gem bundle: lockfile, Ruby, platform, base image,
         native libraries, libpq and bundle configuration.
fixture  key for one database fixture (primary, ledger or events): server
         image digest, schema/migration sources, bootstrap and seed sources.

Both print `{"key": "...", "inputs": {...}}` (with --json) or just the key.
A key mismatch means "do not reuse"; callers fall back to the cold path.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

NATIVE_PACKAGES = ["libpq5", "libpq-dev", "libssl3t64", "libyaml-0-2", "zlib1g", "libffi8", "gcc"]
BUNDLE_ENV = ["BUNDLE_WITHOUT", "BUNDLE_WITH", "BUNDLE_FORCE_RUBY_PLATFORM", "BUNDLE_BUILD__PG"]

COMMON_FIXTURE_INPUTS = [
    "server/lib/tasks/dev_bootstrap.rake",
    "server/bin/auth-check",
    "server/db/seeds.rb",
    "server/config/database.yml",
]
FIXTURE_INPUTS = {
    "primary": {"service": "pg16", "files": ["server/db/schema.rb"], "trees": ["server/db/migrate"]},
    "ledger": {"service": "pg14", "files": ["server/db/ledger_schema.rb"], "trees": ["server/db/ledger_migrate"]},
    "events": {
        "service": "pg17",
        "files": ["services/events-svc/Cargo.lock", "services/events-svc/Cargo.toml"],
        "trees": ["services/events-svc/migrations", "services/events-svc/src"],
    },
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_hash(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"keys: missing input file {path}")
    return sha256_bytes(path.read_bytes())


def tree_hash(root: Path) -> str:
    if not root.is_dir():
        raise SystemExit(f"keys: missing input directory {root}")
    entries = [f"{p.relative_to(root).as_posix()}\0{file_hash(p)}" for p in sorted(root.rglob("*")) if p.is_file()]
    return sha256_bytes("\n".join(entries).encode())


def canonical_key(inputs: dict) -> str:
    return sha256_bytes(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode())


def run(cmd: list[str]) -> str:
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        raise SystemExit(f"keys: command failed: {' '.join(cmd)}: {e}")


def bundle_inputs(repo: Path, pins: dict) -> dict:
    server = repo / "server"
    lock = (server / "Gemfile.lock").read_text()
    bundled_with = re.search(r"^BUNDLED WITH\n\s+(\S+)", lock, re.M)
    ruby_facts = json.loads(run([
        "ruby", "-rjson", "-rrbconfig", "-e",
        'print JSON.generate(description: RUBY_DESCRIPTION, platform: Gem::Platform.local.to_s, arch: RbConfig::CONFIG["arch"])',
    ]))
    dpkg = run(["dpkg-query", "-W", "-f=${Package}=${Version}\\n", *NATIVE_PACKAGES]).splitlines()
    return {
        "gemfile_sha256": file_hash(server / "Gemfile"),
        "gemfile_lock_sha256": sha256_bytes(lock.encode()),
        "bundled_with": bundled_with.group(1) if bundled_with else None,
        "ruby_version_file": (server / ".ruby-version").read_text().strip(),
        "ruby_description": ruby_facts["description"],
        "gem_platform": ruby_facts["platform"],
        "rbconfig_arch": ruby_facts["arch"],
        "base_image_digest": pins["agent_server_base"]["linux_amd64_digest"],
        "native_packages": sorted(dpkg),
        "pg_config_version": run(["pg_config", "--version"]),
        "bundle_env": {k: os.environ.get(k) for k in BUNDLE_ENV},
    }


def fixture_inputs(repo: Path, pins: dict, db: str) -> dict:
    spec = FIXTURE_INPUTS[db]
    service = pins["services"][spec["service"]]
    return {
        "db": db,
        "service": spec["service"],
        "service_ref": service["ref"],
        "service_index_digest": service["index_digest"],
        "major": service["major"],
        "files": {f: file_hash(repo / f) for f in spec["files"] + COMMON_FIXTURE_INPUTS},
        "trees": {t: tree_hash(repo / t) for t in spec["trees"]},
        "fixture_format_version": pins["fixture_format_version"],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", choices=["bundle", "fixture"])
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--pins", type=Path, help="defaults to <repo>/env/pins.json")
    ap.add_argument("--db", choices=sorted(FIXTURE_INPUTS))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    pins = json.loads((args.pins or args.repo / "env/pins.json").read_text())
    if args.kind == "bundle":
        inputs = bundle_inputs(args.repo, pins)
    else:
        if not args.db:
            ap.error("fixture requires --db")
        inputs = fixture_inputs(args.repo, pins, args.db)
    key = canonical_key(inputs)
    print(json.dumps({"key": key, "inputs": inputs}, indent=2, sort_keys=True) if args.json else key)
    return 0


if __name__ == "__main__":
    sys.exit(main())
