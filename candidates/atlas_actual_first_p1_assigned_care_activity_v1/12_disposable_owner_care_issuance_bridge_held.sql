-- P1 HELD acceptance-only transport: isolated RiverSong PG17 ONLY.
-- Native reviewed owner_establish_observed_continuing_care_work_self_api_v1
-- is present in composed held R01 candidate but deliberately has NO client
-- release grant or public endpoint. To run SIGNED acceptance without claiming
-- production release, expose a SECURITY INVOKER scratch-only adapter.
-- The source's exact root Ledger, accepted scope, physical Need, disclosure,
-- no-legacy-obligation, signed observation, and ledger relevance guards are
-- unchanged. A failed source check must deny this call.
-- This test transport is NOT canonical Noel migration or approval for release.
DO $preflight$
BEGIN
 IF to_regprocedure('atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)') IS NULL
    OR to_regprocedure('public.p1_disposable_owner_observe_care_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'STOP held governing owner source unavailable or scratch test adapter exists';
 END IF;
 IF has_function_privilege('authenticated',
 'atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'STOP owner source was unexpectedly pre-granted in scratch';
 END IF;
END;$preflight$;

CREATE FUNCTION public.p1_disposable_owner_observe_care_v1(
 p_organization_id uuid,p_ledger_id uuid,p_rhythm_state_id uuid,p_scope_id uuid,
 p_observed_condition text,p_observation_note text,p_observed_at timestamptz,
 p_service_date date,p_action_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $test_transport$
 SELECT atlas.owner_establish_observed_continuing_care_work_self_api_v1(
  p_organization_id,p_ledger_id,p_rhythm_state_id,p_scope_id,p_observed_condition,
  p_observation_note,p_observed_at,p_service_date,p_action_id);
$test_transport$;

REVOKE ALL ON FUNCTION public.p1_disposable_owner_observe_care_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
-- Only for signed test sessions inside fresh isolated DB. Never ship this.
GRANT EXECUTE ON FUNCTION atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.p1_disposable_owner_observe_care_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)
 TO authenticated;

DO $assert$
BEGIN
 IF has_function_privilege('anon','public.p1_disposable_owner_observe_care_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)','EXECUTE')
    OR has_function_privilege('anon','atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)','EXECUTE')
    OR (SELECT prosecdef FROM pg_proc WHERE oid='public.p1_disposable_owner_observe_care_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)'::regprocedure)
    OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)'::regprocedure)
 THEN RAISE EXCEPTION 'STOP test transport widened authority beyond signed source';
 END IF;
 RAISE NOTICE 'PASS scratch-only invoker transport; signed owner source guards remain sovereign';
END;$assert$;
