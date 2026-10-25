-- SYNTHETIC SQL-only negative-access supplement.
-- Requires fixture-schema.sql, v1/v2/source candidates, and test-source-identity.sql.
-- These role-switching fixtures are NOT genuine GoTrue/PostgREST bearer-token tests.
-- Production must never execute this file.
SELECT pg_catalog.set_config(
 'test.source_identity_a_program',
 (SELECT id::text FROM atlas.personal_training_programs
   WHERE owner_principal_id='00000000-0000-4000-8000-000000000111'
   ORDER BY created_at,id LIMIT 1),false);
SELECT pg_catalog.set_config(
 'test.source_identity_b_program',
 (SELECT id::text FROM atlas.personal_training_programs
   WHERE owner_principal_id='00000000-0000-4000-8000-000000000222'
   ORDER BY created_at,id LIMIT 1),false);

-- A fully authorized but DIFFERENT fictional Principal may not obtain A's packet
-- by guessing its UUID, nor save or approve it.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000202';
DO $t$
DECLARE a_id uuid; b_id uuid; b_packet jsonb; matches jsonb;
BEGIN
 a_id:=current_setting('test.source_identity_a_program')::uuid;
 b_id:=current_setting('test.source_identity_b_program')::uuid;
 IF a_id IS NULL OR b_id IS NULL THEN
  RAISE EXCEPTION 'Synthetic author fixtures missing'; END IF;
 b_packet:=(public.personal_program_author_read_self_api_v2(b_id))->'draftPacket';
 IF b_packet IS NULL THEN RAISE EXCEPTION 'Own synthetic Program cannot be read'; END IF;
 BEGIN
  PERFORM public.personal_program_author_read_self_api_v2(a_id);
  RAISE EXCEPTION 'Foreign author Program read was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_save_self_api_v2(
    a_id,1,b_packet,'foreign-author-save-reject-001');
  RAISE EXCEPTION 'Foreign author Program save was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_approve_self_api_v2(
    a_id,1,repeat('a',64),'foreign-author-approval-reject-001');
  RAISE EXCEPTION 'Foreign author Program approval was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 matches:=public.personal_program_author_same_sources_self_api_v1(
   jsonb_build_array(jsonb_build_object('sha256',repeat('a',64))));
 IF jsonb_array_length(matches->'items')<>1
    OR matches->'items'->0->>'programId'<>b_id::text THEN
   RAISE EXCEPTION 'Cross-author source lookup revealed foreign identity'; END IF;
END;
$t$;
COMMIT;

-- Mock entitlement revocation: the SQL fixture's access guard switches to
-- denied while A remains a syntactically authenticated principal.
-- This is NOT proof that actual signed JWT revocation is enforced via PostgREST.
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='00000000-0000-4000-8000-000000000101';
SET LOCAL test.personal_access='denied';
DO $t$
DECLARE a_id uuid;
BEGIN
 a_id:=current_setting('test.source_identity_a_program')::uuid;
 BEGIN
  PERFORM public.personal_program_author_read_self_api_v2(a_id);
  RAISE EXCEPTION 'Mock-revoked author read was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
 BEGIN
  PERFORM public.personal_program_author_same_sources_self_api_v1(
   jsonb_build_array(jsonb_build_object('sha256',repeat('a',64))));
  RAISE EXCEPTION 'Mock-revoked author source lookup was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$t$;
COMMIT;

-- Anonymous calls and authenticated calls with no user subject must be denied.
BEGIN;
SET LOCAL ROLE anon;
DO $t$
BEGIN
 BEGIN
  PERFORM public.personal_program_author_same_sources_self_api_v1(
   jsonb_build_array(jsonb_build_object('sha256',repeat('a',64))));
  RAISE EXCEPTION 'Anonymous source lookup was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$t$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='';
DO $t$
BEGIN
 BEGIN
  PERFORM public.personal_program_author_same_sources_self_api_v1(
   jsonb_build_array(jsonb_build_object('sha256',repeat('a',64))));
  RAISE EXCEPTION 'Authenticated role without subject was incorrectly permitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN NULL; END;
END;
$t$;
COMMIT;
