-- DISPOSABLE CLONE ONLY. Never install in production.
-- Temporary test-only public PostgREST transport over STILL-PRIVATE held
-- source methods. Does not release, alter or broaden original Flower commands.
BEGIN;

DO $disposable_venue_guard$
BEGIN
 IF current_database() <> 'postgres'
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR (SELECT count(*) FROM auth.users
        WHERE id IN (
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
      SELECT 1 FROM atlas.farm_crop_ledger_custody_v1
      WHERE farm_id='e5200000-0000-4000-8000-000000000b01'::uuid
        AND ledger_id='e5200000-0000-4000-8000-000000000401'::uuid
        AND custody_state='active'
    )
 THEN
   RAISE EXCEPTION 'Refusing Venue signed test transport outside exact fictional clone'
     USING ERRCODE='42501';
 END IF;
END
$disposable_venue_guard$;

CREATE FUNCTION public.clone_test_venue_bed_offer_v1(
 p_flower_ledger_id uuid,p_venue_ledger_id uuid,p_bed_id uuid,p_source_action_id text
) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $$
  SELECT atlas.offer_venue_bed_shared_use_self_v1(
    p_flower_ledger_id,p_venue_ledger_id,p_bed_id,p_source_action_id);
$$;

CREATE FUNCTION public.clone_test_venue_bed_accept_v1(p_offer_id uuid)
RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $$ SELECT atlas.accept_venue_bed_shared_use_self_v1(p_offer_id); $$;

CREATE FUNCTION public.clone_test_venue_bed_link_v1(
 p_use_authorization_id uuid,p_work_item_id uuid,
 p_source_action_id text,p_human_review jsonb
) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $$
  SELECT atlas.establish_venue_work_bed_reference_self_v1(
    p_use_authorization_id,p_work_item_id,p_source_action_id,p_human_review);
$$;

CREATE FUNCTION public.clone_test_venue_bed_withdraw_v1(p_use_id uuid)
RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $$ SELECT atlas.withdraw_venue_bed_shared_use_self_v1(p_use_id); $$;

-- Browser-style temporary transport ONLY in clone. Private source functions
-- remain uncallable to ordinary authenticated SQL roles.
REVOKE ALL ON FUNCTION public.clone_test_venue_bed_offer_v1(uuid,uuid,uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.clone_test_venue_bed_accept_v1(uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.clone_test_venue_bed_link_v1(uuid,uuid,text,jsonb) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.clone_test_venue_bed_withdraw_v1(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.clone_test_venue_bed_offer_v1(uuid,uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clone_test_venue_bed_accept_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clone_test_venue_bed_link_v1(uuid,uuid,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clone_test_venue_bed_withdraw_v1(uuid) TO authenticated;

-- DISPOSABLE fallback transport for the genuine existing Company Work
-- owner decision source. It delegates with the CALLER's signed authenticated
-- role; it never supplies identity or grants any new production endpoint.
-- A released public route, when present, is preferred by the test script.
CREATE FUNCTION public.clone_test_flower_owner_accept_result_v1(
 p_execution_result_id uuid,p_decision text,p_reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $worker_test$
 SELECT atlas.organization_owner_decide_company_work_result_api_v1(
   p_execution_result_id,p_decision,p_reason);
$worker_test$;
REVOKE ALL ON FUNCTION public.clone_test_flower_owner_accept_result_v1(uuid,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.clone_test_flower_owner_accept_result_v1(uuid,text,text)
  TO authenticated;

COMMIT;
