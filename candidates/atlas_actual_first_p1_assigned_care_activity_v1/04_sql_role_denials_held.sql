-- UNI-OPS-01 P1 SQL-only negative behavioral checks in EXACT isolated PG clone.
-- Must be executed in the SAME BEGIN/ROLLBACK after 01/02; no real
-- GoTrue JWT is issued. This is a lower-fidelity SQL role / source ACL test.
-- Never mistake simulated PostgreSQL roles for genuinely signed humans.

CREATE TEMP TABLE p1_negative_baseline ON COMMIT DROP AS
SELECT
 (SELECT count(*) FROM atlas.work_items) AS originals,
 (SELECT count(*) FROM atlas.work_execution_results) AS results,
 (SELECT count(*) FROM atlas.work_result_acceptances) AS acceptances,
 (SELECT count(*) FROM atlas.assigned_care_activity_recognition_links_v1) AS links;

-- Anonymous cannot execute exposed transport at all.
SET LOCAL ROLE anon;
DO $p1_anon$
BEGIN
  BEGIN
    PERFORM public.recognize_assigned_care_activity_self_api_v1(
      'a1100000-0000-4000-8000-000000000001'::uuid,
      'a1100000-0000-4000-8000-000000000002'::uuid,
      'weeded_full', 'clear');
    RAISE EXCEPTION 'P1 FAIL: anon invoked signed recognition';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'PASS P1 SQL role: anonymous recognition denied (not a GoTrue test)';
  END;
END;
$p1_anon$;
RESET ROLE;

-- An authenticated Postgres role without an actual signed GoTrue session
-- cannot present a Person identity. Null/wrong fields remain denied.
SET LOCAL ROLE authenticated;
DO $p1_authenticated$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'P1 FAIL: fresh SQL session unexpectedly has JWT identity';
  END IF;
  BEGIN
    PERFORM public.recognize_assigned_care_activity_self_api_v1(
      'a1100000-0000-4000-8000-000000000001'::uuid,
      'a1100000-0000-4000-8000-000000000002'::uuid,
      'weeded_full', 'clear');
    RAISE EXCEPTION 'P1 FAIL: unbound authenticated SQL role invoked recognition';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'PASS P1 SQL role: unbound authenticated recognition denied (not a GoTrue test)';
  END;
  BEGIN
    PERFORM public.recognize_assigned_care_activity_self_api_v1(
      NULL,NULL,NULL,NULL);
    RAISE EXCEPTION 'P1 FAIL: empty signed operation invoked recognition';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    RAISE NOTICE 'PASS P1 SQL role: empty operation denied (not a GoTrue test)';
  END;
END;
$p1_authenticated$;
RESET ROLE;

DO $p1_counts$
DECLARE v p1_negative_baseline%ROWTYPE;
BEGIN
  SELECT * INTO v FROM p1_negative_baseline;
  IF (SELECT count(*) FROM atlas.work_items)<>v.originals
    OR (SELECT count(*) FROM atlas.work_execution_results)<>v.results
    OR (SELECT count(*) FROM atlas.work_result_acceptances)<>v.acceptances
    OR (SELECT count(*) FROM atlas.assigned_care_activity_recognition_links_v1)<>v.links
  THEN RAISE EXCEPTION 'P1 FAIL: denied SQL role mutated canonical Work/Result/evidence';
  END IF;
  RAISE NOTICE 'PASS P1 SQL negative postconditions: no Work, Result, acceptance or link changed; SIGNED ACCEPTANCE STILL OPEN';
END;
$p1_counts$;
