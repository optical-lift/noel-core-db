-- SCRATCH TEST ONLY. Two fictional Auth accounts from fixture.sql.
-- This file never runs in production or on connected Supabase.
INSERT INTO titus.customer_workspace_entitlements_v1(
 owner_auth_user_id,grant_kind,grant_source_receipt)
VALUES
('00000000-0000-4000-8000-000000000101','private_pilot','fictional-class-a'),
('00000000-0000-4000-8000-000000000102','private_pilot','fictional-class-b');
SET request.jwt.claims='{"sub":"00000000-0000-4000-8000-000000000101","session_id":"00000000-0000-4000-8000-000000000201"}';
SET ROLE authenticated;
DO $test$
DECLARE cat jsonb;outline jsonb;unit_a uuid;unit_b uuid;course uuid;material jsonb;
BEGIN
 cat:=public.titus_customer_start_workspace_self_api_v1('Synthetic Studio');
 cat:=public.titus_customer_create_course_self_api_v1(
  '00000000-0000-4000-8000-000000000301','Synthetic Course');
 course:=(cat->'courses'->0->>'courseId')::uuid;
 outline:=public.titus_customer_outline_read_self_api_v1(course);
 IF outline->'units'<>'[]'::jsonb THEN RAISE EXCEPTION 'Seeded outline'; END IF;
 outline:=public.titus_customer_unit_create_self_api_v1(
  course,'00000000-0000-4000-8000-000000000311','lesson','Class 1');
 unit_a:=(outline->'units'->0->>'unitId')::uuid;
 outline:=public.titus_customer_unit_create_self_api_v1(
  course,'00000000-0000-4000-8000-000000000312','assignment','Homework 1');
 unit_b:=(outline->'units'->1->>'unitId')::uuid;
 IF jsonb_array_length(outline->'units')<>2 THEN RAISE EXCEPTION 'Unit create failed'; END IF;
 outline:=public.titus_customer_unit_move_self_api_v1(unit_b,'up');
 IF (outline->'units'->0->>'unitId')::uuid<>unit_b THEN
  RAISE EXCEPTION 'Reorder was not source durable'; END IF;
 material:=public.titus_customer_unit_save_self_api_v1(
  unit_a,'00000000-0000-4000-8000-000000000321',0,'First class');
 IF material->'material'->>'text'<>'First class' THEN RAISE EXCEPTION 'Class save failed'; END IF;
 material:=public.titus_customer_unit_save_self_api_v1(
  unit_b,'00000000-0000-4000-8000-000000000322',0,'Homework instructions');
 IF material->'material'->>'text'<>'Homework instructions' THEN RAISE EXCEPTION 'Homework save failed'; END IF;
 material:=public.titus_customer_unit_read_self_api_v1(unit_a);
 IF material->'material'->>'text'<>'First class' THEN RAISE EXCEPTION 'Class reopen failed'; END IF;
 material:=public.titus_customer_material_read_self_api_v1(course);
 IF material->'material' IS DISTINCT FROM 'null'::jsonb THEN
  RAISE EXCEPTION 'Class changed old Course manuscript'; END IF;
END $test$;
RESET ROLE;
RESET request.jwt.claims;
SELECT 'PASS: synthetic owner class and homework saved independently, reordered, reopened' AS result;
