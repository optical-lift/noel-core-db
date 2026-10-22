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

-- Signed GoTrue root/member/outsider tests must run against the protected
-- clone through the existing verification harness before production release.
-- Root Ledger: positive source-bound result; ordinary Seat: denied; outsider:
-- denied. Organization context: active authorized membership only. All result
-- coverage.partial and unsupported-family evidence must survive byte-for-byte.
