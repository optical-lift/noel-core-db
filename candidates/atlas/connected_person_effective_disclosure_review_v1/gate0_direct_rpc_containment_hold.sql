-- Gate 0 containment candidate, NOT an independently releasable migration.
-- Noel #2255; Atlas #437. Review external callers and preserve lawful
-- owner/manager operation through governed replacements before release.
-- NOTE: this only closes direct SQL invocation by browser roles. It does
-- NOT close indirect SECURITY DEFINER callers, RLS, storage, server or caches.
BEGIN;
REVOKE EXECUTE ON FUNCTION atlas.zone_registry_source_v1(uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.object_crop_bed_map_v1(uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE EXECUTE ON FUNCTION atlas.farm_care_zone_v1(uuid,text,integer)
  FROM PUBLIC,anon,authenticated;
-- Deliberately no grants or replacement reader in this file.
-- Effective exact-Ledger source-projections must be admitted separately.
COMMIT;
