-- DISPOSABLE PG17+GoTrue+PostgREST CLONE ONLY. Never apply to production.
-- Requires HELD_source_candidate.sql loaded in the clone first.
-- No new TABLE grants. Expose only the one exact source operation to a real
-- signed authenticated actor; the internal SECURITY DEFINER function enforces
-- current native Ledger authority, current Person and source Work relevance.
BEGIN;
GRANT EXECUTE ON FUNCTION
  atlas.establish_ledger_work_existing_bed_reference_self_v1(
    uuid,uuid,uuid,uuid,text) TO authenticated;

CREATE FUNCTION public.clone_test_ledger_work_existing_bed_reference_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_work_item_id uuid,
  p_bed_id uuid,
  p_source_action_id text
) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $$
  SELECT atlas.establish_ledger_work_existing_bed_reference_self_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_bed_id,p_source_action_id);
$$;
REVOKE ALL ON FUNCTION public.clone_test_ledger_work_existing_bed_reference_v1(
  uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clone_test_ledger_work_existing_bed_reference_v1(
  uuid,uuid,uuid,uuid,text) TO authenticated;
COMMIT;
