-- Read-only verification for first native source-provenance migration.
DO $check$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
 JOIN pg_namespace n ON n.oid=t.typnamespace WHERE n.nspname='transcript_core'
 AND t.typname='asset_provenance_class' AND e.enumlabel='manuscript_source')
 THEN RAISE EXCEPTION 'Missing committed native manuscript provenance type'; END IF;
END $check$;
SELECT 'PASS committed native manuscript source provenance; no publication or asset writes' AS result;
