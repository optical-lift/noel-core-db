-- NEGATIVE CONTRACTS in isolated PG17 only; synthetic claims are unsigned.
-- Existing postconditions.sql has created Course A, Class A and Homework A.
SELECT set_config('test.unit_a',(SELECT unit_id::text FROM titus.customer_course_units_v1
 WHERE kind='lesson' LIMIT 1),false);
SELECT set_config('test.course_a',(SELECT course_id::text FROM titus.customer_course_drafts_v1
 LIMIT 1),false);

SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101","session_id":"00000000-0000-4000-8000-000000000201"}';
SET ROLE authenticated;
DO $replay$ DECLARE u uuid:=current_setting('test.unit_a')::uuid;
 c uuid:=current_setting('test.course_a')::uuid;j jsonb;
BEGIN
 j:=public.titus_customer_unit_save_self_api_v1(
  u,'00000000-0000-4000-8000-000000000321',0,'First class');
 IF (j->'material'->>'revisionNumber')::integer<>1 THEN
  RAISE EXCEPTION 'Idempotent retry duplicated revision';
 END IF;
 BEGIN
  PERFORM public.titus_customer_unit_save_self_api_v1(
   u,'00000000-0000-4000-8000-000000000321',0,'Changed replay');
  RAISE EXCEPTION 'Changed replay accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_unit_save_self_api_v1(
   u,'00000000-0000-4000-8000-000000000323',0,'Stale version');
  RAISE EXCEPTION 'Stale class version accepted';
 EXCEPTION WHEN serialization_failure THEN NULL; END;
 j:=public.titus_customer_unit_create_self_api_v1(
  c,'00000000-0000-4000-8000-000000000311','lesson','Class 1');
 IF jsonb_array_length(j->'units')<>2 THEN
  RAISE EXCEPTION 'Duplicate class created on original request replay';
 END IF;
 BEGIN
  PERFORM public.titus_customer_unit_create_self_api_v1(
   c,'00000000-0000-4000-8000-000000000311','lesson','Conflicting name');
  RAISE EXCEPTION 'Changed class create replay accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 j:=public.titus_customer_unit_save_self_api_v1(
  u,'00000000-0000-4000-8000-000000000324',1,'Revised class');
 IF j->'material'->>'text'<>'Revised class' OR
    (j->'material'->>'revisionNumber')::integer<>2 THEN
  RAISE EXCEPTION 'Revision 2 not saved';
 END IF;
 BEGIN
  PERFORM public.titus_customer_unit_save_self_api_v1(
   u,'00000000-0000-4000-8000-000000000325',2,repeat('x',20001));
  RAISE EXCEPTION 'Overlong class accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $replay$;
RESET ROLE;

-- Separate entitled user may not read/move/write or enumerate an owner Course.
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000102","session_id":"00000000-0000-4000-8000-000000000202"}';
SET ROLE authenticated;
DO $outsider$ DECLARE u uuid:=current_setting('test.unit_a')::uuid;
 c uuid:=current_setting('test.course_a')::uuid;
BEGIN
 BEGIN
  PERFORM public.titus_customer_outline_read_self_api_v1(c);
  RAISE EXCEPTION 'Foreign outline readable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_unit_read_self_api_v1(u);
  RAISE EXCEPTION 'Foreign class readable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_unit_save_self_api_v1(
   u,'00000000-0000-4000-8000-000000000331',2,'Foreign edit');
  RAISE EXCEPTION 'Foreign class writable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.titus_customer_unit_move_self_api_v1(c,u,'up');
  RAISE EXCEPTION 'Foreign class movable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $outsider$;
RESET ROLE;
RESET request.jwt.claims;
RESET test.unit_a;
RESET test.course_a;
DO $historical$ BEGIN
 IF (SELECT count(*) FROM titus.customer_course_unit_revisions_v1)<>3 THEN
  RAISE EXCEPTION 'History duplicate count';
 END IF;
 IF (SELECT count(*) FROM titus.customer_course_unit_revisions_v1
   WHERE body_text='First class')<>1 THEN
  RAISE EXCEPTION 'Prior class original mutated';
 END IF;
END $historical$;
SELECT 'PASS: local replay, stale edit, foreign outline/unit denial, history' AS result;
