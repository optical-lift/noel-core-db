-- LOCAL ONLY / FIRST-PARTY PHYSICAL RESULT SYNTHETIC SMOKE
-- EXACT candidate 02 physical actual writer + candidate 04 source guards.
-- Source table fixtures and authorization helpers are FAKE, not production.
-- This does NOT prove real Supabase signed session, native Ledger, or trigger
-- projection correctness; those must be tested against a protected full clone.
-- ROLLBACK discards all fictional schemas, rows, policies and roles.
BEGIN;
DO $guard$
BEGIN
 IF current_database()<>'atlas_test'
 OR current_setting('server_version_num')::integer<170000
 OR to_regnamespace('atlas') IS NOT NULL
 OR to_regnamespace('auth') IS NOT NULL
 THEN RAISE EXCEPTION 'REFUSED: requires empty local atlas_test with PG17'; END IF;
END;$guard$;
CREATE SCHEMA atlas;
CREATE SCHEMA auth;
DO $roles$
DECLARE n text;
BEGIN
 FOREACH n IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=n) THEN
   EXECUTE format('CREATE ROLE %I NOLOGIN',n);
  END IF;
 END LOOP;
END;$roles$;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE SET search_path TO ''
AS $a$SELECT NULLIF(current_setting('atlas_test.auth_uid',true),'')::uuid$a$;
-- Synthetic signed-person identity matches fake Auth only in this test.
CREATE FUNCTION atlas.current_person_id_v1() RETURNS uuid
LANGUAGE sql STABLE SET search_path TO ''
AS $a$SELECT auth.uid()$a$;
CREATE FUNCTION atlas.rhythm_safe_uuid_v1(p_value text) RETURNS uuid
LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $a$
BEGIN
 IF p_value IS NULL OR p_value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RETURN NULL;END IF;
 RETURN p_value::uuid;
END;$a$;
-- Bounded fictional disclosure: it deliberately does NOT prove real RLS.
CREATE FUNCTION atlas.person_original_work_identity_disclosed_self_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_person_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $a$
SELECT auth.uid() IS NOT NULL
 AND p_person_id=auth.uid()
 AND p_organization_id='72000000-0000-4000-8000-000000000001'::uuid
 AND p_ledger_id='72000000-0000-4000-8000-000000000002'::uuid
 AND p_work_item_id='72000000-0000-4000-8000-000000000009'::uuid
 AND p_person_id='72000000-0000-4000-8000-000000000003'::uuid
$a$;
CREATE FUNCTION atlas.rhythm_boundary_at_v1(
 p_start timestamptz,p_seconds integer,p_tz text,p_boundary text
) RETURNS timestamptz
LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $a$SELECT p_start+make_interval(secs=>p_seconds)$a$;

CREATE TABLE atlas.work_result_contract_policies(
 contract_key text PRIMARY KEY, source_domain text, acceptance_mode text,
 active boolean, description text, metadata jsonb
);
CREATE TABLE atlas.work_items(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,
 household_id uuid,source_object_type text,source_object_id uuid,
 result_contract_key text,work_state text,metadata jsonb DEFAULT '{}'::jsonb,
 completed_at timestamptz,updated_at timestamptz DEFAULT now()
);
CREATE TABLE atlas.work_allocations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,
 work_item_id uuid,allocation_role text,establishment_basis_kind text,
 assignee_canonical_person_id uuid,state text,establishment_basis jsonb,
 allocated_at timestamptz DEFAULT now(),completed_at timestamptz,
 updated_at timestamptz DEFAULT now()
);
CREATE TABLE atlas.company_work_native_ledger_relevance(
 organization_id uuid,work_item_id uuid,ledger_id uuid,attribution_state text
);
CREATE TABLE atlas.work_item_context_links(
 organization_id uuid,work_item_id uuid,subject_domain text,
 subject_kind text,subject_id uuid,relation_kind text
);
CREATE TABLE atlas.rhythm_rules(
 id uuid PRIMARY KEY,status text,qualifying_touches jsonb,
 validity_interval_seconds integer,warning_window_seconds integer,
 grace_window_seconds integer,metadata jsonb
);
CREATE TABLE atlas.rhythm_bindings(
 id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,
 rhythm_rule_id uuid,active boolean
);
CREATE TABLE atlas.rhythm_state(
 id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,
 subject_kind text,subject_id uuid,rhythm_binding_id uuid,
 rhythm_rule_id uuid,rhythm_key text,state text,
 last_qualifying_satisfaction_id uuid,lease_started_at timestamptz,
 warning_at timestamptz,due_at timestamptz,failure_at timestamptz,
 recovery_started_at timestamptz,last_evaluated_at timestamptz,
 last_transition_at timestamptz,state_reason jsonb,
 updated_at timestamptz DEFAULT now()
);
CREATE TABLE atlas.growing_objects(id uuid PRIMARY KEY,farm_id uuid);
CREATE TABLE atlas.weed_cards(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),object_id uuid,farm_id uuid,
 created_at timestamptz DEFAULT now(),current_condition text,
 last_session_at timestamptz,next_review_on date,
 metadata jsonb DEFAULT '{}'::jsonb,updated_at timestamptz DEFAULT now()
);
CREATE TABLE atlas.mowing_area_state(
 object_id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,status text,
 last_observed_at timestamptz,last_mowed_at timestamptz,next_check_date date,
 note text,metadata jsonb DEFAULT '{}'::jsonb,updated_at timestamptz DEFAULT now()
);
CREATE TABLE atlas.care_current_state(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),scope_kind text,
 scope_id uuid,subject_domain text,subject_kind text,subject_id text,
 condition_state text,last_observed_at timestamptz,last_observation_id uuid,
 UNIQUE(scope_kind,scope_id,subject_domain,subject_kind,subject_id)
);
CREATE TABLE atlas.care_result_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),subject_domain text,
 subject_kind text,subject_id text,scope_kind text,scope_id uuid,
 occurred_at timestamptz,result_kind text,condition_before text,
 condition_after text,minutes integer,minutes_known boolean,
 actor_user_id uuid,source_kind text,source_key text,note text,
 metadata jsonb DEFAULT '{}'::jsonb
);
CREATE TABLE atlas.care_observation_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),subject_domain text,
 subject_kind text,subject_id text,scope_kind text,scope_id uuid,
 observed_at timestamptz,condition_state text,disposition text,
 observed_by_user_id uuid,source_kind text,source_key text,note text,
 inferred_from_clock boolean,metadata jsonb DEFAULT '{}'::jsonb
);
-- Mimics the existing observation-to-current-source projector for this
-- fictional fixture ONLY. This is explicitly not production projection code.
CREATE FUNCTION atlas.synthetic_observation_to_current_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $p$
BEGIN
 INSERT INTO atlas.care_current_state(
  scope_kind,scope_id,subject_domain,subject_kind,subject_id,
  condition_state,last_observed_at,last_observation_id
 ) VALUES(
  NEW.scope_kind,NEW.scope_id,NEW.subject_domain,NEW.subject_kind,
  NEW.subject_id,NEW.condition_state,NEW.observed_at,NEW.id
 ) ON CONFLICT(scope_kind,scope_id,subject_domain,subject_kind,subject_id)
 DO UPDATE SET condition_state=EXCLUDED.condition_state,
  last_observed_at=EXCLUDED.last_observed_at,
  last_observation_id=EXCLUDED.last_observation_id;
 RETURN NEW;
END;
$p$;
CREATE TRIGGER synthetic_observation_to_current_v1
AFTER INSERT ON atlas.care_observation_events FOR EACH ROW
EXECUTE FUNCTION atlas.synthetic_observation_to_current_v1();
CREATE TABLE atlas.work_execution_results(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,
 household_id uuid,work_item_id uuid,responsible_allocation_id uuid,
 reported_by_user_id uuid,result_kind text,result_contract_key text,
 idempotency_key text,payload jsonb,metadata jsonb,reported_at timestamptz,
 UNIQUE(organization_id,idempotency_key)
);
CREATE TABLE atlas.work_result_acceptances(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,
 household_id uuid,work_item_id uuid,execution_result_id uuid,
 decision text,acceptance_kind text,accepted_by_domain text,evidence jsonb
);
CREATE TABLE atlas.rhythm_satisfactions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,farm_id uuid,
 rhythm_state_id uuid,rhythm_binding_id uuid,rhythm_rule_id uuid,rhythm_key text,
 subject_kind text,subject_id uuid,satisfaction_key text,
 satisfaction_kind text,satisfied_at timestamptz,renewal_interval_seconds integer,
 source_kind text,source_id uuid,source_event text,policy_match jsonb,evidence jsonb,
 created_by_user_id uuid
);
-- Source-aligned FICTIONAL bed, rhythm, native Person and original Work.
INSERT INTO atlas.growing_objects VALUES (
 '72000000-0000-4000-8000-000000000005',
 '72000000-0000-4000-8000-000000000004'
);
INSERT INTO atlas.rhythm_rules VALUES(
 '72000000-0000-4000-8000-000000000007','active',
 '[{"effect":"full","sourceKind":"object","sourceEvent":"weeded_reset"},
   {"effect":"partial","sourceKind":"object","sourceEvent":"weeded",
    "payloadContains":{"metadata":{"transition":"partial"}}}]'::jsonb,
 604800,86400,172800,'{"timezoneName":"America/Chicago"}'::jsonb
);
INSERT INTO atlas.rhythm_bindings VALUES (
 '72000000-0000-4000-8000-000000000008',
 '72000000-0000-4000-8000-000000000001',
 '72000000-0000-4000-8000-000000000004',
 '72000000-0000-4000-8000-000000000007',true
);
INSERT INTO atlas.rhythm_state(
 id,organization_id,farm_id,subject_kind,subject_id,rhythm_binding_id,
 rhythm_rule_id,rhythm_key,state
) VALUES(
 '72000000-0000-4000-8000-000000000006',
 '72000000-0000-4000-8000-000000000001',
 '72000000-0000-4000-8000-000000000004',
 'growing_object','72000000-0000-4000-8000-000000000005',
 '72000000-0000-4000-8000-000000000008',
 '72000000-0000-4000-8000-000000000007','weed_stewardship','due'
);
INSERT INTO atlas.weed_cards(
 id,object_id,farm_id,current_condition
) VALUES(
 '72000000-0000-4000-8000-000000000011',
 '72000000-0000-4000-8000-000000000005',
 '72000000-0000-4000-8000-000000000004','heavy'
);
INSERT INTO atlas.care_current_state(
 scope_kind,scope_id,subject_domain,subject_kind,subject_id,condition_state,
 last_observed_at
) VALUES(
 'farm','72000000-0000-4000-8000-000000000004',
 'farm','growing_object','72000000-0000-4000-8000-000000000005',
 'heavy',now()-interval '1 day'
);
INSERT INTO atlas.work_items(
 id,organization_id,source_object_type,source_object_id,result_contract_key,
 work_state,metadata
) VALUES(
 '72000000-0000-4000-8000-000000000009',
 '72000000-0000-4000-8000-000000000001','rhythm_state',
 '72000000-0000-4000-8000-000000000006',
 'continuing_care_actual_v1','open',
 '{"sourceContract":"continuing_original_work_v1"}'::jsonb
);
INSERT INTO atlas.work_allocations(
 id,organization_id,work_item_id,allocation_role,establishment_basis_kind,
 assignee_canonical_person_id,state,establishment_basis
) VALUES(
 '72000000-0000-4000-8000-000000000010',
 '72000000-0000-4000-8000-000000000001',
 '72000000-0000-4000-8000-000000000009','responsible',
 'delegated_under_standing_scope',
 '72000000-0000-4000-8000-000000000003','active',
 '{"nativeLedgerId":"72000000-0000-4000-8000-000000000002"}'::jsonb
);
INSERT INTO atlas.company_work_native_ledger_relevance VALUES(
 '72000000-0000-4000-8000-000000000001',
 '72000000-0000-4000-8000-000000000009',
 '72000000-0000-4000-8000-000000000002','active'
);
INSERT INTO atlas.work_item_context_links VALUES(
 '72000000-0000-4000-8000-000000000001',
 '72000000-0000-4000-8000-000000000009',
 'spatial','growing_object',
 '72000000-0000-4000-8000-000000000005','acts_on'
);

-- EXACT SOURCE ADAPTER FROM 97b1486a807ee01328c682af49fcd6b7db46f64e
-- DRAFT SOURCE CANDIDATE; requires protected-clone signed positive/negative tests.
-- This is a DOMAIN ADAPTER using universal original Work/Result/Continuation.
-- It DOES NOT create a farm task generator, legacy task, employee seat,
-- new canonical Work store, scheduled task, or automatic next original Work.
-- Apply only after candidate.sql in an isolated, authorized validation clone.
--
-- The existing Household Laundry adapter continues independently under its
-- exact source and Result guard. No generic client is allowed to invent a
-- "source-qualified" Work Result merely by passing a JSON payload.

INSERT INTO atlas.work_result_contract_policies(
  contract_key,source_domain,acceptance_mode,active,description,metadata
)
VALUES(
  'continuing_care_actual_v1','organization','domain_adapter',true,
  'Authenticated original responsible Person reports actual care against a governed continuing Need and physical Subject',
  jsonb_build_object(
    'continuingActualQualification','source_proven_v1',
    'requiresOriginalWork',true,'requiresExactSubject',true,
    'requiresAcceptedNativePerson',true,
    'clockDoesNotAssertCondition',true,
    'noAutogeneratedNextWork',true)
)
ON CONFLICT (contract_key) DO NOTHING;
-- Never overwrite an existing policy with different trust semantics.
DO $policy$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM atlas.work_result_contract_policies p
    WHERE p.contract_key='continuing_care_actual_v1'
      AND p.source_domain='organization' AND p.acceptance_mode='domain_adapter'
      AND p.active
      AND p.metadata->>'continuingActualQualification'='source_proven_v1'
  ) THEN
    RAISE EXCEPTION 'Care Actual contract policy does not match required source qualification';
  END IF;
END;
$policy$;

CREATE OR REPLACE FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  p_work_item_id uuid,
  p_action_id uuid,
  p_actual_kind text,
  p_condition_after text,
  p_minutes integer DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_recheck_on date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $actual$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_allocation atlas.work_allocations%ROWTYPE;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_weed atlas.weed_cards%ROWTYPE;
  v_mowing atlas.mowing_area_state%ROWTYPE;
  v_prior atlas.care_current_state%ROWTYPE;
  v_result atlas.work_execution_results%ROWTYPE;
  v_care uuid;
  v_observation uuid;
  v_acceptance uuid;
  v_satisfaction uuid;
  v_actor uuid;
  v_ledger_id uuid;
  v_source_key text;
  v_kind text := nullif(btrim(coalesce(p_actual_kind,'')),'');
  v_after text := nullif(btrim(coalesce(p_condition_after,'')),'');
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_before text;
  v_effect text;
  v_result_kind text;
  v_care_kind text;
  v_source_kind text;
  v_source_event text;
  v_touch jsonb;
  v_touch_index integer;
  v_renew_seconds integer;
  v_warning_at timestamptz;
  v_due_at timestamptz;
  v_failure_at timestamptz;
  v_tz text;
  v_boundary text;
  v_at timestamptz:=clock_timestamp();
BEGIN
  v_actor:=atlas.current_person_id_v1();
  IF auth.uid() IS NULL OR v_actor IS NULL OR p_work_item_id IS NULL
     OR p_action_id IS NULL OR v_kind IS NULL OR v_after IS NULL
     OR length(v_after)>120 OR length(coalesce(v_note,''))>1500
     OR (p_minutes IS NOT NULL AND (p_minutes<0 OR p_minutes>1440))
     OR (p_recheck_on IS NOT NULL AND p_recheck_on < (now()::date - 1))
  THEN
    RAISE EXCEPTION 'Exact signed physical Work Actual and valid observation required'
      USING ERRCODE='22023';
  END IF;
  v_source_key:='continuing-care-actual:'||p_work_item_id||':'||p_action_id;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-care-actual:'||p_work_item_id::text,0));
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL
    OR v_work.source_object_type<>'rhythm_state'
    OR v_work.result_contract_key<>'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract' IS DISTINCT FROM 'continuing_original_work_v1'
  THEN
    RAISE EXCEPTION 'Original governed continuing Work is not available'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible'
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      AND a.assignee_canonical_person_id=v_actor
      AND a.state IN ('active','completed')
    ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
  IF v_allocation.id IS NULL
    OR coalesce(v_allocation.establishment_basis->>'nativeLedgerId','')
        !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  THEN
    RAISE EXCEPTION 'Real native-Ledger responsible Person required'
      USING ERRCODE='42501';
  END IF;
  v_ledger_id:=(v_allocation.establishment_basis->>'nativeLedgerId')::uuid;
  IF NOT atlas.person_original_work_identity_disclosed_self_v1(
        v_work.organization_id,v_ledger_id,v_work.id,v_actor)
    OR NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.work_item_id=v_work.id
        AND rel.organization_id=v_work.organization_id
        AND rel.ledger_id=v_ledger_id AND rel.attribution_state='active'
    )
  THEN
    RAISE EXCEPTION 'Original Work source and physical Subject are not disclosed'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=v_work.source_object_id
      AND s.organization_id=v_work.organization_id
      AND s.subject_kind='growing_object' FOR UPDATE;
  IF v_state.id IS NULL OR NOT EXISTS(
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.organization_id=v_work.organization_id AND l.work_item_id=v_work.id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on'
    ) THEN
    RAISE EXCEPTION 'Original Work is not linked to this exact physical Subject'
      USING ERRCODE='23514';
  END IF;
  -- Replays must survive a later rule retirement/physical state change;
  -- first confirm the same signed Person, original Subject and exact receipt.
  -- Authorize before replay, so a different Person cannot use the idempotency
  -- key to read someone else's Work Result.
  SELECT * INTO v_result FROM atlas.work_execution_results er
    WHERE er.organization_id=v_work.organization_id
      AND er.idempotency_key=v_source_key;
  IF v_result.id IS NOT NULL THEN
    IF v_result.work_item_id<>v_work.id
      OR v_result.reported_by_user_id IS DISTINCT FROM auth.uid()
      OR v_result.metadata->>'actualKind' IS DISTINCT FROM v_kind
      OR v_result.payload->>'conditionAfter' IS DISTINCT FROM v_after
      OR v_result.payload->>'note' IS DISTINCT FROM v_note
      OR v_result.payload->>'minutes' IS DISTINCT FROM p_minutes::text
      OR v_result.payload->>'recheckOn' IS DISTINCT FROM p_recheck_on::text
      OR NOT EXISTS(
        SELECT 1 FROM atlas.work_result_acceptances a
        WHERE a.organization_id=v_work.organization_id
          AND a.work_item_id=v_work.id AND a.execution_result_id=v_result.id
          AND a.decision='accepted' AND a.acceptance_kind='source_qualified_physical_actual'
      )
    THEN
      RAISE EXCEPTION 'Existing physical Actual does not match original signed action'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'idempotent',true,
      'contractVersion','continuing_care_actual_v1',
      'workItemId',v_work.id,'workResultId',v_result.id,'workState',v_work.work_state,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;


  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.organization_id=v_work.organization_id AND b.farm_id=v_state.farm_id
      AND b.active AND r.status='active';
  IF v_rule.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.growing_objects g
      WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id
    )
  THEN
    RAISE EXCEPTION 'Source cannot verify a current allowed care policy'
      USING ERRCODE='23514';
  END IF;

  -- No "generic done": source event type, effect, and postcondition are
  -- explicitly interpreted by the owning domain. Other domains plug in
  -- their own adapters, without changing the Work/Result lifecycle.
  IF v_state.rhythm_key='mowing' THEN
    SELECT * INTO v_mowing FROM atlas.mowing_area_state m
      WHERE m.object_id=v_state.subject_id
        AND m.organization_id=v_work.organization_id
        AND m.farm_id=v_state.farm_id FOR UPDATE;
    IF v_mowing.object_id IS NULL THEN
      RAISE EXCEPTION 'Mowing source state missing' USING ERRCODE='23514';
    END IF;
    v_source_kind:='mowing_result';v_source_event:=v_kind;
    CASE v_kind
      WHEN 'mowed_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        IF v_after<>'resting' THEN
          RAISE EXCEPTION 'Full mowing must report the resting condition' USING ERRCODE='22023';
        END IF;
      WHEN 'mowed_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        IF v_after<>'partial' THEN
          RAISE EXCEPTION 'Partial mowing must retain unfinished condition' USING ERRCODE='22023';
        END IF;
      WHEN 'acceptable_no_cut' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        IF v_after<>'acceptable' THEN
          RAISE EXCEPTION 'No-cut is an observed acceptable condition, not a mow' USING ERRCODE='22023';
        END IF;
      WHEN 'too_wet' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'too_wet' THEN RAISE EXCEPTION 'Wet-ground block must be observed' USING ERRCODE='22023'; END IF;
      WHEN 'equipment_or_area_problem' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after<>'problem' THEN RAISE EXCEPTION 'Equipment/area problem must be observed' USING ERRCODE='22023'; END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified mowing Actual kind' USING ERRCODE='22023';
    END CASE;
  ELSE
    SELECT * INTO v_weed FROM atlas.weed_cards c
      WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      ORDER BY c.created_at,c.id LIMIT 1 FOR UPDATE;
    IF v_weed.id IS NULL THEN
      RAISE EXCEPTION 'Weed stewardship source state missing' USING ERRCODE='23514';
    END IF;
    CASE v_kind
      WHEN 'weeded_full' THEN
        v_effect:='full';v_result_kind:='completed';v_care_kind:='recovered';
        v_source_kind:='object';v_source_event:='weeded_reset';
        IF v_after<>'clear' THEN
          RAISE EXCEPTION 'Full weed restoration requires observed clear condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeded_partial' THEN
        v_effect:='partial';v_result_kind:='partial';v_care_kind:='improved_more_remains';
        v_source_kind:='object';v_source_event:='weeded';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy') THEN
          RAISE EXCEPTION 'Partial weed work must preserve residual condition' USING ERRCODE='22023';
        END IF;
      WHEN 'inspection_acceptable' THEN
        v_effect:='conditional';v_result_kind:='completed';v_care_kind:='condition_differed';
        v_source_kind:='field_log';v_source_event:='action:weed_inspection_acceptable';
        IF v_after NOT IN ('clear','row_readable') THEN
          RAISE EXCEPTION 'Acceptable weed inspection must preserve observed condition' USING ERRCODE='22023';
        END IF;
      WHEN 'weeding_blocked' THEN
        v_effect:='blocked';v_result_kind:='blocked';v_care_kind:='blocked';
        IF v_after NOT IN ('row_readable','medium_pressure','heavy','unknown') THEN
          RAISE EXCEPTION 'Blocked weeding must preserve real condition' USING ERRCODE='22023';
        END IF;
      ELSE
        RAISE EXCEPTION 'Unqualified weed Actual kind' USING ERRCODE='22023';
    END CASE;
  END IF;

  -- Reject invented success when the configured Rhythm doesn't recognize
  -- the submitted domain event and its effect. Blockers are evidence only.
  IF v_effect IN ('full','partial','conditional') THEN
    SELECT t.value,(t.ordinality)::integer
      INTO v_touch,v_touch_index
    FROM pg_catalog.jsonb_array_elements(v_rule.qualifying_touches)
      WITH ORDINALITY AS t(value,ordinality)
    WHERE t.value->>'effect'=v_effect
      AND t.value->>'sourceKind'=v_source_kind
      AND (
        t.value->>'sourceEvent'=v_source_event
        OR t.value->'sourceEvents' ? v_source_event
      )
      AND (
        v_kind<>'weeded_partial'
        OR t.value#>>'{payloadContains,metadata,transition}'='partial'
      )
    ORDER BY t.ordinality LIMIT 1;
    IF v_touch IS NULL THEN
      RAISE EXCEPTION 'Result does not match original governed Rhythm rule'
        USING ERRCODE='23514';
    END IF;
  END IF;

  IF v_work.work_state<>'open' OR v_allocation.state<>'active'
    OR v_state.state='paused' OR v_rule.status<>'active' THEN
    RAISE EXCEPTION 'Original Work or active Rhythm is no longer actionable'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_prior FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  v_before:=COALESCE(v_prior.condition_state,
     CASE WHEN v_state.rhythm_key='mowing' THEN v_mowing.status
          ELSE v_weed.current_condition END);
  IF v_prior.id IS NOT NULL AND v_prior.last_observed_at>v_at THEN
    RAISE EXCEPTION 'Newer physical observation must be reconciled first' USING ERRCODE='23514';
  END IF;
  -- No ordinary mowing is issued from a stale rhythm state. That condition
  -- gate lives at Work creation, not this legitimate worker reporting step.
  -- The worker is signing the *actual*, not a inferred result of the clock.
  INSERT INTO atlas.care_result_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    occurred_at,result_kind,condition_before,condition_after,
    minutes,minutes_known,actor_user_id,source_kind,source_key,note,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,
    'farm',v_state.farm_id,v_at,v_care_kind,v_before,v_after,
    p_minutes,(p_minutes IS NOT NULL),auth.uid(),'continuing_care_actual',
    v_source_key,v_note,
    jsonb_build_object('workItemId',v_work.id,'rhythmStateId',v_state.id,
      'physicalActualKind',v_kind,'sourceRuleId',v_rule.id,
      'actualReportedByPersonId',v_actor)
  ) RETURNING id INTO v_care;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    v_at,v_after,
    CASE WHEN v_effect='blocked' THEN 'hold'
      WHEN v_effect='partial' THEN 'intervene' ELSE 'observe' END,
    auth.uid(),'continuing_care_actual_observation',
    'continuing-care-observation:'||v_care::text,
    v_note,false,
    jsonb_build_object('careResultId',v_care,'workItemId',v_work.id)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state cs
    WHERE cs.scope_kind='farm' AND cs.scope_id=v_state.farm_id
      AND cs.subject_domain='farm' AND cs.subject_kind='growing_object'
      AND cs.subject_id=v_state.subject_id::text
      AND cs.condition_state=v_after AND cs.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Physical source readback failed'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_execution_results(
    organization_id,work_item_id,responsible_allocation_id,
    reported_by_user_id,result_kind,result_contract_key,
    idempotency_key,payload,metadata,reported_at
  ) VALUES(
    v_work.organization_id,v_work.id,v_allocation.id,
    auth.uid(),v_result_kind,'continuing_care_actual_v1',
    v_source_key,
    jsonb_strip_nulls(jsonb_build_object(
      'careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'conditionAfter',v_after,'note',v_note,
      'minutes',p_minutes,'recheckOn',p_recheck_on)),
    jsonb_build_object('actualKind',v_kind,'rhythmStateId',v_state.id,
      'authenticatedReporterPersonId',v_actor,'nativeLedgerId',v_ledger_id),
    v_at
  ) RETURNING * INTO v_result;
  INSERT INTO atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,
    decision,acceptance_kind,accepted_by_domain,evidence
  ) VALUES(
    v_work.organization_id,v_work.id,v_result.id,'accepted',
    'source_qualified_physical_actual','continuing_care_actual',
    jsonb_build_object('careResultId',v_care,'careObservationId',v_observation,
      'actualKind',v_kind,'sourceRuleId',v_rule.id,'actualReporter',v_actor)
  ) RETURNING id INTO v_acceptance;

  IF v_effect IN ('full','conditional') THEN
    v_renew_seconds:=CASE WHEN coalesce(v_touch->>'renewalIntervalSeconds','') ~ '^[1-9][0-9]*$'
      THEN (v_touch->>'renewalIntervalSeconds')::integer
      ELSE v_rule.validity_interval_seconds END;
    v_tz:=coalesce(nullif(v_rule.metadata->>'timezoneName',''),'America/Chicago');
    v_boundary:=coalesce(nullif(v_rule.metadata->>'boundaryMode',''),'exact_timestamp');
    v_warning_at:=atlas.rhythm_boundary_at_v1(v_at,
      greatest(0,v_renew_seconds-v_rule.warning_window_seconds),v_tz,v_boundary);
    v_due_at:=atlas.rhythm_boundary_at_v1(v_at,v_renew_seconds,v_tz,v_boundary);
    v_failure_at:=atlas.rhythm_boundary_at_v1(v_at,
      v_renew_seconds+v_rule.grace_window_seconds,v_tz,v_boundary);
    IF v_state.last_qualifying_satisfaction_id IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM atlas.rhythm_satisfactions old
        WHERE old.id=v_state.last_qualifying_satisfaction_id
          AND old.satisfied_at>v_at
      ) THEN
      RAISE EXCEPTION 'Existing newer satisfaction must not be reversed'
        USING ERRCODE='23514';
    END IF;
    INSERT INTO atlas.rhythm_satisfactions(
      organization_id,farm_id,rhythm_state_id,rhythm_binding_id,rhythm_rule_id,
      rhythm_key,subject_kind,subject_id,satisfaction_key,satisfaction_kind,
      satisfied_at,renewal_interval_seconds,source_kind,source_id,source_event,
      policy_match,evidence,created_by_user_id
    ) VALUES(
      v_state.organization_id,v_state.farm_id,v_state.id,v_state.rhythm_binding_id,
      v_rule.id,v_state.rhythm_key,v_state.subject_kind,v_state.subject_id,
      'continuing-actual:'||v_result.id::text,v_effect,v_at,
      CASE WHEN v_effect='conditional' THEN v_renew_seconds ELSE NULL END,
      'continuing_care_actual',v_care,v_kind,
      jsonb_build_object('touchIndex',v_touch_index,'touch',v_touch,
        'domainActualVerified',true),
      jsonb_build_object('workItemId',v_work.id,'careResultId',v_care,
        'workResultId',v_result.id),
      auth.uid()
    ) RETURNING id INTO v_satisfaction;
    UPDATE atlas.rhythm_state SET state='resting',
      last_qualifying_satisfaction_id=v_satisfaction,
      lease_started_at=v_at,warning_at=v_warning_at,due_at=v_due_at,
      failure_at=v_failure_at,recovery_started_at=NULL,
      last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'satisfactionId',v_satisfaction,
        'actualKind',v_kind),updated_at=now()
    WHERE id=v_state.id;
  ELSIF v_effect='partial' THEN
    -- One still-open original Work; partial progress does not manufacture
    -- another occurrence. The physical state and Actual remain durable.
    UPDATE atlas.rhythm_state SET state='recovering',
      recovery_started_at=v_at,last_evaluated_at=v_at,last_transition_at=v_at,
      state_reason=jsonb_build_object('source','continuing_care_actual',
        'workItemId',v_work.id,'careResultId',v_care,'actualKind',v_kind),
      updated_at=now()
    WHERE id=v_state.id;
  END IF;

  -- Domain projections retain actual route/bed state; other domains provide
  -- their own projections without altering canonical Work/Result machinery.
  IF v_state.rhythm_key='mowing' THEN
    UPDATE atlas.mowing_area_state SET
      status=v_after,last_observed_at=v_at,
      last_mowed_at=CASE WHEN v_kind='mowed_full' THEN v_at ELSE last_mowed_at END,
      next_check_date=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_check_date END,
      -- source_event_id references legacy mowing_events, NOT care_result_events.
      -- Preserve legacy source_event_id; the canonical Actual is in care history.
      note=v_note,metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
        updated_at=now()
    WHERE object_id=v_state.subject_id AND organization_id=v_work.organization_id;
  ELSIF v_effect IN ('full','partial','conditional') THEN
    UPDATE atlas.weed_cards SET
      current_condition=v_after,
      next_review_on=CASE WHEN v_effect IN ('full','conditional')
        THEN v_due_at::date ELSE next_review_on END,
      metadata=coalesce(metadata,'{}'::jsonb)||
        jsonb_strip_nulls(jsonb_build_object(
          'lastCanonicalCareResultId',v_care,
          'lastCanonicalWorkResultId',v_result.id,
          'workerSuggestedRecheckDate',p_recheck_on)),
      last_session_at=v_at,updated_at=now()
    WHERE id=v_weed.id;
  END IF;

  IF v_result_kind='completed' THEN
    UPDATE atlas.work_items SET work_state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_work.id AND work_state='open';
    UPDATE atlas.work_allocations SET state='completed',
      completed_at=v_at,updated_at=now()
    WHERE id=v_allocation.id AND state='active';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','continuing_care_actual_v1',
    'idempotent',false,'workItemId',v_work.id,
    'workResultId',v_result.id,'careResultId',v_care,
    'careObservationId',v_observation,'acceptanceId',v_acceptance,
    'rhythmSatisfactionId',v_satisfaction,
    'workState',CASE WHEN v_result_kind='completed' THEN 'completed' ELSE 'open' END,
    'sourceConditionAfter',v_after,'sourceResultKind',v_care_kind,
    'nextEligibleAt',v_due_at,
    'noNewWorkCreated',true,'noClockAdmission',true);
END;
$actual$;

-- PRE-RELEASE HOLD. Do not grant a domain reporter to authenticated until
-- real native-Person signed positive/negative clone tests + source disclosure
-- coverage pass. Explicitly deny unsafe direct execution for now.
REVOKE ALL ON FUNCTION atlas.record_continuing_care_actual_self_api_v1(
  uuid,uuid,text,text,integer,text,date
) FROM PUBLIC, anon, authenticated, service_role;

-- EXACT SOURCE GUARDS FROM 4983bace4a5ce83c73580316117955b5964a571c
-- DRAFT; must be included AFTER 02_farm_care_actual_adapter.sql.
-- This is a SOURCE EVIDENCE GUARD for one domain adapter, not a new global
-- Work completion regime. Other domains retain their own Result policies.
CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_actual_result_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF NEW.result_contract_key IS DISTINCT FROM 'continuing_care_actual_v1'
  THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NEW.organization_id IS NULL
    OR NEW.household_id IS NOT NULL
    OR NEW.reported_by_user_id IS DISTINCT FROM auth.uid()
    OR NEW.responsible_allocation_id IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM atlas.work_items w
      JOIN atlas.rhythm_state s ON s.id=w.source_object_id
        AND s.organization_id=w.organization_id
      JOIN atlas.work_allocations a ON a.id=NEW.responsible_allocation_id
        AND a.organization_id=w.organization_id
        AND a.work_item_id=w.id
      JOIN atlas.care_result_events c
        ON c.id=atlas.rhythm_safe_uuid_v1(NEW.payload->>'careResultId')
        AND c.scope_kind='farm' AND c.scope_id=s.farm_id
        AND c.subject_domain='farm' AND c.subject_kind='growing_object'
        AND c.subject_id=s.subject_id::text
        AND c.actor_user_id=NEW.reported_by_user_id
        AND c.source_kind='continuing_care_actual'
      WHERE w.id=NEW.work_item_id
        AND w.organization_id=NEW.organization_id
        AND w.source_object_type='rhythm_state'
        AND w.result_contract_key=NEW.result_contract_key
        AND w.work_state='open'
        AND a.allocation_role='responsible' AND a.state='active'
        AND a.assignee_canonical_person_id=atlas.current_person_id_v1()
        AND c.metadata->>'workItemId'=w.id::text
        AND c.metadata->>'rhythmStateId'=s.id::text
        AND c.metadata->>'physicalActualKind'=NEW.payload->>'actualKind'
        AND c.condition_after=NEW.payload->>'conditionAfter'
        AND (
          (NEW.result_kind='completed'
            AND c.result_kind IN ('recovered','condition_differed'))
          OR (NEW.result_kind='partial'
            AND c.result_kind='improved_more_remains')
          OR (NEW.result_kind='blocked'
            AND c.result_kind='blocked')
        )
    )
  THEN
    RAISE EXCEPTION 'Canonical continuing Work Result requires its accepted first-party Actual'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_actual_result_v1
BEFORE INSERT ON atlas.work_execution_results
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_actual_result_v1();

CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_actual_acceptance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM atlas.work_execution_results r
    WHERE r.id=NEW.execution_result_id
      AND r.organization_id=NEW.organization_id
      AND r.work_item_id=NEW.work_item_id
      AND r.result_contract_key='continuing_care_actual_v1'
  ) THEN RETURN NEW; END IF;

  IF auth.uid() IS NULL OR NEW.household_id IS NOT NULL
     OR NEW.decision<>'accepted'
     OR NEW.acceptance_kind<>'source_qualified_physical_actual'
     OR NEW.accepted_by_domain<>'continuing_care_actual'
     OR NOT EXISTS (
       SELECT 1 FROM atlas.work_execution_results r
       JOIN atlas.care_result_events c
         ON c.id=atlas.rhythm_safe_uuid_v1(r.payload->>'careResultId')
       WHERE r.id=NEW.execution_result_id
         AND r.organization_id=NEW.organization_id
         AND r.work_item_id=NEW.work_item_id
         AND r.reported_by_user_id=auth.uid()
         AND c.actor_user_id=r.reported_by_user_id
         AND c.source_kind='continuing_care_actual'
         AND c.metadata->>'workItemId'=NEW.work_item_id::text
         AND NEW.evidence->>'careResultId'=c.id::text
     )
  THEN
    RAISE EXCEPTION 'Continuing Work acceptance requires exact authenticated physical evidence'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_actual_acceptance_v1
BEFORE INSERT ON atlas.work_result_acceptances
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_actual_acceptance_v1();

CREATE OR REPLACE FUNCTION atlas.guard_continuing_care_work_completion_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $guard$
BEGIN
  IF OLD.work_state IS NOT DISTINCT FROM NEW.work_state
     OR NEW.work_state<>'completed'
     OR NEW.result_contract_key IS DISTINCT FROM 'continuing_care_actual_v1'
  THEN RETURN NEW; END IF;

  IF NEW.organization_id IS NULL OR NEW.household_id IS NOT NULL
     OR NOT EXISTS(
       SELECT 1
       FROM atlas.work_execution_results r
       JOIN atlas.work_result_acceptances a ON a.execution_result_id=r.id
         AND a.work_item_id=r.work_item_id AND a.organization_id=r.organization_id
         AND a.decision='accepted'
         AND a.acceptance_kind='source_qualified_physical_actual'
       JOIN atlas.care_result_events c ON
         c.id=atlas.rhythm_safe_uuid_v1(r.payload->>'careResultId')
         AND c.actor_user_id=r.reported_by_user_id
         AND c.source_kind='continuing_care_actual'
       JOIN atlas.rhythm_satisfactions s ON s.source_id=c.id
         AND s.source_kind='continuing_care_actual'
         AND s.organization_id=NEW.organization_id
         AND s.evidence->>'workItemId'=NEW.id::text
         AND s.satisfaction_kind IN ('full','conditional')
       WHERE r.work_item_id=NEW.id AND r.organization_id=NEW.organization_id
         AND r.result_contract_key=NEW.result_contract_key
         AND r.result_kind='completed'
         AND c.metadata->>'workItemId'=NEW.id::text
     )
  THEN
    RAISE EXCEPTION 'Original continuing Work cannot close without its source-qualified satisfaction'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$guard$;

CREATE TRIGGER z_guard_continuing_care_work_completion_v1
BEFORE UPDATE OF work_state ON atlas.work_items
FOR EACH ROW EXECUTE FUNCTION atlas.guard_continuing_care_work_completion_v1();

-- No privilege change. Trigger functions do not need exposed client EXECUTE.
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_actual_result_v1()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_actual_acceptance_v1()
FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.guard_continuing_care_work_completion_v1()
FROM PUBLIC,anon,authenticated,service_role;


-- Test the actual source writer and source-level guards above, not a mock.
DO $tests$
DECLARE
 worker uuid:='72000000-0000-4000-8000-000000000003';
 outsider uuid:='72000000-0000-4000-8000-000000000012';
 work uuid:='72000000-0000-4000-8000-000000000009';
 state uuid:='72000000-0000-4000-8000-000000000006';
 partial_action uuid:='72000000-0000-4000-8000-000000000021';
 full_action uuid:='72000000-0000-4000-8000-000000000022';
 part jsonb; complete jsonb; replay jsonb;
 care_before uuid;
BEGIN
 PERFORM set_config('atlas_test.auth_uid',worker::text,true);

 -- Defense: Work cannot be marked completed by a generic direct UPDATE.
 BEGIN
  UPDATE atlas.work_items SET work_state='completed' WHERE id=work;
  RAISE EXCEPTION 'FAIL direct Work completion skipped Actual guard';
 EXCEPTION WHEN SQLSTATE '23514' THEN
  RAISE NOTICE 'PASS direct Work completion denied without accepted Actual';
 END;
 -- Defense: arbitrary Result cannot be fabricated with missing care Result.
 BEGIN
  INSERT INTO atlas.work_execution_results(
   organization_id,work_item_id,responsible_allocation_id,reported_by_user_id,
   result_kind,result_contract_key,idempotency_key,payload,metadata,reported_at
  ) VALUES (
   '72000000-0000-4000-8000-000000000001',work,
   '72000000-0000-4000-8000-000000000010',
   worker,'completed','continuing_care_actual_v1','forged-no-evidence',
   '{"careResultId":"72000000-0000-4000-8000-000000000099",
     "actualKind":"weeded_full","conditionAfter":"clear"}'::jsonb,
   '{}'::jsonb,now());
  RAISE EXCEPTION 'FAIL forged Result inserted';
 EXCEPTION WHEN SQLSTATE '23514' THEN
  RAISE NOTICE 'PASS forged canonical Work Result without Actual rejected';
 END;

 -- One physical bed, partial progress, same original Work.
 part:=atlas.record_continuing_care_actual_self_api_v1(
   work,partial_action,'weeded_partial','row_readable',20,
   'Cleared center but weeds remain along edges',NULL);
 IF part->>'workState'<>'open'
    OR part->>'sourceConditionAfter'<>'row_readable'
    OR (SELECT count(*) FROM atlas.work_items WHERE id=work AND work_state='open')<>1
    OR (SELECT count(*) FROM atlas.rhythm_satisfactions)<>0
    OR (SELECT condition_state FROM atlas.care_current_state LIMIT 1)<>'row_readable'
    OR (SELECT current_condition FROM atlas.weed_cards LIMIT 1)<>'row_readable'
    OR (SELECT state FROM atlas.rhythm_state WHERE id=state)<>'recovering'
 THEN RAISE EXCEPTION 'FAIL partial Result changed wrong source/Work or invented satisfaction'; END IF;
 RAISE NOTICE 'PASS partial Actual records residue; Work remains open, no Rhythm renewal';

 -- A worker cannot change the historical meaning of the same action UUID.
 BEGIN
  PERFORM atlas.record_continuing_care_actual_self_api_v1(
   work,partial_action,'weeded_full','clear',20,'Replaced history',NULL);
  RAISE EXCEPTION 'FAIL changed idempotency accepted';
 EXCEPTION WHEN SQLSTATE '23505' THEN
  RAISE NOTICE 'PASS action replay cannot alter signed Actual';
 END;

 -- Other signed Person cannot see or write a responsible worker's Result.
 PERFORM set_config('atlas_test.auth_uid',outsider::text,true);
 BEGIN
  PERFORM atlas.record_continuing_care_actual_self_api_v1(
   work,full_action,'weeded_full','clear',12,'Unauthorized worker attempt',NULL);
  RAISE EXCEPTION 'FAIL unrelated Person could complete bed';
 EXCEPTION WHEN SQLSTATE '42501' THEN
  RAISE NOTICE 'PASS unrelated fictional Person denied';
 END;
 PERFORM set_config('atlas_test.auth_uid',worker::text,true);

 -- No invented 'weeded_full' without observed clear condition.
 BEGIN
  PERFORM atlas.record_continuing_care_actual_self_api_v1(
   work,full_action,'weeded_full','heavy',12,'Cannot call this cleared',NULL);
  RAISE EXCEPTION 'FAIL fake full completion permitted';
 EXCEPTION WHEN SQLSTATE '22023' THEN
  RAISE NOTICE 'PASS false full completion condition refused';
 END;

 -- Finish the actual bed and accept the source-qualified Result.
 complete:=atlas.record_continuing_care_actual_self_api_v1(
   work,full_action,'weeded_full','clear',12,
   'Finished edge roots and verified bed is clear',NULL);
 IF complete->>'workState'<>'completed'
    OR complete->>'sourceConditionAfter'<>'clear'
    OR (complete->>'rhythmSatisfactionId') IS NULL
    OR (SELECT work_state FROM atlas.work_items WHERE id=work)<>'completed'
    OR (SELECT state FROM atlas.work_allocations LIMIT 1)<>'completed'
    OR (SELECT state FROM atlas.rhythm_state WHERE id=state)<>'resting'
    OR (SELECT current_condition FROM atlas.weed_cards LIMIT 1)<>'clear'
    OR (SELECT condition_state FROM atlas.care_current_state LIMIT 1)<>'clear'
    OR (SELECT count(*) FROM atlas.rhythm_satisfactions WHERE satisfaction_kind='full')<>1
 THEN RAISE EXCEPTION 'FAIL completed source Actual did not settle Work + condition + Rhythm';END IF;
 RAISE NOTICE 'PASS full Actual closes SAME Work and creates true Rhythm satisfaction';

 IF (SELECT count(*) FROM atlas.work_items)<>1
    OR (SELECT count(*) FROM atlas.work_execution_results)<>2
    OR (SELECT count(*) FROM atlas.care_result_events)<>2
    OR (SELECT count(*) FROM atlas.care_observation_events)<>2
 THEN RAISE EXCEPTION 'FAIL duplicate Work or fabricated evidence row count'; END IF;
 RAISE NOTICE 'PASS two Results, one original Work, no fabricated new Work';

 -- An accepted signed Result survives rule retirement with identical data.
 UPDATE atlas.rhythm_rules SET status='retired';
 replay:=atlas.record_continuing_care_actual_self_api_v1(
   work,full_action,'weeded_full','clear',12,
   'Finished edge roots and verified bed is clear',NULL);
 IF replay->>'idempotent'<>'true'
   OR (SELECT count(*) FROM atlas.care_result_events)<>2
   OR (SELECT count(*) FROM atlas.rhythm_satisfactions)<>1
 THEN RAISE EXCEPTION 'FAIL replay after rule retirement'; END IF;
 RAISE NOTICE 'PASS signed retry after rule retirement preserves exact Result';

 IF has_function_privilege('authenticated',
   'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)',
   'EXECUTE')
 THEN RAISE EXCEPTION 'FAIL prerelease worker API prematurely exposed';END IF;
 RAISE NOTICE 'PASS unreleased client execution remains denied';
END;
$tests$;
ROLLBACK;
