-- HELD publisher working projection. No roster, listener metrics, rights,
-- media URLs, public station directory or new permission issuer.
DO $preflight$
BEGIN
 IF current_setting('app.shared_course_clone',true) IS DISTINCT FROM 'approved'
 OR to_regprocedure('titus.require_radio_operator_self_v1(uuid,text)') IS NULL
 THEN RAISE EXCEPTION 'held Radio operator workspace prerequisites missing' USING ERRCODE='42501'; END IF;
END $preflight$;
CREATE FUNCTION public.titus_radio_operator_workspace_self_api_v1(p_ledger_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $workspace$
DECLARE actor uuid; op text; standing jsonb; operations text[]:=ARRAY[]::text[];
 stations jsonb; programs jsonb; station_count bigint; program_count bigint;
 at_time timestamptz;
BEGIN
 actor:=atlas.current_person_for_private_course_v1();
 IF actor IS NULL OR p_ledger_id IS NULL THEN
 RAISE EXCEPTION 'operator workspace unavailable' USING ERRCODE='42501'; END IF;
 -- Reuse operation-specific checks, never expand one permission into another.
 -- Held narrow working read: an allowed establishment/offer operation allows
 -- basic same-Ledger station/program names, not subscriber data or publications.
 FOREACH op IN ARRAY ARRAY['establish_station','establish_program','offer_subscription'] LOOP
  BEGIN
   standing:=titus.require_radio_operator_self_v1(p_ledger_id,op);
   IF (standing->>'personId')::uuid IS DISTINCT FROM actor THEN RAISE EXCEPTION 'actor changed' USING ERRCODE='42501'; END IF;
   operations:=array_append(operations,op);
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
 END LOOP;
 IF cardinality(operations)=0 THEN RAISE EXCEPTION 'operator workspace unavailable' USING ERRCODE='42501'; END IF;
 at_time:=clock_timestamp();
 SELECT count(*),coalesce(jsonb_agg(jsonb_build_object('stationId',x.station_id,'title',x.title) ORDER BY x.title,x.station_id),'[]'::jsonb)
 INTO station_count,stations FROM (
 SELECT station_id,title FROM titus.radio_stations_v1
 WHERE ledger_id=p_ledger_id AND retired_at IS NULL AND established_at<=at_time
 ORDER BY title,station_id LIMIT 101) x;
 SELECT count(*),coalesce(jsonb_agg(jsonb_build_object('programId',x.program_id,'stationId',x.station_id,'title',x.title) ORDER BY x.title,x.program_id),'[]'::jsonb)
 INTO program_count,programs FROM (
 SELECT p.program_id,p.station_id,p.title FROM titus.radio_programs_v1 p
 JOIN titus.radio_stations_v1 s ON s.station_id=p.station_id
 WHERE s.ledger_id=p_ledger_id AND s.retired_at IS NULL AND s.established_at<=at_time
 AND p.retired_at IS NULL AND p.established_at<=at_time
 ORDER BY p.title,p.program_id LIMIT 1001) x;
 IF station_count>100 OR program_count>1000 THEN RAISE EXCEPTION 'operator workspace exceeds bound' USING ERRCODE='54000'; END IF;
 RETURN jsonb_build_object('contractVersion','titus_radio_operator_workspace_v1','personId',actor,
 'ledgerId',p_ledger_id,'operations',to_jsonb(operations),'stations',stations,'programs',programs);
END $workspace$;
REVOKE ALL ON FUNCTION public.titus_radio_operator_workspace_self_api_v1(uuid) FROM PUBLIC,anon,authenticated;
DO $acl$
BEGIN
 IF EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN
 EXECUTE 'REVOKE ALL ON FUNCTION public.titus_radio_operator_workspace_self_api_v1(uuid) FROM service_role';
 END IF;
END $acl$;
GRANT EXECUTE ON FUNCTION public.titus_radio_operator_workspace_self_api_v1(uuid) TO authenticated;
