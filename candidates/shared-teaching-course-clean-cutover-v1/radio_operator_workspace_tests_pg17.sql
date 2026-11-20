-- Exact operator workspace is a narrow same-Ledger projection, not a roster.
SAVEPOINT radio_workspace_probe;
\i /source/candidates/shared-teaching-course-clean-cutover-v1/radio_operator_workspace_candidate.sql
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $workspace$
DECLARE r jsonb; denied boolean:=false;
BEGIN
 r:=public.titus_radio_operator_workspace_self_api_v1('77777777-7777-4777-8777-777777777777');
 IF r->>'personId' IS DISTINCT FROM 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
 OR r->'operations' IS DISTINCT FROM '["establish_station","establish_program","offer_subscription"]'::jsonb
 OR jsonb_array_length(r->'stations')<>1 OR jsonb_array_length(r->'programs')<>1
 OR r->'programs'->0->>'stationId' IS DISTINCT FROM r->'stations'->0->>'stationId'
 OR r?'subscriptions' OR r?'offers' THEN RAISE EXCEPTION 'workspace projection incorrect'; END IF;
 BEGIN PERFORM public.titus_radio_operator_workspace_self_api_v1('77777777-7777-4777-8777-999999999999');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'wrong Ledger workspace disclosed'; END IF;
END $workspace$;
RESET ROLE;
UPDATE reality.responsibility_relations SET permitted_operations=ARRAY['establish_program']
WHERE id='f2000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
DO $narrow$
BEGIN
 IF public.titus_radio_operator_workspace_self_api_v1('77777777-7777-4777-8777-777777777777')->'operations'
 IS DISTINCT FROM '["establish_program"]'::jsonb THEN RAISE EXCEPTION 'one operation expanded permission'; END IF;
END $narrow$;
SET LOCAL request.jwt.claims='{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","session_id":"5ccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
DO $outsider$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_operator_workspace_self_api_v1('77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'outsider read publisher workspace'; END IF;
END $outsider$;
RESET ROLE;
UPDATE reality.responsibility_relations SET relation_state='ended',ended_at=clock_timestamp()
WHERE id='f2000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","session_id":"5aaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
DO $revoked$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.titus_radio_operator_workspace_self_api_v1('77777777-7777-4777-8777-777777777777');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'revoked operator read workspace'; END IF;
END $revoked$;
RESET ROLE;
ROLLBACK TO SAVEPOINT radio_workspace_probe;
