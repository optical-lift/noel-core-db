#!/usr/bin/env python3
"""Owner-run synthetic historical vault recovery drill; NO database or real data.

No keys or archives are created on GitHub or on a connected service.
Owner supplies an EXISTING recipient cert, independently kept private key,
private local vault and separate recovery-copy directory. This script only
seals, copies, verifies and removes random FICTIONAL bytes and capsules.

A PASS is not proof of physical off-device recovery or authorized real backup.
"""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PRE = ROOT / "scripts/titus-u113-preflight-private-vault.py"
TRANSPORT = ROOT / "scripts/titus-u112-sealed-custody-transport.py"

spec = importlib.util.spec_from_file_location("titus_u113_preflight", PRE)
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)

CHUNK = 65536
PREFIX = "u115-synthetic-"


def blocked():
    raise ValueError("owner-side synthetic custody drill blocked")


def check_key(path, vault, replica, fictional_test=False):
    key = Path(path)
    if (not key.is_absolute() or not key.is_file()
            or key.is_symlink() or key.resolve() != key):
        blocked()
    info = key.stat()
    if (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077
            or not stat.S_ISREG(info.st_mode)):
        blocked()
    if key.is_relative_to(vault) or key.is_relative_to(replica):
        blocked()
    if any((p / ".git").exists() for p in (key.parent, *key.parents)):
        blocked()
    # This is only a filesystem-separation test, not a physical media attestation.
    if not fictional_test and info.st_dev in (vault.stat().st_dev,
                                               replica.stat().st_dev):
        blocked()


def secure_destination(dirpath, name):
    target = dirpath / name
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                 | getattr(os, "O_NOFOLLOW", 0), 0o600)
    return fd


def fsync_directory(directory):
    fd = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def copy_exact(source, targetdir):
    # Both files are sealed synthetic evidence, never source plaintext.
    target = targetdir / source.name
    before = hashlib.sha256()
    after = hashlib.sha256()
    if (not source.is_file() or source.is_symlink()
            or stat.S_IMODE(source.stat().st_mode) & 0o077):
        blocked()
    fd = secure_destination(targetdir, source.name)
    try:
        with source.open("rb") as reader, os.fdopen(fd, "wb") as writer:
            fd = -1
            while True:
                chunk = reader.read(CHUNK)
                if not chunk:
                    break
                before.update(chunk)
                writer.write(chunk)
            writer.flush()
            os.fsync(writer.fileno())
        with target.open("rb") as reader:
            while True:
                chunk = reader.read(CHUNK)
                if not chunk:
                    break
                after.update(chunk)
        if before.digest() != after.digest():
            blocked()
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    finally:
        if fd >= 0:
            os.close(fd)


def run_transport(operation, root, name, certificate, private_key=None,
                  synthetic_bytes=None):
    command = [sys.executable, str(TRANSPORT), operation,
               "--vault-dir", str(root), "--name", name,
               "--certificate", str(certificate)]
    if private_key is not None:
        command.extend(["--private-key", str(private_key)])
    try:
        process = subprocess.run(command, input=synthetic_bytes,
                                 stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL,
                                 timeout=60, check=False)
    except (OSError, subprocess.TimeoutExpired):
        blocked()
    if process.returncode != 0:
        blocked()


def synthetic_drill(vault_path, replica_path, certificate_path, key_path,
                    fictional_test=False):
    vault = Path(vault_path)
    replica = Path(replica_path)
    cert = Path(certificate_path)
    if (vault == replica or vault in replica.parents or replica in vault.parents):
        blocked()
    # The same U1.13 real-vault permissions, certificate and fsync checks apply.
    preflight.check_vault(str(vault), str(cert), fictional_test=fictional_test)
    preflight.check_vault(str(replica), str(cert), fictional_test=fictional_test)
    if not fictional_test and vault.stat().st_dev == replica.stat().st_dev:
        blocked()
    check_key(key_path, vault, replica, fictional_test=fictional_test)
    name = PREFIX + secrets.token_hex(12)
    generated = [
        vault / (name + ".capsule.cms"), vault / (name + ".witness.cms"),
        replica / (name + ".capsule.cms"), replica / (name + ".witness.cms"),
    ]
    if any(f.exists() or f.is_symlink() for f in generated):
        blocked()
    created = []
    try:
        run_transport("seal", vault, name, cert,
                      synthetic_bytes=secrets.token_bytes(8192))
        created.extend(generated[:2])
        run_transport("verify", vault, name, cert, private_key=key_path)
        for f in generated[:2]:
            copy_exact(f, replica)
            created.append(replica / f.name)
        fsync_directory(replica)
        run_transport("verify", replica, name, cert, private_key=key_path)
    finally:
        # Remove only this invocation's known-created synthetic files.
        for f in created:
            f.unlink(missing_ok=True)
        fsync_directory(vault)
        fsync_directory(replica)
    return {
        "syntheticRoundtrip": True,
        "independentDirectoryCopy": True,
        "encryptedWitnessValidated": True,
        "realCustomerDataRead": False,
        "productionBackupCreated": False,
        "offDeviceDisasterRecoveryProved": False,
        "actualRowCaptureAuthorized": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault-dir", required=True)
    parser.add_argument("--replica-dir", required=True)
    parser.add_argument("--recipient-certificate", required=True)
    parser.add_argument("--private-key", required=True)
    # Fixture-only. The test mode cannot be used to certify real storage.
    parser.add_argument("--fictional-ci-temp", action="store_true")
    args = parser.parse_args()
    try:
        receipt = synthetic_drill(
            args.vault_dir, args.replica_dir,
            args.recipient_certificate, args.private_key,
            fictional_test=args.fictional_ci_temp,
        )
    except (ValueError, OSError, subprocess.SubprocessError):
        # No paths, key contents, cert details or filenames in public output.
        print("BLOCKED synthetic owner vault drill; no historical data processed",
              file=sys.stderr)
        raise SystemExit(2)
    assert receipt["productionBackupCreated"] is False
    print("PASS fictional sealed-copy and key verification only; "
          "no real backup or independent disaster recovery certified")


if __name__ == "__main__":
    main()
