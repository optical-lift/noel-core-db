-- Build 4/5: public API transport only for released root-owner Atlas seams.
-- Candidate (not production DDL). The source functions retain all authorization
-- and scope judgments; no employee-impersonation, role grant, or table read.
BEGIN;

CREATE OR REPLACE FUNCTION public.company_work_accountability_native_ledger_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_scope text DEFAULT 'native_ledger',
  p_limit integer DEFAULT 200,
  p_after_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $$
  SELECT atlas.company_work_accountability_native_ledger_self_api_v1(
    p_organization_id,p_ledger_id,p_scope,p_limit,p_after_work_item_id
  );
$$;
REVOKE ALL ON FUNCTION public.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.company_people_native_ledger_scope_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_limit integer DEFAULT 50,
  p_after_person_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $$
  SELECT atlas.company_people_native_ledger_scope_self_api_v1(
    p_organization_id,p_ledger_id,p_limit,p_after_person_id
  );
$$;
REVOKE ALL ON FUNCTION public.company_people_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.company_people_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.establish_company_work_native_ledger_relevance_self_api_v1(
  p_work_item_id uuid,
  p_ledger_id uuid,
  p_evidence_basis jsonb
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $$
  SELECT atlas.establish_company_work_native_ledger_relevance_self_api_v1(
    p_work_item_id,p_ledger_id,p_evidence_basis
  );
$$;
REVOKE ALL ON FUNCTION public.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)
  TO authenticated;

COMMIT;
