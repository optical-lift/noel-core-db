-- MANUAL LOCAL ONLY. Actual candidate original Work + observed Need authoring source.
-- Support functions/tables, Auth and acceptance are deliberately fictional.
-- PostgreSQL 17 on RiverSong, NO GitHub Actions / production access.
-- Not a substitute for full native Ledger authorization or signed Auth tests.
BEGIN;
DO $guard$
BEGIN
 IF current_database()<>'atlas_test'
 OR current_setting('server_version_num')::integer<170000
 OR to_regnamespace('atlas') IS NOT NULL OR to_regnamespace('auth') IS NOT NULL
 THEN RAISE EXCEPTION 'Refused: requires empty local atlas_test PostgreSQL 17'; END IF;
END;$guard$;
CREATE SCHEMA atlas;
CREATE SCHEMA auth;
DO $role$
DECLARE role_name text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=role_name)
  THEN EXECUTE format('CREATE ROLE %I NOLOGIN',role_name); END IF;
 END LOOP;
END;$role$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE SET search_path TO ''
AS $identity$SELECT NULLIF(current_setting('atlas_test.signed_uid',true),'')::uuid$identity$;
CREATE FUNCTION atlas.current_person_id_v1() RETURNS uuid LANGUAGE sql STABLE SET search_path TO ''
AS $identity$SELECT auth.uid()$identity$;
CREATE FUNCTION atlas.require_household_governor_self_v1(uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $identity$BEGIN RAISE EXCEPTION 'Synthetic farm only' USING ERRCODE='42501'; END;$identity$;
CREATE FUNCTION atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $identity$
BEGIN
 IF $1 IS DISTINCT FROM '73000000-0000-4000-8000-000000000001'::uuid
 OR $2 IS DISTINCT FROM '73000000-0000-4000-8000-000000000002'::uuid
 OR auth.uid() IS DISTINCT FROM '73000000-0000-4000-8000-000000000003'::uuid
 THEN RAISE EXCEPTION 'Synthetic owner/Ledger required' USING ERRCODE='42501'; END IF;
 RETURN auth.uid();
END;$identity$;
CREATE FUNCTION atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $identity$
SELECT $1='73000000-0000-4000-8000-000000000001'::uuid
 AND $2='73000000-0000-4000-8000-000000000002'::uuid
 AND $3='73000000-0000-4000-8000-000000000004'::uuid
$identity$;
CREATE FUNCTION atlas.has_current_subject_disclosure_v1(
 uuid,uuid,text,text,uuid,text
) RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $identity$
SELECT $1='73000000-0000-4000-8000-000000000002'::uuid
 AND $2='73000000-0000-4000-8000-000000000004'::uuid
 AND $3='spatial' AND $4='growing_object'
 AND $5='73000000-0000-4000-8000-000000000006'::uuid
 AND $6 IN ('identity','condition')
 AND current_setting('atlas_test.disclosure',true) IS DISTINCT FROM 'withheld'
$identity$;
CREATE FUNCTION atlas.care_strategy_allows_ordinary_weeding_v1(uuid,date)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $identity$
SELECT $1='73000000-0000-4000-8000-000000000006'::uuid
 AND current_setting('atlas_test.strategy',true) IS DISTINCT FROM 'blocked'
$identity$;

CREATE TABLE atlas.household_need_occurrences_v1(
 id uuid PRIMARY KEY,household_id uuid,instance_id uuid,state text,
 opened_by_observation_id uuid,current_work_item_id uuid,updated_at timestamptz
);
CREATE TABLE atlas.household_kernel_instances(id uuid PRIMARY KEY,household_id uuid,kernel_key text,state text);
CREATE TABLE atlas.farms(id uuid PRIMARY KEY,organization_id uuid,status text);
CREATE TABLE atlas.growing_objects(id uuid PRIMARY KEY,farm_id uuid,label text);
CREATE TABLE atlas.rhythm_rules(
 id uuid PRIMARY KEY,status text,metadata jsonb
);
CREATE TABLE atlas.rhythm_bindings(
 id uuid PRIMARY KEY,rhythm_rule_id uuid,farm_id uuid,organization_id uuid,active boolean
);
CREATE TABLE atlas.rhythm_state(
 id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,subject_kind text,
 subject_id uuid,state text,rhythm_binding_id uuid,rhythm_rule_id uuid,rhythm_key text
);
CREATE TABLE atlas.weed_cards(id uuid PRIMARY KEY,object_id uuid,farm_id uuid);
CREATE TABLE atlas.mowing_area_state(
 object_id uuid,organization_id uuid,farm_id uuid,status text
);
CREATE TABLE atlas.care_current_state(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),scope_kind text,scope_id uuid,
 subject_domain text,subject_kind text,subject_id text,condition_state text,
 last_observed_at timestamptz,last_observation_id uuid,
 UNIQUE(scope_kind,scope_id,subject_domain,subject_kind,subject_id)
);
CREATE TABLE atlas.care_observation_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 subject_domain text,subject_kind text,subject_id text,scope_kind text,scope_id uuid,
 observed_at timestamptz,condition_state text,disposition text,
 observed_by_user_id uuid,source_kind text,source_key text,note text,
 inferred_from_clock boolean,metadata jsonb
);
-- Mimics projection behavior only; not the actual production projector.
CREATE FUNCTION atlas.synthetic_care_current_projection_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO ''
AS $projection$
BEGIN
 INSERT INTO atlas.care_current_state(
  scope_kind,scope_id,subject_domain,subject_kind,subject_id,
  condition_state,last_observed_at,last_observation_id
 ) VALUES(
  NEW.scope_kind,NEW.scope_id,NEW.subject_domain,NEW.subject_kind,
  NEW.subject_id,NEW.condition_state,NEW.observed_at,NEW.id
 ) ON CONFLICT(scope_kind,scope_id,subject_domain,subject_kind,subject_id)
 DO UPDATE SET condition_state=EXCLUDED.condition_state,
 last_observed_at=EXCLUDED.last_observed_at,last_observation_id=EXCLUDED.last_observation_id;
 RETURN NEW;
END;$projection$;
CREATE TRIGGER synthetic_care_current_projection_v1
AFTER INSERT ON atlas.care_observation_events
FOR EACH ROW EXECUTE FUNCTION atlas.synthetic_care_current_projection_v1();

CREATE TABLE atlas.work_result_contract_policies(
 contract_key text PRIMARY KEY,source_domain text,acceptance_mode text,
 active boolean,metadata jsonb
);
CREATE TABLE atlas.work_items(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,household_id uuid,title text NOT NULL,instructions text,
 work_state text NOT NULL,source_object_type text,source_object_id uuid,
 stable_key text,result_contract_key text,created_by_user_id uuid,
 metadata jsonb DEFAULT '{}'::jsonb,created_at timestamptz DEFAULT now(),
 updated_at timestamptz DEFAULT now()
);
CREATE TABLE atlas.work_item_context_links(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,household_id uuid,work_item_id uuid,
 subject_domain text,subject_kind text,subject_id uuid,relation_kind text,
 provenance jsonb,metadata jsonb
);
CREATE TABLE atlas.company_work_standing_assignment_scopes(
 id uuid PRIMARY KEY,organization_id uuid,ledger_id uuid,proposed_by_person_id uuid,
 worker_person_id uuid,worker_membership_id uuid,accepted_by_person_id uuid,
 accepted_at timestamptz,scope_state text,coverage_mode text,valid_until timestamptz
);
CREATE TABLE atlas.company_work_native_ledger_relevance(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,work_item_id uuid,ledger_id uuid,evidence_kind text,
 attestation_source_ref text,attestation_reason text,established_by_person_id uuid,
 attribution_state text DEFAULT 'active'
);
CREATE TABLE atlas.work_allocations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,work_item_id uuid,assignee_canonical_person_id uuid,
 allocation_role text,state text,establishment_basis_kind text,
 establishment_basis jsonb
);
CREATE TABLE atlas.work_execution_plans(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,work_item_id uuid,responsible_allocation_id uuid,
 assignee_membership_id uuid,planned_by_membership_id uuid,
 plan_state text,first_planned_service_date date,planned_service_date date,
 exposure_service_date date,plan_reason text,metadata jsonb
);
CREATE TABLE atlas.work_execution_plan_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,work_item_id uuid,plan_id uuid,event_kind text,
 to_planned_service_date date,to_exposure_service_date date,
 actor_membership_id uuid,reason text,metadata jsonb
);
CREATE TABLE atlas.planned_work_occurrences(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),source_kind text,source_id uuid
);
CREATE TABLE atlas.tasks(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),farm_id uuid,status text,
 planned_occurrence_id uuid,metadata jsonb DEFAULT '{}'::jsonb
);
-- Synthetic standing assignment carrier: returns a canonical allocation,
-- but DOES NOT prove the real installed assignment function or connection.
CREATE FUNCTION atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
 p_work_id uuid,p_scope_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $assign$
DECLARE v_work atlas.work_items%ROWTYPE;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_allocation uuid;
BEGIN
 SELECT * INTO v_work FROM atlas.work_items WHERE id=p_work_id;
 SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes WHERE id=p_scope_id;
 IF v_work.id IS NULL OR v_scope.id IS NULL
 OR v_scope.organization_id<>v_work.organization_id
 OR atlas.company_work_native_ledger_owner_self_v1(v_work.organization_id,v_scope.ledger_id)
 IS DISTINCT FROM auth.uid()
 OR NOT EXISTS(
  SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
  WHERE rel.organization_id=v_work.organization_id AND rel.work_item_id=v_work.id
  AND rel.ledger_id=v_scope.ledger_id AND rel.attribution_state='active')
 THEN RAISE EXCEPTION 'Mock source allocation denied' USING ERRCODE='42501'; END IF;
 INSERT INTO atlas.work_allocations(
  organization_id,work_item_id,assignee_canonical_person_id,allocation_role,
  state,establishment_basis_kind,establishment_basis
 ) VALUES(
  v_work.organization_id,v_work.id,v_scope.worker_person_id,
  'responsible','active','delegated_under_standing_scope',
  jsonb_build_object('nativeLedgerId',v_scope.ledger_id,'scopeId',v_scope.id)
 ) RETURNING id INTO v_allocation;
 RETURN jsonb_build_object('ok',true,'state','assigned',
  'workItemId',v_work.id,'allocationId',v_allocation);
END;$assign$;

-- The exact original Work primitive from draft candidate.sql follows.

-- EXACT BASE SOURCE BLOB a1b45327e3b8de6582b86f446f56cc3b25ab904c
CREATE OR REPLACE FUNCTION atlas.establish_continuing_original_work_internal_v1(
  p_custody_kind text,
  p_custody_id uuid,
  p_ledger_id uuid,
  p_need_kind text,
  p_need_id uuid,
  p_serving_key text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id uuid,
  p_title text,
  p_instructions text,
  p_result_contract_key text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_need atlas.household_need_occurrences_v1%ROWTYPE;
  v_rhythm atlas.rhythm_state%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_person uuid;
  v_stable_key text;
  v_existing_count integer;
  v_source_domain text;
BEGIN
  -- No arbitrary authenticated client is authorized to call this function:
  -- EXECUTE is revoked below. The only authorized caller is a governed
  -- source-owned writer that already proved the exact present Need and
  -- compatible Result, not a planner or a legacy task/clock reader.
  IF auth.uid() IS NULL OR p_custody_kind IS NULL
    OR p_custody_kind NOT IN ('household','organization')
    OR p_need_kind IS NULL OR p_subject_domain IS NULL
    OR p_subject_kind IS NULL
    OR p_custody_id IS NULL OR p_need_id IS NULL
    OR p_subject_id IS NULL OR p_result_contract_key IS NULL
    OR nullif(btrim(coalesce(p_title,'')),'') IS NULL
    OR length(p_title)>500
    OR nullif(btrim(coalesce(p_serving_key,'')),'') IS NULL
    OR length(p_serving_key)>200
    OR length(coalesce(p_instructions,''))>8000
  THEN
    RAISE EXCEPTION 'Exact signed custody, source Need, serving and result are required'
      USING ERRCODE='22023';
  END IF;

  IF p_custody_kind='household' THEN
    IF p_ledger_id IS NOT NULL OR p_need_kind<>'household_need_occurrence'
       OR p_subject_domain<>'household' OR p_subject_kind<>'kernel_instance' THEN
      RAISE EXCEPTION 'Household source cannot claim organization authority'
        USING ERRCODE='42501';
    END IF;
    v_source_domain:='household';
    v_person:=atlas.require_household_governor_self_v1(p_custody_id);
    SELECT * INTO v_need FROM atlas.household_need_occurrences_v1
      WHERE id=p_need_id AND household_id=p_custody_id
        AND instance_id=p_subject_id AND state='open'
      FOR UPDATE;
    IF v_need.id IS NULL THEN
      RAISE EXCEPTION 'Unconfirmed or closed original Household Need'
        USING ERRCODE='23514';
    END IF;
    -- Household Work already has a source guard; preserve its exact custody,
    -- type, and policy. This helper must never silently broaden that guard.
    IF p_result_contract_key<>'household_laundry_begin_cycle_v1' THEN
      RAISE EXCEPTION 'Household Need does not have a released physical Result policy'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.household_kernel_instances inst
      WHERE inst.id=p_subject_id AND inst.household_id=p_custody_id
        AND inst.kernel_key='household.laundry' AND inst.state='active'
    ) THEN
      RAISE EXCEPTION 'Exact established Household kernel and Need are required'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.care_current_state c
      WHERE c.scope_kind='household' AND c.scope_id=p_custody_id
        AND c.subject_domain='household' AND c.subject_kind='household_kernel_instance'
        AND c.subject_id=p_subject_id::text
        AND c.condition_state='ready_for_cycle'
        AND c.last_observation_id=v_need.opened_by_observation_id
    ) THEN
      RAISE EXCEPTION 'Household Need lacks current confirmed physical condition'
        USING ERRCODE='23514';
    END IF;
  ELSE
    IF p_need_kind<>'rhythm_state' OR p_ledger_id IS NULL
       OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object' THEN
      RAISE EXCEPTION 'Organization source requires exact governed jurisdiction'
        USING ERRCODE='42501';
    END IF;
    v_source_domain:='organization';
    v_person:=atlas.company_work_native_ledger_owner_self_v1(
      p_custody_id,p_ledger_id);
    SELECT * INTO v_rhythm FROM atlas.rhythm_state s
    WHERE s.id=p_need_id AND s.organization_id=p_custody_id
      AND s.subject_kind='growing_object' AND s.subject_id=p_subject_id
      AND s.state<>'paused'
      AND EXISTS (
        SELECT 1 FROM atlas.growing_objects go
        WHERE go.id=s.subject_id AND go.farm_id=s.farm_id
      )
      AND EXISTS (
        SELECT 1 FROM atlas.rhythm_bindings b
        JOIN atlas.rhythm_rules r ON r.id=b.rhythm_rule_id
        WHERE b.id=s.rhythm_binding_id AND b.active AND r.status='active'
      )
    FOR UPDATE;
    IF v_rhythm.id IS NULL THEN
      RAISE EXCEPTION 'Absent, paused or non-actionable original Need'
        USING ERRCODE='23514';
    END IF;
    -- The domain writer, not an elapsed clock, proves immediate condition.
    -- This primitive cannot adjudicate weed pressure, mower safety, a
    -- seasonal Resting state, or stale observations. No caller is released
    -- until its domain adapter enforces those independent physical gates.
    -- A special source-qualified physical-Actual policy is also required;
    -- generic worker attestation cannot assert care state/satisfaction.
    -- It is never called by farm_rhythm_tick or by legacy task release.
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.work_result_contract_policies policy
    WHERE policy.contract_key=p_result_contract_key AND policy.active
      AND policy.source_domain=v_source_domain
      AND policy.acceptance_mode='domain_adapter'
      AND (
        v_source_domain='household'
        OR policy.metadata->>'continuingActualQualification'='source_proven_v1'
      )
  ) THEN
    RAISE EXCEPTION 'No active Result contract in exact native custody'
      USING ERRCODE='23514';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-work:'||p_custody_kind||':'||p_custody_id::text||
      ':'||p_need_kind||':'||p_need_id::text,0));

  -- Source-id lock prevents two concurrently valid servings for one Need.
  -- A new serving key may be used only after the previous actual Work closes.
  SELECT count(*) INTO v_existing_count FROM atlas.work_items w
  WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
      OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
    AND w.source_object_type=p_need_kind AND w.source_object_id=p_need_id
    AND w.work_state='open';
  IF v_existing_count>1 THEN
    RAISE EXCEPTION 'Multiple active original Work servings for one Need'
      USING ERRCODE='23514';
  END IF;
  IF v_existing_count=1 THEN
    SELECT * INTO v_work FROM atlas.work_items w
    WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
       OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
      AND w.source_object_type=p_need_kind AND w.source_object_id=p_need_id
      AND w.work_state='open'
    FOR UPDATE;
    IF v_work.result_contract_key IS DISTINCT FROM p_result_contract_key THEN
      RAISE EXCEPTION 'Existing Need Work has a different Result contract'
        USING ERRCODE='23514';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'workItemId',v_work.id,'existingOpenServing',true,
      'noNewWorkCreated',true,'clockAdmitted',false,
      'sourceKind',p_need_kind,'sourceId',p_need_id);
  END IF;

  v_stable_key:='continuing:v1:'||md5(
    p_custody_kind||':'||p_custody_id::text||':'||
    p_need_kind||':'||p_need_id::text||':'||p_serving_key);
  -- A closed identical serving cannot be reopened via a retry.
  IF EXISTS (
    SELECT 1 FROM atlas.work_items w
    WHERE ((p_custody_kind='household' AND w.household_id=p_custody_id)
       OR (p_custody_kind='organization' AND w.organization_id=p_custody_id))
      AND w.stable_key=v_stable_key
  ) THEN
    RAISE EXCEPTION 'This continuing Work serving already has closed history'
      USING ERRCODE='23514';
  END IF;

  INSERT INTO atlas.work_items(
    organization_id,household_id,title,instructions,work_state,
    source_object_type,source_object_id,stable_key,result_contract_key,
    created_by_user_id,metadata
  ) VALUES (
    CASE WHEN p_custody_kind='organization' THEN p_custody_id ELSE NULL END,
    CASE WHEN p_custody_kind='household' THEN p_custody_id ELSE NULL END,
    p_title,p_instructions,'open',p_need_kind,p_need_id,v_stable_key,
    p_result_contract_key,auth.uid(),
    jsonb_build_object(
      'sourceContract','continuing_original_work_v1',
      'needKind',p_need_kind,'needId',p_need_id,'servingKey',p_serving_key,
      'sourceConfirmedBy','governed_domain_writer',
      'noCalendarDateInferred',true,'noClockAdmissionInferred',true)
  ) RETURNING * INTO v_work;

  INSERT INTO atlas.work_item_context_links(
    organization_id,household_id,work_item_id,subject_domain,
    subject_kind,subject_id,relation_kind,provenance,metadata
  ) VALUES (
    v_work.organization_id,v_work.household_id,v_work.id,
    p_subject_domain,p_subject_kind,p_subject_id,'acts_on',
    jsonb_build_object('needKind',p_need_kind,'needId',p_need_id,
      'sourceContract','continuing_original_work_v1'),
    '{}'::jsonb
  );

  IF p_custody_kind='household' THEN
    UPDATE atlas.household_need_occurrences_v1
    SET current_work_item_id=v_work.id,updated_at=now()
    WHERE id=v_need.id AND current_work_item_id IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Household Need already owns another original Work'
        USING ERRCODE='23514';
    END IF;
  END IF;
  -- Native Ledger relevance is NOT inferred or automatically attested here.
  -- The domain writer must establish exact source-governed Ledger relevance
  -- and original Person responsibility in the same authorized transaction,
  -- otherwise the entire source transaction must fail/roll back.

  RETURN jsonb_build_object('ok',true,'contractVersion',
    'continuing_original_work_v1','workItemId',v_work.id,
    'sourceKind',p_need_kind,'sourceId',p_need_id,
    'existingOpenServing',false,'noNewWorkCreated',false,
    'ledgerRelevanceEstablished',false,
    'responsibilityEstablished',false,'clockAdmitted',false);
END;
$function$;
-- Never expose this primitive as an executable signed-user command.
-- Only separately reviewed source domain writers may call it.
REVOKE ALL ON FUNCTION atlas.establish_continuing_original_work_internal_v1(
  text,uuid,uuid,text,uuid,text,text,text,uuid,text,text,text
) FROM PUBLIC, anon, authenticated, service_role;



-- Entirely fictional source data.
INSERT INTO atlas.farms VALUES (
 '73000000-0000-4000-8000-000000000005',
 '73000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.growing_objects VALUES(
 '73000000-0000-4000-8000-000000000006',
 '73000000-0000-4000-8000-000000000005','Fictional Bed A');
INSERT INTO atlas.rhythm_rules VALUES(
 '73000000-0000-4000-8000-000000000007','active',
 '{"timezoneName":"UTC"}'::jsonb);
INSERT INTO atlas.rhythm_bindings VALUES(
 '73000000-0000-4000-8000-000000000008',
 '73000000-0000-4000-8000-000000000007',
 '73000000-0000-4000-8000-000000000005',
 '73000000-0000-4000-8000-000000000001',true);
INSERT INTO atlas.rhythm_state VALUES(
 '73000000-0000-4000-8000-000000000009',
 '73000000-0000-4000-8000-000000000001',
 '73000000-0000-4000-8000-000000000005','growing_object',
 '73000000-0000-4000-8000-000000000006','due',
 '73000000-0000-4000-8000-000000000008',
 '73000000-0000-4000-8000-000000000007','weed_stewardship');
INSERT INTO atlas.weed_cards VALUES(
 '73000000-0000-4000-8000-000000000010',
 '73000000-0000-4000-8000-000000000006',
 '73000000-0000-4000-8000-000000000005');
INSERT INTO atlas.company_work_standing_assignment_scopes VALUES(
 '73000000-0000-4000-8000-000000000011',
 '73000000-0000-4000-8000-000000000001',
 '73000000-0000-4000-8000-000000000002',
 '73000000-0000-4000-8000-000000000003',
 '73000000-0000-4000-8000-000000000004',
 NULL,'73000000-0000-4000-8000-000000000004',
 now()-interval '1 day','active','ledger_all_work',NULL);
INSERT INTO atlas.work_result_contract_policies VALUES(
 'continuing_care_actual_v1','organization','domain_adapter',true,
 '{"continuingActualQualification":"source_proven_v1"}'::jsonb);

-- EXACT OWNER SOURCE BLOB cd2d888c5c210d4d0bf7c9e420a50e771dccc455
-- DRAFT: source-observed Need → one canonical original Work → accepted
-- connected-Person responsibility → an EXPLICIT service date in existing Today.
-- This is a thin farm DOMAIN ADAPTER to universal Work, NOT a new task engine.
-- No silent assignment, inferred physical need, or auto-generated backlog.
-- Requires candidate.sql and 02_farm_care_actual_adapter.sql first.
CREATE OR REPLACE FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_rhythm_state_id uuid,
  p_scope_id uuid,
  p_observed_condition text,
  p_observation_note text,
  p_observed_at timestamptz,
  p_service_date date,
  p_action_id uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $writer$
DECLARE
  v_owner uuid;
  v_state atlas.rhythm_state%ROWTYPE;
  v_rule atlas.rhythm_rules%ROWTYPE;
  v_object atlas.growing_objects%ROWTYPE;
  v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
  v_current atlas.care_current_state%ROWTYPE;
  v_existing atlas.work_items%ROWTYPE;
  v_work uuid;
  v_source jsonb;
  v_assignment jsonb;
  v_allocation uuid;
  v_plan uuid;
  v_observation uuid;
  v_title text;
  v_instructions text;
  v_condition text:=nullif(btrim(coalesce(p_observed_condition,'')),'');
  v_note text:=nullif(btrim(coalesce(p_observation_note,'')),'');
  v_key text;
  v_today date;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
     OR p_rhythm_state_id IS NULL OR p_scope_id IS NULL
     OR p_action_id IS NULL OR p_observed_at IS NULL
     OR p_service_date IS NULL OR v_condition IS NULL
     OR v_note IS NULL OR length(v_note)<10 OR length(v_note)>1500
     OR p_observed_at<now()-interval '3 days'
     OR p_observed_at>now()+interval '5 minutes' THEN
    RAISE EXCEPTION 'Exact fresh source observation and deliberate Person-day decision required'
      USING ERRCODE='22023';
  END IF;

  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  SELECT * INTO v_scope FROM atlas.company_work_standing_assignment_scopes
    WHERE id=p_scope_id FOR UPDATE;
  IF v_scope.id IS NULL OR v_scope.organization_id<>p_organization_id
    OR v_scope.ledger_id<>p_ledger_id
    OR v_scope.proposed_by_person_id IS DISTINCT FROM v_owner
    OR v_scope.scope_state<>'active'
    OR v_scope.worker_membership_id IS NOT NULL
    OR v_scope.accepted_by_person_id IS DISTINCT FROM v_scope.worker_person_id
    OR v_scope.accepted_at IS NULL
    OR v_scope.coverage_mode<>'ledger_all_work'
    OR (v_scope.valid_until IS NOT NULL AND v_scope.valid_until<=now())
    OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_scope.worker_person_id) THEN
    RAISE EXCEPTION 'Existing accepted connected-Person Ledger-wide scope required'
      USING ERRCODE='42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.continuing-need-owner:'||p_organization_id||':'||p_rhythm_state_id,0));
  SELECT * INTO v_state FROM atlas.rhythm_state s
    WHERE s.id=p_rhythm_state_id AND s.organization_id=p_organization_id
      AND s.subject_kind='growing_object' AND s.state<>'paused'
    FOR UPDATE;
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Original active Subject Need unavailable' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_rule FROM atlas.rhythm_rules r
    JOIN atlas.rhythm_bindings b ON b.rhythm_rule_id=r.id
    WHERE b.id=v_state.rhythm_binding_id AND r.id=v_state.rhythm_rule_id
      AND b.farm_id=v_state.farm_id AND b.organization_id=p_organization_id
      AND b.active AND r.status='active';
  SELECT * INTO v_object FROM atlas.growing_objects g
    WHERE g.id=v_state.subject_id AND g.farm_id=v_state.farm_id;
  v_today:=(now() at time zone
    coalesce(nullif(v_rule.metadata->>'timezoneName',''),'UTC'))::date;
  IF p_service_date<v_today-1 OR p_service_date>v_today+14 THEN
    RAISE EXCEPTION 'Person-day placement must be an explicit bounded civil date'
      USING ERRCODE='22023';
  END IF;
  IF v_rule.id IS NULL OR v_object.id IS NULL
    OR v_state.rhythm_key NOT IN ('weed_stewardship','mowing')
    OR NOT EXISTS(
      SELECT 1 FROM atlas.farms f WHERE f.id=v_state.farm_id
      AND f.organization_id=p_organization_id AND f.status='active'
    ) THEN
    RAISE EXCEPTION 'Care Need is not sourced from an active governed place'
      USING ERRCODE='23514';
  END IF;

  IF v_state.rhythm_key='mowing' THEN
    IF v_condition NOT IN ('needs_inspection','ready_for_mowing','overgrown')
      OR NOT EXISTS(
        SELECT 1 FROM atlas.mowing_area_state m
        WHERE m.object_id=v_state.subject_id
          AND m.farm_id=v_state.farm_id
          AND m.organization_id=p_organization_id AND m.status<>'closed'
      ) THEN
      RAISE EXCEPTION 'Mowing needs a real observed route and permitted condition'
        USING ERRCODE='23514';
    END IF;
    v_title:='Inspect and mow if warranted — '||v_object.label;
    v_instructions:='Inspect the route and ground safety. Mow only if appropriate. Report the real outcome: full, partial, acceptable no-cut, too wet, or equipment/area problem.';
  ELSE
    IF v_condition NOT IN ('needs_inspection','row_readable',
         'medium_pressure','heavy')
      OR NOT EXISTS(
        SELECT 1 FROM atlas.weed_cards c
        WHERE c.object_id=v_state.subject_id AND c.farm_id=v_state.farm_id
      )
      OR NOT atlas.care_strategy_allows_ordinary_weeding_v1(
        v_state.subject_id,p_observed_at::date) THEN
      RAISE EXCEPTION 'Weeding needs an observed eligible care strategy'
        USING ERRCODE='23514';
    END IF;
    v_title:='Inspect and weed if warranted — '||v_object.label;
    v_instructions:='Inspect current weed condition and care strategy. Weed only if warranted. Report the real outcome: full, partial, acceptable inspection, or blocked.';
  END IF;

  -- The source Disclosure gate is NOT the same as assigning responsibility.
  -- The worker must actually be permitted to find identity AND condition.
  IF NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
     v_state.subject_id,'identity')
    OR NOT atlas.has_current_subject_disclosure_v1(
     p_ledger_id,v_scope.worker_person_id,'spatial','growing_object',
     v_state.subject_id,'condition')
  THEN
    RAISE EXCEPTION 'The connected Person cannot receive this protected physical Subject'
      USING ERRCODE='42501';
  END IF;

  -- Same source action is never a second original, even after completion.
  SELECT * INTO v_existing FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='rhythm_state'
    AND w.source_object_id=v_state.id
    AND w.metadata->>'servingKey'=p_action_id::text
  ORDER BY w.created_at LIMIT 1 FOR UPDATE;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.metadata->>'sourceScopeId' IS DISTINCT FROM p_scope_id::text
      OR v_existing.metadata->>'sourceServiceDate' IS DISTINCT FROM p_service_date::text
      OR v_existing.metadata->>'sourceObservedCondition' IS DISTINCT FROM v_condition
      OR v_existing.metadata->>'sourceObservedAt' IS DISTINCT FROM p_observed_at::text
      OR v_existing.metadata->>'sourceObservationNoteDigest' IS DISTINCT FROM md5(v_note)
    THEN
      RAISE EXCEPTION 'Source action replay cannot change original Person, date or observed condition'
        USING ERRCODE='23505';
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=p_organization_id AND rel.work_item_id=v_existing.id
        AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'Replayed action does not match the native Ledger'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,
      'contractVersion','observed_continuing_care_work_v1',
      'workItemId',v_existing.id,'existingAction',true,
      'noNewWorkCreated',true,'clockAdmitted',false);
  END IF;

  SELECT * INTO v_existing FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='rhythm_state'
    AND w.source_object_id=v_state.id AND w.work_state='open'
  LIMIT 1 FOR UPDATE;
  IF v_existing.id IS NOT NULL THEN
    -- Never reveal or reassign an existing original that belongs to another
    -- native Ledger, even when the same underlying spatial Subject is known.
    IF NOT EXISTS(
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=p_organization_id
        AND rel.work_item_id=v_existing.id
        AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'Another governing Ledger already has the open original Work'
        USING ERRCODE='23514';
    END IF;
    -- Never overwrite another person's task/plan with a later observation.
    RETURN jsonb_build_object('ok',true,
      'contractVersion','observed_continuing_care_work_v1',
      'workItemId',v_existing.id,'existingOpenServing',true,
      'noNewWorkCreated',true,'assignmentUnchanged',true,
      'noNewObservationCreated',true,'clockAdmitted',false);
  END IF;

  -- Do not promote the same Need while an unresolved legacy obligation
  -- still exists. Keep that older task and its history unchanged; exact
  -- legacy disposition/transfer is a separate governed owner decision.
  IF EXISTS (
    SELECT 1 FROM atlas.tasks t
    LEFT JOIN atlas.planned_work_occurrences o ON o.id=t.planned_occurrence_id
    WHERE t.farm_id=v_state.farm_id AND t.status IN ('open','blocked')
      AND (
        t.metadata->>'rhythm_state_id'=v_state.id::text
        OR (o.source_kind='rhythm_state' AND o.source_id=v_state.id)
      )
  ) THEN
    RAISE EXCEPTION 'An older active task still serves this exact Need; resolve its custody before creating another original Work'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_current FROM atlas.care_current_state c
  WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
    AND c.subject_domain='farm' AND c.subject_kind='growing_object'
    AND c.subject_id=v_state.subject_id::text FOR UPDATE;
  IF v_current.id IS NOT NULL AND v_current.last_observed_at>p_observed_at THEN
    RAISE EXCEPTION 'Newer physical state cannot be overwritten by older evidence'
      USING ERRCODE='23514';
  END IF;

  v_key:='governed-continuing-need-observation:'||p_action_id::text;
  IF EXISTS(SELECT 1 FROM atlas.care_observation_events e
    WHERE e.source_key=v_key) THEN
    RAISE EXCEPTION 'Source action already belongs to an observation; reconcile first'
      USING ERRCODE='23505';
  END IF;
  INSERT INTO atlas.care_observation_events(
    subject_domain,subject_kind,subject_id,scope_kind,scope_id,
    observed_at,condition_state,disposition,observed_by_user_id,
    source_kind,source_key,note,inferred_from_clock,metadata
  ) VALUES(
    'farm','growing_object',v_state.subject_id::text,'farm',v_state.farm_id,
    p_observed_at,v_condition,'reassess',auth.uid(),
    'governed_continuing_need_observation',v_key,v_note,false,
    jsonb_build_object('rhythmStateId',v_state.id,
      'observingGovernorPersonId',v_owner,
      'chosenLedgerId',p_ledger_id,'notClockInferred',true)
  ) RETURNING id INTO v_observation;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.care_current_state c
    WHERE c.scope_kind='farm' AND c.scope_id=v_state.farm_id
      AND c.subject_domain='farm' AND c.subject_kind='growing_object'
      AND c.subject_id=v_state.subject_id::text
      AND c.condition_state=v_condition AND c.last_observation_id=v_observation
  ) THEN
    RAISE EXCEPTION 'Source observation did not become current physical state'
      USING ERRCODE='23514';
  END IF;

  v_source:=atlas.establish_continuing_original_work_internal_v1(
    'organization',p_organization_id,p_ledger_id,'rhythm_state',v_state.id,
    p_action_id::text,'spatial','growing_object',v_state.subject_id,
    left(v_title,500),v_instructions,'continuing_care_actual_v1');
  v_work:=(v_source->>'workItemId')::uuid;
  IF v_work IS NULL OR v_source->>'noNewWorkCreated' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Original Work serving was not newly established'
      USING ERRCODE='23514';
  END IF;

  -- Freeze the original signed source action: replay must be an exact
  -- repeat, never a second assignment, observation or service date.
  UPDATE atlas.work_items SET
    metadata=metadata||jsonb_build_object(
      'sourceScopeId',p_scope_id,
      'sourceServiceDate',p_service_date,
      'sourceObservedCondition',v_condition,
      'sourceObservedAt',p_observed_at::text,
      'sourceObservationNoteDigest',md5(v_note)),
    updated_at=now()
  WHERE id=v_work AND organization_id=p_organization_id;

  INSERT INTO atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id
  ) VALUES(
    p_organization_id,v_work,p_ledger_id,'owner_attested',
    'atlas.care_observation_events:'||v_observation::text,
    'Governor explicitly chose this Ledger for Work following a fresh signed physical observation.',
    v_owner
  );

  -- Reuse the governed native Person allocation, not an employee seat.
  v_assignment:=atlas.assign_native_ledger_company_work_under_scope_owner_self_api_v1(
    v_work,p_scope_id,
    'Fresh original physical Need explicitly given under an accepted native connected-Person scope.');
  IF v_assignment->>'state' IS DISTINCT FROM 'assigned'
    OR v_assignment->>'workItemId' IS DISTINCT FROM v_work::text THEN
    RAISE EXCEPTION 'Exact native Person responsibility was not verified'
      USING ERRCODE='23514';
  END IF;
  v_allocation:=(v_assignment->>'allocationId')::uuid;

  -- Only the governor-selected service date creates this Work's Person-day
  -- plan. Rhythm due_at is NOT the Person's scheduling/attention authority.
  INSERT INTO atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,
    assignee_membership_id,planned_by_membership_id,
    plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_allocation,NULL,NULL,'active',
    p_service_date,p_service_date,p_service_date,
    'Governor explicitly chose service date for real observed continuing Need.',
    jsonb_build_object('source','observed_continuing_care_work_v1',
      'ownerPersonId',v_owner,'sourceObservationId',v_observation,
      'connectedPersonDay',true,'principalClockAdmitted',false)
  ) RETURNING id INTO v_plan;
  INSERT INTO atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    to_planned_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata
  ) VALUES(
    p_organization_id,v_work,v_plan,'planned',
    p_service_date,p_service_date,NULL,
    'Governor selected actual service date from observed Need',
    jsonb_build_object('sourceObservationId',v_observation,
      'governorPersonId',v_owner,'notLegacyWorkerDay',true)
  );

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','observed_continuing_care_work_v1',
    'workItemId',v_work,'rhythmStateId',v_state.id,
    'observationId',v_observation,
    'responsiblePersonId',v_scope.worker_person_id,
    'allocationId',v_allocation,'planId',v_plan,
    'serviceDate',p_service_date,
    'newOriginalWorkCreated',true,
    'sourceObservationSigned',true,
    'clockAdmitted',false,'noNextWorkPrecreated',true);
END;
$writer$;

-- Denied until protected-clone signed authority/privacy tests pass. This
-- function is a source-governor operation, not a generic task creation RPC.
REVOKE ALL ON FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid
) FROM PUBLIC,anon,authenticated,service_role;


DO $tests$
DECLARE
 v_org uuid:='73000000-0000-4000-8000-000000000001';
 v_ledger uuid:='73000000-0000-4000-8000-000000000002';
 v_owner uuid:='73000000-0000-4000-8000-000000000003';
 v_worker uuid:='73000000-0000-4000-8000-000000000004';
 v_state uuid:='73000000-0000-4000-8000-000000000009';
 v_bed uuid:='73000000-0000-4000-8000-000000000006';
 v_scope uuid:='73000000-0000-4000-8000-000000000011';
 v_action uuid:='73000000-0000-4000-8000-000000000021';
 v_other_action uuid:='73000000-0000-4000-8000-000000000022';
 v_service_date date:= (now() AT TIME ZONE 'UTC')::date;
 v_observed_at timestamptz:=now()-interval '5 minutes';
 v_note text:='Fictional Bed A has visible weed pressure; inspect and weed.';
 v_packet jsonb; v_work uuid;
BEGIN
 PERFORM set_config('atlas_test.signed_uid',v_owner::text,true);
 PERFORM set_config('atlas_test.disclosure','withheld',true);
 BEGIN
 PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_action);
 RAISE EXCEPTION 'FAIL withhold permitted original Work';
 EXCEPTION WHEN SQLSTATE '42501' THEN
 RAISE NOTICE 'PASS withheld Subject blocks original Work';
 END;
 IF (SELECT count(*) FROM atlas.work_items)<>0 THEN
 RAISE EXCEPTION 'FAIL unauthorized Work persisted';END IF;
 PERFORM set_config('atlas_test.disclosure','granted',true);

 -- Old active rhythm task has custody until explicit resolution.
 INSERT INTO atlas.tasks(farm_id,status,metadata) VALUES(
  '73000000-0000-4000-8000-000000000005','open',
  jsonb_build_object('rhythm_state_id',v_state));
 BEGIN
 PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_action);
 RAISE EXCEPTION 'FAIL duplicate old legacy task accepted';
 EXCEPTION WHEN SQLSTATE '23514' THEN
 RAISE NOTICE 'PASS existing old task blocks duplicate original Work';
 END;
 DELETE FROM atlas.tasks; -- fake original-task row only, inside ROLLBACK

 PERFORM set_config('atlas_test.strategy','blocked',true);
 BEGIN
 PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_action);
 RAISE EXCEPTION 'FAIL ineligible physical care strategy permitted';
 EXCEPTION WHEN SQLSTATE '23514' THEN
 RAISE NOTICE 'PASS physical care strategy blocks unsupported Work';
 END;
 PERFORM set_config('atlas_test.strategy','allowed',true);

 v_packet:=atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_action);
 v_work:=(v_packet->>'workItemId')::uuid;
 IF v_work IS NULL OR v_packet->>'newOriginalWorkCreated'<>'true'
 OR v_packet->>'responsiblePersonId' IS DISTINCT FROM v_worker::text
 OR (v_packet->>'serviceDate')::date<>v_service_date
 OR (SELECT count(*) FROM atlas.work_items)<>1
 OR (SELECT count(*) FROM atlas.care_observation_events)<>1
 OR (SELECT count(*) FROM atlas.work_allocations)<>1
 OR (SELECT count(*) FROM atlas.work_execution_plans)<>1
 OR (SELECT count(*) FROM atlas.work_execution_plan_events)<>1
 THEN RAISE EXCEPTION 'FAIL original Need/Work/Person-day construction'; END IF;
 RAISE NOTICE 'PASS real draft source creates one fictional observed Need, original Work and Person-day';

 IF NOT EXISTS(
 SELECT 1 FROM atlas.work_items wi
 JOIN atlas.work_item_context_links ctx ON ctx.work_item_id=wi.id
 JOIN atlas.company_work_native_ledger_relevance rel ON rel.work_item_id=wi.id
 JOIN atlas.work_execution_plans plan ON plan.work_item_id=wi.id
 JOIN atlas.work_allocations alloc ON alloc.id=plan.responsible_allocation_id
 WHERE wi.id=v_work AND wi.source_object_id=v_state AND wi.work_state='open'
 AND ctx.subject_id=v_bed AND ctx.relation_kind='acts_on'
 AND rel.ledger_id=v_ledger AND rel.evidence_kind='owner_attested'
 AND alloc.assignee_canonical_person_id=v_worker AND plan.planned_service_date=v_service_date
 ) THEN RAISE EXCEPTION 'FAIL native source relationships'; END IF;
 RAISE NOTICE 'PASS Work, Ledger, Subject, Person allocation and chosen date reference SAME original';

 v_packet:=atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_action);
 IF v_packet->>'existingAction'<>'true'
 OR (v_packet->>'workItemId')::uuid<>v_work
 OR (SELECT count(*) FROM atlas.work_items)<>1
 OR (SELECT count(*) FROM atlas.care_observation_events)<>1
 THEN RAISE EXCEPTION 'FAIL replay duplicated source';END IF;
 RAISE NOTICE 'PASS same owner action is idempotent, no duplicate observation';

 BEGIN
 PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date+1,v_action);
 RAISE EXCEPTION 'FAIL action replay changed service date';
 EXCEPTION WHEN SQLSTATE '23505' THEN
 RAISE NOTICE 'PASS action replay cannot silently change service date';
 END;

 v_packet:=atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_other_action);
 IF v_packet->>'existingOpenServing'<>'true'
 OR (v_packet->>'workItemId')::uuid<>v_work
 OR (SELECT count(*) FROM atlas.care_observation_events)<>1
 THEN RAISE EXCEPTION 'FAIL alternative action duplicated open Work';END IF;
 RAISE NOTICE 'PASS second action cannot create competing open original Work';

 PERFORM set_config('atlas_test.signed_uid',v_worker::text,true);
 BEGIN
 PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state,v_scope,'heavy',v_note,
  v_observed_at,v_service_date,v_other_action);
 RAISE EXCEPTION 'FAIL connected worker forged governor source';
 EXCEPTION WHEN SQLSTATE '42501' THEN
 RAISE NOTICE 'PASS connected Person cannot impersonate observing governor';
 END;
 PERFORM set_config('atlas_test.signed_uid',v_owner::text,true);
 IF (SELECT count(*) FROM atlas.work_items)<>1
 THEN RAISE EXCEPTION 'FAIL Work count changed on denied action';END IF;
 IF has_function_privilege('authenticated',
    'atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL unreleased owner API granted to clients';END IF;
 RAISE NOTICE 'PASS owner writer client EXECUTE still revoked';
END;$tests$;
ROLLBACK;
