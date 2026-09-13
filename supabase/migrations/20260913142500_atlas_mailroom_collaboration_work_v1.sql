-- Mailroom collaboration + communication-derived work v1
-- Communication evidence, attention, response responsibility, and derived work remain separate authorities.

begin;

create table atlas.communication_derived_work_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  institutional_conversation_id uuid not null references atlas.institutional_conversations(id) on delete restrict,
  communication_event_id uuid not null references atlas.communication_events(id) on delete restrict,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  created_by_membership_id uuid not null,
  evidence_excerpt text,
  evidence_start integer,
  evidence_end integer,
  evidence_sha256 text,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint communication_derived_work_creator_org_fk
    foreign key (organization_id, created_by_membership_id)
    references atlas.organization_memberships(organization_id, id) on delete restrict,
  constraint communication_derived_work_work_org_fk
    foreign key (organization_id, work_item_id)
    references atlas.work_items(organization_id, id) on delete restrict,
  constraint communication_derived_work_metadata_object_check
    check (jsonb_typeof(metadata) = 'object'),
  constraint communication_derived_work_idempotency_nonblank_check
    check (btrim(idempotency_key) <> ''),
  constraint communication_derived_work_excerpt_check
    check (
      (evidence_excerpt is null and evidence_start is null and evidence_end is null and evidence_sha256 is null)
      or
      (evidence_excerpt is not null and evidence_start is not null and evidence_end is not null
       and evidence_start >= 0 and evidence_end > evidence_start and evidence_sha256 is not null)
    )
);

create unique index communication_derived_work_org_idempotency_uq
  on atlas.communication_derived_work_links(organization_id, idempotency_key);
create unique index communication_derived_work_work_uq
  on atlas.communication_derived_work_links(work_item_id);
create index communication_derived_work_conversation_idx
  on atlas.communication_derived_work_links(institutional_conversation_id, created_at);
create index communication_derived_work_event_idx
  on atlas.communication_derived_work_links(communication_event_id, created_at);

revoke all on table atlas.communication_derived_work_links from anon, authenticated;

create or replace function atlas.prevent_communication_derived_work_link_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $$
begin
  raise exception 'Communication-derived work provenance is append-only.' using errcode='42501';
end;
$$;

create trigger communication_derived_work_links_append_only_v1
before update or delete on atlas.communication_derived_work_links
for each row execute function atlas.prevent_communication_derived_work_link_mutation_v1();

create or replace function atlas.create_communication_derived_work_self_api_v1(
  p_institutional_conversation_id uuid,
  p_communication_event_id uuid,
  p_excerpt text,
  p_title text,
  p_instructions text,
  p_assignee_membership_id uuid,
  p_due_at timestamptz,
  p_expected_duration_minutes integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth, extensions
as $$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_event atlas.communication_events%rowtype;
  v_endpoint_id uuid;
  v_actor atlas.organization_memberships%rowtype;
  v_assignee atlas.organization_memberships%rowtype;
  v_existing atlas.communication_derived_work_links%rowtype;
  v_work_id uuid := gen_random_uuid();
  v_link_id uuid := gen_random_uuid();
  v_excerpt text := nullif(btrim(coalesce(p_excerpt,'')), '');
  v_pos integer;
  v_start integer;
  v_end integer;
  v_sha text;
  v_assignment jsonb;
  v_time_contract_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_title,'')),'') is null or length(btrim(p_title)) > 220 then
    raise exception 'Task title is required and must be 220 characters or fewer.' using errcode='22023';
  end if;
  if length(coalesce(p_instructions,'')) > 6000 then
    raise exception 'Task details must be 6000 characters or fewer.' using errcode='22023';
  end if;
  if v_excerpt is not null and length(v_excerpt) > 3000 then
    raise exception 'Selected evidence must be 3000 characters or fewer.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null or length(btrim(p_idempotency_key)) > 240 then
    raise exception 'A valid idempotency key is required.' using errcode='22023';
  end if;
  if p_expected_duration_minutes is not null and (p_expected_duration_minutes < 0 or p_expected_duration_minutes > 1440) then
    raise exception 'Expected duration must be between 0 and 1440 minutes.' using errcode='22023';
  end if;

  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;

  select e.* into v_event
  from atlas.institutional_conversation_messages m
  join atlas.communication_events e on e.id=m.communication_event_id
  where m.institutional_conversation_id=v_conv.id and m.communication_event_id=p_communication_event_id
  limit 1;
  if v_event.id is null then raise exception 'Message does not belong to this conversation.' using errcode='22023'; end if;

  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;

  select * into v_actor from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=auth.uid() and active
  order by created_at limit 1;
  if v_actor.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select * into v_existing from atlas.communication_derived_work_links
  where organization_id=v_conv.organization_id and idempotency_key=btrim(p_idempotency_key) limit 1;
  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','communication_derived_work_create_v1','deduplicated',true,
      'linkId',v_existing.id,'workItemId',v_existing.work_item_id
    );
  end if;

  if v_excerpt is not null then
    v_pos := strpos(coalesce(v_event.body,''),v_excerpt);
    if v_pos <= 0 then raise exception 'Selected text is not present in the canonical message body.' using errcode='22023'; end if;
    v_start := v_pos - 1;
    v_end := v_start + char_length(v_excerpt);
    v_sha := encode(extensions.digest(v_event.id::text || ':' || v_excerpt,'sha256'),'hex');
  end if;

  if p_assignee_membership_id is not null then
    select * into v_assignee from atlas.organization_memberships
    where id=p_assignee_membership_id and organization_id=v_conv.organization_id and active;
    if v_assignee.id is null then raise exception 'Choose an active organization member.' using errcode='22023'; end if;
    if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_assignee.id,'view') then
      raise exception 'The assignee must be authorized to view this communication endpoint.' using errcode='42501';
    end if;
    if v_assignee.id is distinct from v_actor.id
       and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff') then
      raise exception 'Endpoint handoff authority is required to assign communication-derived work to another member.' using errcode='42501';
    end if;
  end if;

  insert into atlas.work_items(
    id,organization_id,organization_unit_id,title,instructions,work_state,
    jurisdiction_key,source_object_type,source_object_id,created_by_user_id,stable_key,metadata
  ) values (
    v_work_id,v_conv.organization_id,v_conv.organization_unit_id,btrim(p_title),nullif(btrim(coalesce(p_instructions,'')),''),'open',
    'communication:endpoint:'||v_endpoint_id::text,'communication_event',v_event.id,auth.uid(),
    'communication-derived-work:'||v_link_id::text,
    jsonb_build_object('contractVersion','communication_derived_work_v1','institutionalConversationId',v_conv.id,'communicationEventId',v_event.id)
  );

  insert into atlas.communication_derived_work_links(
    id,organization_id,institutional_conversation_id,communication_event_id,work_item_id,
    created_by_membership_id,evidence_excerpt,evidence_start,evidence_end,evidence_sha256,idempotency_key,metadata
  ) values (
    v_link_id,v_conv.organization_id,v_conv.id,v_event.id,v_work_id,v_actor.id,
    v_excerpt,v_start,v_end,v_sha,btrim(p_idempotency_key),jsonb_build_object('source','mailroom')
  );

  if p_due_at is not null or p_expected_duration_minutes is not null then
    insert into atlas.work_time_contracts(
      organization_id,work_item_id,contract_state,latest_lawful_at,hard_finish_at,
      expected_duration_minutes,movement_policy,consequence_of_delay,source_kind,source_id,source_confidence,metadata
    ) values (
      v_conv.organization_id,v_work_id,'active',p_due_at,p_due_at,p_expected_duration_minutes,
      case when p_due_at is null then 'unplaced' else 'fixed' end,'{}'::jsonb,
      'communication_derived_work',v_link_id,1,
      jsonb_build_object('institutionalConversationId',v_conv.id,'communicationEventId',v_event.id)
    ) returning id into v_time_contract_id;
  end if;

  if v_assignee.id is not null then
    v_assignment := atlas.set_company_work_responsibility_internal_v1(
      v_work_id,v_assignee.id,v_actor.id,'communication_derived_work_assignment',
      jsonb_build_object('source','create_communication_derived_work_self_api_v1','derivedWorkLinkId',v_link_id)
    );
  end if;

  return jsonb_build_object(
    'contractVersion','communication_derived_work_create_v1','deduplicated',false,
    'linkId',v_link_id,'workItemId',v_work_id,'conversationId',v_conv.id,'communicationEventId',v_event.id,
    'title',btrim(p_title),'responsibleMembershipId',v_assignee.id,'timeContractId',v_time_contract_id,
    'assignment',v_assignment,
    'evidence',case when v_excerpt is null then null else jsonb_build_object('excerpt',v_excerpt,'start',v_start,'end',v_end,'sha256',v_sha) end
  );
end;
$$;

create or replace function atlas.handoff_communication_derived_work_self_api_v1(
  p_work_item_id uuid,p_target_membership_id uuid,p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_link atlas.communication_derived_work_links%rowtype;
  v_conv atlas.institutional_conversations%rowtype;
  v_endpoint_id uuid;
  v_actor atlas.organization_memberships%rowtype;
  v_target atlas.organization_memberships%rowtype;
  v_current atlas.work_allocations%rowtype;
  v_assignment jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_link from atlas.communication_derived_work_links where work_item_id=p_work_item_id;
  if v_link.id is null then raise exception 'Communication-derived work item not found.' using errcode='P0002'; end if;
  select * into v_conv from atlas.institutional_conversations where id=v_link.institutional_conversation_id;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_actor from atlas.organization_memberships
  where organization_id=v_link.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_actor.id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;

  select * into v_current from atlas.work_allocations
  where work_item_id=p_work_item_id and allocation_role='responsible' and state='active' limit 1;
  if v_current.id is not null
     and v_current.assignee_membership_id is distinct from v_actor.id
     and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff') then
    raise exception 'Current work responsibility or endpoint handoff authority required.' using errcode='42501';
  end if;
  if v_current.id is null
     and v_link.created_by_membership_id is distinct from v_actor.id
     and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff') then
    raise exception 'Work creator or endpoint handoff authority required.' using errcode='42501';
  end if;

  select * into v_target from atlas.organization_memberships
  where id=p_target_membership_id and organization_id=v_link.organization_id and active;
  if v_target.id is null then raise exception 'Choose an active organization member.' using errcode='22023'; end if;
  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_target.id,'view') then
    raise exception 'The target member must be authorized to view the source correspondence.' using errcode='42501';
  end if;

  v_assignment := atlas.set_company_work_responsibility_internal_v1(
    p_work_item_id,v_target.id,v_actor.id,coalesce(nullif(btrim(p_reason),''),'communication_derived_work_handoff'),
    jsonb_build_object('source','handoff_communication_derived_work_self_api_v1','derivedWorkLinkId',v_link.id)
  );
  return jsonb_build_object(
    'contractVersion','communication_derived_work_handoff_v1','workItemId',p_work_item_id,'derivedWorkLinkId',v_link.id,
    'fromMembershipId',v_current.assignee_membership_id,'toMembershipId',v_target.id,'assignment',v_assignment
  );
end;
$$;

create or replace function atlas.add_institutional_conversation_collaborator_self_api_v1(
  p_institutional_conversation_id uuid,p_target_membership_id uuid,p_allocation_role text default 'participant'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_endpoint_id uuid;
  v_actor atlas.organization_memberships%rowtype;
  v_target atlas.organization_memberships%rowtype;
  v_responsible atlas.work_allocations%rowtype;
  v_existing atlas.work_allocations%rowtype;
  v_allocation_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_allocation_role not in ('participant','approver') then raise exception 'Collaborator role must be participant or approver.' using errcode='22023'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_actor from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_actor.id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  select * into v_case from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id and case_state not in ('complete','informational') order by case_number desc limit 1;
  select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
  if v_binding.id is null then raise exception 'Claim the conversation before adding collaborators.' using errcode='22023'; end if;
  select * into v_responsible from atlas.work_allocations
  where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active' limit 1;
  if v_responsible.assignee_membership_id is distinct from v_actor.id
     and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff') then
    raise exception 'Current response responsibility or endpoint handoff authority required.' using errcode='42501';
  end if;
  select * into v_target from atlas.organization_memberships
  where id=p_target_membership_id and organization_id=v_conv.organization_id and active;
  if v_target.id is null then raise exception 'Choose an active organization member.' using errcode='22023'; end if;
  if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_target.id,'view') then
    raise exception 'Collaborators must be authorized to view this communication endpoint.' using errcode='42501';
  end if;

  perform 1 from atlas.work_items where id=v_binding.work_item_id for update;
  select * into v_existing from atlas.work_allocations
  where work_item_id=v_binding.work_item_id and assignee_membership_id=v_target.id
    and allocation_role=p_allocation_role and state='active' order by allocated_at desc limit 1;
  if v_existing.id is not null then
    return jsonb_build_object('contractVersion','institutional_conversation_collaborator_v1','deduplicated',true,
      'allocationId',v_existing.id,'workItemId',v_binding.work_item_id,'membershipId',v_target.id,'allocationRole',p_allocation_role);
  end if;

  insert into atlas.work_allocations(
    organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,allocation_role,state,metadata
  ) values (
    v_conv.organization_id,v_binding.work_item_id,v_target.id,v_actor.id,p_allocation_role,'active',
    jsonb_build_object('source','institutional_conversation_collaborator','institutionalConversationId',v_conv.id,'responseCaseId',v_case.id)
  ) returning id into v_allocation_id;
  return jsonb_build_object('contractVersion','institutional_conversation_collaborator_v1','deduplicated',false,
    'allocationId',v_allocation_id,'workItemId',v_binding.work_item_id,'membershipId',v_target.id,'allocationRole',p_allocation_role);
end;
$$;

create or replace function atlas.remove_institutional_conversation_collaborator_self_api_v1(
  p_institutional_conversation_id uuid,p_target_membership_id uuid,p_allocation_role text default 'participant'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_case atlas.institutional_conversation_response_cases%rowtype;
  v_binding atlas.institutional_conversation_response_work_bindings%rowtype;
  v_endpoint_id uuid;
  v_actor atlas.organization_memberships%rowtype;
  v_responsible atlas.work_allocations%rowtype;
  v_target_allocation atlas.work_allocations%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_allocation_role not in ('participant','approver') then raise exception 'Collaborator role must be participant or approver.' using errcode='22023'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_actor from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_actor.id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;
  select * into v_case from atlas.institutional_conversation_response_cases
  where institutional_conversation_id=v_conv.id and case_state not in ('complete','informational') order by case_number desc limit 1;
  select * into v_binding from atlas.institutional_conversation_response_work_bindings where response_case_id=v_case.id;
  if v_binding.id is null then raise exception 'Conversation response work not found.' using errcode='P0002'; end if;
  select * into v_responsible from atlas.work_allocations
  where work_item_id=v_binding.work_item_id and allocation_role='responsible' and state='active' limit 1;
  if v_actor.id is distinct from p_target_membership_id
     and v_responsible.assignee_membership_id is distinct from v_actor.id
     and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff') then
    raise exception 'Collaborator self-removal, current response responsibility, or endpoint handoff authority required.' using errcode='42501';
  end if;
  select * into v_target_allocation from atlas.work_allocations
  where work_item_id=v_binding.work_item_id and assignee_membership_id=p_target_membership_id
    and allocation_role=p_allocation_role and state='active' order by allocated_at desc limit 1 for update;
  if v_target_allocation.id is null then
    return jsonb_build_object('contractVersion','institutional_conversation_collaborator_remove_v1','released',false,
      'workItemId',v_binding.work_item_id,'membershipId',p_target_membership_id,'allocationRole',p_allocation_role);
  end if;
  update atlas.work_allocations set state='released',released_at=now(),release_reason='conversation_collaborator_removed',updated_at=now()
  where id=v_target_allocation.id;
  return jsonb_build_object('contractVersion','institutional_conversation_collaborator_remove_v1','released',true,
    'allocationId',v_target_allocation.id,'workItemId',v_binding.work_item_id,'membershipId',p_target_membership_id,'allocationRole',p_allocation_role);
end;
$$;

create or replace function atlas.institutional_conversation_detail_self_v3(p_institutional_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_endpoint_id uuid;
  v_member atlas.organization_memberships%rowtype;
  v_messages jsonb;
  v_response jsonb;
  v_participants jsonb;
  v_collaborators jsonb;
  v_derived_work jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;
  select communication_endpoint_id into v_endpoint_id from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_member from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at,x.communication_event_id),'[]'::jsonb) into v_messages
  from (
    select e.id communication_event_id,e.occurred_at,e.direction,e.speaker_address,e.body,e.body_state,e.canonical_event,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'participantId',p.id,'role',p.participant_role,'address',p.address,'addressNormalized',p.address_normalized,
          'addressKind',p.address_kind,'isSelf',p.is_self,'transportDisplayName',nullif(p.metadata->>'displayName',''),
          'resolutionState',lr.resolution_state,'externalRelationshipId',lr.external_relationship_id,
          'identitySubjectId',lr.subject_id,'resolvedDisplayName',lr.resolved_display_name,'resolvedSubjectKind',lr.subject_kind
        ) order by case p.participant_role when 'sender' then 0 when 'to' then 1 when 'cc' then 2 when 'bcc' then 3 else 4 end,p.address_normalized)
        from atlas.communication_event_participants p
        left join lateral (
          select r.resolution_state,r.external_relationship_id,er.subject_id,isp.display_name resolved_display_name,isp.subject_kind
          from atlas.communication_participant_relationship_resolutions r
          left join atlas.external_relationships er on er.id=r.external_relationship_id
          left join atlas.identity_subject_projections isp on isp.subject_id=er.subject_id and isp.organization_id=v_conv.organization_id
          where r.communication_event_participant_id=p.id
          order by r.created_at desc,r.id desc limit 1
        ) lr on true
        where p.communication_event_id=e.id
      ),'[]'::jsonb) participants,
      (select min(a.occurred_at) from atlas.communication_attention_events a where a.communication_event_id=e.id and a.attention_kind='opened') first_opened_at,
      coalesce((select case when a.attention_kind='marked_unread' then false else true end
        from atlas.communication_attention_events a where a.communication_event_id=e.id and a.membership_id=v_member.id
          and a.attention_kind in ('opened','marked_read','marked_unread') order by a.occurred_at desc,a.id desc limit 1),false) opened_by_me
    from atlas.institutional_conversation_messages m
    join atlas.communication_events e on e.id=m.communication_event_id
    where m.institutional_conversation_id=v_conv.id
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'address',q.address,'addressNormalized',q.address_normalized,'addressKind',q.address_kind,'isSelf',q.is_self,
    'displayName',q.display_name,'roles',to_jsonb(q.roles),'lastSeenAt',q.last_seen_at
  ) order by q.is_self,q.display_name nulls last,q.address_normalized),'[]'::jsonb) into v_participants
  from (
    select p.address,p.address_normalized,p.address_kind,bool_or(p.is_self) is_self,
      max(nullif(p.metadata->>'displayName','')) display_name,
      array_agg(distinct p.participant_role order by p.participant_role) roles,max(e.occurred_at) last_seen_at
    from atlas.institutional_conversation_messages m
    join atlas.communication_events e on e.id=m.communication_event_id
    join atlas.communication_event_participants p on p.communication_event_id=e.id
    where m.institutional_conversation_id=v_conv.id
    group by p.address,p.address_normalized,p.address_kind
  ) q;

  select to_jsonb(r) into v_response from atlas.v_institutional_shared_inbox_v1 r
  where r.institutional_conversation_id=v_conv.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'allocationId',a.id,'membershipId',a.assignee_membership_id,'allocationRole',a.allocation_role,
    'displayName',coalesce(up.display_name,om.role),'role',om.role,'allocatedAt',a.allocated_at
  ) order by case a.allocation_role when 'responsible' then 0 when 'participant' then 1 else 2 end,a.allocated_at),'[]'::jsonb)
  into v_collaborators
  from atlas.institutional_conversation_response_cases rc
  join atlas.institutional_conversation_response_work_bindings b on b.response_case_id=rc.id
  join atlas.work_allocations a on a.work_item_id=b.work_item_id and a.state='active'
  join atlas.organization_memberships om on om.id=a.assignee_membership_id
  left join atlas.user_profiles up on up.user_id=om.user_id
  where rc.institutional_conversation_id=v_conv.id and rc.case_state not in ('complete','informational')
    and a.allocation_role in ('responsible','participant','approver');

  select coalesce(jsonb_agg(jsonb_build_object(
    'linkId',l.id,'workItemId',w.id,'communicationEventId',l.communication_event_id,
    'title',w.title,'instructions',w.instructions,'workState',w.work_state,
    'evidenceExcerpt',l.evidence_excerpt,'createdAt',l.created_at,'createdByMembershipId',l.created_by_membership_id,
    'responsibleMembershipId',ra.assignee_membership_id,'responsibleDisplayName',coalesce(rp.display_name,rm.role),
    'dueAt',tc.hard_finish_at,'expectedDurationMinutes',tc.expected_duration_minutes
  ) order by l.created_at,l.id),'[]'::jsonb) into v_derived_work
  from atlas.communication_derived_work_links l
  join atlas.work_items w on w.id=l.work_item_id
  left join lateral (select a.* from atlas.work_allocations a
    where a.work_item_id=w.id and a.allocation_role='responsible' and a.state='active'
    order by a.allocated_at desc limit 1) ra on true
  left join atlas.organization_memberships rm on rm.id=ra.assignee_membership_id
  left join atlas.user_profiles rp on rp.user_id=rm.user_id
  left join lateral (select t.* from atlas.work_time_contracts t
    where t.work_item_id=w.id and t.contract_state='active' order by t.created_at desc limit 1) tc on true
  where l.institutional_conversation_id=v_conv.id;

  return jsonb_build_object(
    'contractVersion','institutional_conversation_detail_v3',
    'conversation',jsonb_build_object('id',v_conv.id,'subject',v_conv.subject,'state',v_conv.conversation_state,'endpointId',v_endpoint_id),
    'response',coalesce(v_response,'{}'::jsonb),'messages',v_messages,'participants',v_participants,
    'collaborators',v_collaborators,'derivedWork',v_derived_work,'membershipId',v_member.id
  );
end;
$$;

-- Browser membranes add no authority. Internal self APIs still enforce identity,
-- organization membership, endpoint capability, and responsibility.
create or replace function public.institutional_conversation_detail_self_v3(p_institutional_conversation_id uuid)
returns jsonb language sql stable security invoker set search_path=pg_catalog,atlas
as $$ select atlas.institutional_conversation_detail_self_v3(p_institutional_conversation_id); $$;

create or replace function public.create_communication_derived_work_self_api_v1(
  p_institutional_conversation_id uuid,p_communication_event_id uuid,p_excerpt text,p_title text,p_instructions text,
  p_assignee_membership_id uuid,p_due_at timestamptz,p_expected_duration_minutes integer,p_idempotency_key text
)
returns jsonb language sql volatile security invoker set search_path=pg_catalog,atlas
as $$ select atlas.create_communication_derived_work_self_api_v1(p_institutional_conversation_id,p_communication_event_id,p_excerpt,p_title,p_instructions,p_assignee_membership_id,p_due_at,p_expected_duration_minutes,p_idempotency_key); $$;

create or replace function public.handoff_communication_derived_work_self_api_v1(p_work_item_id uuid,p_target_membership_id uuid,p_reason text default null)
returns jsonb language sql volatile security invoker set search_path=pg_catalog,atlas
as $$ select atlas.handoff_communication_derived_work_self_api_v1(p_work_item_id,p_target_membership_id,p_reason); $$;

create or replace function public.add_institutional_conversation_collaborator_self_api_v1(p_institutional_conversation_id uuid,p_target_membership_id uuid,p_allocation_role text default 'participant')
returns jsonb language sql volatile security invoker set search_path=pg_catalog,atlas
as $$ select atlas.add_institutional_conversation_collaborator_self_api_v1(p_institutional_conversation_id,p_target_membership_id,p_allocation_role); $$;

create or replace function public.remove_institutional_conversation_collaborator_self_api_v1(p_institutional_conversation_id uuid,p_target_membership_id uuid,p_allocation_role text default 'participant')
returns jsonb language sql volatile security invoker set search_path=pg_catalog,atlas
as $$ select atlas.remove_institutional_conversation_collaborator_self_api_v1(p_institutional_conversation_id,p_target_membership_id,p_allocation_role); $$;

revoke all on function public.institutional_conversation_detail_self_v3(uuid) from public,anon;
revoke all on function public.create_communication_derived_work_self_api_v1(uuid,uuid,text,text,text,uuid,timestamptz,integer,text) from public,anon;
revoke all on function public.handoff_communication_derived_work_self_api_v1(uuid,uuid,text) from public,anon;
revoke all on function public.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) from public,anon;
revoke all on function public.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) from public,anon;

grant execute on function atlas.institutional_conversation_detail_self_v3(uuid) to authenticated,service_role;
grant execute on function atlas.create_communication_derived_work_self_api_v1(uuid,uuid,text,text,text,uuid,timestamptz,integer,text) to authenticated,service_role;
grant execute on function atlas.handoff_communication_derived_work_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function atlas.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.institutional_conversation_detail_self_v3(uuid) to authenticated,service_role;
grant execute on function public.create_communication_derived_work_self_api_v1(uuid,uuid,text,text,text,uuid,timestamptz,integer,text) to authenticated,service_role;
grant execute on function public.handoff_communication_derived_work_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text) to authenticated,service_role;

comment on table atlas.communication_derived_work_links is 'Append-only provenance linking exact communication evidence to independently governed Company Work.';
comment on function atlas.institutional_conversation_detail_self_v3(uuid) is 'Participant-aware Mailroom detail projection with collaborators and communication-derived Company Work.';

commit;
