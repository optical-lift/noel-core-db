#!/usr/bin/env python3
"""Local-only, fail-closed installer/test harness for Noel #2263.

Not a production migration, deployment, or privacy certification. No linked
Supabase project, db reset, cloud branch, remote SQL, secrets, or real people.
Requires an ALREADY RUNNING, disposable, FULL-SCHEMA local Supabase stack.
Use --preflight first; --execute applies held source candidates ONLY locally.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "candidates/atlas/connected_person_effective_disclosure_review_v1"
FIXTURE = ROOT / "validation/fixtures/20261024231215_shared_native_ledger_standing_work_person_only_v1.sql"
AUTH_IDS = tuple(f"e5200000-0000-4000-8000-{i:012d}" for i in (1, 2, 3, 4))
ORG_ID = "e5200000-0000-4000-8000-000000000801"
PERSON_IDS = tuple(f"e5200000-0000-4000-8000-{i:012d}" for i in (101, 102, 103, 104, 201))
WORK_IDS = tuple(f"e5200000-0000-4000-8000-{i:012d}" for i in (901, 902, 903))
LEDGER_IDS = tuple(f"e5200000-0000-4000-8000-{i:012d}" for i in (401, 402))
INSTALL_ORDER = (
    "connected_person_work_field_decisions_hold.sql",
    "candidate.sql",
    "connected_person_work_read_candidate.sql",
    "connected_person_my_work_existing_reader_cutover_hold.sql",
    "connected_person_today_existing_reader_cutover_hold.sql",
    "connected_person_dated_work_existing_reader_cutover_hold.sql",
)
POSTCONDITIONS = (
    "connected_person_work_field_decisions_postconditions_hold.sql",
    "postconditions.sql",
    "connected_person_work_read_postconditions.sql",
    "connected_person_my_work_existing_reader_cutover_postconditions_hold.sql",
    "connected_person_today_existing_reader_cutover_postconditions_hold.sql",
    "connected_person_dated_work_existing_reader_cutover_postconditions_hold.sql",
)
SIGNER = ROOT / "scripts/validate-atlas-connected-person-work-signed-http.py"

def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)

def run(args: list[str], cwd: Path | None = None, input_data: str | None = None) -> str:
    process = subprocess.run(args, cwd=cwd, text=True, input=input_data,
                             capture_output=True, check=False, timeout=1500)
    require(process.returncode == 0,
            f"{args[0]} failed (exit {process.returncode}): "
            f"{(process.stderr or process.stdout)[-1800:]}")
    return process.stdout.strip()

def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"

def sql(db_url: str, statement: str) -> str:
    return run(["psql", db_url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
                "-c", statement])

def file_sql(db_url: str, path: Path) -> None:
    print(f"Applying local-only held SQL: {path.name}", flush=True)
    run(["psql", db_url, "-X", "-v", "ON_ERROR_STOP=1", "-f", str(path)])

def local_status(stack_dir: Path) -> tuple[str, str]:
    require((stack_dir / "supabase/config.toml").is_file(),
            "No initialized local Supabase stack here. Specify --stack-dir "
            "pointing to an existing local project with supabase/config.toml.")
    output = run(["supabase", "status", "-o", "env"], cwd=stack_dir)
    env = dict(line.strip().split("=", 1) for line in output.splitlines()
               if "=" in line)
    db_url = env.get("DB_URL", "").strip('"')
    api_url = env.get("API_URL", "").strip('"')
    db = urlparse(db_url)
    api = urlparse(api_url)
    require(db.scheme in ("postgresql", "postgres")
            and db.hostname == "127.0.0.1"
            and db.port is not None
            and db.path == "/postgres"
            and db.username == "postgres"
            and db.password,
            "Refusing SQL: status DB_URL is not the expected local Supabase "
            "127.0.0.1 postgres database with an explicit password.")
    require(api.scheme == "http" and api.hostname in ("127.0.0.1", "localhost")
            and api.port is not None, "Refusing signed HTTP: API is not local.")
    return db_url, api_url

def allowed_local_data(db_url: str) -> tuple[int, int]:
    """Refuse real data even if a production server is tunneled onto localhost."""
    checks = (
        ("auth.users", "id", AUTH_IDS),
        ("atlas.organizations", "id", (ORG_ID,)),
        ("atlas.work_items", "id", WORK_IDS),
        ("ledger.ledgers", "id", LEDGER_IDS),
        ("reality.entities", "id", PERSON_IDS),
    )
    for table, key, allowed in checks:
        literals = ",".join(quote(x) + "::uuid" for x in allowed)
        unexpected = sql(db_url, f"SELECT count(*) FROM {table} "
                             f"WHERE {key} NOT IN ({literals})")
        require(unexpected == "0",
                f"REFUSED: {table} contains non-fixture records. "
                "Never test this packet against any real-data database.")
    auth = int(sql(db_url, "SELECT count(*) FROM auth.users"))
    org = int(sql(db_url, "SELECT count(*) FROM atlas.organizations"))
    require(auth in (0, 4) and org in (0, 1),
            "Unexpected partial fixture in local database. Use a new disposable clone.")
    if auth == 0:
        require(org == 0 and sql(db_url, "SELECT count(*) FROM atlas.work_items") == "0"
                and sql(db_url, "SELECT count(*) FROM ledger.ledgers") == "0",
                "Fixture cannot be applied over nonempty existing organization/Work.")
    else:
        require(org == 1
                and sql(db_url, "SELECT count(*) FROM atlas.work_items") == "3",
                "Existing fixture is partial or differs from expected isolated test.")
    return auth, org

def collect_hashes() -> dict[str, str]:
    files = (FIXTURE, SIGNER) + tuple(BASE / x for x in INSTALL_ORDER + POSTCONDITIONS)
    for path in files:
        require(path.is_file(), f"Required reviewed source is missing: {path}")
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in files}

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true",
                        help="Default: inspect tools, source and local stack; never write SQL.")
    parser.add_argument("--execute", action="store_true",
                        help="Opt in to synthetic fixture, held SQL and real local GoTrue tests.")
    parser.add_argument("--stack-dir", type=Path, default=ROOT,
                        help="Existing initialized and RUNNING local Supabase project.")
    parser.add_argument("--receipt-dir", type=Path, default=ROOT / ".local-security-receipts",
                        help="Local output directory, no secrets copied.")
    args = parser.parse_args()
    require(not (args.preflight and args.execute), "Choose only one mode.")
    for tool in ("supabase", "psql", "git"):
        require(shutil.which(tool) is not None, f"{tool} is required; no installations performed.")
    hashes = collect_hashes()
    db_url, _ = local_status(args.stack_dir.resolve())
    require(sql(db_url, "SELECT current_database()") == "postgres",
            "Unexpected database identity; refusing.")
    auth, _ = allowed_local_data(db_url)
    print("PASS: local 127.0.0.1 database and API, only synthetic/empty records")
    print("PASS: all held sources, postconditions and local signed test present")
    print("Source SHA256 manifest files:", len(hashes))
    if not args.execute:
        print("PREFLIGHT ONLY: no SQL, migrations, fixtures, grants or signed tests executed.")
        return

    # Only a clean full-schema test DB or a complete existing synthetic fixture
    # is allowed; no data from real users will ever be modified by this runner.
    if auth == 0:
        file_sql(db_url, FIXTURE)
    else:
        print("Reusing existing synthetic fixture; do not reinsert it.")
    allowed_local_data(db_url)
    for name in INSTALL_ORDER:
        file_sql(db_url, BASE / name)
    for name in POSTCONDITIONS:
        file_sql(db_url, BASE / name)
    sql(db_url, "NOTIFY pgrst, 'reload schema'")
    print("PASS: all held SQL and clone-only structural postconditions")
    output = args.receipt_dir.resolve() / "connected-person-signed-http.txt"
    output.parent.mkdir(parents=True, exist_ok=True)
    # Signed script does NOT fabricate JWTs; verifies GoTrue auth.sessions.
    # Its own --db-url check rejects anything except local 127.0.0.1.
    run([sys.executable, str(SIGNER), "--db-url", db_url,
         "--output", str(output)], cwd=args.stack_dir.resolve())
    require(output.is_file() and "PASS" in output.read_text(),
            "Signed GoTrue result receipt missing; DO NOT claim success.")
    receipt = {
        "status": "LOCAL_CANDIDATE_SIGNED_TEST_PASS_NOT_PRODUCTION_CERTIFICATION",
        "time": datetime.now(timezone.utc).isoformat(),
        "commit": run(["git", "rev-parse", "HEAD"], cwd=ROOT),
        "source_sha256": hashes,
        "result": output.read_text().strip(),
        "disclosure_review_complete": False,
        "other_readers_and_browser_acceptance_complete": False,
        "production_release_authorized": False,
    }
    (output.parent / "connected-person-receipt.json").write_text(
        json.dumps(receipt, indent=2) + "\n")
    print("PASS: genuine independent local GoTrue/PostgREST synthetic tests")
    print("NOT A PRODUCTION RELEASE: old farm/Event/Index/cache/browser gates remain.")

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"STOP / NO SIGNED PASS: {error}", file=sys.stderr)
        sys.exit(1)
