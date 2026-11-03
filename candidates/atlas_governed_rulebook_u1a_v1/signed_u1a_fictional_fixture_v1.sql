-- U1A signed test fixture. NEVER run against production, RiverSong's retained
-- noel_schema_clone:55432, or a database with real People or real Work.
-- The original C1 synthetic native Ledger/Bed 3 fixture and held U1A source
-- must already exist on a FRESH disposable Supabase local 127.0.0.1:54322 DB.
DO $u1a_fixture_guard$
BEGIN
 -- PostgreSQL reports its INTERNAL listening port/address from inside
 -- the container, not the Supabase host-mapped port. The controller verifies
 -- the host-bound loopback endpoint and fresh isolated project separately.
 -- The fixture additionally needs this session-local, controller-provided
 -- clone-only assertion and the exact four synthetic C1 identities below.
 IF current_database()<>'postgres'
    OR current_setting('u1a.disposable_clone',true) IS DISTINCT FROM 'true'
    OR (SELECT count(*) FROM auth.users WHERE id IN (
      'e5200000-0000-4000-8000-000000000001'::uuid,
      'e5200000-0000-4000-8000-000000000002'::uuid,
      'e5200000-0000-4000-8000-000000000003'::uuid,
      'e5200000-0000-4000-8000-000000000004'::uuid))<>4
    OR (SELECT count(*) FROM atlas.growing_objects o
         JOIN atlas.farms f ON f.id=o.farm_id
        WHERE o.id='e5200000-0000-4000-8000-000000000b03'::uuid
          AND f.organization_id='e5200000-0000-4000-8000-000000000801'::uuid)<>1
    OR (SELECT count(*) FROM atlas.ledger_organization_participations
        WHERE ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
          AND organization_id='e5200000-0000-4000-8000-000000000801'::uuid
          AND participation_kind='governing' AND status='active'
          AND is_compatibility_primary)<>1
    OR to_regprocedure('atlas.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)') IS NULL
    OR EXISTS (SELECT 1 FROM atlas.governed_rulebook_versions_v1)
    OR EXISTS (SELECT 1 FROM reality.entities
               WHERE id='e5200000-0000-4000-8000-000000000b03'::uuid)
    OR EXISTS (SELECT 1 FROM atlas.work_requirements
               WHERE id='ec310000-0000-4000-8000-000000000001'::uuid)
 THEN
   RAISE EXCEPTION 'Refusing U1A fictional fixture outside fresh protected signed C1 clone'
     USING ERRCODE='42501';
 END IF;
END;
$u1a_fixture_guard$;

-- C1 seeds the root Principal. Source review needs an independent signed
-- human Principal for its already-connected Worker/Reviewer.
INSERT INTO atlas.principals(id,user_id,person_id,stable_key,name,status)
SELECT
 'e5200000-0000-4000-8000-000000000112'::uuid,
 'e5200000-0000-4000-8000-000000000002'::uuid,
 'e5200000-0000-4000-8000-000000000102'::uuid,
 'c1-validation-reviewer-principal','Fictional independent reviewer','active'
WHERE NOT EXISTS (
 SELECT 1 FROM atlas.principals
 WHERE user_id='e5200000-0000-4000-8000-000000000002'::uuid
);

-- A synthetic canonical Reality twin for EXACTLY the existing synthetic
-- Bed 3 source. No other Work, Subject, Person or real farm is admitted.
INSERT INTO reality.entities(
 id,stable_key,entity_kind,display_name,identity_state,metadata
) VALUES (
 'e5200000-0000-4000-8000-000000000b03',
 'u1a-fictional-bed-3-reality-link','growing_object',
 'Fictional Bed 3 for Rulebook source-only test','canonical',
 '{"subjectDomain":"spatial","cloneFixture":true}'::jsonb
);

INSERT INTO atlas.work_requirements(
 id,organization_id,requirement_kind,summary,source_object_type,
 source_object_id,state,jurisdiction_key,metadata
) VALUES (
 'ec310000-0000-4000-8000-000000000001',
 'e5200000-0000-4000-8000-000000000801',
 'operational','Fictional Bed 3 stewardship need: source governance test only',
 'reality_entity','e5200000-0000-4000-8000-000000000b03',
 'active','u1a-disposable-signed-only',
 '{"needKey":"fictional_bed3_restorative_maintenance","cloneFixture":true}'::jsonb
);

-- No Rulebook version is preapproved by the fixture. Both identity/condition
-- Subject grants, original Foundry Event and independent custody approval
-- MUST come from the separately signed native RPCs in the Python test.
DO $u1a_fixture_assert$
BEGIN
 IF (SELECT count(*) FROM atlas.work_requirements WHERE
      id='ec310000-0000-4000-8000-000000000001'::uuid
      AND source_object_type='reality_entity'
      AND metadata->>'needKey'='fictional_bed3_restorative_maintenance')<>1
    OR EXISTS (SELECT 1 FROM atlas.governed_rulebook_versions_v1)
    OR EXISTS (SELECT 1 FROM atlas.governed_rulebook_bindings_v1)
 THEN RAISE EXCEPTION 'U1A fixture established wrong source or unauthorized policy'; END IF;
 RAISE NOTICE 'U1A isolated fictional Subject/Need fixture PASS: zero adopted Rulebook or Work';
END;
$u1a_fixture_assert$;
