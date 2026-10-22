-- Clone-only public Calendar read boundary verification.
-- This proves transport posture, not signed three-Person application behavior.
DO $proof$
DECLARE
  v_ledger oid := to_regprocedure(
    'public.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)');
  v_context oid := to_regprocedure(
    'public.organization_context_temporal_composer_self_api_v2(uuid,uuid,date,date,text,integer)');
  v_source_ledger oid := to_regprocedure(
    'atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)');
  v_source_context oid := to_regprocedure(
    'atlas.organization_context_temporal_composer_self_api_v2(uuid,uuid,date,date,text,integer)');
BEGIN
  IF v_ledger IS NULL OR v_context IS NULL
    OR v_source_ledger IS NULL OR v_source_context IS NULL THEN
    RAISE EXCEPTION 'Missing exact source-owned Calendar read transport';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc
    WHERE oid IN (v_ledger,v_context) AND (prosecdef OR provolatile<>'s'))
    OR NOT has_function_privilege('authenticated',v_ledger,'EXECUTE')
    OR NOT has_function_privilege('authenticated',v_context,'EXECUTE')
    OR has_function_privilege('anon',v_ledger,'EXECUTE')
    OR has_function_privilege('anon',v_context,'EXECUTE') THEN
    RAISE EXCEPTION 'Calendar wrappers changed authorization or invocation posture';
  END IF;
  IF NOT (SELECT pg_get_functiondef(v_ledger)
          LIKE '%atlas.ledger_temporal_composer_self_api_v1(%')
    OR NOT (SELECT pg_get_functiondef(v_context)
          LIKE '%atlas.organization_context_temporal_composer_self_api_v2(%')
    OR to_regclass('atlas.calendar_events') IS NOT NULL THEN
    RAISE EXCEPTION 'Calendar transport invented second Event authority';
  END IF;
END
$proof$;


-- Denial behavior: anonymous and authenticated-without-a-signed-person are
-- distinct test actors. No real auth identity is simulated by privileged SQL.
BEGIN;
SET LOCAL ROLE anon;
DO $anonymous$
DECLARE v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.ledger_temporal_composer_self_api_v1(
      'f5210000-0000-4000-8000-000000000014'::uuid,
      date '2030-10-01',date '2030-10-31','America/Chicago',10);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Anonymous caller reached Ledger Calendar composer';
  END IF;
  v_denied := false;
  BEGIN
    PERFORM public.organization_context_temporal_composer_self_api_v2(
      'f5210000-0000-4000-8000-000000000010'::uuid,
      'f5210000-0000-4000-8000-000000000011'::uuid,
      date '2030-10-01',date '2030-10-31','America/Chicago',10);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Anonymous caller reached Organization Calendar composer';
  END IF;
END
$anonymous$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
DO $without_person$
DECLARE v_denied boolean := false;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'No signed Person may be present in clone role test';
  END IF;
  BEGIN
    PERFORM public.ledger_temporal_composer_self_api_v1(
      'f5210000-0000-4000-8000-000000000014'::uuid,
      date '2030-10-01',date '2030-10-31','America/Chicago',10);
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Authenticated role without Person reached Ledger Calendar';
  END IF;
  v_denied := false;
  BEGIN
    PERFORM public.organization_context_temporal_composer_self_api_v2(
      'f5210000-0000-4000-8000-000000000010'::uuid,
      'f5210000-0000-4000-8000-000000000011'::uuid,
      date '2030-10-01',date '2030-10-31','America/Chicago',10);
  EXCEPTION WHEN SQLSTATE '28000' OR insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'Authenticated role without Person reached Organization Calendar';
  END IF;
END
$without_person$;
ROLLBACK;

-- Positive real-user authorization, cross-Ledger and context isolation
-- require the separately prepared signed local GoTrue+REST proof. This file
-- never claims that unsourced Postgres role settings are genuine sessions.


-- The protected synthetic member is ONE Reality/Atlas Person, never an
-- accidental legacy user fork. Checked as fixture state, not production data.
DO $identity$
DECLARE v_total integer;
BEGIN
  SELECT count(*)::integer INTO v_total
  FROM reality.auth_person_bindings r
  JOIN atlas.person_auth_credentials c
    ON c.auth_user_id=r.auth_user_id
   AND c.person_id=r.person_entity_id
   AND c.status='active'
  WHERE r.auth_user_id IN (
    'f5210000-0000-4000-8000-000000000401'::uuid,
    'f5210000-0000-4000-8000-000000000403'::uuid
  )
  AND r.binding_state='active' AND r.retired_at IS NULL;
  IF v_total<>2 THEN
    RAISE EXCEPTION 'Disposable signed Calendar Persons do not resolve to one identity';
  END IF;
END
$identity$;
