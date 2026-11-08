-- HELD UNI-OPS Option A: fictional mowing source only, NEVER production.
-- Tested after exact 18-source local clone application. This is first-party
-- observational source data for a clearly fictional area, NOT a simulated
-- signed root policy decision or worker acceptance.
DO $guard$
BEGIN
  IF current_database()<>'postgres'
   OR current_setting('uniops.disposable_signed',true) IS DISTINCT FROM 'true'
   OR (SELECT count(*) FROM auth.users WHERE id IN (
     'e5200000-0000-4000-8000-000000000001'::uuid,
     'e5200000-0000-4000-8000-000000000002'::uuid,
     'e5200000-0000-4000-8000-000000000003'::uuid,
     'e5200000-0000-4000-8000-000000000004'::uuid))<>4
   OR (SELECT count(*) FROM atlas.farms WHERE
      id='e5200000-0000-4000-8000-000000000b01'::uuid
      AND organization_id='e5200000-0000-4000-8000-000000000801'::uuid)<>1
   OR to_regclass('atlas.governed_prework_candidate_offers_v1') IS NULL
   OR to_regclass('atlas.historical_self_adoption_review_events_v1') IS NULL
   OR EXISTS (SELECT 1 FROM atlas.governed_prework_candidate_offers_v1)
  THEN RAISE EXCEPTION 'Refusing fixture outside known clean signed clone' USING ERRCODE='42501';
  END IF;
END; $guard$;

-- Reviewer Principal maps to existing independently authenticated worker,
-- as in the source-owned U1A fictional signed fixture. It does NOT record
-- approval, policy adoption or delegated Work acceptance.
INSERT INTO atlas.principals(id,user_id,person_id,stable_key,name,status)
SELECT 'e5200000-0000-4000-8000-000000000112'::uuid,
 'e5200000-0000-4000-8000-000000000002'::uuid,
 'e5200000-0000-4000-8000-000000000102'::uuid,
 'u2-test-connected-worker-principal','Fictional connected worker','active'
WHERE NOT EXISTS (SELECT 1 FROM atlas.principals
                  WHERE user_id='e5200000-0000-4000-8000-000000000002'::uuid);

-- A NEW fictional native Area, not the existing Bed 3 care example.
INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state,metadata)
VALUES ('e5200000-0000-4000-8000-000000000d01',
'clone-test-mowing-area-reality','growing_object',
'Fictional mowing area, not actual Elm ground','canonical',
'{"subjectDomain":"spatial","cloneFixture":true}'::jsonb);
INSERT INTO atlas.growing_objects(id,farm_id,stable_key,label,object_type,metadata)
VALUES ('e5200000-0000-4000-8000-000000000d01',
'e5200000-0000-4000-8000-000000000b01',
'clone-test-mowing-area','Fictional mowing area','area',
'{"cloneFixture":true}'::jsonb);

-- The synthetic native Ledger's farm-crop custody and current rhythm source
-- pre-exist the signed policy decision and recipient's own consent.
INSERT INTO atlas.farm_crop_ledger_custody_v1(
 id,farm_id,ledger_id,established_by_principal_id,adjudication)
VALUES ('e5200000-0000-4000-8000-000000000d02',
'e5200000-0000-4000-8000-000000000b01',
'e5200000-0000-4000-8000-000000000401',
'e5200000-0000-4000-8000-000000000111',
'{"cloneFixture":true,"evidence":"synthetic farm-crop ledger custody"}'::jsonb);
INSERT INTO atlas.rhythm_rules(
 id,organization_id,farm_id,rule_key,rhythm_key,version,label,status,
 validity_interval_seconds,metadata)
VALUES ('e5200000-0000-4000-8000-000000000d03',
'e5200000-0000-4000-8000-000000000801',
'e5200000-0000-4000-8000-000000000b01',
'clone-mowing-stewardship','mowing',1,'Fictional mowing inspection','active',
604800,'{"timezoneName":"UTC","cloneFixture":true}'::jsonb);
INSERT INTO atlas.rhythm_bindings(
 id,organization_id,farm_id,rhythm_rule_id,binding_key,
 inheritance_layer,subject_kind,subject_id)
VALUES ('e5200000-0000-4000-8000-000000000d04',
'e5200000-0000-4000-8000-000000000801',
'e5200000-0000-4000-8000-000000000b01',
'e5200000-0000-4000-8000-000000000d03',
'clone-mowing-area','subject_override','growing_object',
'e5200000-0000-4000-8000-000000000d01');
INSERT INTO atlas.rhythm_state(
 id,organization_id,farm_id,rhythm_binding_id,rhythm_rule_id,rhythm_key,
 subject_kind,subject_id,state,effective_rule_version,visibility_scope,due_at)
VALUES ('e5200000-0000-4000-8000-000000000d05',
'e5200000-0000-4000-8000-000000000801',
'e5200000-0000-4000-8000-000000000b01',
'e5200000-0000-4000-8000-000000000d04',
'e5200000-0000-4000-8000-000000000d03','mowing','growing_object',
'e5200000-0000-4000-8000-000000000d01',
'due',1,'assigned_worker',now()-interval '1 day');
INSERT INTO atlas.mowing_area_state(
 object_id,organization_id,farm_id,status,last_observed_at,metadata)
VALUES ('e5200000-0000-4000-8000-000000000d01',
'e5200000-0000-4000-8000-000000000801',
'e5200000-0000-4000-8000-000000000b01',
'resting',now(),'{"cloneFixture":true,"physicalConditionAsserted":false}'::jsonb);

DO $check$
BEGIN
 IF (SELECT count(*) FROM atlas.rhythm_state
     WHERE id='e5200000-0000-4000-8000-000000000d05'::uuid
       AND rhythm_key='mowing')<>1
 OR (SELECT count(*) FROM atlas.governed_farm_rulebook_scope_versions_v1)<>0
 OR (SELECT count(*) FROM atlas.governed_prework_candidate_offers_v1)<>0
 OR (SELECT count(*) FROM atlas.work_items
     WHERE source_object_id='e5200000-0000-4000-8000-000000000d05'::uuid)<>0
 THEN RAISE EXCEPTION 'Test fixture illegally preapproved policy or Work' USING ERRCODE='23514';
 END IF;
END; $check$;
