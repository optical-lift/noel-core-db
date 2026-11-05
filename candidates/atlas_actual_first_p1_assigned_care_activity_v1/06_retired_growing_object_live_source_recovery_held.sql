-- UNI-OPS-01 / held Noel source recovery, not a migration or production patch.
-- Read-only canonical Noel Postgres pg_get_functiondef inspected 2026-11-05.
-- Exact live function: atlas.is_retired_growing_object_v1(text).
-- This function is PRESENT in live Noel; absent from RiverSong's retained
-- schema-only clone and missing from the investigated GitHub SQL ancestry.
-- Recover the LIVE source definition in fresh disposable validation only.
-- Do not invent semantics, disable retained retirement guards or touch
-- the live database. This restores exactly the existing live predicate.
CREATE OR REPLACE FUNCTION atlas.is_retired_growing_object_v1(p_object_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'atlas', 'public'
AS $function$
  select exists (
    select 1
    from atlas.growing_objects go
    where go.id::text = p_object_id
      and (
        go.object_mode = 'historical_tombstone'
        or lower(coalesce(go.metadata ->> 'canonicalDeleted', 'false')) = 'true'
        or lower(coalesce(go.metadata ->> 'subjectRetired', 'false')) = 'true'
      )
  );
$function$;

-- Preserve live observed ACL (postgres owner and explicit authenticated and
-- service_role execute; no PUBLIC/anon access). Not a new source grant.
REVOKE ALL ON FUNCTION atlas.is_retired_growing_object_v1(text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.is_retired_growing_object_v1(text)
  TO authenticated,service_role;

DO $verified_live_source$
BEGIN
  IF pg_catalog.to_regprocedure('atlas.is_retired_growing_object_v1(text)')
       IS NULL
     OR (SELECT p.prosecdef FROM pg_catalog.pg_proc p
         WHERE p.oid='atlas.is_retired_growing_object_v1(text)'::regprocedure)
     OR (SELECT p.provolatile FROM pg_catalog.pg_proc p
         WHERE p.oid='atlas.is_retired_growing_object_v1(text)'::regprocedure)
        IS DISTINCT FROM 's'
     OR pg_catalog.has_function_privilege('anon',
       'atlas.is_retired_growing_object_v1(text)','EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated',
       'atlas.is_retired_growing_object_v1(text)','EXECUTE')
     OR atlas.is_retired_growing_object_v1(
       'f6000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Recovered retirement helper diverged from live source contract';
  END IF;
  RAISE NOTICE 'PASS exact live-source retired-object predicate and observed ACL';
END;
$verified_live_source$;
