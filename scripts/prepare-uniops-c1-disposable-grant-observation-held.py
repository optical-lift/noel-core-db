#!/usr/bin/env python3
"""Source-only preparation of a read-only C1 ACL observation on the clone.

Builds a disposable psql candidate-validation wrapper. It first SELECTs the
six protected C1 function privileges into a private temporary report, then
includes the EXACT immutable canonical postconditions in their original order.
No canonical source, grants, schema or production resource is changed.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
import re
import stat

SOURCE_BLOB = "239a1f3d264d9c66ced7965c325d5d22f0945224"
PROBE = Path(__file__).with_name("uniops-c1-readonly-disposable-grants-held.py")
SAFE_PATH = re.compile(r"^/[A-Za-z0-9_./-]+$")
FALLBACK = "unclassified"


def git_blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def valid_path(path: Path) -> bool:
    return bool(SAFE_PATH.fullmatch(str(path)) and ".." not in path.parts)


def probe_module():
    spec = importlib.util.spec_from_file_location("c1_clone_acl", PROBE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_wrapper(source_path: Path, wrapper_path: Path, report_path: Path) -> None:
    for path in (source_path, wrapper_path, report_path):
        if not valid_path(path):
            raise ValueError("refuse unsafe or non-absolute diagnostic path")
    if source_path.is_symlink() or not source_path.is_file():
        raise ValueError("canonical source must be a regular file")
    if git_blob(source_path.read_bytes()) != SOURCE_BLOB:
        raise ValueError("pinned canonical C1 postcondition SQL changed")
    if wrapper_path.exists() or report_path.exists():
        raise ValueError("refuse to overwrite existing diagnostic files")
    # A wrapper with exactly one absolute \i is not a replacement for the
    # original postconditions: psql still runs every original assertion
    # with ON_ERROR_STOP=1 and fails at the same real SQL statement.
    sql = probe_module().QUERY
    wrapper = (
        "-- Read-only C1 clone ACL parity; canonical postconditions unchanged.\n"
        "\\pset tuples_only on\n"
        "\\pset format unaligned\n"
        "\\pset fieldsep |\n"
        f"\\o {report_path}\n"
        + sql + "\n"
        "\\o\n"
        "\\pset tuples_only off\n"
        "\\pset format aligned\n"
        f"\\i {source_path}\n"
    )
    wrapper_path.write_text(wrapper, encoding="utf-8")


def summarize(path: Path) -> str:
    if not valid_path(path) or path.is_symlink():
        return FALLBACK
    try:
        if not path.is_file() or path.stat().st_size > 8192:
            return FALLBACK
        return probe_module().classify(path.read_text(encoding="utf-8"))
    except (UnicodeError, OSError):
        return FALLBACK


def main() -> None:
    p = argparse.ArgumentParser()
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument("--create-wrapper", action="store_true")
    group.add_argument("--report", type=Path)
    p.add_argument("--pinned-postconditions", type=Path)
    p.add_argument("--wrapper", type=Path)
    p.add_argument("--private-report", type=Path)
    args = p.parse_args()
    if args.report is not None:
        print("C1_CLONE_ACL=" + summarize(args.report))
        return
    if None in (args.pinned_postconditions, args.wrapper, args.private_report):
        raise SystemExit("Source, output wrapper and private report paths required")
    try:
        make_wrapper(args.pinned_postconditions, args.wrapper, args.private_report)
    except (ValueError, OSError) as exc:
        raise SystemExit("Refuse C1 clone observation: " + str(exc))
    print("PASS source-pinned readonly C1 clone observation wrapper; no database change")


if __name__ == "__main__":
    main()
