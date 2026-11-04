-- Disposable PG17 source-boundary acceptance, never a Supabase migration.
-- The candidate MUST deny even a positive-looking membership when issuer false.
INSERT INTO titus.classroom_pilot_participation_v1(
 thread_id,person_entity_id,actor_role,assignment_state,
 assignment_receipt_id,issued_by_person_entity_id,effective_at
) VALUES
 ('00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000201','learner','active',
  '00000000-0000-4000-8000-000000000301',
  '00000000-0000-4000-8000-000000000204',now()-interval '5 minutes'),
 ('00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000202','teacher','active',
  '00000000-0000-4000-8000-000000000302',
  '00000000-0000-4000-8000-000000000204',now()-interval '5 minutes'),
 ('00000000-0000-4000-8000-000000000102',
  '00000000-0000-4000-8000-000000000203','learner','active',
  '00000000-0000-4000-8000-000000000303',
  '00000000-0000-4000-8000-000000000204',now()-interval '5 minutes');
INSERT INTO titus.classroom_pilot_parts_v1 VALUES
 ('00000000-0000-4000-8000-000000000100','class'),
 ('00000000-0000-4000-8000-000000000100','homework'),
 ('00000000-0000-4000-8000-000000000100','block:reading-1'),
 ('00000000-0000-4000-8000-000000000102','class'),
 ('00000000-0000-4000-8000-000000000102','homework');

DO $secure$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies
    WHERE schemaname='titus' AND tablename LIKE 'classroom_pilot_%')
  THEN RAISE EXCEPTION 'FAIL: public pilot table policies found'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='titus' AND c.relname='classroom_pilot_participation_v1'
      AND c.relrowsecurity)
  THEN RAISE EXCEPTION 'FAIL: participation RLS absent'; END IF;
  IF has_table_privilege('authenticated',
       'titus.classroom_pilot_participation_v1','SELECT')
    OR has_table_privilege('anon',
       'titus.classroom_pilot_participation_v1','SELECT')
  THEN RAISE EXCEPTION 'FAIL: direct roster access granted'; END IF;
  IF has_function_privilege('anon',
    'public.titus_classroom_authorize_self_api_v1(uuid,text)','EXECUTE')
  THEN RAISE EXCEPTION 'FAIL: anonymous source reader'; END IF;
  IF NOT has_function_privilege('authenticated',
    'public.titus_classroom_authorize_self_api_v1(uuid,text)','EXECUTE')
  THEN RAISE EXCEPTION 'FAIL: no authenticated RPC transport'; END IF;
END;$secure$;

SELECT set_config('titus.test_user','00000000-0000-4000-8000-000000000501',false);
SELECT set_config('titus.test_person','00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $denied$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: source granted access before issuer authenticity'; END IF;
END;$denied$;
RESET ROLE;

-- TEST-ONLY issuer override. Not part of candidate and restored false below.
CREATE OR REPLACE FUNCTION titus.classroom_pilot_assignment_issued_v1(
 p_thread_id uuid,p_person_entity_id uuid,p_actor_role text,p_assignment_receipt_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$
 SELECT p_thread_id='00000000-0000-4000-8000-000000000100'::uuid
 AND (
  (p_person_entity_id='00000000-0000-4000-8000-000000000201'::uuid
    AND p_actor_role='learner'
    AND p_assignment_receipt_id='00000000-0000-4000-8000-000000000301'::uuid)
  OR
  (p_person_entity_id='00000000-0000-4000-8000-000000000202'::uuid
    AND p_actor_role='teacher'
    AND p_assignment_receipt_id='00000000-0000-4000-8000-000000000302'::uuid)
 )
$$;
REVOKE ALL ON FUNCTION titus.classroom_pilot_assignment_issued_v1(
 uuid,uuid,text,uuid) FROM PUBLIC;

-- Learner can read and submit, cannot review or switch into another class.
SET ROLE authenticated;
DO $learner$
DECLARE receipt jsonb;
BEGIN
 receipt:=public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read');
 IF receipt IS NULL OR receipt->>'viewerRole'<>'learner'
    OR receipt->>'viewerPersonId'<>'00000000-0000-4000-8000-000000000201'
    OR receipt->>'unitRef'<>'song-01'
    OR jsonb_array_length(receipt->'allowedParts')<>3
 THEN RAISE EXCEPTION 'FAIL: exact learner read not issued'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_submission') IS NULL
 THEN RAISE EXCEPTION 'FAIL: learner submission not authorized'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_feedback') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: learner impersonates teacher'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000101','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: class scope leak'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','made_up_operation') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: invented operation allowed'; END IF;
END;$learner$;
RESET ROLE;

SELECT set_config('titus.test_person','00000000-0000-4000-8000-000000000202',false);
SET ROLE authenticated;
DO $teacher$
DECLARE receipt jsonb;
BEGIN
 receipt:=public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_feedback');
 IF receipt IS NULL OR receipt->>'viewerRole'<>'teacher' OR
   receipt->>'sourceReceiptId'<>'00000000-0000-4000-8000-000000000302'
 THEN RAISE EXCEPTION 'FAIL: teacher not exactly appointed'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','homework_submission') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: teacher submits as learner'; END IF;
END;$teacher$;
RESET ROLE;

-- Retired, outsider and a forged testing-session claim must not pass.
SELECT set_config('titus.test_person','00000000-0000-4000-8000-000000000203',false);
SET ROLE authenticated;
DO $outsider$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: unrelated Person read'; END IF;
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000102','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: unrelated issuer gave edition access'; END IF;
END;$outsider$;
RESET ROLE;
SELECT set_config('titus.test_user','',false);
SELECT set_config('titus.test_person','00000000-0000-4000-8000-000000000201',false);
SET ROLE authenticated;
DO $no_signin$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: unsigned source reader'; END IF;
END;$no_signin$;
RESET ROLE;

-- Withdrawal, expiry and removed lesson parts deny previously allowed access.
SELECT set_config('titus.test_user','00000000-0000-4000-8000-000000000501',false);
UPDATE titus.classroom_pilot_participation_v1 SET assignment_state='revoked',
 withdrawn_at=now()
WHERE thread_id='00000000-0000-4000-8000-000000000100'
  AND person_entity_id='00000000-0000-4000-8000-000000000201';
SET ROLE authenticated;
DO $revoked$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: revoked learner still authorized'; END IF;
END;$revoked$;
RESET ROLE;

UPDATE titus.classroom_pilot_participation_v1 SET assignment_state='active',
 withdrawn_at=NULL,
 expires_at=now()-interval '1 minute'
WHERE thread_id='00000000-0000-4000-8000-000000000100'
  AND person_entity_id='00000000-0000-4000-8000-000000000201';
SET ROLE authenticated;
DO $expired$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: expired learner still authorized'; END IF;
END;$expired$;
RESET ROLE;
UPDATE titus.classroom_pilot_participation_v1 SET expires_at=NULL
WHERE thread_id='00000000-0000-4000-8000-000000000100'
  AND person_entity_id='00000000-0000-4000-8000-000000000201';
DELETE FROM titus.classroom_pilot_parts_v1
WHERE thread_id='00000000-0000-4000-8000-000000000100'
  AND part_ref='homework';
SET ROLE authenticated;
DO $parts$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: malformed lesson parts authorized'; END IF;
END;$parts$;
RESET ROLE;

-- Restore hard false. The exact authorized records cannot defeat it.
CREATE OR REPLACE FUNCTION titus.classroom_pilot_assignment_issued_v1(
 p_thread_id uuid,p_person_entity_id uuid,p_actor_role text,p_assignment_receipt_id uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog
AS $$SELECT false$$;
SELECT set_config('titus.test_person','00000000-0000-4000-8000-000000000202',false);
-- Inspect the private hard-false issuer ONLY as the fixture administrator.
-- The authenticated browser role must not have schema usage or direct
-- EXECUTE on the underlying private issuer; that denial is intentional.
DO $closed$
BEGIN
 IF titus.classroom_pilot_assignment_issued_v1(
  '00000000-0000-4000-8000-000000000100',
  '00000000-0000-4000-8000-000000000202','teacher',
  '00000000-0000-4000-8000-000000000302') THEN
  RAISE EXCEPTION 'FAIL: test issuer left open'; END IF;
END;$closed$;
SET ROLE authenticated;
DO $public_closed$
BEGIN
 IF public.titus_classroom_authorize_self_api_v1(
   '00000000-0000-4000-8000-000000000100','read') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL: end-state issuer not closed'; END IF;
END;$public_closed$;
RESET ROLE;
