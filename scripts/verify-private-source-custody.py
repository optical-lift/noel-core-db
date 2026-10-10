#!/usr/bin/env python3
"""Verify a signed private-Git source inclusion proof without reading private SQL.

Fail-closed, no network access to the private source repository. GitHub's
web-flow signing key is fetched via GitHub HTTPS; its signature binds an exact
Git tree and the private SQL Git blob IDs. The live ledger hash is checked
separately by the production custody reconciler.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import urllib.request
from pathlib import Path

SHA = re.compile(r"^[a-f0-9]{40}$")
PRIVATE_REPO = "optical-lift/song-ontology"
EXPECTED = {
    "20261010214537_noel_reality_h1847_knowledge_source_anchors_v1.sql": "b94131f94526032acdfbdf0b81718c7fc7964afd",
    "20261010214627_noel_reality_h1847_evidence_scoped_edges_v1.sql": "c632c6464203485a1c85db3277554c0efc616506",
}
DIRS = [
    "",
    "provenance",
    "provenance/noel-private-migration-custody",
    "provenance/noel-private-migration-custody/2026-10-10",
]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def git_object_sha(kind: str, body: bytes) -> str:
    return hashlib.sha1(kind.encode("ascii") + b" " + str(len(body)).encode("ascii") + b"\\x00" + body).hexdigest()


def tree_hash(entries: list[dict]) -> str:
    seen = set()
    objects = []
    for entry in entries:
        name = entry["name"]
        mode = entry["mode"]
        typ = entry["type"]
        oid = entry["sha"]
        require(isinstance(name, str) and name and "/" not in name and "\\x00" not in name and name not in (".", ".."), "unsafe Git tree name")
        require(name not in seen, "duplicate Git tree name")
        seen.add(name)
        require(typ in ("tree", "blob"), "unsupported tree entry type")
        require((typ == "tree" and mode == "040000") or (typ == "blob" and mode in ("100644", "100755")), "untrusted Git mode/type")
        require(isinstance(oid, str) and bool(SHA.fullmatch(oid)), "invalid SHA-1 object name")
        normalized_mode = mode.lstrip("0").encode("ascii")
        objects.append((name.encode("utf-8") + (b"/" if typ == "tree" else b""), normalized_mode + b" " + name.encode("utf-8") + b"\\x00" + bytes.fromhex(oid)))
    body = b"".join(raw for _, raw in sorted(objects, key=lambda item: item[0]))
    return git_object_sha("tree", body)


def verify_inclusion(proof: dict) -> dict:
    require(proof.get("contractVersion") == 1, "unrecognized proof contract")
    require(proof.get("classification") == "private_git_signed_source_inclusion_evidence", "not a private Git source proof")
    require(proof.get("publicTarget") == "optical-lift/noel-core-db", "wrong public custodian")
    require(proof.get("privateSourceRepository") == PRIVATE_REPO, "wrong private source owner")
    require(proof.get("githubSigningKeyUrl") == "https://github.com/web-flow.gpg", "unexpected trust root")
    require(proof.get("privateSourceVisibility") == "private_at_capture", "source private visibility not established")
    signed = proof["signedCommit"]
    payload = signed["payload"]
    require(payload.startswith("tree " + signed["treeSha1"] + "\\n"), "commit payload tree mismatch")
    require("\\nauthor optical-lift <" in "\\n" + payload, "unexpected signed author")
    require("\\ncommitter GitHub <noreply@github.com> " in payload, "unexpected signed committer")
    require(isinstance(signed["signature"], str) and "BEGIN PGP SIGNATURE" in signed["signature"], "missing signed commit")
    require(SHA.fullmatch(proof["privateSourceCommitSha1"]) is not None, "invalid Git commit identity")
    trees = proof["gitTrees"]
    require([x["directory"] for x in trees] == DIRS, "incorrect rooted private Git proof path")
    require(trees[0]["sha"] == signed["treeSha1"], "private root tree mismatch")
    for i, t in enumerate(trees):
        require(tree_hash(t["entries"]) == t["sha"], "Git tree hash mismatch: " + t["directory"])
        if i + 1 < len(trees):
            label = DIRS[i + 1].split("/")[-1]
            children = [e for e in t["entries"] if e["name"] == label]
            require(len(children) == 1 and children[0]["type"] == "tree", "private Git tree path is absent")
            require(children[0]["sha"] == trees[i + 1]["sha"], "private Git tree link mismatch")
    leaves = {e["name"]: e for e in trees[-1]["entries"] if e["type"] == "blob"}
    sources = proof["sources"]
    require(len(sources) == 2 and {s["filename"] for s in sources} == set(EXPECTED), "wrong protected source census")
    for s in sources:
        name = s["filename"]
        require(s["version"] == name[:14], "wrong protected version")
        require(s["privatePath"] == DIRS[-1] + "/" + name, "unexpected private source path")
        require(s["liveGitBlobSha1"] == EXPECTED[name], "protected source SHA-1 changed")
        require(name in leaves and leaves[name]["sha"] == EXPECTED[name], "signed Git tree lacks exact protected SQL blob")
    return dict(EXPECTED)


def verify_github_signature(proof: dict) -> None:
    payload = proof["signedCommit"]["payload"]
    signature = proof["signedCommit"]["signature"]
    with tempfile.TemporaryDirectory(prefix="noel-private-attestation-") as temp:
        root = Path(temp)
        key = root / "web-flow.gpg"
        with urllib.request.urlopen("https://github.com/web-flow.gpg", timeout=20) as response:
            key.write_bytes(response.read(128 * 1024 + 1))
        require(0 < key.stat().st_size <= 128 * 1024, "unexpected signing key size")
        (root / "payload").write_bytes(payload.encode("utf-8"))
        (root / "signature.asc").write_bytes(signature.encode("utf-8"))
        home = root / "gnupg"
        home.mkdir(mode=0o700)
        imp = subprocess.run(["gpg", "--homedir", str(home), "--batch", "--import", str(key)], capture_output=True, text=True)
        require(imp.returncode == 0, "could not import official GitHub signer")
        result = subprocess.run(["gpg", "--homedir", str(home), "--batch", "--status-fd", "1", "--verify", str(root / "signature.asc"), str(root / "payload")], capture_output=True, text=True)
        require(result.returncode == 0 and "[GNUPG:] VALIDSIG " in result.stdout and "[GNUPG:] GOODSIG " in result.stdout, "signed GitHub commit signature invalid")


def verify_proof(proof: dict) -> dict:
    ids = verify_inclusion(proof)
    verify_github_signature(proof)
    return ids


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("proof", type=Path)
    args = parser.parse_args()
    proof = json.loads(args.proof.read_text())
    ids = verify_proof(proof)
    for name, sha in sorted(ids.items()):
        print("PRIVATE_GIT_SIGNED_SOURCE_VERIFIED=" + name + " sha1=" + sha)
    print("PRIVATE_GIT_SIGNED_ATTESTATION=PASS (no protected SQL read or emitted)")


if __name__ == "__main__":
    main()
