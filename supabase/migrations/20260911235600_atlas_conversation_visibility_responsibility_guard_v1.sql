begin;

create or replace function atlas.set_institutional_conversation_visibility_self_api_v1(
  p_institutional_conversation_id uuid,
  p_visibility_class text,
  p_allowed_membership_ids uuid[] default '{}'::uuid[],
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_conv atlas.institutional_conversations%rowtype;
  v_actor atlas.organization_memberships%rowtype;
  v_class text:=lower(btrim(coalesce(p_visibility_class,'')));
  v_allowed uuid[]:=coalesce(p_allowed_membership_ids,'{}'::uuid[]);
  v_member_id uuid;
  v_grants jsonb;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_class not in ('endpoint','restricted') then raise exception 'Visibility class must be endpoint or restricted.' using errcode='22023'; end if;

  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
  select * into v_actor
  from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=v_user and active and role='owner'
  order by created_at limit 1;
  if v_actor.id is null then raise exception 'Organization owner authority is required to change conversation visibility.' using errcode='42501'; end if;

  if exists (
    select 1
    from unnest(v_allowed) as allowed(membership_id)
    where not exists (
      select 1 from atlas.organization_memberships m
      where m.id=allowed.membership_id and m.organization_id=v_conv.organization_id and m.active
    )
  ) then raise exception 'Every allowed membership must be active in the conversation organization.' using errcode='23514'; end if;

  if v_class='restricted' and exists (
    select 1
    from atlas.institutional_conversation_response_cases rc
    join atlas.institutional_conversation_response_work_bindings wb on wb.response_case_id=rc.id
    join atlas.work_allocations wa on wa.work_item_id=wb.work_item_id
      and wa.allocation_role='responsible' and wa.state='active'
    join atlas.organization_memberships responsible on responsible.id=wa.assignee_membership_id
    where rc.institutional_conversation_id=v_conv.id
      and responsible.active
      and responsible.role<>'owner'
      and not (wa.assignee_membership_id=any(v_allowed))
  ) then
    raise exception 'Restricted visibility would hide this conversation from an active responsible membership. Handoff/complete that responsibility or include the membership first.' using errcode='23514';
  end if;

  insert into atlas.institutional_conversation_visibility_policies(
    institutional_conversation_id,visibility_class,set_by_membership_id,reason,metadata
  ) values (
    v_conv.id,v_class,v_actor.id,nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object('source','explicit_owner_visibility_change')
  )
  on conflict (institutional_conversation_id) do update
  set visibility_class=excluded.visibility_class,
      set_by_membership_id=excluded.set_by_membership_id,
      reason=excluded.reason,
      metadata=atlas.institutional_conversation_visibility_policies.metadata||excluded.metadata,
      updated_at=now();

  update atlas.institutional_conversation_view_grants
  set grant_state='revoked',revoked_at=coalesce(revoked_at,now()),updated_at=now()
  where institutional_conversation_id=v_conv.id and grant_state='active';

  if v_class='restricted' then
    foreach v_member_id in array v_allowed loop
      insert into atlas.institutional_conversation_view_grants(
        institutional_conversation_id,membership_id,granted_by_membership_id,grant_state,granted_at,revoked_at,metadata
      ) values (
        v_conv.id,v_member_id,v_actor.id,'active',now(),null,jsonb_build_object('source','explicit_owner_visibility_change')
      )
      on conflict (institutional_conversation_id,membership_id) do update
      set grant_state='active',granted_by_membership_id=excluded.granted_by_membership_id,
          granted_at=now(),revoked_at=null,
          metadata=atlas.institutional_conversation_view_grants.metadata||excluded.metadata,
          updated_at=now();
    end loop;
  end if;

  select coalesce(jsonb_agg(g.membership_id order by g.membership_id),'[]'::jsonb)
  into v_grants
  from atlas.institutional_conversation_view_grants g
  where g.institutional_conversation_id=v_conv.id and g.grant_state='active';

  return jsonb_build_object(
    'contractVersion','institutional_conversation_visibility_v1',
    'institutionalConversationId',v_conv.id,
    'visibilityClass',v_class,
    'allowedMembershipIds',v_grants,
    'ownerAlwaysAllowed',true,
    'endpointViewStillRequiredForNonOwners',true,
    'activeResponsibilityPreserved',true
  );
end;
$function$;
revoke all on function atlas.set_institutional_conversation_visibility_self_api_v1(uuid,text,uuid[],text) from public,anon;
grant execute on function atlas.set_institutional_conversation_visibility_self_api_v1(uuid,text,uuid[],text) to authenticated;

create or replace function atlas.guard_endpoint_grant_against_hidden_responsibility_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if exists (
    select 1
    from atlas.institutional_conversation_endpoints ce
    join atlas.institutional_conversation_visibility_policies vp
      on vp.institutional_conversation_id=ce.institutional_conversation_id
      and vp.visibility_class='restricted'
    join atlas.institutional_conversation_response_cases rc
      on rc.institutional_conversation_id=ce.institutional_conversation_id
    join atlas.institutional_conversation_response_work_bindings wb on wb.response_case_id=rc.id
    join atlas.work_allocations wa on wa.work_item_id=wb.work_item_id
      and wa.assignee_membership_id=old.membership_id
      and wa.allocation_role='responsible' and wa.state='active'
    where ce.communication_endpoint_id=old.communication_endpoint_id
      and not atlas.institutional_conversation_membership_can_view_v1(ce.institutional_conversation_id,old.membership_id)
  ) then
    raise exception 'Endpoint capability change would hide a restricted conversation from an active responsible membership. Handoff/complete responsibility first.' using errcode='23514';
  end if;

  if tg_op='DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

drop trigger if exists endpoint_grant_hidden_responsibility_guard_update on atlas.communication_endpoint_member_grants;
create trigger endpoint_grant_hidden_responsibility_guard_update
after update of capability,grant_state on atlas.communication_endpoint_member_grants
for each row execute function atlas.guard_endpoint_grant_against_hidden_responsibility_v1();

drop trigger if exists endpoint_grant_hidden_responsibility_guard_delete on atlas.communication_endpoint_member_grants;
create trigger endpoint_grant_hidden_responsibility_guard_delete
after delete on atlas.communication_endpoint_member_grants
for each row execute function atlas.guard_endpoint_grant_against_hidden_responsibility_v1();

comment on function atlas.guard_endpoint_grant_against_hidden_responsibility_v1() is
  'Prevents endpoint grant revocation/deletion from making an active restricted-conversation responsibility inaccessible to its assignee.';

commit;
