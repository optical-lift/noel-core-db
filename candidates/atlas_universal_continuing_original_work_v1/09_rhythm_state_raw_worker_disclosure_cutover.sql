-- DRAFT ONLY: source-enforced raw Rhythm state disclosure cutover.
-- Read-only production role/claims probe 2026-10-28: a current legacy
-- authenticated farm_hand had SELECT access to 181 assigned_worker rhythms,
-- including 102 growing_objects with ZERO current exact identity/condition
-- grants. Scoped Work Subject APIs must be used for selective disclosure.
-- Do not make RLS on the raw table a parallel, unrestricted farm reader.
--
-- This guard keeps existing owner, management, project and system paths.
-- It removes only the legacy worker-credential shortcut and fail-closes
-- unknown visibility values instead of trusting broad farm membership.
-- Historical assignments and rows are preserved (no UPDATE/DELETE).
-- This change MUST be validated with signed genuine Auth/REST + installed
-- schema clone before deployment; it may narrow historic farm-hand reads.
--
-- Fingerprint prevents replacing a concurrently revised source authority.
DO $drift$
DECLARE v_existing text;
BEGIN
 IF to_regprocedure('atlas.can_read_rhythm_state_v1(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Existing raw Rhythm state disclosure function missing'
     USING ERRCODE='23514';
 END IF;
 SELECT md5(pg_catalog.pg_get_functiondef(
   'atlas.can_read_rhythm_state_v1(uuid)'::regprocedure))
 INTO v_existing;
 IF v_existing <> '2b7d7019230d0a9bf172e5e1b3224db3' THEN
   RAISE EXCEPTION 'Raw Rhythm read source changed; reconcile before cutover'
     USING ERRCODE='23514';
 END IF;
END;
$drift$;

CREATE OR REPLACE FUNCTION atlas.can_read_rhythm_state_v1(p_state_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas'
AS $gate$
 SELECT coalesce((
   SELECT CASE s.visibility_scope
     WHEN 'owner' THEN atlas.is_farm_owner(s.farm_id)
     WHEN 'management' THEN atlas.is_farm_manager_or_owner(s.farm_id)
     -- Raw Rhythm state contains full metadata, timings and source details.
     -- Neither historic farm_hand status nor assigned_user_id alone
     -- proves current native Ledger/Subject disclosure for the exact Person.
     -- Connected Persons use bounded source-disclosed original Work readers.
     WHEN 'assigned_worker' THEN atlas.is_farm_manager_or_owner(s.farm_id)
     WHEN 'project_shared' THEN s.subject_kind='project'
       AND atlas.can_read_project(s.subject_id)
     WHEN 'system_internal' THEN atlas.is_farm_owner(s.farm_id)
     -- Unknown/new visibility must not silently restore old farm membership.
     ELSE atlas.is_farm_manager_or_owner(s.farm_id)
   END
   FROM atlas.rhythm_state s WHERE s.id=p_state_id
 ),false);
$gate$;

-- Do not change EXECUTE grants or RLS policies here: the existing
-- atlas.rhythm_state SELECT policy calls this same source function.
-- Do not create an employee seat, blanket Subject grant, or separate reader.
