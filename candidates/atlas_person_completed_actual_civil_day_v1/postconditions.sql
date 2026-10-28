-- Read-only guard on the loaded candidate after applying to disposable clone.
DO $check$
DECLARE
  v_oid oid;
  v_def text;
BEGIN
  SELECT p.oid,pg_get_functiondef(p.oid) INTO v_oid,v_def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname='connected_person_company_work_day_self_api_v1'
    AND pg_get_function_identity_arguments(p.oid)='p_date date';
  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'Signed Person day reader absent';
  END IF;
  IF NOT (v_def LIKE '%principal_authoritative_timezone_v1%'
    AND v_def LIKE '%completedOnActualCivilDay%'
    AND v_def LIKE '%res.acceptance_decision=%'
    AND v_def LIKE '%(res.reported_at AT TIME ZONE v_timezone)::date=p_date%'
    AND v_def LIKE '%person_original_work_identity_disclosed_self_v1%'
    AND v_def LIKE '%person_has_native_ledger_connection_v1%'
    AND v_def LIKE '%originalExposureDate%')
  THEN RAISE EXCEPTION 'Missing accepted-result/day/authority invariant';
  END IF;
  IF has_function_privilege('anon',v_oid,'EXECUTE')
    OR has_function_privilege('PUBLIC',v_oid,'EXECUTE')
  THEN RAISE EXCEPTION 'Private canonical day reader exposed to anon/PUBLIC';
  END IF;
END
$check$;

-- Signed acceptance matrix required before release:
-- Person with real work: signed GoTrue/PostgREST call for completed-before-plan
-- shows it ONLY on local Result day, with originalExposureDate intact.
-- Planned future day MUST NOT contain that completed Work.
-- Repeat with late completion after planned day and with midnight UTC crossing.
-- Owner, outsider, revoked connection, unsigned and stale sessions must not
-- retrieve another Person's records via this or any alternate reader.
-- A partial/blocked or nonaccepted result must not be displayed as done.
-- No changes to Result, Work, plan, allocation or history are permitted.
