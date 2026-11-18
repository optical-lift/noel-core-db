#!/usr/bin/env python3
"""U1.13 private vault readiness. No database access, customer data or keys read.

Preflights the place where a separately owner-authorized encrypted historical
capsule may eventually be stored. Creates/deletes ONE random canary only.
It is not a backup, a durable replication check, or production authorization.
"""
import argparse
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys

TEMP_ROOTS = ("/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp",
              "/dev/shm", "/run", "/var/folders")
MARKER = ".titus-u113-test-"


def reject(message):
    raise ValueError(message)


def check_vault(path, cert, fictional_test=False):
    root = Path(path)
    if not root.is_absolute() or not root.is_dir():
        reject("vault must be an existing absolute directory")
    if root.is_symlink() or root.resolve() != root:
        reject("vault has a symlink in its path")
    if any(root == Path(t) or root.is_relative_to(Path(t)) for t in TEMP_ROOTS):
        if not fictional_test:
            reject("ephemeral filesystem cannot be owner historical vault")
    if any((d / ".git").exists() for d in (root, *root.parents)):
        reject("historical vault cannot be a Git working tree")
    for name in ("GITHUB_WORKSPACE", "RUNNER_TEMP", "GITHUB_ACTION_PATH"):
        path = os.environ.get(name)
        if path and root.is_relative_to(Path(path).resolve()):
            if not fictional_test:
                reject("GitHub runner storage is not a persistent historical vault")
    info = root.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        reject("vault must be owner-only 0700")
    if not os.access(root, os.W_OK | os.X_OK):
        reject("vault must be writable by its owner")
    public = Path(cert)
    if not public.is_file():
        reject("recipient X.509 certificate file missing")
    try:
        inspect = subprocess.run(["openssl", "x509", "-in", str(public), "-noout",
                                  "-checkend", "604800"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        reject("X.509 certificate validation unavailable")
    if inspect.returncode != 0:
        reject("X.509 recipient certificate is invalid or expires within seven days")
    # Write only random synthetic canary bytes; never store historical data here.
    marker = root / (MARKER + secrets.token_hex(12))
    fd = None
    try:
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(marker, flags, 0o600)
        with os.fdopen(fd, "wb") as handle:
            fd = None
            handle.write(secrets.token_bytes(64))
            handle.flush()
            os.fsync(handle.fileno())
        marker.unlink()
        directory = os.open(root, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except OSError:
        reject("owner vault cannot complete exclusive write/fsync/cleanup")
    finally:
        if fd is not None:
            os.close(fd)
        marker.unlink(missing_ok=True)
    return {
        "contract": "titus_u113_owner_vault_preflight_only_v1",
        "vaultPrivate": True, "recipientCertificateValid": True,
        "exclusiveFileWriteAndFsync": True, "fictionalCanaryRemoved": True,
        "productionDataAccess": False, "ownerDataBackupCreated": False,
        "rowSelectionAuthorized": False, "productionWriteAuthorized": False,
    }


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--vault-dir", required=True)
    p.add_argument("--recipient-certificate", required=True)
    p.add_argument("--fictional-ci-temp", action="store_true")
    args = p.parse_args()
    try:
        result = check_vault(args.vault_dir, args.recipient_certificate,
                             args.fictional_ci_temp)
    except ValueError as exc:
        print("BLOCKED private vault readiness: " + str(exc), file=sys.stderr)
        raise SystemExit(2)
    print("PASS private vault preflight; no historical data, key or backup accessed")
    # Detailed result is a fixed boolean-only contract, not a storage receipt.
    assert result["ownerDataBackupCreated"] is False


if __name__ == "__main__":
    main()
