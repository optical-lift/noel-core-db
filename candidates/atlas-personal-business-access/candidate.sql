BEGIN;

-- The existing atlas.reality_access_self_api_v1() is the canonical authenticated
-- self read for Reality Person, Personal Atlas and active Ledger Seats.
-- PostgREST in the Atlas browser calls only exposed public RPC wrappers.
-- Delegate without copying auth/seat logic or granting any new Entity authority.
CREATE OR REPLACE FUNCTION public.reality_access_self_api_v1()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog
AS $function$
  SELECT atlas.reality_access_self_api_v1();
$function$;

COMMENT ON FUNCTION public.reality_access_self_api_v1() IS
  'Authenticated browser-facing, read-only wrapper of Atlas canonical Reality access. Returns only the caller''s active Ledger Seats and self identity packet; never establishes ownership or authorization.';

REVOKE ALL ON FUNCTION public.reality_access_self_api_v1() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reality_access_self_api_v1() TO authenticated;

COMMIT;
