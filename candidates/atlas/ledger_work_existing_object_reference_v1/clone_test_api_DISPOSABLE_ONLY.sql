-- DISPOSABLE PG17+GoTrue+PostgREST CLONE ONLY. Never apply to production.
-- Requires HELD_source_candidate.sql and the exact C1 fictional Venue extension.
-- No TABLE grants and no authenticated access to the held source function.
BEGIN;

DO $disposable_bed_reference_guard$
BEGIN
  IF current_database() <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR (SELECT count(*) FROM auth.users WHERE id IN (
      'e5200000-0000-4000-8000-000000000001'::uuid,
      'e5200000-0000-4000-8000-000000000002'::uuid,
      'e5200000-0000-4000-8000-000000000003'::uuid,
      'e5200000-0000-4000-8000-000000000004'::uuid
    )) <> 4
    OR NOT EXISTS (
      SELECT 1 FROM atlas.growing_objects
      WHERE id='e5200000-0000-4000-8000-000000000b03'::uuid
        AND stable_key='clone-upick-bed-3'
    )
    OR NOT EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance
      WHERE work_item_id='e5200000-0000-4000-8000-000000000b20'::uuid
        AND ledger_id='e5200000-0000-4000-8000-000000000402'::uuid
        AND attribution_state='active'
    )
  THEN
    RAISE EXCEPTION 'Refuse signed test transport outside exact fictional clone'
      USING ERRCODE='42501';
  END IF;
END;
$disposable_bed_reference_guard$;

CREATE FUNCTION public.clone_test_ledger_work_existing_bed_reference_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_work_item_id uuid,
  p_bed_id uuid,
  p_source_action_id text
) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $$
  SELECT atlas.establish_ledger_work_existing_bed_reference_self_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_bed_id,p_source_action_id);
$$;
REVOKE ALL ON FUNCTION public.clone_test_ledger_work_existing_bed_reference_v1(
  uuid,uuid,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.clone_test_ledger_work_existing_bed_reference_v1(
  uuid,uuid,uuid,uuid,text) TO authenticated;
COMMIT;
