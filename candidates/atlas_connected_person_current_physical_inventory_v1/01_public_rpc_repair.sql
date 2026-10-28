-- Fix live 2026-10-28 Ledger "Share current farm inventory" disappearance.
-- Production REST requests use the exposed PUBLIC schema, while the four
-- source-enforced functions from inventory v1 live only in atlas. These are
-- thin SECURITY INVOKER entrypoints. The atlas functions remain the single
-- source of authorization, native Person, and privacy decisions.
-- Do not replace them with a blanket farm-view grant.

CREATE OR REPLACE FUNCTION public.governor_farm_current_inventory_options_self_api_v1(
  p_ledger_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
 SELECT atlas.governor_farm_current_inventory_options_self_api_v1(p_ledger_id);
$function$;

CREATE OR REPLACE FUNCTION public.governor_set_farm_current_inventory_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_target_person_id uuid,
  p_farm_id uuid,p_decision_kind text,p_source_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $function$
 SELECT atlas.governor_set_farm_current_inventory_self_api_v1(
  p_organization_id,p_ledger_id,p_target_person_id,p_farm_id,
  p_decision_kind,p_source_action_id,p_reason);
$function$;

CREATE OR REPLACE FUNCTION public.connected_person_current_farm_inventory_sources_self_api_v1(
  p_ledger_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
 SELECT atlas.connected_person_current_farm_inventory_sources_self_api_v1(p_ledger_id);
$function$;

CREATE OR REPLACE FUNCTION public.connected_person_farm_current_inventory_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
 SELECT atlas.connected_person_farm_current_inventory_self_api_v1(
  p_organization_id,p_ledger_id,p_farm_id);
$function$;

REVOKE ALL ON FUNCTION public.governor_farm_current_inventory_options_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.governor_set_farm_current_inventory_self_api_v1(uuid,uuid,uuid,uuid,text,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.connected_person_current_farm_inventory_sources_self_api_v1(uuid)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.connected_person_farm_current_inventory_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.governor_farm_current_inventory_options_self_api_v1(uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.governor_set_farm_current_inventory_self_api_v1(uuid,uuid,uuid,uuid,text,uuid,text)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.connected_person_current_farm_inventory_sources_self_api_v1(uuid)
 TO authenticated;
GRANT EXECUTE ON FUNCTION public.connected_person_farm_current_inventory_self_api_v1(uuid,uuid,uuid)
 TO authenticated;

-- Invalidate PostgREST schema cache so the exact named RPC signatures are
-- available without changing browser client schema or weakening RLS.
NOTIFY pgrst, 'reload schema';
