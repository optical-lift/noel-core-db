-- Atlas ONE Calendar: thin PUBLIC transport of already-governed source-owned
-- Temporal Contribution composers. Candidate only; never apply directly.
-- Does not create a Calendar table, grant Event write authority, widen
-- Organization/Ledger access, or claim that every source family is present.
BEGIN;

-- A native Ledger ROOT may inspect the rich Ledger scheduling field.
-- The owning private self API performs the signed principal/root check
-- before executing its broad private composer. A mere Seat cannot call it.
CREATE OR REPLACE FUNCTION public.ledger_temporal_composer_self_api_v1(
  p_ledger_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer DEFAULT 5000
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $calendar$
  SELECT atlas.ledger_temporal_composer_self_api_v1(
    p_ledger_id,p_start_date,p_end_date,p_timezone_name,p_limit)
$calendar$;
REVOKE ALL ON FUNCTION public.ledger_temporal_composer_self_api_v1(
  uuid,date,date,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ledger_temporal_composer_self_api_v1(
  uuid,date,date,text,integer) TO authenticated;

-- Organization context calendar access remains explicitly governed
-- by current_effective_organization_membership inside the private source API.
-- This is not a route through a native Ledger Seat; those permissions must
-- be reconciled separately before treating it as a universal seat calendar.
CREATE OR REPLACE FUNCTION public.organization_context_temporal_composer_self_api_v2(
  p_organization_id uuid,
  p_context_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text DEFAULT NULL,
  p_limit integer DEFAULT 5000
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO ''
AS $calendar$
  SELECT atlas.organization_context_temporal_composer_self_api_v2(
    p_organization_id,p_context_id,p_start_date,p_end_date,
    p_timezone_name,p_limit)
$calendar$;
REVOKE ALL ON FUNCTION public.organization_context_temporal_composer_self_api_v2(
  uuid,uuid,date,date,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.organization_context_temporal_composer_self_api_v2(
  uuid,uuid,date,date,text,integer) TO authenticated;
COMMIT;
