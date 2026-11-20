#!/usr/bin/env python3
"""Fail-closed source contract for the exact PRE1 live row-preservation guard."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from atlas_pre1_production_row_integrity import (
    AFTER, BEFORE, GIT_BLOB, NAME, VERSION, augment, git_blob,
)

source_path = ROOT / "supabase" / "migrations" / (
    VERSION + "_" + NAME + ".sql"
)
raw = source_path.read_bytes()
assert git_blob(raw) == GIT_BLOB
source = raw.decode("utf-8")
assert source.count("DROP FUNCTION atlas.tending_task_context_v1(uuid,uuid,text) RESTRICT;") == 1
assert source.count("DROP FUNCTION atlas.tending_card_json_v1(uuid,jsonb,boolean) RESTRICT;") == 1
assert source.rstrip().endswith("COMMIT;")

# Simulate the already-governed releaser's atomic canonical custody receipt.
before_commit = source.rsplit("COMMIT;", 1)[0]
receipt = ("insert into supabase_migrations.schema_migrations "
           "(version, statements, name, created_by) VALUES (...);\ncommit;\n")
governed = before_commit + receipt
out = augment(governed, raw, VERSION, NAME)
assert out != governed
assert out.count("BEGIN;") == 1
assert out.count("insert into supabase_migrations.schema_migrations") == 1
assert out.count("CREATE TEMP TABLE pg_temp.atlas_pre1_original_rows_guard") == 1
assert out.count("ON COMMIT DROP;") == 1
assert out.count("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;") == 1
assert out.count("LOCK TABLE %I.%I IN ACCESS SHARE MODE NOWAIT") == 1
assert out.count("SET LOCAL statement_timeout = '600s'") == 2
assert out.count("FROM %I.%I AS t") == 2
assert out.count("COUNT(*)::bigint") == 2
assert out.count("to_jsonb(t)::text") == 4
assert out.count("RAISE EXCEPTION 'PRE1 original row identity/content mismatch") == 1
assert "RAISE EXCEPTION 'PRE1 original Atlas relation census drift" in out
assert out.index("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;") < out.index("SET LOCAL lock_timeout = '3s';", out.index("SET TRANSACTION ISOLATION"))
assert out.index("$atlas_pre1_capture_all_rows$") < out.index("DROP FUNCTION atlas.tending_task_context_v1")
assert out.index("DROP FUNCTION atlas.tending_card_json_v1") < out.index("$atlas_pre1_verify_all_rows$")
assert out.index("$atlas_pre1_verify_all_rows$") < out.index("insert into supabase_migrations.schema_migrations")
assert out.rstrip().endswith("commit;")
assert "RAISE NOTICE 'PASS PRE1 same-transaction original-row conservation" in out
assert "RAISE NOTICE 'PRE1 baseline:" in out
for name in ("tasks", "work_items", "crop_cycles", "crop_placements",
             "growing_objects", "care_state_history", "zones"):
    assert f"relname='{name}'" in BEFORE
assert "SELECT COUNT(*) FROM pg_temp.atlas_pre1_original_rows_guard" in AFTER
assert "ORDER BY relname" in AFTER
assert "RAISE EXCEPTION" in AFTER
assert "sha256(convert_to(to_jsonb(t)::text" in BEFORE
assert "sha256(convert_to(to_jsonb(t)::text" in AFTER

# Every other migration follows the unchanged established releaser.
assert augment(governed, raw, "20261120211525", NAME) == governed
for altered_raw, version, name in (
    (raw + b"\n", VERSION, NAME),
    (raw, VERSION, NAME + "_changed"),
):
    try:
        augment(governed, altered_raw, version, name)
    except ValueError:
        pass
    else:
        raise AssertionError("PRE1 guard accepted unapproved canonical source")

for invalid in (
    governed.replace("insert into supabase_migrations.schema_migrations", "missing"),
    governed.replace("BEGIN;", "BEGIN TRANSACTION;"),
    governed.replace("commit;", "rollback;"),
):
    try:
        augment(invalid, raw, VERSION, NAME)
    except ValueError:
        pass
    else:
        raise AssertionError("PRE1 guard accepted a broken transaction seam")

release_source = (ROOT / "scripts" / "release-production-migration.sh").read_text()
assert "if version == '20261120211526':" in release_source
assert "from atlas_pre1_production_row_integrity import augment" in release_source
assert "governed_sql = augment(governed_sql, raw, version, name)" in release_source
assert "out_path.write_text(governed_sql" in release_source
assert "psql \"$NOEL_CORE_DATABASE_URL\"" in release_source
clone_source = (ROOT / "scripts" / "validate-production-schema-clone.sh").read_text()
assert 'if [ "$lane" = atlas ] && [ "$version" = 20261120211526 ]' in clone_source
# The canonical clone allocates its own 38000..60999 loopback port.
# The exact-version guard must bind to THAT port, not a fixed default or a
# remote-compatible connection string; candidate/source guards remain intact.
assert 'ports=list(range(38000, 61000))' in clone_source
assert 'port = {port}' in clone_source
assert 'database_url="postgresql://postgres:postgres@127.0.0.1:${local_database_port}/postgres"' in clone_source
assert '[[ ! "$local_database_port" =~ ^[0-9]{5}$ ]]' in clone_source
assert '[ "$local_database_port" -lt 38000 ]' in clone_source
assert '[ "$local_database_port" -ge 61000 ]' in clone_source
assert '[ "$database_url" != "postgresql://postgres:postgres@127.0.0.1:${local_database_port}/postgres" ]' in clone_source
assert "[ \"$database_url\" != 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' ]" not in clone_source
assert '[ "$(git hash-object "$candidate_migration")" != ac8552f35e4de14f1ae337c29cfc1c2971af1c9b ]' in clone_source
assert '[ "$(git hash-object "$candidate_validation")" != aff86ae537a7dfbffefa4320e6d21328c32c78d7 ]' in clone_source
assert "NOEL_CORE_DATABASE_URL=\"$database_url\"" in clone_source
assert "GITHUB_RELEASE_SHA=0000000000000000000000000000000000000000" in clone_source
assert 'bash scripts/release-production-migration.sh "$version"' in clone_source
assert "PASS PRE1 same-transaction original-row conservation: 730 Atlas base relations" in clone_source
print("PASS PRE1 exact-version release row guard and fail-closed source contract")
