-- UNI-OPS-01 P3/U2C: HELD overlay on R01's EXISTING protected
-- legacy task admission guard. Does NOT add a competing trigger or new engine.
-- Assemble AFTER R01 #2362's exact original 07 gate and after U1A #2465,
-- U1B #2481. One integrated review must reconcile R02/U2C direct writers.
-- SOURCE ONLY; never run directly against production.
DO $preflight$
BEGIN
 IF pg_catalog.to_regprocedure(
   'atlas.continuing_rhythm_original_work_has_custody_v1(uuid)'
 ) IS NULL OR pg_catalog.to_regprocedure(
   'atlas.guard_continuing_original_rhythm_old_carrier_v1()'
 ) IS NULL OR pg_catalog.to_regclass(
   'atlas.governed_rulebook_versions_v1'
 ) IS NULL OR pg_catalog.to_regclass(
   'atlas.governed_farm_rulebook_scope_versions_v1'
 ) IS NULL OR NOT EXISTS (
   SELECT 1 FROM pg_catalog.pg_trigger
   WHERE tgrelid='atlas.tasks'::regclass
     AND tgname='z_guard_continuing_original_rhythm_old_task_v1'
 ) OR NOT EXISTS (
   SELECT 1 FROM pg_catalog.pg_trigger
   WHERE tgrelid='atlas.planned_work_occurrences'::regclass
     AND tgname='z_guard_continuing_original_rhythm_old_occurrence_v1'
 )
 THEN
  RAISE EXCEPTION 'Pinned R01 legacy duplicate guard and both governed Rulebook sources required';
 END IF;
END;
$preflight$;

-- A governed policy is an immutable historical source fact. Latest paused
-- or retired authority may NOT silently reactivate old automatic task
-- issuance or provide a separate fallback outside the accepted-first U2C.
-- This helper does not adjudicate active policy or authorize an offer.
CREATE FUNCTION atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(
 p_state_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $governed$
 SELECT COALESCE(EXISTS(
   SELECT 1 FROM atlas.rhythm_state s
   WHERE s.id=p_state_id AND s.subject_kind='growing_object'
     AND (
       EXISTS (
         SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1 r
         WHERE r.organization_id=s.organization_id
           AND r.farm_id=s.farm_id
           AND r.source_rule_id=s.rhythm_rule_id
           -- Include latest and historical decisions; retire/paused
           -- NEVER mean "go back to ungoverned legacy auto issuance."
       )
       OR EXISTS (
         SELECT 1 FROM atlas.governed_rulebook_versions_v1 r
         WHERE r.organization_id=s.organization_id
           AND r.subject_entity_id=s.subject_id
           -- No Company/Household normalization or invented Ledger relation.
           -- Same original canonical Subject, regardless of which approved
           -- root's policy history currently wins.
       )
     )
 ),false);
$governed$;
REVOKE ALL ON FUNCTION
 atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Exact owning R01 existing method overlay: its already-guarded native
-- Original source remains first and unchanged. U1 history is now an additional
-- reason to HOLD legacy task creation rather than delegate policy to clock.
CREATE OR REPLACE FUNCTION atlas.ensure_rhythm_task_v1(
  p_state_id uuid,p_target_state text,p_boundary_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','atlas'
AS $body$
DECLARE
  v_state atlas.rhythm_state%ROWTYPE;
BEGIN
  SELECT state.* INTO v_state
  FROM atlas.rhythm_state state WHERE state.id=p_state_id;
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Rhythm state not found.' USING ERRCODE='P0002';
  END IF;

  -- The FIRST canonical original Work is the exact Need's cutover.
  -- Retain the old rhythm clock but suppress future legacy task births from
  -- this scheduled route, including later cycles; only separately observed
  -- condition + authorization may create a new original Work.
  IF atlas.continuing_rhythm_original_work_has_custody_v1(p_state_id)
     OR atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(p_state_id)
  THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','native_original_or_governed_rulebook_has_custody',
      'legacyTaskCreated',false);
  END IF;

  IF v_state.rhythm_key='weed_stewardship'
    AND v_state.subject_kind='growing_object'
    AND NOT atlas.weed_card_allows_ordinary_work_v1(
      v_state.subject_id,
      (coalesce(p_boundary_at,now()) at time zone 'America/Chicago')::date
    )
  THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','physical_weed_need_not_present',
      'objectId',v_state.subject_id,
      'clockState',p_target_state);
  END IF;

  RETURN atlas.ensure_rhythm_task_without_physical_gate_v1(
    p_state_id,p_target_state,p_boundary_at);
END;
$body$;


-- Exact owning R01 existing guard overlay: original trigger attachments are
-- REUSED unchanged. It blocks direct old task/occurrence INSERT under any
-- governed source history. Existing historical rows are NOT modified.
CREATE OR REPLACE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $body$
DECLARE
  v_state uuid;
BEGIN
  IF TG_TABLE_NAME='planned_work_occurrences' THEN
    IF NEW.source_kind IS DISTINCT FROM 'rhythm_state' THEN RETURN NEW; END IF;
    v_state:=NEW.source_id;
  ELSIF TG_TABLE_NAME='tasks' THEN
    -- Live legacy carriers often have generated_from NULL and use only
    -- metadata.rhythm_state_id plus an occurrence; do NOT rely on the
    -- generated_from value or an unrelated generated_from_id.
    v_state:=atlas.rhythm_safe_uuid_v1(
      NEW.metadata->>'rhythm_state_id');
    IF v_state IS NULL AND NEW.planned_occurrence_id IS NOT NULL THEN
      SELECT o.source_id INTO v_state
      FROM atlas.planned_work_occurrences o
      WHERE o.id=NEW.planned_occurrence_id
        AND o.source_kind='rhythm_state';
    END IF;
    IF v_state IS NULL AND NEW.generated_from='rhythm_clock' THEN
      SELECT s.id INTO v_state FROM atlas.rhythm_state s
      WHERE s.id=NEW.generated_from_id;
    END IF;
  ELSE RETURN NEW;
  END IF;
  IF v_state IS NOT NULL
     AND (
       atlas.continuing_rhythm_original_work_has_custody_v1(v_state)
       OR atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(v_state)
     ) THEN
    RAISE EXCEPTION 'Legacy rhythm task carrier held by native original or adopted Rulebook'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;


-- Existing client ACLs/trigger gates preserved; no additional public grant.
REVOKE ALL ON FUNCTION
 atlas.guard_continuing_original_rhythm_old_carrier_v1()
 FROM PUBLIC,anon,authenticated,service_role;
