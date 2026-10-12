"""Shared helpers for prepare-workspace, oh-phase, oh-verify and oh-cleanup.

Stdlib only. Nothing here reads or prints secret values.
"""
import hashlib
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

PREPARED = Path(os.environ.get("OH_PREPARED_DIR", "/opt/prepared"))
DEFAULT_TASK_ROOT = Path(os.environ.get("OH_TASK_ROOT", "/workspace/project/oh-tasks"))
DEFAULT_REPO_URL = "https://github.com/rajistics-demo/prepared-monorepo-demo.git"

LOGICAL_DBS = {
    "primary": {"service": "pg16", "port_env": "PG16_PORT", "databases": ["server_primary_development", "server_primary_test"]},
    "ledger": {"service": "pg14", "port_env": "PG14_PORT", "databases": ["server_ledger_development", "server_ledger_test"]},
    "events": {"service": "pg17", "port_env": "PG17_PORT", "databases": ["server_events_development", "server_events_test"]},
}
IMAGE_ENV = {"pg14": "PG14_IMAGE", "pg16": "PG16_IMAGE", "pg17": "PG17_IMAGE", "events-svc": "EVENTS_SVC_IMAGE"}
PORT_ENVS = ["PG14_PORT", "PG16_PORT", "PG17_PORT", "EVENTS_SVC_PORT"]

ROW_COUNTS_SQL = (
    "SELECT table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', "
    "table_schema, table_name), false, true, '')))[1]::text FROM information_schema.tables "
    "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name"
)
DB_FACTS_SQL = (
    "SELECT pg_encoding_to_char(encoding) || '|' || datcollate || '|' || datctype FROM pg_database "
    "WHERE datname = current_database()"
)
EXTENSIONS_SQL = "SELECT extname || '=' || extversion FROM pg_extension ORDER BY extname"


class PhaseError(Exception):
    def __init__(self, phase: str, message: str, exit_code: int = 1):
        super().__init__(message)
        self.phase = phase
        self.exit_code = exit_code


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def run(cmd, *, phase: str, cwd=None, env=None, timeout=300, log: Path | None = None, input_bytes=None,
        stdin_file: Path | None = None, check=True, capture=False) -> subprocess.CompletedProcess:
    """Run a command; append its output to `log`. Raises PhaseError on failure or timeout."""
    full_env = dict(os.environ)
    if env:
        full_env.update(env)
    out_target = subprocess.PIPE if (capture or log) else None
    stdin = open(stdin_file, "rb") if stdin_file else None
    started = time.monotonic()
    try:
        proc = subprocess.run(cmd, cwd=cwd, env=full_env, timeout=timeout, input=input_bytes, stdin=stdin,
                              stdout=out_target, stderr=subprocess.STDOUT if out_target else None)
    except subprocess.TimeoutExpired:
        raise PhaseError(phase, f"timed out after {timeout}s: {shlex.join(map(str, cmd))}")
    except OSError as e:
        raise PhaseError(phase, f"cannot run {cmd[0]}: {e}")
    finally:
        if stdin:
            stdin.close()
    output = proc.stdout or b""
    if log:
        log.parent.mkdir(parents=True, exist_ok=True)
        with open(log, "ab") as f:
            f.write(f"\n$ {shlex.join(map(str, cmd))}  ({time.monotonic() - started:.1f}s, exit {proc.returncode})\n".encode())
            f.write(output)
    if check and proc.returncode != 0:
        tail = output.decode(errors="replace").strip().splitlines()[-15:]
        raise PhaseError(phase, f"{shlex.join(map(str, cmd))} exited {proc.returncode}\n" + "\n".join(tail))
    return proc


class Timeline:
    def __init__(self):
        self.phases = []

    def phase(self, name: str):
        timeline = self

        class _Ctx:
            def __enter__(self):
                self.t0 = time.monotonic()
                self.entry = {"phase": name, "started_at": now_iso()}
                return self.entry

            def __exit__(self, exc_type, exc, tb):
                self.entry["seconds"] = round(time.monotonic() - self.t0, 3)
                self.entry["ok"] = exc_type is None
                timeline.phases.append(self.entry)
                return False

        return _Ctx()


def docker_cmd() -> list[str]:
    """`docker`, or `sudo -n docker` when the socket is root-only."""
    if subprocess.run(["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        return ["docker"]
    return ["sudo", "-n", "docker"]


def load_task_env(task: Path) -> dict:
    state = json.loads((task / "state" / "prepare.json").read_text())
    if state.get("state") != "READY":
        raise SystemExit(f"task {task} is not READY (state={state.get('state')})")
    return state


def task_env(state: dict) -> dict:
    return dict(state["env"])


def compose_base(state_or_env: dict, docker: list[str]) -> list[str]:
    env = state_or_env.get("env", state_or_env)
    return [*docker, "compose", "--env-file", env["OH_COMPOSE_ENV_FILE"], "-p", env["COMPOSE_PROJECT_NAME"],
            "-f", env["OH_COMPOSE_FILE"]]


def psql_lines(compose: list[str], service: str, db: str, sql: str, *, phase: str, log=None) -> list[str]:
    proc = run([*compose, "exec", "-T", service, "psql", "-X", "-U", "postgres", "-d", db, "-Atc", sql],
               phase=phase, capture=True, timeout=60, log=None)
    if log:
        with open(log, "ab") as f:
            f.write(f"\n[psql {service}/{db}] {sql[:80]}...\n".encode())
    return [l for l in proc.stdout.decode().splitlines() if l.strip()]


def git(repo: Path, *args, phase="git", capture=True, timeout=300, env=None, log=None) -> str:
    proc = run(["git", "-C", str(repo), *args], phase=phase, capture=capture, timeout=timeout, env=env, log=log)
    return (proc.stdout or b"").decode().strip()


def git_auth_env() -> dict:
    """Credential helper that reads GITHUB_TOKEN from the environment at call time.

    The token is never written to .git/config or to logs.
    """
    if not os.environ.get("GITHUB_TOKEN"):
        return {}
    helper = "!f() { echo username=x-access-token; echo \"password=${GITHUB_TOKEN}\"; }; f"
    return {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": helper}


def run_rails_tests(task: Path, state: dict, paths: list[str], label: str, timeout=900) -> dict:
    """Run `bin/rails test` with the task env; return parsed evidence plus exit code."""
    server = task / "repo" / "server"
    rel = f"tmp/evidence/{label}-{int(time.time() * 1000)}.json"
    env = task_env(state)
    env["EVIDENCE_JSON"] = rel
    env["RAILS_ENV"] = "test"
    started = time.monotonic()
    rel_paths = [p.removeprefix("server/") for p in paths]
    proc = run(["bin/rails", "test", *rel_paths], phase=f"test:{label}", cwd=server, env=env, timeout=timeout,
               log=task / "state" / "logs" / f"test-{label}.log", check=False)
    evidence_path = server / rel
    evidence = json.loads(evidence_path.read_text()) if evidence_path.exists() else {
        "classification": "ENV_ERROR", "counts": {}, "results": [], "note": "reporter did not run"}
    evidence["exit_code"] = proc.returncode
    evidence["seconds"] = round(time.monotonic() - started, 3)
    evidence["paths"] = paths
    evidence["head_sha"] = git(task / "repo", "rev-parse", "HEAD")
    return evidence


def failures_within(evidence: dict, paths: list[str]) -> bool:
    failed = [r for r in evidence.get("results", []) if r["status"] in ("failure", "error")]
    norm = [p.removeprefix("server/") for p in paths]
    return bool(failed) and all(any((r.get("file") or "").endswith(p) for p in norm) for r in failed)


def blob_shas(repo: Path, rev: str, paths: list[str]) -> dict:
    out = {}
    for p in paths:
        try:
            out[p] = git(repo, "rev-parse", f"{rev}:{p}")
        except PhaseError:
            out[p] = None
    return out


def die(msg: str, code: int = 1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def which_or_die(name: str):
    if not shutil.which(name):
        die(f"required tool not found: {name}")
