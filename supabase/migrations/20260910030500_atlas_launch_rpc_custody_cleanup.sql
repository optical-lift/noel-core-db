-- First-user launch custody cleanup for browser-facing Atlas RPCs.
-- The browser calls public PostgREST RPC names; Atlas-domain functions remain the governed authority.

create or replace function public.organization_access_inviter_contexts_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_access_inviter_contexts_self_api_v1();
$function$;

create or replace function public.list_pending_organization_employee_invitations_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.list_pending_organization_employee_invitations_self_api_v1();
$function$;

create or replace function public.accept_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $function$
  select atlas.accept_organization_employee_invitation_self_api_v1(p_invitation_id);
$function$;

create or replace function public.decline_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $function$
  select atlas.decline_organization_employee_invitation_self_api_v1(p_invitation_id);
$function$;

revoke all on function public.organization_access_inviter_contexts_self_api_v1() from public,anon;
revoke all on function public.list_pending_organization_employee_invitations_self_api_v1() from public,anon;
revoke all on function public.accept_organization_employee_invitation_self_api_v1(uuid) from public,anon;
revoke all on function public.decline_organization_employee_invitation_self_api_v1(uuid) from public,anon;

grant execute on function public.organization_access_inviter_contexts_self_api_v1() to authenticated,service_role;
grant execute on function public.list_pending_organization_employee_invitations_self_api_v1() to authenticated,service_role;
grant execute on function public.accept_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;
grant execute on function public.decline_organization_employee_invitation_self_api_v1(uuid) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.organization_access_inviter_contexts_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','List organizations the signed-in human may invite into.'),now()),
  ('atlas.list_pending_organization_employee_invitations_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Signed-in human pending organization invitation projection.'),now()),
  ('atlas.accept_organization_employee_invitation_self_api_v1(p_invitation_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Accept a pending organization employee invitation for the signed-in human.'),now()),
  ('atlas.decline_organization_employee_invitation_self_api_v1(p_invitation_id uuid)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Decline a pending organization employee invitation for the signed-in human.'),now()),
  ('atlas.organization_ledger_owner_window_api_v1(p_organization_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_after_revision bigint, p_limit integer)','app_endpoint','verified','active',true,true,false,false,1,0,jsonb_build_object('purpose','Owner-authorized Organization Ledger window projection used by notebook adapters.'),now())
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
