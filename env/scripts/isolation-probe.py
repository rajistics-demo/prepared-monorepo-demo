#!/usr/bin/env python3
"""Concurrent marker-write probe between two READY tasks in the same sandbox.

  isolation-probe.py <task-dir-A> <task-dir-B>

For every database (primary/ledger/events test DBs) both tasks write their own
marker at the same time, then each checks that the other's marker is absent.
Also records that the two tasks use distinct Compose projects, containers,
volumes, ports and checkouts. Probe tables are dropped afterwards.
Prints a JSON report; exit 0 only if every check passes.

This proves isolation between tasks that share one sandbox's Docker daemon.
It says nothing about isolation between sandboxes or about credentials.
"""
import json
import sys
import threading
from pathlib import Path

sys.path[:0] = ["/usr/local/lib/oh-prepared", str(Path(__file__).resolve().parents[1] / "image")]
from oh_common import LOGICAL_DBS, compose_base, docker_cmd, load_task_env, psql_lines, run  # noqa: E402

TEST_DB = {logical: next(d for d in spec["databases"] if d.endswith("_test")) for logical, spec in LOGICAL_DBS.items()}


def sql(state, service, db, statement):
    return psql_lines(compose_base(state, DOCKER), service, db, statement, phase="probe")


def write_marker(state, marker, barrier, errors):
    try:
        barrier.wait(timeout=60)
        for logical, db in TEST_DB.items():
            svc = LOGICAL_DBS[logical]["service"]
            sql(state, svc, db, "CREATE TABLE IF NOT EXISTS oh_isolation_probe (marker text NOT NULL)")
            sql(state, svc, db, f"INSERT INTO oh_isolation_probe VALUES ('{marker}')")
    except Exception as e:  # recorded, not swallowed
        errors.append(f"{marker}: {e}")


def markers(state):
    out = {}
    for logical, db in TEST_DB.items():
        out[db] = sql(state, LOGICAL_DBS[logical]["service"], db, "SELECT marker FROM oh_isolation_probe ORDER BY 1")
    return out


def project_resources(state):
    project = state["env"]["COMPOSE_PROJECT_NAME"]
    label = f"label=com.docker.compose.project={project}"
    containers = run([*DOCKER, "ps", "-q", "--filter", label], phase="probe", capture=True).stdout.decode().split()
    volumes = run([*DOCKER, "volume", "ls", "-q", "--filter", label], phase="probe", capture=True).stdout.decode().split()
    return {"project": project, "containers": sorted(containers), "volumes": sorted(volumes),
            "ports": {k: state["env"][k] for k in ("PG14_PORT", "PG16_PORT", "PG17_PORT", "EVENTS_SVC_PORT")},
            "repo": state["repo"]}


DOCKER = docker_cmd()


def main() -> int:
    a, b = (load_task_env(Path(p).resolve()) for p in sys.argv[1:3])
    ma, mb = f"marker-{Path(a['task_dir']).name}", f"marker-{Path(b['task_dir']).name}"
    barrier, errors = threading.Barrier(2), []
    threads = [threading.Thread(target=write_marker, args=(s, m, barrier, errors)) for s, m in ((a, ma), (b, mb))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    seen_a, seen_b = markers(a), markers(b)
    ra, rb = project_resources(a), project_resources(b)
    checks = {
        "no_write_errors": not errors,
        "a_sees_only_own_marker": all(v == [ma] for v in seen_a.values()),
        "b_sees_only_own_marker": all(v == [mb] for v in seen_b.values()),
        "distinct_projects": ra["project"] != rb["project"],
        "no_shared_containers": not set(ra["containers"]) & set(rb["containers"]),
        "no_shared_volumes": bool(ra["volumes"]) and bool(rb["volumes"]) and not set(ra["volumes"]) & set(rb["volumes"]),
        "distinct_ports": not set(ra["ports"].values()) & set(rb["ports"].values()),
        "distinct_checkouts": ra["repo"] != rb["repo"],
    }
    for s in (a, b):
        for logical, db in TEST_DB.items():
            sql(s, LOGICAL_DBS[logical]["service"], db, "DROP TABLE IF EXISTS oh_isolation_probe")
    report = {"ok": all(checks.values()), "checks": checks, "errors": errors, "seen": {"a": seen_a, "b": seen_b},
              "resources": {"a": ra, "b": rb},
              "scope": "two tasks sharing one sandbox Docker daemon; not inter-sandbox or credential isolation"}
    print(json.dumps(report, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
