-- Atlas Work Sentence Context v1
-- The rendered sentence is a projection. Typed relations remain authoritative.

create table if not exists atlas.work_item_context_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete cascade,
  subject_domain text not null,
  subject_kind text not null,
  subject_id uuid not null,
  relation_kind text not null,
  created_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint work_item_context_links_subject_pair_v1 check (
    (subject_domain='spatial' and subject_kind in ('zone','place'))
    or (subject_domain='identity' and subject_kind in ('identity_subject','external_relationship'))
  ),
  constraint work_item_context_links_relation_v1 check (
    relation_kind in ('about','for','located_in','acts_on','supports')
  ),
  constraint work_item_context_links_unique_v1 unique (
    work_item_id, subject_domain, subject_kind, subject_id, relation_kind
  )
);

create index if not exists work_item_context_links_work_v1
  on atlas.work_item_context_links(organization_id, work_item_id, created_at);

create index if not exists work_item_context_links_subject_v1
  on atlas.work_item_context_links(organization_id, subject_domain, subject_kind, subject_id);

alter table atlas.work_item_context_links enable row level security;
revoke all on table atlas.work_item_context_links from public, anon, authenticated;
grant select, insert, update, delete on table atlas.work_item_context_links to service_role;

create or replace function atlas.attach_work_item_context_internal_v1(
  p_work_item_id uuid,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id uuid,
  p_relation_kind text,
  p_created_by_membership_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_work atlas.work_items%rowtype;
  v_domain text := lower(btrim(coalesce(p_subject_domain,'')));
  v_kind text := lower(btrim(coalesce(p_subject_kind,'')));
  v_relation text := lower(btrim(coalesce(p_relation_kind,'')));
  v_link_id uuid;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then
    raise exception 'Company Work item not found.' using errcode='P0002';
  end if;

  if p_created_by_membership_id is not null and not exists (
    select 1 from atlas.organization_memberships m
    where m.id=p_created_by_membership_id and m.organization_id=v_work.organization_id and m.active
  ) then
    raise exception 'Context creator must be an active member of the work organization.' using errcode='42501';
  end if;

  if v_domain='spatial' and v_kind='zone' then
    if v_relation not in ('about','located_in','acts_on','supports') then
      raise exception 'That relation is not valid for a zone context.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.zones z
      join atlas.farms f on f.id=z.farm_id
      where z.id=p_subject_id and f.organization_id=v_work.organization_id
    ) then
      raise exception 'Zone context must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='spatial' and v_kind='place' then
    if v_relation not in ('about','located_in','acts_on','supports') then
      raise exception 'That relation is not valid for a place context.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.places p
      join atlas.farms f on f.id=p.farm_id
      where p.id=p_subject_id and f.organization_id=v_work.organization_id
    ) then
      raise exception 'Place context must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='identity' and v_kind='identity_subject' then
    if v_relation not in ('about','for','supports') then
      raise exception 'That relation is not valid for an identity subject.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.identity_subject_projections s
      where s.subject_id=p_subject_id and s.organization_id=v_work.organization_id
    ) then
      raise exception 'Identity subject must belong to the work organization.' using errcode='42501';
    end if;
  elsif v_domain='identity' and v_kind='external_relationship' then
    if v_relation not in ('about','for','supports') then
      raise exception 'That relation is not valid for an external relationship.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.external_relationships r
      where r.id=p_subject_id and r.organization_id=v_work.organization_id
    ) then
      raise exception 'External relationship must belong to the work organization.' using errcode='42501';
    end if;
  else
    raise exception 'Unsupported Company Work context subject.' using errcode='22023';
  end if;

  insert into atlas.work_item_context_links(
    organization_id,work_item_id,subject_domain,subject_kind,subject_id,relation_kind,
    created_by_membership_id,provenance,metadata
  ) values (
    v_work.organization_id,v_work.id,v_domain,v_kind,p_subject_id,v_relation,
    p_created_by_membership_id,coalesce(p_provenance,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (work_item_id,subject_domain,subject_kind,subject_id,relation_kind)
  do update set
    provenance=atlas.work_item_context_links.provenance || excluded.provenance,
    metadata=atlas.work_item_context_links.metadata || excluded.metadata
  returning id into v_link_id;

  return v_link_id;
end;
$$;

revoke all on function atlas.attach_work_item_context_internal_v1(uuid,text,text,uuid,text,uuid,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.attach_work_item_context_internal_v1(uuid,text,text,uuid,text,uuid,jsonb,jsonb) to service_role;

create or replace function atlas.create_communication_derived_work_self_api_v2(
  p_institutional_conversation_id uuid,
  p_communication_event_id uuid,
  p_excerpt text,
  p_title text,
  p_instructions text,
  p_assignee_membership_id uuid,
  p_due_at timestamptz,
  p_handling_mode text,
  p_context_links jsonb,
  p_related_work jsonb,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth, extensions
as $$
declare
  v_mode text := lower(btrim(coalesce(p_handling_mode,'')));
  v_base jsonb;
  v_work_id uuid;
  v_work atlas.work_items%rowtype;
  v_actor atlas.organization_memberships%rowtype;
  v_entry jsonb;
  v_subject_id uuid;
  v_target_id uuid;
  v_relation text;
  v_context_result jsonb := '[]'::jsonb;
  v_related_result jsonb := '[]'::jsonb;
begin
  if v_mode not in ('do','decide','research','prepare','watch') then
    raise exception 'Choose how Atlas should handle this work.' using errcode='22023';
  end if;

  if p_context_links is not null and jsonb_typeof(p_context_links) <> 'array' then
    raise exception 'Context links must be an array.' using errcode='22023';
  end if;
  if p_related_work is not null and jsonb_typeof(p_related_work) <> 'array' then
    raise exception 'Related work must be an array.' using errcode='22023';
  end if;
  if jsonb_array_length(coalesce(p_context_links,'[]'::jsonb)) > 24 then
    raise exception 'No more than 24 work contexts may be attached at once.' using errcode='22023';
  end if;
  if jsonb_array_length(coalesce(p_related_work,'[]'::jsonb)) > 24 then
    raise exception 'No more than 24 work relations may be attached at once.' using errcode='22023';
  end if;

  v_base := atlas.create_communication_derived_work_self_api_v1(
    p_institutional_conversation_id,
    p_communication_event_id,
    p_excerpt,
    p_title,
    p_instructions,
    p_assignee_membership_id,
    p_due_at,
    null,
    p_idempotency_key
  );

  v_work_id := nullif(v_base->>'workItemId','')::uuid;
  select * into v_work from atlas.work_items where id=v_work_id;
  if v_work.id is null then
    raise exception 'Company Work item was not created.' using errcode='P0002';
  end if;

  select * into v_actor from atlas.organization_memberships
  where organization_id=v_work.organization_id and user_id=auth.uid() and active
  order by created_at limit 1;
  if v_actor.id is null then
    raise exception 'Active organization membership required.' using errcode='42501';
  end if;

  update atlas.work_items
  set metadata = metadata || jsonb_build_object(
    'handlingMode',v_mode,
    'sentenceContractVersion','work_sentence_context_v1'
  ), updated_at=now()
  where id=v_work.id;

  for v_entry in select value from jsonb_array_elements(coalesce(p_context_links,'[]'::jsonb))
  loop
    begin
      v_subject_id := nullif(v_entry->>'subjectId','')::uuid;
    exception when invalid_text_representation then
      raise exception 'Each context requires a valid subject id.' using errcode='22023';
    end;
    if v_subject_id is null then
      raise exception 'Each context requires a subject id.' using errcode='22023';
    end if;

    perform atlas.attach_work_item_context_internal_v1(
      v_work.id,
      v_entry->>'subjectDomain',
      v_entry->>'subjectKind',
      v_subject_id,
      v_entry->>'relationKind',
      v_actor.id,
      jsonb_build_object(
        'source','communication_derived_work_v2',
        'institutionalConversationId',p_institutional_conversation_id,
        'communicationEventId',p_communication_event_id
      ),
      coalesce(v_entry->'metadata','{}'::jsonb)
    );
  end loop;

  for v_entry in select value from jsonb_array_elements(coalesce(p_related_work,'[]'::jsonb))
  loop
    begin
      v_target_id := nullif(v_entry->>'workItemId','')::uuid;
    exception when invalid_text_representation then
      raise exception 'Each related-work entry requires a valid work item id.' using errcode='22023';
    end;
    v_relation := lower(btrim(coalesce(v_entry->>'relationKind','')));
    if v_target_id is null or v_target_id=v_work.id then
      raise exception 'Related work must identify another Company Work item.' using errcode='22023';
    end if;
    if v_relation not in ('blocks','enables','depends_on','part_of','alternative_to','handoff_to') then
      raise exception 'Unsupported Company Work relation.' using errcode='22023';
    end if;
    if not exists (
      select 1 from atlas.work_items target
      where target.id=v_target_id and target.organization_id=v_work.organization_id
    ) then
      raise exception 'Related work must belong to the same organization.' using errcode='42501';
    end if;

    if not exists (
      select 1 from atlas.work_item_relations r
      where r.organization_id=v_work.organization_id
        and r.from_work_item_id=v_work.id
        and r.to_work_item_id=v_target_id
        and r.relation_kind=v_relation
        and r.active
    ) then
      insert into atlas.work_item_relations(
        organization_id,from_work_item_id,to_work_item_id,relation_kind,active,metadata
      ) values (
        v_work.organization_id,v_work.id,v_target_id,v_relation,true,
        jsonb_build_object(
          'source','communication_derived_work_v2',
          'institutionalConversationId',p_institutional_conversation_id,
          'communicationEventId',p_communication_event_id
        )
      );
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'subjectDomain',c.subject_domain,
    'subjectKind',c.subject_kind,
    'subjectId',c.subject_id,
    'relationKind',c.relation_kind
  ) order by c.created_at,c.id),'[]'::jsonb)
  into v_context_result
  from atlas.work_item_context_links c where c.work_item_id=v_work.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'relationKind',r.relation_kind,
    'workItemId',r.to_work_item_id
  ) order by r.created_at,r.id),'[]'::jsonb)
  into v_related_result
  from atlas.work_item_relations r
  where r.from_work_item_id=v_work.id and r.active;

  return v_base || jsonb_build_object(
    'contractVersion','communication_derived_work_create_v2',
    'handlingMode',v_mode,
    'contextLinks',v_context_result,
    'relatedWork',v_related_result
  );
end;
$$;

revoke all on function atlas.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,text) from public, anon;
grant execute on function atlas.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,text) to authenticated, service_role;

create or replace function atlas.communication_work_context_candidates_self_v1(
  p_institutional_conversation_id uuid,
  p_query text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_endpoint_id uuid;
  v_member atlas.organization_memberships%rowtype;
  v_query text := nullif(btrim(coalesce(p_query,'')),'');
  v_people jsonb;
  v_places jsonb;
  v_work jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then
    raise exception 'Institutional conversation not found.' using errcode='P0002';
  end if;
  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;
  select * into v_member from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=auth.uid() and active
  order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_member.id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectDomain','identity',
    'subjectKind','identity_subject',
    'subjectId',x.subject_id,
    'label',x.display_name,
    'kind',x.subject_kind
  ) order by x.display_name),'[]'::jsonb)
  into v_people
  from (
    select distinct on (s.subject_id) s.subject_id,s.display_name,s.subject_kind,s.updated_at
    from atlas.identity_subject_projections s
    where s.organization_id=v_conv.organization_id
      and nullif(btrim(coalesce(s.display_name,'')),'') is not null
      and (v_query is null or s.display_name ilike '%'||v_query||'%')
    order by s.subject_id,s.updated_at desc
    limit 40
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectDomain','spatial',
    'subjectKind',x.subject_kind,
    'subjectId',x.subject_id,
    'label',x.label,
    'kind',x.context_kind
  ) order by x.label),'[]'::jsonb)
  into v_places
  from (
    select z.id subject_id,'zone'::text subject_kind,z.label,'zone'::text context_kind
    from atlas.zones z join atlas.farms f on f.id=z.farm_id
    where f.organization_id=v_conv.organization_id
      and (v_query is null or z.label ilike '%'||v_query||'%')
    union all
    select p.id,'place'::text,p.label,p.place_type
    from atlas.places p join atlas.farms f on f.id=p.farm_id
    where f.organization_id=v_conv.organization_id
      and (v_query is null or p.label ilike '%'||v_query||'%')
    order by label
    limit 80
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',x.id,
    'label',x.title,
    'operationClass',x.operation_class,
    'workState',x.work_state,
    'handlingMode',x.metadata->>'handlingMode'
  ) order by x.updated_at desc,x.title),'[]'::jsonb)
  into v_work
  from (
    select w.* from atlas.work_items w
    where w.organization_id=v_conv.organization_id
      and w.work_state='open'
      and (v_query is null or w.title ilike '%'||v_query||'%')
    order by w.updated_at desc
    limit 80
  ) x;

  return jsonb_build_object(
    'contractVersion','communication_work_context_candidates_v1',
    'conversationId',v_conv.id,
    'people',v_people,
    'places',v_places,
    'relatedWork',v_work
  );
end;
$$;

revoke all on function atlas.communication_work_context_candidates_self_v1(uuid,text) from public, anon;
grant execute on function atlas.communication_work_context_candidates_self_v1(uuid,text) to authenticated, service_role;

create or replace function atlas.institutional_conversation_detail_self_v4(
  p_institutional_conversation_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_detail jsonb;
  v_derived jsonb;
begin
  v_detail := atlas.institutional_conversation_detail_self_v3(p_institutional_conversation_id);

  select coalesce(jsonb_agg(
    d.item || jsonb_build_object(
      'handlingMode',w.metadata->>'handlingMode',
      'contextLinks',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',c.id,
          'subjectDomain',c.subject_domain,
          'subjectKind',c.subject_kind,
          'subjectId',c.subject_id,
          'relationKind',c.relation_kind,
          'label',case
            when c.subject_domain='spatial' and c.subject_kind='zone'
              then (select z.label from atlas.zones z where z.id=c.subject_id)
            when c.subject_domain='spatial' and c.subject_kind='place'
              then (select p.label from atlas.places p where p.id=c.subject_id)
            when c.subject_domain='identity' and c.subject_kind='identity_subject'
              then (select s.display_name from atlas.identity_subject_projections s where s.subject_id=c.subject_id and s.organization_id=w.organization_id order by s.updated_at desc limit 1)
            when c.subject_domain='identity' and c.subject_kind='external_relationship'
              then (select s.display_name from atlas.external_relationships r left join atlas.identity_subject_projections s on s.subject_id=r.subject_id and s.organization_id=r.organization_id where r.id=c.subject_id order by s.updated_at desc limit 1)
            else null
          end
        ) order by c.created_at,c.id)
        from atlas.work_item_context_links c where c.work_item_id=w.id
      ),'[]'::jsonb),
      'relatedWork',coalesce((
        select jsonb_agg(jsonb_build_object(
          'relationKind',r.relation_kind,
          'workItemId',r.to_work_item_id,
          'title',target.title,
          'workState',target.work_state
        ) order by r.created_at,r.id)
        from atlas.work_item_relations r
        join atlas.work_items target on target.id=r.to_work_item_id
        where r.from_work_item_id=w.id and r.active
      ),'[]'::jsonb)
    ) order by d.ordinality
  ),'[]'::jsonb)
  into v_derived
  from jsonb_array_elements(coalesce(v_detail->'derivedWork','[]'::jsonb)) with ordinality d(item,ordinality)
  left join atlas.work_items w on w.id=nullif(d.item->>'workItemId','')::uuid;

  v_detail := jsonb_set(v_detail,'{derivedWork}',v_derived,true);
  return v_detail || jsonb_build_object('contractVersion','institutional_conversation_detail_v4');
end;
$$;

revoke all on function atlas.institutional_conversation_detail_self_v4(uuid) from public, anon;
grant execute on function atlas.institutional_conversation_detail_self_v4(uuid) to authenticated, service_role;

create or replace function public.create_communication_derived_work_self_api_v2(
  p_institutional_conversation_id uuid,
  p_communication_event_id uuid,
  p_excerpt text,
  p_title text,
  p_instructions text,
  p_assignee_membership_id uuid,
  p_due_at timestamptz,
  p_handling_mode text,
  p_context_links jsonb,
  p_related_work jsonb,
  p_idempotency_key text
) returns jsonb
language sql
set search_path = pg_catalog, atlas
as $$
  select atlas.create_communication_derived_work_self_api_v2(
    p_institutional_conversation_id,p_communication_event_id,p_excerpt,p_title,p_instructions,
    p_assignee_membership_id,p_due_at,p_handling_mode,p_context_links,p_related_work,p_idempotency_key
  );
$$;

create or replace function public.communication_work_context_candidates_self_v1(
  p_institutional_conversation_id uuid,
  p_query text default null
) returns jsonb
language sql
stable
set search_path = pg_catalog, atlas
as $$
  select atlas.communication_work_context_candidates_self_v1(p_institutional_conversation_id,p_query);
$$;

create or replace function public.institutional_conversation_detail_self_v4(
  p_institutional_conversation_id uuid
) returns jsonb
language sql
stable
set search_path = pg_catalog, atlas
as $$
  select atlas.institutional_conversation_detail_self_v4(p_institutional_conversation_id);
$$;

revoke all on function public.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,text) from public, anon;
revoke all on function public.communication_work_context_candidates_self_v1(uuid,text) from public, anon;
revoke all on function public.institutional_conversation_detail_self_v4(uuid) from public, anon;

grant execute on function public.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,text) to authenticated, service_role;
grant execute on function public.communication_work_context_candidates_self_v1(uuid,text) to authenticated, service_role;
grant execute on function public.institutional_conversation_detail_self_v4(uuid) to authenticated, service_role;

comment on table atlas.work_item_context_links is
  'Typed non-causal semantic context for Company Work. Human-readable work sentences are projections of these links plus allocation/time/work relations.';
comment on function atlas.create_communication_derived_work_self_api_v2(uuid,uuid,text,text,text,uuid,timestamptz,text,jsonb,jsonb,text) is
  'Creates correspondence-derived Company Work with handling mode, typed subject/place context, and explicit related-work relations while preserving v1 evidence authority.';
