#!/usr/bin/env python3
"""U1.12 source-only sealed-capsule transport. NO database connections.

Only opaque stdin can be sealed. A separate invocation with the holder's
private key verifies authenticated decryption and a sealed byte witness.
This does not decide which real rows may be captured, or prove PostgreSQL
restorability. Never pass customer data to CI or GitHub artifacts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

CHUNK = 1 << 16
MAX_BYTES = 512 * 1024 * 1024
NAME = re.compile(r"[a-z][a-z0-9_-]{1,60}\Z")
VERSION = "titus_u112_sealed_transport_v1"


def reject(message):
    raise ValueError(message)


def secure_root(path):
    root = Path(path)
    if not root.is_absolute() or root.is_symlink() or not root.is_dir():
        reject("vault must be an existing, non-symlink absolute directory")
    info = root.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        reject("vault must be owned by caller and private (0700)")
    for env in ("GITHUB_WORKSPACE", "GITHUB_ACTION_PATH"):
        workspace = os.environ.get(env)
        if workspace and root.resolve().is_relative_to(Path(workspace).resolve()):
            reject("vault cannot be inside a GitHub repository/workspace")
    if any((parent / ".git").exists() for parent in (root, *root.parents)):
        reject("vault cannot be inside a Git worktree")
    return root


def names(root, name):
    if not NAME.fullmatch(name):
        reject("invalid capsule name")
    return root / (name + ".capsule.cms"), root / (name + ".witness.cms")


def cms_encrypt(cert, dest, reader):
    proc = subprocess.Popen(
        ["openssl", "cms", "-encrypt", "-binary", "-aes-256-gcm",
         "-outform", "DER", str(cert)],
        stdin=subprocess.PIPE, stdout=dest, stderr=subprocess.DEVNULL,
    )
    try:
        reader(proc.stdin)
    except (BrokenPipeError, OSError):
        proc.kill()
        proc.wait()
        reject("sealed encryption failed")
    finally:
        if proc.stdin and not proc.stdin.closed:
            proc.stdin.close()
    if proc.wait() != 0:
        reject("sealed encryption failed")


def decrypt_cmd(cert, key, path):
    return ["openssl", "cms", "-decrypt", "-binary", "-inform", "DER",
            "-in", str(path), "-recip", str(cert), "-inkey", str(key)]


def decrypt_small(cert, key, path):
    try:
        proc = subprocess.run(decrypt_cmd(cert, key, path),
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              timeout=30)
    except subprocess.TimeoutExpired:
        reject("sealed witness timed out")
    if proc.returncode or len(proc.stdout) > 4096:
        reject("sealed witness verification failed")
    return proc.stdout


def seal(args):
    root = secure_root(args.vault_dir)
    capsule, witness = names(root, args.name)
    if capsule.exists() or witness.exists() or capsule.is_symlink() or witness.is_symlink():
        reject("refusing to overwrite existing custody evidence")
    if not Path(args.certificate).is_file():
        reject("recipient certificate missing")
    if sys.stdin.isatty():
        reject("opaque archive must be piped on stdin")
    created = []
    try:
        digest = hashlib.sha256()
        count = 0
        with os.fdopen(os.open(capsule, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "wb") as target:
            created.append(capsule)
            def pump(stdin):
                nonlocal count
                while True:
                    chunk = sys.stdin.buffer.read(CHUNK)
                    if not chunk:
                        break
                    count += len(chunk)
                    if count > MAX_BYTES:
                        reject("archive exceeds bounded custody limit")
                    digest.update(chunk)
                    stdin.write(chunk)
            cms_encrypt(args.certificate, target, pump)
        if count == 0:
            reject("refusing empty custody archive")
        private_witness = json.dumps(
            {"version": VERSION, "sha256": digest.hexdigest(), "byteCount": count},
            sort_keys=True, separators=(",", ":"),
        ).encode("utf-8")
        with os.fdopen(os.open(witness, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "wb") as target:
            created.append(witness)
            cms_encrypt(args.certificate, target,
                        lambda stdin: stdin.write(private_witness))
    except Exception:
        for file in created:
            file.unlink(missing_ok=True)
        raise
    print("PASS sealed opaque capsule and encrypted private witness created; no plaintext retained")


def verify(args):
    root = secure_root(args.vault_dir)
    capsule, witness = names(root, args.name)
    if not capsule.is_file() or not witness.is_file() or capsule.is_symlink() or witness.is_symlink():
        reject("sealed capsule or witness missing")
    if not Path(args.certificate).is_file() or not Path(args.private_key).is_file():
        reject("recipient certificate or private key missing")
    private_key = Path(args.private_key)
    if (private_key.is_symlink()
            or private_key.stat().st_uid != os.getuid()
            or stat.S_IMODE(private_key.stat().st_mode) & 0o077):
        reject("recipient private key must be caller-owned and unreadable by others")
    try:
        claim = json.loads(decrypt_small(args.certificate, args.private_key, witness))
    except (json.JSONDecodeError, UnicodeDecodeError):
        reject("sealed witness has invalid format")
    if set(claim) != {"version", "sha256", "byteCount"} or claim["version"] != VERSION:
        reject("sealed witness contract mismatch")
    if not isinstance(claim["byteCount"], int) or not 0 < claim["byteCount"] <= MAX_BYTES:
        reject("sealed witness byte count invalid")
    if not isinstance(claim["sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", claim["sha256"]):
        reject("sealed witness fingerprint invalid")
    proc = subprocess.Popen(decrypt_cmd(args.certificate, args.private_key, capsule),
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    digest = hashlib.sha256()
    count = 0
    while True:
        chunk = proc.stdout.read(CHUNK)
        if not chunk:
            break
        count += len(chunk)
        if count > MAX_BYTES:
            proc.kill()
            proc.wait()
            reject("decoded archive exceeds bounded custody limit")
        digest.update(chunk)
    if proc.wait() != 0:
        reject("authenticated sealed archive decryption failed")
    if count != claim["byteCount"] or digest.hexdigest() != claim["sha256"]:
        reject("private historical byte witness mismatch")
    print("PASS independently verified sealed capsule authenticity and private byte witness; no plaintext emitted")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    for action in ("seal", "verify"):
        p = actions.add_parser(action)
        p.add_argument("--vault-dir", required=True)
        p.add_argument("--name", required=True)
        p.add_argument("--certificate", required=True)
        if action == "verify":
            p.add_argument("--private-key", required=True)
    args = parser.parse_args()
    try:
        (seal if args.action == "seal" else verify)(args)
    except ValueError as exc:
        # Only authored, generic rejection messages may be emitted.
        print("BLOCKED sealed custody transport: " + str(exc), file=sys.stderr)
        raise SystemExit(2)
    except (OSError, subprocess.SubprocessError):
        # OS errors may contain sensitive local vault/key paths: never print them.
        print("BLOCKED sealed custody transport: local cryptographic operation failed",
              file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
