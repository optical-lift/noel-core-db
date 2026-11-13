#!/usr/bin/env python3
"""TEST ONLY: full-row identity/content conservation on a disposable Atlas schema clone.

No production connection is accepted. This computes SHA-256 digests of each entire
row (including its original ID and all history columns), sorts the row digests
as a multiset, and hashes that multiset per Atlas base relation. Only counts,
table names and opaque fingerprints are held in an ephemeral local snapshot.
The comparison prints no source rows, IDs, metadata, notes or fingerprints.
A schema-only clone does NOT contain the original Production data: passing
this local guard is NOT proof of Production historical identity no-loss.
"""
import argparse
import csv
import io
import json
import os
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit

REQUIRED = {
    "atlas.tasks",
    "atlas.work_items",
    "atlas.crop_cycles",
    "atlas.crop_placements",
    "atlas.growing_objects",
    "atlas.care_state_history",
    "atlas.zones",
}
VERSION = 1


def local_database_only(raw):
    url = urlsplit(raw)
    if (
        url.scheme not in ("postgres", "postgresql")
        or url.hostname != "127.0.0.1"
        or url.port is None
        or url.path != "/postgres"
        or url.query
        or url.fragment
    ):
        raise ValueError("PRE1 row-integrity refuses every nonlocal or non-postgres database URL")
    return raw


def select_only(db_url, sql):
    # Fixed SELECT statements generated from system catalog identifiers; no writes.
    completed = subprocess.run(
        ["psql", db_url, "-X", "-q", "-A", "-t", "-F", "\t",
         "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, check=False,
    )
    if completed.returncode:
        # Do not include a connection URL, SQL, source values or server diagnostics.
        raise RuntimeError("PRE1 row-integrity local read-only query failed")
    return list(csv.reader(io.StringIO(completed.stdout), delimiter="\t"))


def quote_ident(value):
    return '"' + value.replace('"', '""') + '"'


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def table_names(db_url):
    rows = select_only(db_url, """
      SELECT c.relname
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'atlas'
        AND c.relkind IN ('r','p')
        AND NOT c.relispartition
      ORDER BY c.relname;
    """)
    names = [row[0] for row in rows if len(row) == 1 and row[0]]
    if len(names) != len(rows) or len(names) != len(set(names)):
        raise RuntimeError("PRE1 row-integrity ambiguous Atlas base relation inventory")
    scoped = {"atlas." + name for name in names}
    if not REQUIRED.issubset(scoped):
        raise RuntimeError("PRE1 row-integrity missing required original Work/crop/care relation")
    return names


def fingerprint(db_url):
    names = table_names(db_url)
    pieces = []
    for name in names:
        qualified = "atlas." + name
        # ALL columns of EACH row, including its canonical id, not just counts.
        # Sorting hashes retains repeated identical rows and is row-order invariant.
        row_digest = "encode(sha256(convert_to(to_jsonb(t)::text,'UTF8')),'hex')"
        pieces.append(
            "SELECT " + literal(qualified) + "::text AS relation_name, "
            "COUNT(*)::bigint AS row_count, "
            "encode(sha256(convert_to(COALESCE(string_agg(" + row_digest +
            ", '' ORDER BY " + row_digest + "),''),'UTF8')),'hex') AS digest "
            "FROM " + quote_ident("atlas") + "." + quote_ident(name) + " AS t"
        )
    rows = select_only(db_url, " UNION ALL ".join(pieces) + " ORDER BY relation_name;")
    result = {}
    for row in rows:
        if len(row) != 3 or row[0] in result or not row[1].isdigit():
            raise RuntimeError("PRE1 row-integrity malformed local fingerprint result")
        if not (len(row[2]) == 64 and all(ch in "0123456789abcdef" for ch in row[2])):
            raise RuntimeError("PRE1 row-integrity malformed digest")
        result[row[0]] = {"rows": int(row[1]), "digest": row[2]}
    if set(result) != {"atlas." + name for name in names}:
        raise RuntimeError("PRE1 row-integrity incomplete base relation fingerprint")
    return result


def run(db_url, mode, snapshot):
    local_database_only(db_url)
    current = fingerprint(db_url)
    if mode == "capture":
        # EXCLUSIVE: no silent rewrite of the before image.
        body = json.dumps({"version": VERSION, "tables": current}, sort_keys=True)
        fd = os.open(snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(body + "\n")
        print("PRE1 LOCAL row-integrity baseline captured: " + str(len(current)) + " Atlas base tables")
        return
    original = json.loads(Path(snapshot).read_text(encoding="utf-8"))
    if original.get("version") != VERSION or not isinstance(original.get("tables"), dict):
        raise RuntimeError("PRE1 row-integrity missing or invalid before image")
    baseline = original["tables"]
    changed = sorted(name for name in set(current) | set(baseline)
                     if current.get(name) != baseline.get(name))
    if changed:
        # Relation names only. Never put row bodies, row IDs, values or hashes in CI.
        raise RuntimeError("PRE1 ROW-INTEGRITY FAIL: changed Atlas relations: " +
                           ", ".join(changed))
    print("PASS ACCESS03C-PRE1 local all-base-row identity/content conservation: " +
          str(len(current)) + " Atlas base tables")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--mode", required=True, choices=("capture", "verify"))
    args = parser.parse_args()
    try:
        run(args.db_url, args.mode, args.snapshot)
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
