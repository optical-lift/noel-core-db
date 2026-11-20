#!/usr/bin/env python3
"""Exact Atlas PRE1 production row-preservation guard for the governed releaser.

Only migration 20261120211526 is eligible. The wrapper inserts transaction-local,
read-only all-Atlas-row fingerprints before and after the exact approved SQL.
The original migration bytes remain unchanged in the atomic release ledger.
No private hashes, row bodies, or row IDs are written to logs or artifacts.
"""
import hashlib
import re

VERSION = "20261120211526"
NAME = "atlas_access03c_pre1_tending_v1_pair_retirement_v1"
GIT_BLOB = "ac8552f35e4de14f1ae337c29cfc1c2971af1c9b"
EXPECTED_ATLAS_TABLES = 730

# Both passes use exactly the local signed-test SHA-256 construction. A sorted
# multiset of hashes of complete to_jsonb rows preserves duplicate rows.
HASH_QUERY = r"""
SELECT COUNT(*)::bigint,
       encode(sha256(convert_to(
         COALESCE(string_agg(
           encode(sha256(convert_to(to_jsonb(t)::text, 'UTF8')), 'hex'),
           '' ORDER BY encode(sha256(convert_to(to_jsonb(t)::text, 'UTF8')), 'hex')
         ), ''), 'UTF8')), 'hex')
FROM %I.%I AS t
"""

BEFORE = (
    r"""
-- Atlas PRE1 protected release guard: same transaction and repeatable snapshot.
-- No persistent table, function, schema or user-record changes are introduced.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '600s';
CREATE TEMP TABLE pg_temp.atlas_pre1_original_rows_guard (
  relname text PRIMARY KEY,
  original_count bigint NOT NULL,
  full_row_digest text NOT NULL
) ON COMMIT DROP;
DO $atlas_pre1_capture_all_rows$
DECLARE
  item record;
  original_count bigint;
  full_digest text;
  table_count integer := 0;
BEGIN
  FOR item IN
    SELECT c.relname
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = 'atlas'
      AND c.relkind IN ('r', 'p')
      AND NOT c.relispartition
    ORDER BY c.relname
  LOOP
    -- ACCESS SHARE is compatible with ordinary DML but prevents concurrent
    -- relation DDL until commit. NOWAIT fails closed on incompatible locks.
    EXECUTE format('LOCK TABLE %I.%I IN ACCESS SHARE MODE NOWAIT',
                   'atlas', item.relname);
    EXECUTE format($atlas_pre1_sql$"""
    + HASH_QUERY +
    r"""$atlas_pre1_sql$, 'atlas', item.relname)
      INTO original_count, full_digest;
    IF original_count IS NULL
       OR full_digest !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION 'PRE1 original-row fingerprint incomplete';
    END IF;
    INSERT INTO pg_temp.atlas_pre1_original_rows_guard
      (relname, original_count, full_row_digest)
    VALUES (item.relname, original_count, full_digest);
    table_count := table_count + 1;
  END LOOP;
  IF table_count <> """
    + str(EXPECTED_ATLAS_TABLES) +
    r""" THEN
    RAISE EXCEPTION 'PRE1 original Atlas relation census drift: %', table_count;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='tasks')
     OR NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='work_items')
     OR NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='crop_cycles')
     OR NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='crop_placements')
     OR NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='growing_objects')
     OR NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='care_state_history')
     OR NOT EXISTS (SELECT 1 FROM pg_temp.atlas_pre1_original_rows_guard WHERE relname='zones')
  THEN
    RAISE EXCEPTION 'PRE1 original Work, crop, care or zone relation missing';
  END IF;
  RAISE NOTICE 'PRE1 baseline: % original Atlas base relations fingerprinted privately', table_count;
END
$atlas_pre1_capture_all_rows$;
"""
)

AFTER = (
    r"""
-- Post-drop, pre-receipt. Any mismatch aborts the transaction and both drops.
SET LOCAL statement_timeout = '600s';
DO $atlas_pre1_verify_all_rows$
DECLARE
  item record;
  checked_count integer := 0;
  post_count bigint;
  post_digest text;
  current_inventory integer;
BEGIN
  SELECT COUNT(*) INTO current_inventory
  FROM pg_catalog.pg_class AS c
  JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
  WHERE n.nspname='atlas' AND c.relkind IN ('r','p')
    AND NOT c.relispartition;
  IF current_inventory <> (SELECT COUNT(*) FROM pg_temp.atlas_pre1_original_rows_guard)
     OR current_inventory <> """
    + str(EXPECTED_ATLAS_TABLES) +
    r""" THEN
    RAISE EXCEPTION 'PRE1 relation inventory changed during governed release';
  END IF;
  FOR item IN
    SELECT relname, original_count, full_row_digest
    FROM pg_temp.atlas_pre1_original_rows_guard ORDER BY relname
  LOOP
    IF to_regclass(format('%I.%I','atlas',item.relname)) IS NULL THEN
      RAISE EXCEPTION 'PRE1 original relation missing at release verification: %', item.relname;
    END IF;
    EXECUTE format($atlas_pre1_sql$"""
    + HASH_QUERY +
    r"""$atlas_pre1_sql$, 'atlas', item.relname)
      INTO post_count, post_digest;
    IF post_count IS DISTINCT FROM item.original_count
       OR post_digest IS DISTINCT FROM item.full_row_digest THEN
      RAISE EXCEPTION 'PRE1 original row identity/content mismatch: atlas.%', item.relname;
    END IF;
    checked_count := checked_count + 1;
  END LOOP;
  RAISE NOTICE 'PASS PRE1 same-transaction original-row conservation: % Atlas base relations', checked_count;
END
$atlas_pre1_verify_all_rows$;
"""
)


def git_blob(raw: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(raw)).encode("ascii") + b"\x00" + raw).hexdigest()


def augment(governed_sql: str, raw: bytes, version: str, name: str) -> str:
    """Insert guards only for the exact authorized immutable Atlas migration."""
    if version != VERSION:
        return governed_sql
    if name != NAME or git_blob(raw) != GIT_BLOB:
        raise ValueError("PRE1 live row guard: unapproved version, name or SQL source")
    if governed_sql.count("insert into supabase_migrations.schema_migrations") != 1:
        raise ValueError("PRE1 live row guard: missing unique atomic custody receipt")
    receipt = governed_sql.index("insert into supabase_migrations.schema_migrations")
    # The canonical custody receipt contains an archival dollar-quoted copy
    # of the exact source migration, including its BEGIN; line. Count only
    # executable transaction entry before that receipt, never quoted history.
    executable_prefix = governed_sql[:receipt]
    if len(re.findall(r"(?m)^BEGIN;\s*$", executable_prefix)) != 1:
        raise ValueError("PRE1 live row guard: missing unique canonical BEGIN")
    begin = re.search(r"(?m)^BEGIN;[ \t]*(?:\r?\n)", executable_prefix)
    if begin is None:
        raise ValueError("PRE1 live row guard: canonical BEGIN line changed")
    if receipt <= begin.end():
        raise ValueError("PRE1 live row guard: invalid transaction order")
    if not governed_sql.rstrip().lower().endswith("commit;"):
        raise ValueError("PRE1 live row guard: terminal COMMIT missing")
    return (governed_sql[:begin.end()] + BEFORE +
            governed_sql[begin.end():receipt] + AFTER +
            governed_sql[receipt:])
