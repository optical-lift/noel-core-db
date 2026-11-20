#!/usr/bin/env python3
"""Fail-closed source contract for the exact PRE1 live row-preservation guard."""
import hashlib
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

# Exercise the actual canonical releaser's archive: it stores the complete,
# immutable migration including BEGIN inside the receipt as dollar-quoted
# literal text. The guard must count executable SQL, not that archived copy.
tag = "$noel_core_migration_" + hashlib.sha256(raw).hexdigest() + "$"
real_receipt = (
    "insert into supabase_migrations.schema_migrations "
    "(version, statements, name, created_by) values (\n"
    f"  '{VERSION}',\n"
    f"  array[{tag}{source}{tag}],\n"
    f"  '{NAME}',\n"
    "  'github-actions:noel-core-db@0000000000000000000000000000000000000000'\n"
    ");\ncommit;\n"
)
real_governed = before_commit + real_receipt
assert real_governed.count("BEGIN;") == 2  # executable + archived
actual_out = augment(real_governed, raw, VERSION, NAME)
assert actual_out.count("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;") == 1
assert actual_out.index("$atlas_pre1_capture_all_rows$") < actual_out.index("DROP FUNCTION atlas.tending_task_context_v1")
assert actual_out.index("$atlas_pre1_verify_all_rows$") < actual_out.index("insert into supabase_migrations.schema_migrations")
# An additional executable BEGIN before the receipt remains prohibited.
try:
    augment(before_commit + "BEGIN;\n" + real_receipt, raw, VERSION, NAME)
except ValueError as exc:
    assert "missing unique canonical BEGIN" in str(exc)
else:
    raise AssertionError("PRE1 accepted a second executable transaction start")
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
# The production user-schema snapshot deliberately excludes Supabase-managed
# migration metadata. Prove only the exact PRE1 disposable test can provision
# the pinned native version/statement/name columns plus Noel's created_by.
assert 'pre1_container="supabase_db_$pre1_project_id"' in clone_source
assert 'test "$(docker inspect --format' in clone_source
assert 'docker port "$pre1_container" 5432/tcp | grep -Eq ":$local_database_port$"' in clone_source
assert 'validation_20261120211526_[0-9a-f]{8}' in clone_source
assert 'phase="PRE1 disposable native migration-history compatibility"' in clone_source
assert "CREATE SCHEMA IF NOT EXISTS supabase_migrations;" in clone_source
assert "CREATE TABLE supabase_migrations.schema_migrations (" in clone_source
assert "version text NOT NULL PRIMARY KEY," in clone_source
assert "statements text[]," in clone_source
assert "name text," in clone_source
assert "created_by text" in clone_source
assert "REVOKE ALL ON TABLE supabase_migrations.schema_migrations FROM PUBLIC;" in clone_source
assert "to_regclass('supabase_migrations.schema_migrations') IS NOT NULL" in clone_source
assert "SELECT count(*) FROM supabase_migrations.schema_migrations" in clone_source
assert clone_source.index("phase=\"PRE1 disposable native migration-history compatibility\"") > clone_source.index('if [ "$lane" = atlas ] && [ "$version" = 20261120211526 ]')
assert clone_source.index("phase=\"PRE1 disposable native migration-history compatibility\"") < clone_source.index('bash scripts/release-production-migration.sh "$version"')
assert "NOEL_CORE_DATABASE_URL=\"$database_url\"" in clone_source
assert "GITHUB_RELEASE_SHA=0000000000000000000000000000000000000000" in clone_source
assert 'bash scripts/release-production-migration.sh "$version"' in clone_source
assert "PASS PRE1 same-transaction original-row conservation: 730 Atlas base relations" in clone_source
print("PASS PRE1 exact-version release row guard and fail-closed source contract")
