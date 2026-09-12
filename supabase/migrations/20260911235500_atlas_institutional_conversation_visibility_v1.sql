begin;

create table atlas.institutional_conversation_visibility_policies (
  institutional_conversation_id uuid primary key references atlas.institutional_conversations(id) on delete cascade,
  visibility_class text not null default 'endpoint' check (visibility_class in ('endpoint','restricted')),
  set_by_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  reason text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table atlas.institutional_conversation_view_grants (
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete cascade,
  membership_id uuid not null references atlas.organization_memberships(id) on delete cascade,
  granted_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  grant_state text not null default 'active' check (grant_state in ('active','revoked')),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(institutional_conversation_id,membership_id),
  check ((grant_state='active' and revoked_at is null) or (grant_state='revoked' and revoked_at is not null))
);

revoke all on table atlas.institutional_conversation_visibility_policies from public,anon,authenticated;
revoke all on table atlas.institutional_conversation_view_grants from public,anon,authenticated;
alter table atlas.institutional_conversation_visibility_policies enable row level security;
alter table atlas.institutional_conversation_view_grants enable row level security;

comment on table atlas.institutional_conversation_visibility_policies is
  'Atlas-owned institutional conversation visibility. Absence or endpoint means ordinary endpoint capability governs; restricted requires explicit conversation grant except for an active organization owner.';
comment on table atlas.institutional_conversation_view_grants is
  'Explicit membership grants for restricted institutional conversations. A grant never substitutes for endpoint view authority.';

create or replace function atlas.institutional_conversation_membership_can_view_v1(
  p_institutional_conversation_id uuid,
  p_membership_id uuid
) returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  with context as (
    select c.id as conversation_id,c.organization_id,
      coalesce(v.visibility_class,'endpoint') as visibility_class,
      m.id as membership_id,m.role
    from atlas.institutional_conversations c
    join atlas.organization_memberships m
      on m.id=p_membership_id and m.organization_id=c.organization_id and m.active
    left join atlas.institutional_conversation_visibility_policies v
      on v.institutional_conversation_id=c.id
    where c.id=p_institutional_conversation_id
  )
  select coalesce((
    select
      case
        when context.role='owner' then true
        when not exists (
          select 1
          from atlas.institutional_conversation_endpoints ce
          where ce.institutional_conversation_id=context.conversation_id
            and atlas.communication_endpoint_membership_has_capability_v1(ce.communication_endpoint_id,context.membership_id,'view')
        ) then false
        when context.visibility_class='endpoint' then true
        when context.visibility_class='restricted' then exists (
          select 1
          from atlas.institutional_conversation_view_grants g
          where g.institutional_conversation_id=context.conversation_id
            and g.membership_id=context.membership_id
            and g.grant_state='active'
        )
        else false
      end
    from context
  ),false);
$function$;
revoke all on function atlas.institutional_conversation_membership_can_view_v1(uuid,uuid) from public,anon,authenticated;

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
    select 1 from unnest(v_allowed) id
    where not exists (
      select 1 from atlas.organization_memberships m
      where m.id=id and m.organization_id=v_conv.organization_id and m.active
    )
  ) then raise exception 'Every allowed membership must be active in the conversation organization.' using errcode='23514'; end if;

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
    'endpointViewStillRequiredForNonOwners',true
  );
end;
$function$;
revoke all on function atlas.set_institutional_conversation_visibility_self_api_v1(uuid,text,uuid[],text) from public,anon;
grant execute on function atlas.set_institutional_conversation_visibility_self_api_v1(uuid,text,uuid[],text) to authenticated;

create or replace function public.set_institutional_conversation_visibility_self_api_v1(
  p_institutional_conversation_id uuid,
  p_visibility_class text,
  p_allowed_membership_ids uuid[] default '{}'::uuid[],
  p_reason text default null
) returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.set_institutional_conversation_visibility_self_api_v1(
    p_institutional_conversation_id,p_visibility_class,p_allowed_membership_ids,p_reason
  );
$function$;
revoke all on function public.set_institutional_conversation_visibility_self_api_v1(uuid,text,uuid[],text) from public,anon;
grant execute on function public.set_institutional_conversation_visibility_self_api_v1(uuid,text,uuid[],text) to authenticated;

create or replace function atlas.guard_conversation_attention_visibility_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.institutional_conversation_id is not null
     and not atlas.institutional_conversation_membership_can_view_v1(new.institutional_conversation_id,new.membership_id) then
    raise exception 'Membership may not observe attention state for this institutional conversation.' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists communication_attention_conversation_visibility_guard on atlas.communication_attention_events;
create trigger communication_attention_conversation_visibility_guard
before insert or update of institutional_conversation_id,membership_id on atlas.communication_attention_events
for each row execute function atlas.guard_conversation_attention_visibility_v1();

create or replace function atlas.guard_conversation_outbound_visibility_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.institutional_conversation_id is not null
     and new.initiated_by_membership_id is not null
     and not atlas.institutional_conversation_membership_can_view_v1(new.institutional_conversation_id,new.initiated_by_membership_id) then
    raise exception 'Membership may not send from this institutional conversation.' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists communication_outbound_conversation_visibility_guard on atlas.communication_outbound_operations;
create trigger communication_outbound_conversation_visibility_guard
before insert or update of institutional_conversation_id,initiated_by_membership_id on atlas.communication_outbound_operations
for each row execute function atlas.guard_conversation_outbound_visibility_v1();

create or replace function atlas.guard_conversation_response_event_visibility_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.actor_membership_id is not null
     and not atlas.institutional_conversation_membership_can_view_v1(new.institutional_conversation_id,new.actor_membership_id) then
    raise exception 'Actor membership may not act on this institutional conversation.' using errcode='42501';
  end if;
  if new.target_membership_id is not null
     and not atlas.institutional_conversation_membership_can_view_v1(new.institutional_conversation_id,new.target_membership_id) then
    raise exception 'Target membership may not receive responsibility for this institutional conversation.' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists institutional_response_event_conversation_visibility_guard on atlas.institutional_conversation_response_events;
create trigger institutional_response_event_conversation_visibility_guard
before insert or update of institutional_conversation_id,actor_membership_id,target_membership_id on atlas.institutional_conversation_response_events
for each row execute function atlas.guard_conversation_response_event_visibility_v1();

create or replace function atlas.guard_conversation_work_allocation_visibility_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_conversation_id uuid;
begin
  if new.state<>'active' or new.allocation_role<>'responsible' or new.assignee_membership_id is null then return new; end if;
  select rc.institutional_conversation_id into v_conversation_id
  from atlas.institutional_conversation_response_work_bindings wb
  join atlas.institutional_conversation_response_cases rc on rc.id=wb.response_case_id
  where wb.work_item_id=new.work_item_id
  limit 1;
  if v_conversation_id is not null
     and not atlas.institutional_conversation_membership_can_view_v1(v_conversation_id,new.assignee_membership_id) then
    raise exception 'Responsibility may not be allocated to a membership that cannot view the institutional conversation.' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists work_allocation_conversation_visibility_guard on atlas.work_allocations;
create trigger work_allocation_conversation_visibility_guard
before insert or update of work_item_id,assignee_membership_id,allocation_role,state on atlas.work_allocations
for each row execute function atlas.guard_conversation_work_allocation_visibility_v1();

create or replace function atlas.institutional_shared_inbox_self_v1(p_communication_endpoint_id uuid,p_limit integer default 200)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_member atlas.organization_memberships%rowtype; v_endpoint atlas.communication_endpoints%rowtype; v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>1000 then raise exception 'Limit must be between 1 and 1000.' using errcode='22023'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id;
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.last_activity_at desc,x.institutional_conversation_id),'[]'::jsonb) into v_items from (
    select v.*,
      coalesce((select p.visibility_class from atlas.institutional_conversation_visibility_policies p where p.institutional_conversation_id=v.institutional_conversation_id),'endpoint') as visibility_class,
      exists(select 1 from atlas.communication_attention_events a where a.communication_event_id=v.last_message_event_id and a.membership_id=v_member.id and a.attention_kind in ('opened','marked_read')) as last_message_opened_by_me
    from atlas.v_institutional_shared_inbox_v1 v
    where v.communication_endpoint_id=v_endpoint.id
      and atlas.institutional_conversation_membership_can_view_v1(v.institutional_conversation_id,v_member.id)
    order by v.last_activity_at desc limit p_limit
  ) x;
  return jsonb_build_object('contractVersion','institutional_shared_inbox_v1','communicationEndpointId',v_endpoint.id,'membershipId',v_member.id,'items',v_items);
end;
$function$;

create or replace function atlas.institutional_conversation_detail_self_v1(p_institutional_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare v_conv atlas.institutional_conversations%rowtype; v_endpoint_id uuid; v_member atlas.organization_memberships%rowtype; v_messages jsonb; v_response jsonb; v_visibility text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_member from atlas.organization_memberships where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.institutional_conversation_membership_can_view_v1(v_conv.id,v_member.id) then raise exception 'Institutional conversation view authority required.' using errcode='42501'; end if;
  select coalesce(visibility_class,'endpoint') into v_visibility from atlas.institutional_conversation_visibility_policies where institutional_conversation_id=v_conv.id;
  v_visibility:=coalesce(v_visibility,'endpoint');
  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at,x.communication_event_id),'[]'::jsonb) into v_messages from (
    select e.id as communication_event_id,e.occurred_at,e.direction,e.speaker_address,e.body,e.body_state,e.canonical_event,
      (select min(a.occurred_at) from atlas.communication_attention_events a where a.communication_event_id=e.id and a.attention_kind='opened') as first_opened_at,
      (select a.membership_id from atlas.communication_attention_events a where a.communication_event_id=e.id and a.attention_kind='opened' order by a.occurred_at,a.id limit 1) as first_opened_by_membership_id,
      exists(select 1 from atlas.communication_attention_events a where a.communication_event_id=e.id and a.membership_id=v_member.id and a.attention_kind in ('opened','marked_read')) as opened_by_me
    from atlas.institutional_conversation_messages m join atlas.communication_events e on e.id=m.communication_event_id
    where m.institutional_conversation_id=v_conv.id
  ) x;
  select to_jsonb(r) into v_response from atlas.v_institutional_shared_inbox_v1 r where r.institutional_conversation_id=v_conv.id;
  return jsonb_build_object('contractVersion','institutional_conversation_detail_v1','conversation',jsonb_build_object('id',v_conv.id,'subject',v_conv.subject,'state',v_conv.conversation_state,'endpointId',v_endpoint_id,'visibilityClass',v_visibility),'response',coalesce(v_response,'{}'::jsonb),'messages',v_messages,'membershipId',v_member.id);
end;
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.set_institutional_conversation_visibility_self_api_v1(uuid, text, uuid[], text)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'source','atlas_institutional_conversation_visibility_v1',
    'purpose','Allow an active organization owner to restrict or restore endpoint-level visibility for one institutional conversation.',
    'boundary','Restricted conversations remain inside the same organization and endpoint custody. Non-owner access requires both endpoint view capability and an explicit conversation grant. Active owners remain able to view.',
    'truthBoundary','Visibility controls observation and action authority only; it does not alter provider evidence, infer sensitivity, assign responsibility, or delete history.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),now(),false
) on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;
