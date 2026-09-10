-- Complete the browser-facing membrane for invitation-specific review and identity correction.
-- Atlas-domain functions remain the authority; public functions are authenticated PostgREST wrappers only.

create or replace function public.pending_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.pending_organization_employee_invitation_self_api_v1(p_invitation_id);
$function$;

create or replace function public.mark_organization_employee_invitation_not_me_self_api_v1(p_invitation_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $function$
  select atlas.mark_organization_employee_invitation_not_me_self_api_v1(p_invitation_id);
$function$;

revoke all on function public.pending_organization_employee_invitation_self_api_v1(uuid) from public,anon;
revoke all on function public.mark_organization_employee_invitation_not_me_self_api_v1(uuid) from public,anon;

grant execute on function public.pending_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;
grant execute on function public.mark_organization_employee_invitation_not_me_self_api_v1(uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.pending_organization_employee_invitation_self_api_v1(p_invitation_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Review one pending organization employee invitation belonging to the signed-in human.'),now()),
  ('atlas.mark_organization_employee_invitation_not_me_self_api_v1(p_invitation_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Record that a pending organization employee invitation may not belong to the signed-in human without accepting it.'),now())
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence || excluded.evidence,
  reviewed_at=now();