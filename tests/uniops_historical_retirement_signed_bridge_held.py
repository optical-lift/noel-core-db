#!/usr/bin/env python3
"""HELD / TEST ONLY: bridge genuine signed U2 actors to pinned historic retirement proof.

SOURCE CUSTODY: Noel #2368 immutable head ddfb0bf5374798301fe076a61d2b944dfb52ff63,
tests/validate-atlas-native-historical-retirement-signed-http.py Git blob
79151f723e60b33410c760acef715155a53771f3.

This is not a CLI or an automatic test hook. A separately owner-authorized
protected disposable-schema validator must first authenticate four independent
fictional GoTrue sessions, load the exact immutable #2368 source into a local
checkout, and then invoke prove() explicitly. NO production/remote access,
no new Work issuer, historical-review impersonation, or feature release.
"""
import hashlib
import re
import types
from pathlib import Path

PINNED_SOURCE_COMMIT = "ddfb0bf5374798301fe076a61d2b944dfb52ff63"
PINNED_SOURCE_PATH = "tests/validate-atlas-native-historical-retirement-signed-http.py"
PINNED_SOURCE_BLOB = "79151f723e60b33410c760acef715155a53771f3"
ACTORS = frozenset(("owner", "worker", "outsider", "no-seat"))
LOCAL_PG = re.compile(
    r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres"
)


class HeldProofRefusal(RuntimeError):
    """Static and bounded, never include tokens, SQL, network payload or identities."""


def git_blob_sha(data: bytes) -> str:
    """Exactly the object hash Git uses for file content (not a commit hash)."""
    return hashlib.sha1(
        b"blob " + str(len(data)).encode("ascii") + b"\0" + data
    ).hexdigest()


def load_pinned_companion(source_path):
    """Fail closed *before executing* even one byte of unreviewed test source."""
    path = Path(source_path)
    if path.name != Path(PINNED_SOURCE_PATH).name or not path.is_file():
        raise HeldProofRefusal("Missing reviewed historical retirement companion")
    data = path.read_bytes()
    if git_blob_sha(data) != PINNED_SOURCE_BLOB:
        raise HeldProofRefusal("Historical retirement companion blob mismatch")
    module = types.ModuleType("held_exact_historical_retirement_companion")
    module.__file__ = str(path)
    exec(compile(data, str(path), "exec"), module.__dict__)
    if not callable(getattr(module, "proof", None)):
        raise HeldProofRefusal("Reviewed historical retirement proof missing")
    return module


def expected_denial_code(label):
    """Exact known source denial: stale snapshot is serialization failure."""
    if label == "Stale dependency snapshot must not cancel Work":
        return "40001"
    return "42501"


def prove(db, api, key, tokens, *, source_path, sql, rpc, c1):
    """Called ONLY from a separately approved genuine signed LOCAL validator.

    Inputs come from the existing signer; no session is minted here. The
    upstream validated GoTrue sessions must remain active for this invocation.
    Source #2368 owns the proof/fixture/Work IDs and all historical semantics.
    """
    if not isinstance(db, str) or LOCAL_PG.fullmatch(db) is None:
        raise HeldProofRefusal("Refuse historical test outside local Postgres clone")
    if (not isinstance(tokens, dict) or set(tokens) != ACTORS
        or any(not isinstance(t, str) or not t for t in tokens.values())
        or len(set(tokens.values())) != 4):
        raise HeldProofRefusal("Four independently issued synthetic actor tokens required")
    if not all(callable(f) for f in (sql, rpc, getattr(c1, "sql", None))):
        raise HeldProofRefusal("Trusted signed SQL and HTTP helpers required")
    companion = load_pinned_companion(source_path)

    def check(condition, label):
        if not condition:
            # Pinned companion owns only static error labels, never expose data.
            raise HeldProofRefusal("Historical retirement assertion failed: " + label)

    def literal(value):
        return "'" + str(value).replace("'", "''") + "'"

    def allow(_api, _key, token, name, params):
        status, obj = rpc(_api, _key, token, name, params)
        if status != 200 or not isinstance(obj, dict) or obj.get("ok") is not True:
            raise HeldProofRefusal("Expected signed historical permission: " + name)
        return obj

    def deny(_api, _key, token, name, params, label):
        status, obj = rpc(_api, _key, token, name, params)
        code = obj.get("code") if isinstance(obj, dict) else None
        if status not in (400, 401, 403, 409) or code != expected_denial_code(label):
            raise HeldProofRefusal("Signed historical denial not established: " + label)

    h = types.SimpleNamespace(
        check=check, sql=sql, literal=literal, allow=allow, deny=deny, c1=c1
    )
    result = companion.proof(db, api, key, tokens, h)
    if not isinstance(result, str) or not result.startswith(
        "PASS genuine signed governor historic retirement:"
    ):
        raise HeldProofRefusal("Pinned historical proof has no positive receipt")
    return result
