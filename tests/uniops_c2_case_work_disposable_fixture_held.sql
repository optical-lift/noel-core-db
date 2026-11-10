-- HELD UNI-OPS C2: synthetic Case -> original Work relevance discrimination.
-- TEST DATA ONLY. Requires disposable PG17 C1 fixture, completed signed C1
-- establish/revise probe, and candidate #2668 installed ONLY on the clone.
-- This file is never a migration, production seed, or permission grant.
\set ON_ERROR_STOP on
BEGIN;
DO $c2_guard$
DECLARE
  v_source text;
BEGIN
  IF current_database() IS DISTINCT FROM 'postgres'
    OR current_setting('server_version_num')::integer/10000 <> 17
    OR current_setting('uni_ops.disposable_clone',true) IS DISTINCT FROM 'true'
    OR (SELECT count(*) FROM auth.users WHERE id IN (
      'e5200000-0000-4000-8000-000000000001'::uuid,
      'e5200000-0000-4000-8000-000000000002'::uuid,
      'e5200000-0000-4000-8000-000000000003'::uuid,
      'e5200000-0000-4000-8000-000000000004'::uuid)) <> 4
    OR (SELECT count(*) FROM atlas.company_work_operating_register_entries
      WHERE organization_id='e5200000-0000-4000-8000-000000000801'::uuid
        AND ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
        AND stable_key='signed_http_c1') <> 1
    OR EXISTS (SELECT 1 FROM atlas.ledgers
      WHERE id='e5200000-0000-4000-8000-000000000402'::uuid)
    OR EXISTS (SELECT 1 FROM atlas.work_items
      WHERE id IN (
        'e5200000-0000-4000-8000-000000000c21'::uuid,
        'e5200000-0000-4000-8000-000000000c22'::uuid,
        'e5200000-0000-4000-8000-000000000c23'::uuid,
        'e5200000-0000-4000-8000-000000000c24'::uuid))
  THEN
    RAISE EXCEPTION 'Refuse C2: exact disposable C1 clone prerequisite missing'
      USING ERRCODE='42501';
  END IF;
  SELECT pg_get_functiondef(
    'atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure
  ) INTO v_source;
  IF position('rel.work_item_id=i.id' IN v_source)=0
    OR position('rel.ledger_id=p_ledger_id' IN v_source)=0
    OR position('rel.attribution_state=''active''' IN v_source)=0
    OR position('company_work_native_ledger_exact_source_v1' IN v_source)=0
  THEN
    RAISE EXCEPTION 'Refuse C2: exact Ledger relevance source predicate absent'
      USING ERRCODE='42501';
  END IF;
END
$c2_guard$;

-- C1 supplies a real *synthetic* native Ledger B and outsider native seat.
-- Add its missing Atlas institution participation. Never make it primary.
INSERT INTO atlas.ledgers(id,stable_key,name,ledger_kind,status,organization_id)
VALUES ('e5200000-0000-4000-8000-000000000402'::uuid,
  'c2-foreign-ledger-b','C2 Synthetic L2','governed_reality','active',
  'e5200000-0000-4000-8000-000000000801'::uuid);
INSERT INTO atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,basis
) VALUES (
  'e5200000-0000-4000-8000-000000000804'::uuid,
  'e5200000-0000-4000-8000-000000000402'::uuid,
  'e5200000-0000-4000-8000-000000000801'::uuid,
  'operating',false,'{"cloneFixture":true,"case":"C2-only"}'::jsonb
);

-- All four are preexisting fictional canonical original Work in the clone,
-- not issued by this reader or allocated to a Person.
INSERT INTO atlas.work_items(id,organization_id,title,work_state,metadata)
VALUES
('e5200000-0000-4000-8000-000000000c21'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'C2 qualified current L1 original','open','{"cloneFixture":"C2"}'::jsonb),
('e5200000-0000-4000-8000-000000000c22'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'C2 FOREIGN L2 ONLY NOT DISCLOSABLE','open','{"cloneFixture":"C2"}'::jsonb),
('e5200000-0000-4000-8000-000000000c23'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'C2 WITHDRAWN L1 NOT DISCLOSABLE','open','{"cloneFixture":"C2"}'::jsonb),
('e5200000-0000-4000-8000-000000000c24'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'C2 INACTIVE HISTORICAL LINK','completed','{"cloneFixture":"C2"}'::jsonb);

-- All links share the one signed, source-created C1 operating requirement.
-- Three links remain active, so denial cannot be attributed to link absence.
INSERT INTO atlas.work_requirement_links(
  id,organization_id,requirement_id,work_item_id,link_role,active,metadata
)
SELECT fixture.link_id, r.organization_id,r.requirement_id,
       fixture.work_id,'advances',fixture.is_active,
       '{"cloneFixture":"C2"}'::jsonb
FROM atlas.company_work_operating_register_entries r
CROSS JOIN (VALUES
  ('e5200000-0000-4000-8000-000000000d21'::uuid,
   'e5200000-0000-4000-8000-000000000c21'::uuid,true),
  ('e5200000-0000-4000-8000-000000000d22'::uuid,
   'e5200000-0000-4000-8000-000000000c22'::uuid,true),
  ('e5200000-0000-4000-8000-000000000d23'::uuid,
   'e5200000-0000-4000-8000-000000000c23'::uuid,true),
  ('e5200000-0000-4000-8000-000000000d24'::uuid,
   'e5200000-0000-4000-8000-000000000c24'::uuid,false)
) AS fixture(link_id,work_id,is_active)
WHERE r.organization_id='e5200000-0000-4000-8000-000000000801'::uuid
  AND r.ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
  AND r.stable_key='signed_http_c1';

-- This is explicitly *fixture-simulated* attribution evidence, not a claim
-- that a real governor performed an owner attestation through an API.
-- It tests the source predicate's handling of persisted evidence classes.
INSERT INTO atlas.company_work_native_ledger_relevance(
  id,organization_id,work_item_id,ledger_id,evidence_kind,
  attestation_source_ref,attestation_reason,established_by_person_id,
  attribution_state,withdrawn_at,withdrawn_by_person_id,withdrawal_reason
)
VALUES
('e5200000-0000-4000-8000-000000000e21'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'e5200000-0000-4000-8000-000000000c21'::uuid,
 'e5200000-0000-4000-8000-000000000401'::uuid,
 'owner_attested','c2-fixture-source-l1','Synthetic L1 evidence only',
 'e5200000-0000-4000-8000-000000000101'::uuid,
 'active',null,null,null),
('e5200000-0000-4000-8000-000000000e22'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'e5200000-0000-4000-8000-000000000c22'::uuid,
 'e5200000-0000-4000-8000-000000000402'::uuid,
 'owner_attested','c2-fixture-source-l2','Synthetic foreign Ledger evidence',
 'e5200000-0000-4000-8000-000000000101'::uuid,
 'active',null,null,null),
('e5200000-0000-4000-8000-000000000e23'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'e5200000-0000-4000-8000-000000000c23'::uuid,
 'e5200000-0000-4000-8000-000000000401'::uuid,
 'owner_attested','c2-fixture-withdrawn','Previously relevant now withdrawn',
 'e5200000-0000-4000-8000-000000000101'::uuid,
 'withdrawn',now(),
 'e5200000-0000-4000-8000-000000000101'::uuid,
 'Synthetic withdrawal with preserved history'),
('e5200000-0000-4000-8000-000000000e24'::uuid,
 'e5200000-0000-4000-8000-000000000801'::uuid,
 'e5200000-0000-4000-8000-000000000c24'::uuid,
 'e5200000-0000-4000-8000-000000000401'::uuid,
 'owner_attested','c2-fixture-old-link','Historical link currently inactive',
 'e5200000-0000-4000-8000-000000000101'::uuid,
 'active',null,null,null);

DO $c2_post$
BEGIN
 IF (SELECT count(*) FROM atlas.work_items WHERE id IN (
   'e5200000-0000-4000-8000-000000000c21'::uuid,
   'e5200000-0000-4000-8000-000000000c22'::uuid,
   'e5200000-0000-4000-8000-000000000c23'::uuid,
   'e5200000-0000-4000-8000-000000000c24'::uuid)) <> 4
 OR (SELECT count(*) FROM atlas.work_allocations WHERE work_item_id IN (
   'e5200000-0000-4000-8000-000000000c21'::uuid,
   'e5200000-0000-4000-8000-000000000c22'::uuid,
   'e5200000-0000-4000-8000-000000000c23'::uuid,
   'e5200000-0000-4000-8000-000000000c24'::uuid)) <> 0
 OR (SELECT count(*) FROM atlas.work_requirement_links WHERE id IN (
   'e5200000-0000-4000-8000-000000000d21'::uuid,
   'e5200000-0000-4000-8000-000000000d22'::uuid,
   'e5200000-0000-4000-8000-000000000d23'::uuid,
   'e5200000-0000-4000-8000-000000000d24'::uuid)) <> 4
 THEN
   RAISE EXCEPTION 'C2 synthetic fixture identity or no-allocation invariant failed';
 END IF;
END
$c2_post$;
COMMIT;
