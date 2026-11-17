#!/usr/bin/env python3
"""HELD ONLY: fixed-vocabulary diagnosis of a disposable native pre-U2 gate.

No database access, network, credentials, SQL or raw error text. The protected
controller may print only this classifier's two finite markers. No previous
one-shot authorization is reused by this file.
"""
import argparse
from pathlib import Path
import re

MARKER="uniops-native-pre-u2-stage.safe"
GRANT_LOG="uniops-native-test-access-private.log"
GATES=frozenset((
    "projection_fingerprint_check",
    "projection_source_mismatch",
    "projection_source_probe_refused",
    "projection_install_refused",
    "grant_source_refused",
    "grant_receipt_refused",
    "signed_u2_ready",
))
GRANT_STAGES=frozenset((
    "environment","actor_and_root","source_acl","source_function_missing",
    "source_anon_exposed","source_authenticated_exposed","source_postgres_denied",
    "source_acl_multiple_mismatches","source_acl_probe_refused",
    "source_acl_inconsistent","preexisting_access","canonical_grant",
    "postcondition"
))

def read_bounded(path,maximum):
    if not path.is_file() or path.is_symlink() or path.stat().st_size > maximum:
        raise ValueError("Required private diagnostic unavailable")
    # Preserve raw line endings: universal-newline text reading would silently
    # accept injected CRLF as the single canonical LF marker.
    return path.read_bytes().decode("utf8")

def diagnose(folder):
    path=Path(folder)
    if not path.is_dir() or path.is_symlink() or not path.is_absolute():
        raise ValueError("Private diagnostics directory not available")
    marker=path/MARKER
    if marker.is_symlink() or not marker.is_file():
        gate="not_recorded"
    else:
        try:
            source=read_bounded(marker,256)
            m=re.fullmatch(r"UNI_OPS_NATIVE_PRE_U2_STAGE=([a-z0-9_]+)\n",source)
            gate=m.group(1) if m and m.group(1) in GATES else "unclassified"
        except (ValueError,UnicodeError,OSError):
            gate="unclassified"
    detail="not_applicable"
    if gate=="grant_source_refused":
        try:
            # The real error never leaves the runner. Only the existing
            # explicit enum from the source-authored grant helper can leave.
            private=read_bounded(path/GRANT_LOG,65536)
            stages=re.findall(r"(?m)^ATLAS_NATIVE_GOVERNOR_GRANT_STAGE=([a-z_]+)$",private)
            detail=stages[0] if len(stages)==1 and stages[0] in GRANT_STAGES else "unclassified"
        except (ValueError,UnicodeError,OSError):
            detail="not_recorded"
    return gate,detail

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--artifacts-dir",required=True)
    args=p.parse_args()
    try:
        gate,detail=diagnose(args.artifacts_dir)
    except (ValueError,OSError):
        gate,detail="not_recorded","not_applicable"
    print("UNI_OPS_NATIVE_PRE_U2_GATE="+gate)
    print("UNI_OPS_NATIVE_GRANT_STAGE="+detail)

if __name__=="__main__":
    main()
