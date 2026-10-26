BEGIN;
-- Same original atlas.household_rhythms, not a new scheduler or task system.
-- An author-controlled metadata flag cannot substitute for this authorized
-- immutable decision history. Requires household canonical guards candidate.
CREATE TABLE atlas.household_rhythm_explicit_decisions_v1 (
 decision_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 decision_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
 household_id uuid NOT NULL REFERENCES atlas.households(id) ON DELETE RESTRICT,
 rhythm_id uuid NOT NULL REFERENCES atlas.household_rhythms(id) ON DELETE RESTRICT,
 instance_id uuid NOT NULL REFERENCES atlas.household_kernel_instances(id) ON DELETE RESTRICT,
 decision_kind text NOT NULL CHECK(decision_kind IN ('establish','withdraw')),
 qualifying_event text NOT NULL CHECK(qualifying_event='wash_started'),
 renew_after_days integer CHECK(renew_after_days BETWEEN 1 AND 365),
 source_action_id uuid NOT NULL,
 decision_reason text NOT NULL CHECK(length(btrim(decision_reason)) BETWEEN 12 AND 1200),
 governor_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT household_rhythm_explicit_action_once_v1 UNIQUE(household_id,source_action_id),
 CONSTRAINT household_rhythm_decision_value_v1 CHECK(
   (decision_kind='establish' AND renew_after_days IS NOT NULL)
   OR (decision_kind='withdraw' AND renew_after_days IS NULL)
 )
);
CREATE INDEX household_rhythm_decision_latest_v1
 ON atlas.household_rhythm_explicit_decisions_v1(household_id,rhythm_id,decision_seq DESC);
ALTER TABLE atlas.household_rhythm_explicit_decisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.household_rhythm_explicit_decisions_v1
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.guard_household_rhythm_decision_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 RAISE EXCEPTION 'Original Household Rhythm decisions are append-only'
   USING ERRCODE='42501';
END;
$function$;
REVOKE ALL ON FUNCTION atlas.guard_household_rhythm_decision_immutable_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER household_rhythm_decision_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.household_rhythm_explicit_decisions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_household_rhythm_decision_immutable_v1();

CREATE OR REPLACE FUNCTION atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_decision_kind text,
 p_renew_after_days integer,p_decision_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_instance atlas.household_kernel_instances%rowtype;
 v_person uuid;
 v_rhythm atlas.household_rhythms%rowtype;
 v_existing atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_decision atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_latest atlas.household_rhythm_explicit_decisions_v1%rowtype;
 v_expect integer;
 v_key text:='kernel:household.laundry:general';
 v_is_new boolean:=false;
 v_reason text:=nullif(btrim(coalesce(p_decision_reason,'')),'');
BEGIN
 IF p_kernel_instance_id IS NULL OR p_action_id IS NULL
   OR p_decision_kind NOT IN ('establish','withdraw')
   OR (p_decision_kind='establish' AND
      (p_renew_after_days IS NULL OR p_renew_after_days NOT BETWEEN 1 AND 365))
   OR (p_decision_kind='withdraw' AND p_renew_after_days IS NOT NULL)
   OR v_reason IS NULL OR length(v_reason) NOT BETWEEN 12 AND 1200 THEN
  RAISE EXCEPTION 'Explicit bounded Household Rhythm decision required'
   USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_instance FROM atlas.household_kernel_instances
 WHERE id=p_kernel_instance_id AND kernel_key='household.laundry'
   AND state='active';
 IF v_instance.id IS NULL THEN
  RAISE EXCEPTION 'Original Laundry Subject not admitted' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.require_household_governor_self_v1(v_instance.household_id);
 PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.household.laundry.explicit_rhythm:'||v_instance.household_id::text,0));
 SELECT * INTO v_existing FROM atlas.household_rhythm_explicit_decisions_v1
 WHERE household_id=v_instance.household_id AND source_action_id=p_action_id;
 IF v_existing.decision_id IS NOT NULL THEN
   IF v_existing.instance_id IS DISTINCT FROM v_instance.id
      OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
      OR v_existing.renew_after_days IS DISTINCT FROM p_renew_after_days
      OR v_existing.decision_reason IS DISTINCT FROM v_reason
      OR v_existing.governor_person_id IS DISTINCT FROM v_person THEN
      RAISE EXCEPTION 'Rhythm decision ID previously used for different intent'
       USING ERRCODE='23505';
   END IF;
   v_decision:=v_existing;
 ELSE
   SELECT * INTO v_rhythm FROM atlas.household_rhythms
   WHERE household_id=v_instance.household_id AND stable_key=v_key FOR UPDATE;
   IF p_decision_kind='withdraw' AND v_rhythm.id IS NULL THEN
     RAISE EXCEPTION 'No original Household Rhythm to withdraw'
       USING ERRCODE='23514';
   END IF;
   IF p_decision_kind='establish' THEN
     v_expect:=CASE WHEN
       (v_instance.configuration->>'expectedMinutes') ~ '^[1-9][0-9]{0,3}$'
       THEN (v_instance.configuration->>'expectedMinutes')::integer ELSE 45 END;
     INSERT INTO atlas.household_rhythms(
       household_id,stable_key,area,title,cadence_rule,
       next_window_start,next_window_end,expected_minutes,
       protection_level,floor_class,interruptibility,principal_required,
       consequence,reason_for_floor,active,blocks_capacity,metadata)
     VALUES(
       v_instance.household_id,v_key,'laundry','Laundry',
       'every_'||p_renew_after_days::text||'_days',
       NULL,NULL,v_expect,'standard',1,'interruptible',false,
       'An actual laundry cycle may need attention after a prior wash.',
       v_reason,true,false,
       jsonb_build_object('worldKernelKey','household.laundry',
        'explicitRhythmDecision',true,'qualifyingEvent','wash_started',
        'renewAfterDays',p_renew_after_days,
        'source','household_laundry_explicit_rhythm_decision_v1'))
     ON CONFLICT(household_id,stable_key) DO UPDATE SET
       cadence_rule=excluded.cadence_rule,
       next_window_start=NULL,next_window_end=NULL,
       expected_minutes=excluded.expected_minutes,
       protection_level='standard',floor_class=1,principal_required=false,
       blocks_capacity=false,active=true,
       reason_for_floor=excluded.reason_for_floor,
       metadata=atlas.household_rhythms.metadata||excluded.metadata,
       updated_at=now()
     RETURNING * INTO v_rhythm;
   ELSE
     UPDATE atlas.household_rhythms
       SET active=false,blocks_capacity=false,principal_required=false,
          next_window_start=NULL,next_window_end=NULL,
          metadata=metadata||jsonb_build_object(
            'explicitRhythmDecision',false,
            'source','household_laundry_explicit_rhythm_decision_v1'),
          updated_at=now()
     WHERE id=v_rhythm.id RETURNING * INTO v_rhythm;
   END IF;
   INSERT INTO atlas.household_rhythm_explicit_decisions_v1(
     household_id,rhythm_id,instance_id,decision_kind,qualifying_event,
     renew_after_days,source_action_id,decision_reason,governor_person_id)
   VALUES (
     v_instance.household_id,v_rhythm.id,v_instance.id,p_decision_kind,
     'wash_started',p_renew_after_days,p_action_id,v_reason,v_person
   ) RETURNING * INTO v_decision;
   v_is_new:=true;
 END IF;
 SELECT * INTO v_latest FROM atlas.household_rhythm_explicit_decisions_v1
 WHERE household_id=v_instance.household_id AND rhythm_id=v_decision.rhythm_id
 ORDER BY decision_seq DESC LIMIT 1;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','household_laundry_explicit_rhythm_decision_v1',
   'householdId',v_instance.household_id,'instanceId',v_instance.id,
   'rhythmId',v_decision.rhythm_id,'decisionId',v_decision.decision_id,
   'actionId',p_action_id,'decisionKind',p_decision_kind,
   'renewAfterDays',p_renew_after_days,
   'currentlyEstablished',v_latest.decision_kind='establish',
   'isGovernedByOriginalDecision',true,
   'automaticCalibrationRhythmCreated',false,
   'workCreated',false,'idempotent',NOT v_is_new);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 p_kernel_instance_id uuid,p_action_id uuid,p_decision_kind text,
 p_renew_after_days integer,p_decision_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.household_laundry_explicit_rhythm_decide_self_api_v1(
 p_kernel_instance_id,p_action_id,p_decision_kind,p_renew_after_days,p_decision_reason);
$function$;
REVOKE ALL ON FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.household_laundry_explicit_rhythm_decide_self_api_v1(
 uuid,uuid,text,integer,text) TO authenticated;
COMMIT;
