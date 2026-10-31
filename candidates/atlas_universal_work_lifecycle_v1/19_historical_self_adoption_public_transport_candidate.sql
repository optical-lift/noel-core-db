-- HELD source-only PostgREST transport; no raw historical table exposure.
-- Every internal writer independently requires the exact native governor
-- or signed current worker/Seat/Subject disclosure; PUBLIC and anon denied.
CREATE OR REPLACE FUNCTION public.governor_link_historical_self_adoption_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_allocation_id uuid,p_related_person_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.governor_link_historical_self_adoption_self_api_v1(p_organization_id,p_ledger_id,p_work_item_id,p_allocation_id,p_related_person_id,p_action_id); $rpc$;
REVOKE ALL ON FUNCTION public.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_link_historical_self_adoption_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.report_historical_self_adoption_pending_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_evidence_text text,p_action_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.report_historical_self_adoption_pending_self_api_v1(p_organization_id,p_ledger_id,p_link_id,p_evidence_text,p_action_id); $rpc$;
REVOKE ALL ON FUNCTION public.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.report_historical_self_adoption_pending_self_api_v1(uuid,uuid,uuid,text,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.governor_review_historical_self_adoption_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_link_id uuid,p_outcome text,p_evidence_id uuid,p_action_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.governor_review_historical_self_adoption_self_api_v1(p_organization_id,p_ledger_id,p_link_id,p_outcome,p_evidence_id,p_action_id); $rpc$;
REVOKE ALL ON FUNCTION public.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_review_historical_self_adoption_self_api_v1(uuid,uuid,uuid,text,uuid,uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.governor_historical_self_adoption_history_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $rpc$ SELECT atlas.governor_historical_self_adoption_history_self_api_v1(p_organization_id,p_ledger_id,p_work_item_id); $rpc$;
REVOKE ALL ON FUNCTION public.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid) TO authenticated;
