-- Original-Work smoke test: synthetic fake domain rows; exact drafted primitive.
-- LOCAL ONLY, DB atlas_test ONLY. ROLLBACK restores everything after success.
-- Not real Auth/Supabase; not the full care-Result/Today cycle.
BEGIN;
DO $guard$
BEGIN
 IF current_database()<>'atlas_test' OR current_setting('server_version_num')::integer<170000
 OR to_regnamespace('atlas') IS NOT NULL OR to_regnamespace('auth') IS NOT NULL
 THEN RAISE EXCEPTION 'Refused: requires empty local atlas_test on PG17'; END IF;
END;$guard$;
CREATE SCHEMA atlas;
CREATE SCHEMA auth;
DO $roles$
DECLARE n text;
BEGIN
 FOREACH n IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname=n)
 THEN EXECUTE format('CREATE ROLE %I NOLOGIN',n); END IF;
 END LOOP;
END;$roles$;
-- Explicit test substitutes, NOT production authority implementations:
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE SET search_path TO ''
AS $t$SELECT nullif(current_setting('atlas_smoke.uid',true),'')::uuid$t$;
CREATE FUNCTION atlas.require_household_governor_self_v1(uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $t$
BEGIN RAISE EXCEPTION 'Synthetic household not configured' USING ERRCODE='42501';END;$t$;
CREATE FUNCTION atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $t$
BEGIN
 IF $1 IS DISTINCT FROM '71000000-0000-4000-8000-000000000001'::uuid
 OR $2 IS DISTINCT FROM '71000000-0000-4000-8000-000000000002'::uuid
 OR auth.uid() IS DISTINCT FROM '71000000-0000-4000-8000-000000000003'::uuid
 THEN RAISE EXCEPTION 'Wrong synthetic Ledger or owner' USING ERRCODE='42501'; END IF;
 RETURN auth.uid();
END;$t$;
CREATE TABLE atlas.household_need_occurrences_v1(
id uuid PRIMARY KEY,household_id uuid,instance_id uuid,state text,opened_by_observation_id uuid,
current_work_item_id uuid,updated_at timestamptz);
CREATE TABLE atlas.household_kernel_instances(id uuid PRIMARY KEY,household_id uuid,kernel_key text,state text);
CREATE TABLE atlas.care_current_state(
scope_kind text,scope_id uuid,subject_domain text,subject_kind text,subject_id text,
condition_state text,last_observation_id uuid);
CREATE TABLE atlas.growing_objects(id uuid PRIMARY KEY,farm_id uuid);
CREATE TABLE atlas.rhythm_rules(id uuid PRIMARY KEY,status text);
CREATE TABLE atlas.rhythm_bindings(id uuid PRIMARY KEY,active boolean,rhythm_rule_id uuid);
CREATE TABLE atlas.rhythm_state(
id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,subject_kind text,
subject_id uuid,state text,rhythm_binding_id uuid);
CREATE TABLE atlas.work_result_contract_policies(
contract_key text PRIMARY KEY,active boolean,source_domain text,acceptance_mode text,metadata jsonb);
CREATE TABLE atlas.work_items(
id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
organization_id uuid,household_id uuid,title text NOT NULL,instructions text,work_state text NOT NULL,
source_object_type text,source_object_id uuid,stable_key text,result_contract_key text,
created_by_user_id uuid,metadata jsonb DEFAULT '{}'::jsonb,updated_at timestamptz DEFAULT now());
CREATE TABLE atlas.work_item_context_links(
id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid,household_id uuid,
work_item_id uuid,subject_domain text,subject_kind text,subject_id uuid,relation_kind text,
provenance jsonb,metadata jsonb);
INSERT INTO atlas.rhythm_rules VALUES('71000000-0000-4000-8000-000000000007','active');
INSERT INTO atlas.rhythm_bindings VALUES(
'71000000-0000-4000-8000-000000000006',true,'71000000-0000-4000-8000-000000000007');
INSERT INTO atlas.growing_objects VALUES(
'71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000004');
INSERT INTO atlas.rhythm_state VALUES (
'71000000-0000-4000-8000-000000000008',
'71000000-0000-4000-8000-000000000001',
'71000000-0000-4000-8000-000000000004',
'growing_object','71000000-0000-4000-8000-000000000005',
'due','71000000-0000-4000-8000-000000000006');
INSERT INTO atlas.work_result_contract_policies VALUES(
'continuing_care_actual_v1',true,'organization','domain_adapter',
'{"continuingActualQualification":"source_proven_v1"}');
-- Source-exact primitive function follows. Source hash maintained in Git.

-- Imported directly from candidate.sql blob a1b45327e3b8de6582b86f446f56cc3b25ab904c
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


DO $test$
DECLARE
 owner uuid:='71000000-0000-4000-8000-000000000003';
 org uuid:='71000000-0000-4000-8000-000000000001';
 ledger uuid:='71000000-0000-4000-8000-000000000002';
 state uuid:='71000000-0000-4000-8000-000000000008';
 bed uuid:='71000000-0000-4000-8000-000000000005';
 result jsonb; original uuid; second uuid;
BEGIN
 PERFORM set_config('atlas_smoke.uid',owner::text,true);
 result:=atlas.establish_continuing_original_work_internal_v1(
 'organization',org,ledger,'rhythm_state',state,'first',
 'spatial','growing_object',bed,'Synthetic Bed 3 weeding',
 'Fictional physical Need','continuing_care_actual_v1');
 IF result->>'noNewWorkCreated'<>'false' THEN
 RAISE EXCEPTION 'FAIL: first original not created';END IF;
 original:=(result->>'workItemId')::uuid;
 IF (SELECT count(*) FROM atlas.work_items)<>1 THEN
 RAISE EXCEPTION 'FAIL: initial Work count';END IF;
 RAISE NOTICE 'PASS original Work created on exact fictional Need';

 result:=atlas.establish_continuing_original_work_internal_v1(
 'organization',org,ledger,'rhythm_state',state,'first',
 'spatial','growing_object',bed,'Synthetic Bed 3 weeding',
 'Fictional physical Need','continuing_care_actual_v1');
 IF result->>'noNewWorkCreated'<>'true'
 OR (result->>'workItemId')::uuid<>original
 OR (SELECT count(*) FROM atlas.work_items)<>1
 THEN RAISE EXCEPTION 'FAIL: replay duplicate'; END IF;
 RAISE NOTICE 'PASS retry preserves exact original Work';

 result:=atlas.establish_continuing_original_work_internal_v1(
 'organization',org,ledger,'rhythm_state',state,'second',
 'spatial','growing_object',bed,'Synthetic Bed 3 weeding',
 'Fictional physical Need','continuing_care_actual_v1');
 IF result->>'noNewWorkCreated'<>'true'
 OR (result->>'workItemId')::uuid<>original
 THEN RAISE EXCEPTION 'FAIL: open Need duplicated'; END IF;
 RAISE NOTICE 'PASS open Need cannot spawn duplicate Work';

 IF (SELECT count(*) FROM atlas.work_item_context_links
 WHERE work_item_id=original AND subject_id=bed
 AND subject_domain='spatial' AND subject_kind='growing_object'
 AND relation_kind='acts_on')<>1
 THEN RAISE EXCEPTION 'FAIL: Subject link mismatch'; END IF;
 RAISE NOTICE 'PASS correct Subject context';

 PERFORM set_config('atlas_smoke.uid','',true);
 BEGIN
 PERFORM atlas.establish_continuing_original_work_internal_v1(
 'organization',org,ledger,'rhythm_state',state,'forged',
 'spatial','growing_object',bed,'Unsafe attempt',
 'Unsigned work','continuing_care_actual_v1');
 RAISE EXCEPTION 'FAIL: unsigned permitted';
 EXCEPTION WHEN SQLSTATE '22023' THEN
 RAISE NOTICE 'PASS synthetic unsigned invocation denied';
 END;
 PERFORM set_config('atlas_smoke.uid',owner::text,true);
 BEGIN
 PERFORM atlas.establish_continuing_original_work_internal_v1(
 'organization',org,'71000000-0000-4000-8000-000000000009',
 'rhythm_state',state,'forged','spatial','growing_object',
 bed,'Bad ledger','Unsafe','continuing_care_actual_v1');
 RAISE EXCEPTION 'FAIL: other Ledger permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN
 RAISE NOTICE 'PASS wrong synthetic Ledger denied';
 END;

 UPDATE atlas.work_items SET work_state='completed' WHERE id=original;
 BEGIN
 PERFORM atlas.establish_continuing_original_work_internal_v1(
 'organization',org,ledger,'rhythm_state',state,'first',
 'spatial','growing_object',bed,'Old work','Stale key',
 'continuing_care_actual_v1');
 RAISE EXCEPTION 'FAIL: closed serving reopened';
 EXCEPTION WHEN SQLSTATE '23514' THEN
 RAISE NOTICE 'PASS closed serving identity cannot reopen';
 END;
 result:=atlas.establish_continuing_original_work_internal_v1(
 'organization',org,ledger,'rhythm_state',state,'second',
 'spatial','growing_object',bed,'New serving','Separate identity',
 'continuing_care_actual_v1');
 second:=(result->>'workItemId')::uuid;
 IF second=original OR (SELECT count(*) FROM atlas.work_items)<>2 THEN
 RAISE EXCEPTION 'FAIL: new serving did not preserve history'; END IF;
 RAISE NOTICE 'PASS new serving only after prior original Work closed';

 IF has_function_privilege(
 'authenticated',
 'atlas.establish_continuing_original_work_internal_v1(text,uuid,uuid,text,uuid,text,text,text,uuid,text,text,text)',
 'EXECUTE')
 THEN RAISE EXCEPTION 'FAIL internal helper exposed to authenticated'; END IF;
 RAISE NOTICE 'PASS internal helper EXECUTE denied to authenticated role';
END;$test$;
ROLLBACK;
