begin;

create or replace function atlas.organization_access_inviter_contexts_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_items jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  with candidates as (
    select o.id as organization_id, o.name as organization_name
    from atlas.organizations o
    where o.status='active'
      and (
        exists (
          select 1 from atlas.organization_memberships m
          where m.organization_id=o.id
            and m.user_id=v_uid
            and m.active
            and m.role='owner'
        )
        or exists (
          select 1 from atlas.organization_onboarding_actors a
          where a.organization_id=o.id
            and a.human_user_id=v_uid
            and a.active
            and a.ended_at is null
        )
      )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId',c.organization_id,
    'organizationName',c.organization_name
  ) order by c.organization_name,c.organization_id),'[]'::jsonb)
  into v_items
  from candidates c;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_access_inviter_context_v1',
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_access_inviter_contexts_self_api_v1() from public,anon;
grant execute on function atlas.organization_access_inviter_contexts_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values (
  'atlas.organization_access_inviter_contexts_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_organization_access_inviter_context_list_v1',
    'purpose','List organizations for which the signed-in human may prepare organization employee invitations.',
    'truthBoundary','Read only; uses the same owner/setup-actor authority classes as invitation preparation and creates no access or authority.',
    'classificationRuleVersion',3
  ),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;