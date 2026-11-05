-- Exact-source compatibility gate for the currently scheduled legacy clock.
-- This does NOT change unrelated rhythms or erase old task/history records.
-- Source snapshot: atlas.ensure_rhythm_task_v1 md5
-- d195ec2ccf9b36858cba9c5bfbfb2724 on 2026-10-28.
-- Verify this fingerprint before replacing in protected clone and prior to
-- any production release; direct legacy helper entrypoints are separately
-- covered by the insert admission guards below.
CREATE OR REPLACE FUNCTION atlas.continuing_rhythm_original_work_has_custody_v1(
  p_state_id uuid
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $body$
  SELECT COALESCE(p_state_id IS NOT NULL AND EXISTS(
    SELECT 1 FROM atlas.rhythm_state s
    JOIN atlas.work_items w ON w.organization_id=s.organization_id
      AND w.source_object_type='rhythm_state'
      AND w.source_object_id=s.id
      AND w.metadata->>'sourceContract'='continuing_original_work_v1'
    WHERE s.id=p_state_id
  ),false);
$body$;
REVOKE ALL ON FUNCTION atlas.continuing_rhythm_original_work_has_custody_v1(
  uuid
) FROM PUBLIC, anon, authenticated, service_role;

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
  IF atlas.continuing_rhythm_original_work_has_custody_v1(p_state_id) THEN
    RETURN jsonb_build_object(
      'taskId',NULL,'occurrenceId',NULL,
      'action','canonical_original_work_has_custody',
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

-- A source-owned DEFENSE-IN-DEPTH gate covers *direct* legacy task and
-- planned-occurrence insert paths not routed through ensure_rhythm_task_v1.
-- This intentionally rejects an attempted duplicate rather than silently
-- creating ambiguous history. Legacy direct writer callers may need to
-- handle the explicit cutover exception; release tests must prove no
-- uncontrolled tick retry/error churn before this source can be deployed.
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
     AND atlas.continuing_rhythm_original_work_has_custody_v1(v_state) THEN
    RAISE EXCEPTION 'Legacy rhythm task carrier cannot be created after native original Work custody'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$body$;

CREATE TRIGGER z_guard_continuing_original_rhythm_old_task_v1
BEFORE INSERT ON atlas.tasks FOR EACH ROW
EXECUTE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1();

CREATE TRIGGER z_guard_continuing_original_rhythm_old_occurrence_v1
BEFORE INSERT ON atlas.planned_work_occurrences FOR EACH ROW
EXECUTE FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1();

REVOKE ALL ON FUNCTION atlas.guard_continuing_original_rhythm_old_carrier_v1()
FROM PUBLIC, anon, authenticated, service_role;
