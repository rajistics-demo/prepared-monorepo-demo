#!/usr/bin/env python3
"""Minimal OCI distribution client for the settlement corpus data artifact (stdlib only).

The corpus is published as ONE new tag in an already-public synthetic package. It is an
OCI 1.1 artifact (empty config, custom artifactType), not a runnable image. Consumers
pin blobs by digest from corpus.lock.json, so the tag is only a human label.

  oci.py snapshot  --repo R --out tags.json        anonymous: every tag -> manifest digest
  oci.py absent    --repo R --tag T                exit 1 if the tag already exists
  oci.py push-blob --repo R --file F               needs GITHUB_TOKEN with packages:write
  oci.py push-artifact --repo R --tag T --shards s*.json --manifest manifest.json
                   --source-repo O/N --revision SHA --out descriptor.json
  oci.py verify    --lock corpus.lock.json --manifest manifest.json   anonymous provenance check
  oci.py compare   --before a.json --after b.json --allow-new T       existing tags untouched
"""
import argparse
import base64
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REGISTRY = "ghcr.io"
ARTIFACT_TYPE = "application/vnd.rajistics.settlements-corpus.v1"
SHARD_MEDIA_TYPE = "application/vnd.rajistics.settlements-corpus.shard.v1.tar+gzip"
MANIFEST_MEDIA_TYPE = "application/vnd.rajistics.settlements-corpus.manifest.v1+json"
OCI_MANIFEST = "application/vnd.oci.image.manifest.v1+json"
EMPTY = {"mediaType": "application/vnd.oci.empty.v1+json",
         "digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a", "size": 2}
ACCEPT = ", ".join([OCI_MANIFEST, "application/vnd.oci.image.index.v1+json",
                    "application/vnd.docker.distribution.manifest.v2+json",
                    "application/vnd.docker.distribution.manifest.list.v2+json"])
UA = {"User-Agent": "settlements-corpus-oci/1"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def token(repo: str, push: bool = False) -> str:
    scope = f"repository:{repo}:pull" + (",push" if push else "")
    url = f"https://{REGISTRY}/token?" + urllib.parse.urlencode({"service": REGISTRY, "scope": scope})
    headers = dict(UA)
    if push:
        cred = f"{os.environ.get('GITHUB_ACTOR', 'token')}:{os.environ['GITHUB_TOKEN']}"
        headers["Authorization"] = "Basic " + base64.b64encode(cred.encode()).decode()
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        return json.load(r)["token"]


def _req(method, url, tok, headers=None, data=None, timeout=120):
    h = dict(UA) | {"Authorization": f"Bearer {tok}"} | (headers or {})
    try:
        return _opener.open(urllib.request.Request(url, data=data, headers=h, method=method), timeout=timeout)
    except urllib.error.HTTPError as e:
        if 300 <= e.code < 400:
            return e
        raise


def _abs(location: str) -> str:
    return urllib.parse.urljoin(f"https://{REGISTRY}/", location)


def open_blob(repo: str, digest: str, tok: str, timeout=120):
    """Return a readable response for a blob. Registry redirects go to a signed CDN URL,
    which must be fetched WITHOUT the registry bearer token."""
    r = _req("GET", f"https://{REGISTRY}/v2/{repo}/blobs/{digest}", tok, timeout=timeout)
    if r.status in (301, 302, 303, 307, 308):
        loc = r.headers["Location"]
        r.close()
        return urllib.request.urlopen(urllib.request.Request(loc, headers=UA), timeout=timeout)
    return r


def manifest_digest(repo: str, ref: str, tok: str):
    try:
        with _req("HEAD", f"https://{REGISTRY}/v2/{repo}/manifests/{ref}", tok, {"Accept": ACCEPT}) as r:
            return r.headers.get("Docker-Content-Digest")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def get_manifest(repo: str, ref: str, tok: str) -> bytes:
    with _req("GET", f"https://{REGISTRY}/v2/{repo}/manifests/{ref}", tok, {"Accept": ACCEPT}) as r:
        return r.read()


def list_tags(repo: str, tok: str):
    tags, url = [], f"https://{REGISTRY}/v2/{repo}/tags/list?n=1000"
    while url:
        with _req("GET", url, tok) as r:
            tags += json.load(r).get("tags") or []
            link = r.headers.get("Link", "")
        url = _abs(link.split(";")[0].strip("<> ")) if 'rel="next"' in link else None
    return sorted(tags)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def push_blob(repo: str, tok: str, data=None, path: Path = None, digest: str = None) -> dict:
    size = len(data) if data is not None else path.stat().st_size
    digest = digest or ("sha256:" + hashlib.sha256(data).hexdigest() if data is not None else sha256_file(path))
    try:
        with _req("HEAD", f"https://{REGISTRY}/v2/{repo}/blobs/{digest}", tok) as r:
            if r.status in (200, 307):
                return {"digest": digest, "size": size, "uploaded": False}
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
    with _req("POST", f"https://{REGISTRY}/v2/{repo}/blobs/uploads/", tok, {"Content-Length": "0"}, b"") as r:
        loc = _abs(r.headers["Location"])
    body = data if data is not None else open(path, "rb")
    try:
        with _req("PATCH", loc, tok, {"Content-Type": "application/octet-stream", "Content-Length": str(size)},
                  body, timeout=1800) as r:
            loc = _abs(r.headers["Location"])
    finally:
        if data is None:
            body.close()
    sep = "&" if "?" in loc else "?"
    with _req("PUT", f"{loc}{sep}digest={urllib.parse.quote(digest)}", tok, {"Content-Length": "0"}, b"") as r:
        if r.status != 201:
            sys.exit(f"blob PUT returned {r.status}")
        got = r.headers.get("Docker-Content-Digest")
    if got and got != digest:
        sys.exit(f"registry digest {got} != {digest}")
    return {"digest": digest, "size": size, "uploaded": True}


def cmd_snapshot(a):
    tok = token(a.repo)
    snap = {t: manifest_digest(a.repo, t, tok) for t in list_tags(a.repo, tok)}
    Path(a.out).write_text(json.dumps({"repo": a.repo, "tags": snap}, indent=1, sort_keys=True) + "\n")
    print(f"{len(snap)} tags in {a.repo}")


def cmd_absent(a):
    d = manifest_digest(a.repo, a.tag, token(a.repo))
    if d:
        sys.exit(f"{a.repo}:{a.tag} already exists at {d}; data artifact tags are never overwritten")
    print(f"{a.repo}:{a.tag} is free")


def cmd_push_blob(a):
    print(json.dumps(push_blob(a.repo, token(a.repo, push=True), path=Path(a.file))))


def cmd_push_artifact(a):
    tok = token(a.repo, push=True)
    if manifest_digest(a.repo, a.tag, tok):
        sys.exit(f"{a.repo}:{a.tag} already exists; refusing to overwrite")
    shards = sorted((json.loads(Path(p).read_text()) for p in a.shards), key=lambda s: s["shard"])
    layers = []
    for s in shards:
        d = "sha256:" + s["asset"]["sha256"]
        with _req("HEAD", f"https://{REGISTRY}/v2/{a.repo}/blobs/{d}", tok) as r:
            if r.status not in (200, 307):
                sys.exit(f"shard {s['shard']} blob {d} is not in the registry")
        layers.append({"mediaType": SHARD_MEDIA_TYPE, "digest": d, "size": s["asset"]["bytes"],
                       "annotations": {"org.opencontainers.image.title": s["asset"]["name"],
                                       "first_day": s["files"][0]["settled_on"], "last_day": s["files"][-1]["settled_on"]}})
    mbytes = Path(a.manifest).read_bytes()
    m = push_blob(a.repo, tok, data=mbytes)
    layers.append({"mediaType": MANIFEST_MEDIA_TYPE, "digest": m["digest"], "size": m["size"],
                   "annotations": {"org.opencontainers.image.title": "manifest.json"}})
    push_blob(a.repo, tok, data=b"{}")
    doc = {"schemaVersion": 2, "mediaType": OCI_MANIFEST, "artifactType": ARTIFACT_TYPE,
           "config": EMPTY | {"data": "e30="}, "layers": layers,
           "annotations": {
               "org.opencontainers.image.title": "Synthetic settlement corpus (data artifact)",
               "org.opencontainers.image.description":
                   "DATA ARTIFACT, NOT A CONTAINER IMAGE. Synthetic, deterministic test data generated by "
                   "tools/settlements-corpus/generate.py. No real customer or payment data.",
               "org.opencontainers.image.source": f"https://github.com/{a.source_repo}",
               "org.opencontainers.image.revision": a.revision}}
    body = json.dumps(doc, separators=(",", ":"), sort_keys=True).encode()
    digest = "sha256:" + hashlib.sha256(body).hexdigest()
    with _req("PUT", f"https://{REGISTRY}/v2/{a.repo}/manifests/{a.tag}", tok,
              {"Content-Type": OCI_MANIFEST, "Content-Length": str(len(body))}, body) as r:
        got = r.headers.get("Docker-Content-Digest")
    if got and got != digest:
        sys.exit(f"registry manifest digest {got} != {digest}")
    desc = {"registry": REGISTRY, "repository": a.repo, "tag": a.tag, "manifest_digest": digest,
            "artifact_type": ARTIFACT_TYPE, "manifest_json_digest": m["digest"]}
    Path(a.out).write_text(json.dumps(desc, indent=1) + "\n")
    print(json.dumps(desc))


def cmd_verify(a):
    lock = json.loads(Path(a.lock).read_text())
    src = lock["source"]
    tok = token(src["repository"])
    body = get_manifest(src["repository"], src["manifest_digest"], tok)
    if "sha256:" + hashlib.sha256(body).hexdigest() != src["manifest_digest"]:
        sys.exit("published OCI manifest bytes do not hash to the pinned digest")
    doc = json.loads(body)
    want = ["sha256:" + x["sha256"] for x in lock["assets"]]
    shard_layers = [l for l in doc["layers"] if l["mediaType"] == SHARD_MEDIA_TYPE]
    if doc.get("artifactType") != ARTIFACT_TYPE or [l["digest"] for l in shard_layers] != want:
        sys.exit("published OCI artifact does not match corpus.lock.json")
    mlayer = [l for l in doc["layers"] if l["mediaType"] == MANIFEST_MEDIA_TYPE]
    local = "sha256:" + hashlib.sha256(Path(a.manifest).read_bytes()).hexdigest()
    if len(mlayer) != 1 or mlayer[0]["digest"] != local:
        sys.exit("published manifest.json layer does not match the committed manifest.json")
    with open_blob(src["repository"], mlayer[0]["digest"], tok) as r:
        if "sha256:" + hashlib.sha256(r.read()).hexdigest() != local:
            sys.exit("anonymous fetch of manifest.json layer returned different bytes")
    tag_digest = manifest_digest(src["repository"], src["tag"], tok)
    print(json.dumps({"anonymous_pull": "ok", "manifest_digest": src["manifest_digest"],
                      "tag_points_to_pinned_digest": tag_digest == src["manifest_digest"],
                      "shard_layers": len(shard_layers)}))


def cmd_compare(a):
    before = json.loads(Path(a.before).read_text())["tags"]
    after = json.loads(Path(a.after).read_text())["tags"]
    changed = {t: (d, after.get(t)) for t, d in before.items() if after.get(t) != d}
    added = sorted(set(after) - set(before))
    print(json.dumps({"existing_tags": len(before), "changed_or_removed": changed, "added": added}))
    if changed or added != [a.allow_new]:
        sys.exit("package tags changed beyond the single new data-artifact tag")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot"); s.add_argument("--repo", required=True); s.add_argument("--out", required=True)
    s = sub.add_parser("absent"); s.add_argument("--repo", required=True); s.add_argument("--tag", required=True)
    s = sub.add_parser("push-blob"); s.add_argument("--repo", required=True); s.add_argument("--file", required=True)
    s = sub.add_parser("push-artifact")
    for k in ("--repo", "--tag", "--manifest", "--source-repo", "--revision", "--out"):
        s.add_argument(k, required=True)
    s.add_argument("--shards", nargs="+", required=True)
    s = sub.add_parser("verify"); s.add_argument("--lock", required=True); s.add_argument("--manifest", required=True)
    s = sub.add_parser("compare")
    s.add_argument("--before", required=True); s.add_argument("--after", required=True)
    s.add_argument("--allow-new", required=True)
    a = ap.parse_args()
    {"snapshot": cmd_snapshot, "absent": cmd_absent, "push-blob": cmd_push_blob, "push-artifact": cmd_push_artifact,
     "verify": cmd_verify, "compare": cmd_compare}[a.cmd](a)


if __name__ == "__main__":
    main()
