-- TEST ONLY. Apply after canonical held original-Work fixture and the
-- combined #2368/#2362 SQL in a newly disposable Supabase local clone.
-- NEVER apply on Noel production, RiverSong's retained clone, or real Elm.
-- Adds ONLY fictional governed care source rows, not an employee seat.
DO $fixture_guard$
BEGIN
 IF current_database()<>'postgres'
   OR to_regclass('atlas.work_lifecycle_events_v1') IS NULL
   OR to_regprocedure('atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)') IS NULL
   OR (SELECT count(*) FROM atlas.growing_objects
       WHERE id IN ('e5200000-0000-4000-8000-000000000b03'::uuid,
                    'e5200000-0000-4000-8000-000000000b04'::uuid))<>2
   OR (SELECT count(*) FROM atlas.work_items
       WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid
       AND source_object_type='rhythm_state')<>0
 THEN RAISE EXCEPTION 'Refusing care fixture outside the exact disposable signed-original-Work clone'; END IF;
END;
$fixture_guard$;

INSERT INTO atlas.rhythm_rules(
 id,organization_id,farm_id,rule_key,rhythm_key,version,label,status,
 applicability,validity_interval_seconds,warning_window_seconds,
 grace_window_seconds,qualifying_touches,failure_consequence,player_routing,
 metadata
) VALUES
('ec300000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'clone-signed-bed3-weed','weed_stewardship',1,'Fictional Bed 3 care','active',
 '{}'::jsonb,604800,86400,86400,
 '[{"effect":"full","sourceKind":"object","sourceEvent":"weeded_reset"},
   {"effect":"partial","sourceKind":"object","sourceEvent":"weeded",
    "payloadContains":{"metadata":{"transition":"partial"}}},
   {"effect":"conditional","sourceKind":"field_log",
    "sourceEvent":"action:weed_inspection_acceptable"}]'::jsonb,
 '{}'::jsonb,'{}'::jsonb,'{"timezoneName":"America/Chicago"}'::jsonb);

INSERT INTO atlas.rhythm_bindings(
 id,organization_id,farm_id,rhythm_rule_id,binding_key,inheritance_layer,
 subject_kind,subject_id,priority,active,metadata
) VALUES
('ec300000-0000-4000-8000-000000000002',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'ec300000-0000-4000-8000-000000000001',
 'clone-signed-bed3-specific','subject_override','growing_object',
 'e5200000-0000-4000-8000-000000000b03',100,true,'{}'::jsonb);

INSERT INTO atlas.rhythm_state(
 id,organization_id,farm_id,rhythm_binding_id,rhythm_rule_id,rhythm_key,
 subject_kind,subject_id,state,effective_rule_version,visibility_scope,
 state_reason,metadata
) VALUES
('ec300000-0000-4000-8000-000000000003',
 'e5200000-0000-4000-8000-000000000801',
 'e5200000-0000-4000-8000-000000000b01',
 'ec300000-0000-4000-8000-000000000002',
 'ec300000-0000-4000-8000-000000000001',
 'weed_stewardship','growing_object',
 'e5200000-0000-4000-8000-000000000b03',
 'due',1,'owner','{"source":"fictional_signed_care_proof"}'::jsonb,
 '{}'::jsonb);

INSERT INTO atlas.weed_cards(
 id,farm_id,object_id,card_key,current_condition,target_condition,metadata
) VALUES
('ec300000-0000-4000-8000-000000000004',
 'e5200000-0000-4000-8000-000000000b01',
 'e5200000-0000-4000-8000-000000000b03',
 'clone-signed-bed3','heavy','clear','{}'::jsonb);

DO $post$
BEGIN
 IF (SELECT count(*) FROM atlas.rhythm_state
     WHERE id='ec300000-0000-4000-8000-000000000003'::uuid
       AND state='due')<>1
 OR (SELECT count(*) FROM atlas.work_items
     WHERE source_object_id='ec300000-0000-4000-8000-000000000003'::uuid)<>0
 THEN RAISE EXCEPTION 'Fictional care baseline pre-created Work or drifted'; END IF;
END;
$post$;
