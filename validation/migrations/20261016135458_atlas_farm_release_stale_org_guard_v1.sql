-- Run only in a disposable schema clone after the candidate is applied.
do $$
declare
  src text;
begin
  select pg_get_functiondef(oid) into src
  from pg_proc
  where oid = to_regprocedure('atlas.release_eligible_work_without_weed_physical_gate_v1(uuid,date,integer)');
  if src is null
     or position('releaseHoldReason' in src)=0
     or position('unresolved_organization' in src)=0
     or position('invalidOrganizationHeld' in src)=0
     or position('from atlas.organizations org' in src)=0 then
    raise exception 'Release hold candidate absent or incomplete';
  end if;
  if not exists(select 1 from pg_constraint where conname='tasks_organization_id_fkey') then
    raise exception 'Task organization foreign key must remain enforced';
  end if;
end $$;


-- Behavioral fixture in the disposable production-schema clone ONLY.
-- Roll back every synthetic row and task before the lint/advisor pass.
BEGIN;
DO $proof$
DECLARE
  v_org uuid := gen_random_uuid();
  v_bad_org uuid := gen_random_uuid();
  v_farm uuid := gen_random_uuid();
  v_definition uuid := gen_random_uuid();
  v_policy uuid := gen_random_uuid();
  v_bad_occ uuid := gen_random_uuid();
  v_good_occ uuid := gen_random_uuid();
  v_first_hold timestamptz;
  v_result jsonb;
  v_count int;
BEGIN
  INSERT INTO atlas.organizations(id,stable_key,name)
  VALUES(v_org,'ci_release_org_'||substr(replace(v_org::text,'-',''),1,20),'Isolated release validation');

  INSERT INTO atlas.farms(id,stable_key,name,organization_id)
  VALUES(v_farm,'ci_release_farm_'||substr(replace(v_farm::text,'-',''),1,20),'Isolated release farm',v_org);

  INSERT INTO atlas.farm_task_release_settings(farm_id,active,maximum_release_batch_size,maximum_active_safety_tasks)
  VALUES(v_farm,true,10,50);

  INSERT INTO atlas.work_definitions(id,farm_id,stable_key,title_template)
  VALUES(v_definition,v_farm,'ci_release_definition','Validation work');

  INSERT INTO atlas.work_release_policies(
    id,farm_id,work_definition_id,stable_key,gate_type,horizon_days,maximum_active_instances
  ) VALUES(
    v_policy,v_farm,v_definition,'ci_release_policy','immediate',2,10
  );

  INSERT INTO atlas.planned_work_occurrences(
    id,farm_id,work_definition_id,release_policy_id,occurrence_key,
    title,planned_due_date,not_before_date,state,task_payload,work_lane,commitment_kind,
    created_at
  ) VALUES
  (v_bad_occ,v_farm,v_definition,v_policy,'ci_bad','CI invalid organization',current_date,current_date,
   'eligible',jsonb_build_object('organization_id',v_bad_org,'title','CI invalid organization',
   'metadata',jsonb_build_object('work_window_key','none')),
   'required','hard_date',now()-interval '2 minutes'),
  (v_good_occ,v_farm,v_definition,v_policy,'ci_good','CI valid organization',current_date,current_date,
   'eligible',jsonb_build_object('organization_id',v_org,'title','CI valid organization',
   'metadata',jsonb_build_object('work_window_key','none')),
   'required','hard_date',now()-interval '1 minute');

  IF NOT atlas.work_occurrence_gate_satisfied_v1(v_bad_occ,current_date)
    OR NOT atlas.work_occurrence_gate_satisfied_v1(v_good_occ,current_date) THEN
    RAISE EXCEPTION 'Fixture occurrences do not meet the production release gate';
  END IF;

  v_result:=atlas.release_eligible_work_without_weed_physical_gate_v1(v_farm,current_date,10);
  IF coalesce((v_result->>'released')::int,-1)<>1
     OR coalesce((v_result->>'invalidOrganizationHeld')::int,-1)<>1 THEN
    RAISE EXCEPTION 'Wrong valid-release/invalid-hold counts: %',v_result;
  END IF;
  IF EXISTS(SELECT 1 FROM atlas.tasks WHERE planned_occurrence_id=v_bad_occ)
     OR NOT EXISTS(SELECT 1 FROM atlas.tasks
       WHERE planned_occurrence_id=v_good_occ AND organization_id=v_org AND status='open')
     OR NOT EXISTS(SELECT 1 FROM atlas.planned_work_occurrences
       WHERE id=v_bad_occ AND state='eligible'
       AND metadata->>'releaseHoldReason'='unresolved_organization'
       AND metadata->>'releaseHoldOrgId'=v_bad_org::text)
  THEN
    RAISE EXCEPTION 'Invalid occurrence was lost, or correct task was not released';
  END IF;

  SELECT (metadata->>'releaseHeldAt')::timestamptz INTO v_first_hold
  FROM atlas.planned_work_occurrences WHERE id=v_bad_occ;
  IF v_first_hold IS NULL THEN RAISE EXCEPTION 'Missing original audit hold timestamp'; END IF;

  v_result:=atlas.release_eligible_work_without_weed_physical_gate_v1(v_farm,current_date,10);
  IF coalesce((v_result->>'released')::int,-1)<>0
     OR coalesce((v_result->>'invalidOrganizationHeld')::int,-1)<>1
     OR (SELECT (metadata->>'releaseHeldAt')::timestamptz
         FROM atlas.planned_work_occurrences WHERE id=v_bad_occ) IS DISTINCT FROM v_first_hold
     OR (SELECT count(*) FROM atlas.tasks WHERE farm_id=v_farm)<>1 THEN
    RAISE EXCEPTION 'Retry duplicated work or rewrote immutable first hold: %',v_result;
  END IF;

  -- A separately authorized upstream source correction makes the held work
  -- eligible again; the function must not auto-reassign its org.
  UPDATE atlas.planned_work_occurrences
  SET task_payload=jsonb_set(task_payload,'{organization_id}',to_jsonb(v_org::text))
  WHERE id=v_bad_occ;

  v_result:=atlas.release_eligible_work_without_weed_physical_gate_v1(v_farm,current_date,10);
  IF coalesce((v_result->>'released')::int,-1)<>1
     OR (SELECT count(*) FROM atlas.tasks WHERE farm_id=v_farm)<>2
     OR NOT EXISTS(SELECT 1 FROM atlas.planned_work_occurrences
       WHERE id=v_bad_occ AND state='released' AND released_task_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Corrected source did not release exactly once: %',v_result;
  END IF;

  SELECT count(*) INTO v_count FROM atlas.task_release_events
  WHERE occurrence_id IN (v_bad_occ,v_good_occ);
  IF v_count<>2 THEN
    RAISE EXCEPTION 'Expected exactly two canonical release events; found %',v_count;
  END IF;

  RAISE NOTICE 'Passed release behavior: valid=1 held=1, retry idempotent, corrected=1, total release events=2.';
END;
$proof$;
ROLLBACK;
