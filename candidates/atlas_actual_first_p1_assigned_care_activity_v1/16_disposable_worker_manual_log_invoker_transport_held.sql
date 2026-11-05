-- HELD: temporary RiverSong ONLY signed worker manual activity adapter.
-- Canonical atlas.record_worker_activity_log_v1 exists in Noel's 2026-08-29
-- historical source, installed on fresh PG17 before this file. Its authentic
-- farm-membership, authored sentence, live-day, idempotency and evidence-only
-- guards are preserved and executed. No Work or Clock admission here.
-- No production migration or new release grant. Revoke after scratch teardown.
DO $before$
BEGIN
 IF to_regprocedure('atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)') IS NULL
 OR to_regprocedure('public.p1_disposable_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'STOP authentic worker manual-log writer missing or test adapter already present';
 END IF;
END;$before$;

CREATE FUNCTION public.p1_disposable_worker_activity_log_v1(
 p_farm_id uuid,p_log_date date,p_summary_sentence text,p_idempotency_key text,
 p_clock_now_task_id uuid DEFAULT NULL,p_clock_now_start_at timestamptz DEFAULT NULL,
 p_clock_now_end_at timestamptz DEFAULT NULL,p_clock_projection_revision text DEFAULT NULL
) RETURNS TABLE(field_log_id uuid,actor_membership_id uuid,logged_at timestamptz,replayed boolean)
LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $transport$
 SELECT * FROM atlas.record_worker_activity_log_v1(
   p_farm_id,p_log_date,p_summary_sentence,p_idempotency_key,
   p_clock_now_task_id,p_clock_now_start_at,p_clock_now_end_at,p_clock_projection_revision);
$transport$;
REVOKE ALL ON FUNCTION public.p1_disposable_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.p1_disposable_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) TO authenticated;
DO $post$
BEGIN
 IF has_function_privilege('anon','public.p1_disposable_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)','EXECUTE')
 OR has_function_privilege('anon','atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)','EXECUTE')
 OR (SELECT prosecdef FROM pg_proc WHERE oid='public.p1_disposable_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)'::regprocedure)
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)'::regprocedure)
 THEN RAISE EXCEPTION 'STOP worker logged activity source permissions widened to anon or invoker forged';
 END IF;
 RAISE NOTICE 'PASS bounded scratch worker manual-log transport; authentic farm membership required';
END;$post$;
