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



-- EXACT DOMAIN ACTUAL ADAPTER SOURCE BLOB 97b1486a807ee01328c682af49fcd6b7db46f64e

-- Integrated source-support additions, never released. Base owner fixture
-- is the same source-exact code as the previously passing governor test.
ALTER TABLE atlas.work_result_contract_policies ADD COLUMN description text;
ALTER TABLE atlas.work_items ADD COLUMN completed_at timestamptz;
ALTER TABLE atlas.work_allocations
 ADD COLUMN allocated_at timestamptz NOT NULL DEFAULT now(),
 ADD COLUMN completed_at timestamptz,
 ADD COLUMN updated_at timestamptz DEFAULT now();
ALTER TABLE atlas.rhythm_rules
 ADD COLUMN qualifying_touches jsonb,
 ADD COLUMN validity_interval_seconds integer,
 ADD COLUMN warning_window_seconds integer,
 ADD COLUMN grace_window_seconds integer;
ALTER TABLE atlas.rhythm_state
 ADD COLUMN last_qualifying_satisfaction_id uuid,
 ADD COLUMN lease_started_at timestamptz,
 ADD COLUMN warning_at timestamptz,
 ADD COLUMN due_at timestamptz,
 ADD COLUMN failure_at timestamptz,
 ADD COLUMN recovery_started_at timestamptz,
 ADD COLUMN last_evaluated_at timestamptz,
 ADD COLUMN last_transition_at timestamptz,
 ADD COLUMN state_reason jsonb,
 ADD COLUMN updated_at timestamptz DEFAULT now();
ALTER TABLE atlas.weed_cards
 ADD COLUMN created_at timestamptz DEFAULT now(),
 ADD COLUMN current_condition text,
 ADD COLUMN last_session_at timestamptz,
 ADD COLUMN next_review_on date,
 ADD COLUMN metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN updated_at timestamptz DEFAULT now();
UPDATE atlas.weed_cards SET current_condition='heavy';
UPDATE atlas.rhythm_rules SET
 qualifying_touches='[
  {"effect":"full","sourceKind":"object","sourceEvent":"weeded_reset"},
  {"effect":"partial","sourceKind":"object","sourceEvent":"weeded",
   "payloadContains":{"metadata":{"transition":"partial"}}}
 ]'::jsonb,
 validity_interval_seconds=604800,
 warning_window_seconds=86400,
 grace_window_seconds=172800;

CREATE FUNCTION atlas.rhythm_safe_uuid_v1(p_value text) RETURNS uuid
LANGUAGE plpgsql IMMUTABLE SET search_path TO ''
AS $f$
BEGIN
 IF p_value IS NULL
 OR p_value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RETURN NULL;END IF;
 RETURN p_value::uuid;
END;$f$;
CREATE FUNCTION atlas.rhythm_boundary_at_v1(
 p_start timestamptz,p_seconds integer,p_tz text,p_boundary text
) RETURNS timestamptz
LANGUAGE sql IMMUTABLE SET search_path TO ''
AS $f$SELECT p_start+make_interval(secs=>p_seconds)$f$;

-- Mock only: NOT the production signed native Subject reader.
CREATE FUNCTION atlas.person_original_work_identity_disclosed_self_v1(
 p_org uuid,p_ledger uuid,p_work uuid,p_person uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path TO ''
AS $f$
SELECT p_org='73000000-0000-4000-8000-000000000001'::uuid
 AND p_ledger='73000000-0000-4000-8000-000000000002'::uuid
 AND p_person='73000000-0000-4000-8000-000000000004'::uuid
 AND p_person=auth.uid()
 AND EXISTS(
   SELECT 1 FROM atlas.work_allocations a
   WHERE a.work_item_id=p_work AND a.assignee_canonical_person_id=p_person
     AND a.state IN ('active','completed')
 )
 AND current_setting('atlas_test.disclosure',true) IS DISTINCT FROM 'withheld'
$f$;

CREATE TABLE atlas.care_result_events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 subject_domain text,subject_kind text,subject_id text,
 scope_kind text,scope_id uuid,
 occurred_at timestamptz,result_kind text,condition_before text,
 condition_after text,minutes integer,minutes_known boolean,
 actor_user_id uuid,source_kind text,source_key text,
 note text,metadata jsonb DEFAULT '{}'::jsonb
);
CREATE TABLE atlas.work_execution_results(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,household_id uuid,work_item_id uuid,
 responsible_allocation_id uuid,reported_by_user_id uuid,result_kind text,
 result_contract_key text,idempotency_key text,payload jsonb,
 metadata jsonb,reported_at timestamptz,
 UNIQUE(organization_id,idempotency_key)
);
CREATE TABLE atlas.work_result_acceptances(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,household_id uuid,
 work_item_id uuid,execution_result_id uuid,
 decision text,acceptance_kind text,accepted_by_domain text,evidence jsonb
);
CREATE TABLE atlas.rhythm_satisfactions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid,farm_id uuid,rhythm_state_id uuid,
 rhythm_binding_id uuid,rhythm_rule_id uuid,rhythm_key text,
 subject_kind text,subject_id uuid,satisfaction_key text,
 satisfaction_kind text,satisfied_at timestamptz,
 renewal_interval_seconds integer,source_kind text,source_id uuid,
 source_event text,policy_match jsonb,evidence jsonb,created_by_user_id uuid
);

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

-- EXACT FIRST-PARTY ACTUAL GUARDS SOURCE BLOB 4983bace4a5ce83c73580316117955b5964a571c
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


DO $integrated$
DECLARE
 v_org uuid:='73000000-0000-4000-8000-000000000001';
 v_ledger uuid:='73000000-0000-4000-8000-000000000002';
 v_owner uuid:='73000000-0000-4000-8000-000000000003';
 v_worker uuid:='73000000-0000-4000-8000-000000000004';
 v_outsider uuid:='73000000-0000-4000-8000-000000000099';
 v_state_id uuid:='73000000-0000-4000-8000-000000000009';
 v_bed uuid:='73000000-0000-4000-8000-000000000006';
 v_scope uuid:='73000000-0000-4000-8000-000000000011';
 v_action uuid:='73000000-0000-4000-8000-000000000021';
 v_partial_action uuid:='73000000-0000-4000-8000-000000000022';
 v_full_action uuid:='73000000-0000-4000-8000-000000000023';
 v_date date:=(now() AT TIME ZONE 'UTC')::date;
 v_observed_at timestamptz:=now()-interval '5 minutes';
 v_note text:='Observed heavy weed pressure in fictional Bed A.';
 v_work uuid;
 v_receipt jsonb;
 v_partial jsonb;
 v_full jsonb;
 v_readback jsonb;
BEGIN
 -- Actual owner writes source Need, original Work, accepted standing scope,
 -- Person allocation and intentional service date (not rhythm due_at).
 PERFORM set_config('atlas_test.signed_uid',v_owner::text,true);
 v_receipt:=atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state_id,v_scope,'heavy',v_note,
  v_observed_at,v_date,v_action
 );
 v_work:=(v_receipt->>'workItemId')::uuid;
 IF v_work IS NULL OR v_receipt->>'newOriginalWorkCreated'<>'true'
 OR (SELECT count(*) FROM atlas.work_items)<>1
 OR (SELECT count(*) FROM atlas.work_allocations)<>1
 OR (SELECT count(*) FROM atlas.work_execution_plans)<>1
 OR (SELECT count(*) FROM atlas.care_observation_events)<>1
 THEN RAISE EXCEPTION 'FAIL integrated governor Need -> Work + Person-day';END IF;
 RAISE NOTICE 'PASS governor observation establishes one Work with one Person-day';

 IF (SELECT planned_service_date FROM atlas.work_execution_plans
      WHERE work_item_id=v_work LIMIT 1)<>v_date
 OR (SELECT condition_state FROM atlas.care_current_state
     WHERE subject_id=v_bed::text LIMIT 1)<>'heavy'
 THEN RAISE EXCEPTION 'FAIL service date or observed precondition lost';END IF;
 RAISE NOTICE 'PASS governor date and source physical condition persisted';

 -- Same original Work reported by the actually assigned fictional Person.
 PERFORM set_config('atlas_test.signed_uid',v_worker::text,true);
 v_partial:=atlas.record_continuing_care_actual_self_api_v1(
  v_work,v_partial_action,'weeded_partial','row_readable',18,
  'Weeded center and left edge roots for next session',NULL);
 IF v_partial->>'workState'<>'open'
 OR (SELECT work_state FROM atlas.work_items WHERE id=v_work)<>'open'
 OR (SELECT condition_state FROM atlas.care_current_state
    WHERE subject_id=v_bed::text LIMIT 1)<>'row_readable'
 OR (SELECT current_condition FROM atlas.weed_cards WHERE object_id=v_bed)<>'row_readable'
 OR (SELECT count(*) FROM atlas.rhythm_satisfactions)<>0
 THEN RAISE EXCEPTION 'FAIL integrated partial Actual changed wrong physical state or Work';END IF;
 RAISE NOTICE 'PASS assigned Person partially weeds the SAME open original';

 PERFORM set_config('atlas_test.signed_uid',v_outsider::text,true);
 BEGIN
  PERFORM atlas.record_continuing_care_actual_self_api_v1(
   v_work,v_full_action,'weeded_full','clear',10,
   'Outside Person should not complete this Work',NULL);
  RAISE EXCEPTION 'FAIL unrelated Person completed Work';
 EXCEPTION WHEN SQLSTATE '42501' THEN
  RAISE NOTICE 'PASS outsider cannot submit result for someone else';
 END;
 PERFORM set_config('atlas_test.signed_uid',v_worker::text,true);

 v_full:=atlas.record_continuing_care_actual_self_api_v1(
  v_work,v_full_action,'weeded_full','clear',12,
  'Finished outer edges; verified all rows clear',NULL);
 IF v_full->>'workState'<>'completed'
 OR (SELECT work_state FROM atlas.work_items WHERE id=v_work)<>'completed'
 OR (SELECT state FROM atlas.rhythm_state WHERE id=v_state_id)<>'resting'
 OR (SELECT state FROM atlas.work_allocations
     WHERE work_item_id=v_work LIMIT 1)<>'completed'
 OR (SELECT current_condition FROM atlas.weed_cards WHERE object_id=v_bed)<>'clear'
 OR (SELECT condition_state FROM atlas.care_current_state
     WHERE subject_id=v_bed::text LIMIT 1)<>'clear'
 OR (SELECT count(*) FROM atlas.rhythm_satisfactions
     WHERE satisfaction_kind='full')<>1
 THEN RAISE EXCEPTION 'FAIL integrated full Actual did not settle original Need';END IF;
 RAISE NOTICE 'PASS full Actual closes same Work, sets clear and satisfies Rhythm';

 IF (SELECT count(*) FROM atlas.work_items)<>1
 OR (SELECT count(*) FROM atlas.work_execution_results)<>2
 OR (SELECT count(*) FROM atlas.work_result_acceptances)<>2
 OR (SELECT count(*) FROM atlas.care_result_events)<>2
 OR (SELECT count(*) FROM atlas.care_observation_events)<>3
 OR (SELECT count(*) FROM atlas.work_execution_plans)<>1
 THEN RAISE EXCEPTION 'FAIL integrated history or Work duplicates';END IF;
 RAISE NOTICE 'PASS observed Need plus two actual Results preserve one canonical Work';

 -- Owner may replay prior original action after completion but never
 -- reopen closed Work, create another Work or rewrite observed conditions.
 PERFORM set_config('atlas_test.signed_uid',v_owner::text,true);
 v_readback:=atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  v_org,v_ledger,v_state_id,v_scope,'heavy',v_note,
  v_observed_at,v_date,v_action);
 IF v_readback->>'existingAction'<>'true'
 OR (v_readback->>'workItemId')::uuid<>v_work
 OR (SELECT count(*) FROM atlas.work_items)<>1
 OR (SELECT count(*) FROM atlas.care_observation_events)<>3
 THEN RAISE EXCEPTION 'FAIL owner replay re-opened original or repeated Need';END IF;
 RAISE NOTICE 'PASS owner action retry after completion retains original historical identity';

 -- A NEW observation whose timestamp predates the actual completed Work
 -- cannot overwrite the latest physical source and create phantom Work.
 BEGIN
  PERFORM atlas.owner_establish_observed_continuing_care_work_self_api_v1(
   v_org,v_ledger,v_state_id,v_scope,'heavy',
   'Fictional stale observation should not override completed Result',
   v_observed_at,v_date,'73000000-0000-4000-8000-000000000024'::uuid);
  RAISE EXCEPTION 'FAIL older physical observation created phantom Work';
 EXCEPTION WHEN SQLSTATE '23514' THEN
  RAISE NOTICE 'PASS older observation cannot create a next Work';
 END;

 IF has_function_privilege('authenticated',
   'atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)','EXECUTE')
 OR has_function_privilege('authenticated',
   'atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL prerelease source writer exposed to ordinary role';END IF;
 RAISE NOTICE 'PASS both unreleased client writers remain denied';
END;
$integrated$;
ROLLBACK;
