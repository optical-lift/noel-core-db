-- Atlas temporal marker routing kernel v1
-- Add date-native canonical reality alongside entities and occurrences.

create table if not exists local_intel.temporal_markers (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  title text not null,
  marker_kind text not null,
  start_date date not null,
  end_date date,
  jurisdiction jsonb not null default '{}'::jsonb,
  recurrence_rule jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  source_id uuid references local_intel.sources(id) on delete set null,
  last_verified_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint temporal_markers_stable_key_nonblank_v1 check (btrim(stable_key) <> ''),
  constraint temporal_markers_title_nonblank_v1 check (btrim(title) <> ''),
  constraint temporal_markers_kind_nonblank_v1 check (btrim(marker_kind) <> ''),
  constraint temporal_markers_date_order_v1 check (end_date is null or end_date >= start_date),
  constraint temporal_markers_jurisdiction_object_v1 check (jsonb_typeof(jurisdiction)='object'),
  constraint temporal_markers_recurrence_object_v1 check (jsonb_typeof(recurrence_rule)='object'),
  constraint temporal_markers_metadata_object_v1 check (jsonb_typeof(metadata)='object')
);

comment on table local_intel.temporal_markers is
  'Canonical Shared Intelligence date/date-range meaning. A temporal marker is not an occurrence and does not require a host, venue, or time-of-day.';

create or replace function local_intel.set_temporal_marker_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists temporal_markers_updated_at_v1
  on local_intel.temporal_markers;

create trigger temporal_markers_updated_at_v1
before update on local_intel.temporal_markers
for each row
execute function local_intel.set_temporal_marker_updated_at_v1();

create table if not exists atlas.organization_temporal_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  temporal_marker_id uuid not null references local_intel.temporal_markers(id) on delete restrict,
  binding_state text not null default 'active'
    check (binding_state in ('active','inactive')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,temporal_marker_id),
  unique (organization_id,id)
);

comment on table atlas.organization_temporal_bindings is
  'Organization-private binding to one canonical Shared Intelligence temporal marker. The binding records relevance/use and does not copy canonical date identity.';

alter table atlas.organization_temporal_bindings enable row level security;

revoke all on table atlas.organization_temporal_bindings from public,anon,authenticated;
grant select,insert,update,delete on table atlas.organization_temporal_bindings to service_role;

create or replace function atlas.set_organization_temporal_binding_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists organization_temporal_bindings_updated_at_v1
  on atlas.organization_temporal_bindings;

create trigger organization_temporal_bindings_updated_at_v1
before update on atlas.organization_temporal_bindings
for each row
execute function atlas.set_organization_temporal_binding_updated_at_v1();

alter table atlas.organization_purpose_context_memberships
  add column if not exists temporal_binding_id uuid;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.organization_purpose_context_memberships'::regclass
      and conname='organization_purpose_context_memberships_temporal_binding_org_fk'
  ) then
    alter table atlas.organization_purpose_context_memberships
      add constraint organization_purpose_context_memberships_temporal_binding_org_fk
      foreign key (organization_id,temporal_binding_id)
      references atlas.organization_temporal_bindings(organization_id,id)
      on delete restrict;
  end if;
end
$$;

alter table atlas.organization_purpose_context_memberships
  drop constraint if exists organization_purpose_context_memberships_member_kind_check;

alter table atlas.organization_purpose_context_memberships
  add constraint organization_purpose_context_memberships_member_kind_check
  check (member_kind in ('external_relationship','occurrence_binding','temporal_binding'));

alter table atlas.organization_purpose_context_memberships
  drop constraint if exists organization_purpose_context_memberships_referent_shape_check;

alter table atlas.organization_purpose_context_memberships
  add constraint organization_purpose_context_memberships_referent_shape_check
  check (
    (
      member_kind='external_relationship'
      and external_relationship_id is not null
      and occurrence_binding_id is null
      and temporal_binding_id is null
    )
    or
    (
      member_kind='occurrence_binding'
      and occurrence_binding_id is not null
      and external_relationship_id is null
      and temporal_binding_id is null
    )
    or
    (
      member_kind='temporal_binding'
      and temporal_binding_id is not null
      and external_relationship_id is null
      and occurrence_binding_id is null
    )
  );

create unique index if not exists organization_purpose_context_memberships_temporal_uq
  on atlas.organization_purpose_context_memberships(context_id,temporal_binding_id)
  where temporal_binding_id is not null;

create or replace function atlas.bind_canonical_temporal_marker_service_v1(
  p_organization_id uuid,
  p_temporal_marker_id uuid,
  p_metadata jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_binding atlas.organization_temporal_bindings%rowtype;
begin
  if not exists(
    select 1 from atlas.organizations o
    where o.id=p_organization_id and o.status='active'
  ) then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;

  if not exists(
    select 1 from local_intel.temporal_markers t
    where t.id=p_temporal_marker_id and t.status='active'
  ) then
    raise exception 'Canonical temporal marker not found or inactive.' using errcode='P0002';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Temporal binding metadata must be a JSON object.' using errcode='22023';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships om
    where om.id=p_created_by_membership_id and om.organization_id=p_organization_id
  ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  insert into atlas.organization_temporal_bindings(
    organization_id,temporal_marker_id,binding_state,metadata,created_by_membership_id
  )
  values(
    p_organization_id,p_temporal_marker_id,'active',
    coalesce(p_metadata,'{}'::jsonb),p_created_by_membership_id
  )
  on conflict (organization_id,temporal_marker_id) do update
  set binding_state='active',
      metadata=atlas.organization_temporal_bindings.metadata || excluded.metadata,
      created_by_membership_id=coalesce(
        excluded.created_by_membership_id,
        atlas.organization_temporal_bindings.created_by_membership_id
      ),
      updated_at=now()
  returning * into v_binding;

  return jsonb_build_object(
    'contractVersion','organization_temporal_binding_v1',
    'bindingId',v_binding.id,
    'organizationId',v_binding.organization_id,
    'temporalMarkerId',v_binding.temporal_marker_id,
    'bindingState',v_binding.binding_state
  );
end
$function$;

create or replace function atlas.bind_canonical_temporal_marker_self_api_v1(
  p_organization_id uuid,
  p_temporal_marker_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;

  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.bind_canonical_temporal_marker_service_v1(
    p_organization_id,p_temporal_marker_id,p_metadata,v_membership_id
  );
end
$function$;

create or replace function atlas.add_temporal_marker_to_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_temporal_binding_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_roles text[];
  v_membership atlas.organization_purpose_context_memberships%rowtype;
begin
  if not exists(
    select 1 from atlas.organization_purpose_contexts c
    where c.id=p_context_id
      and c.organization_id=p_organization_id
      and c.context_state='active'
  ) then
    raise exception 'Active purpose context is outside organization or missing.' using errcode='42501';
  end if;

  if not exists(
    select 1 from atlas.organization_temporal_bindings b
    where b.id=p_temporal_binding_id
      and b.organization_id=p_organization_id
      and b.binding_state='active'
  ) then
    raise exception 'Active temporal binding is outside organization or missing.' using errcode='42501';
  end if;

  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object' then
    raise exception 'Membership payload and provenance must be JSON objects.' using errcode='22023';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships om
    where om.id=p_created_by_membership_id
      and om.organization_id=p_organization_id
  ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  select coalesce(array_agg(x.role_key order by x.role_key),'{}'::text[])
  into v_roles
  from (
    select distinct lower(btrim(v)) as role_key
    from unnest(coalesce(p_role_keys,'{}'::text[])) v
    where btrim(v) <> ''
      and lower(btrim(v)) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
  ) x;

  insert into atlas.organization_purpose_context_memberships(
    organization_id,context_id,member_kind,temporal_binding_id,
    membership_state,role_keys,payload,provenance,created_by_membership_id
  )
  values(
    p_organization_id,p_context_id,'temporal_binding',p_temporal_binding_id,
    'active',v_roles,coalesce(p_payload,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb),p_created_by_membership_id
  )
  on conflict (context_id,temporal_binding_id)
    where temporal_binding_id is not null
  do update set
    membership_state='active',
    role_keys=excluded.role_keys,
    payload=excluded.payload,
    provenance=excluded.provenance,
    created_by_membership_id=coalesce(
      excluded.created_by_membership_id,
      atlas.organization_purpose_context_memberships.created_by_membership_id
    ),
    updated_at=now()
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','purpose_context_membership_v1',
    'membershipId',v_membership.id,
    'contextId',v_membership.context_id,
    'memberKind',v_membership.member_kind,
    'temporalBindingId',v_membership.temporal_binding_id,
    'membershipState',v_membership.membership_state,
    'roleKeys',to_jsonb(v_membership.role_keys),
    'payload',v_membership.payload
  );
end
$function$;

create or replace function atlas.add_temporal_marker_to_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_temporal_binding_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;

  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.add_temporal_marker_to_purpose_context_service_v1(
    p_organization_id,p_context_id,p_temporal_binding_id,
    p_role_keys,p_payload,p_provenance,v_membership_id
  );
end
$function$;

create or replace function atlas.remove_temporal_marker_from_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_temporal_binding_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_membership atlas.organization_purpose_context_memberships%rowtype;
begin
  update atlas.organization_purpose_context_memberships m
  set membership_state='archived',updated_at=now()
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id
    and m.temporal_binding_id=p_temporal_binding_id
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','remove_purpose_context_membership_v1',
    'removed',v_membership.id is not null,
    'membershipId',v_membership.id,
    'contextId',p_context_id,
    'temporalBindingId',p_temporal_binding_id
  );
end
$function$;

create or replace function atlas.remove_temporal_marker_from_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_temporal_binding_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;

  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.remove_temporal_marker_from_purpose_context_service_v1(
    p_organization_id,p_context_id,p_temporal_binding_id
  );
end
$function$;

create or replace function atlas.purpose_context_detail_service_v1(
  p_organization_id uuid,
  p_context_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_context atlas.organization_purpose_contexts%rowtype;
  v_members jsonb;
begin
  select * into v_context
  from atlas.organization_purpose_contexts c
  where c.id=p_context_id and c.organization_id=p_organization_id;

  if v_context.id is null then
    raise exception 'Purpose context is outside organization or missing.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'membershipId',m.id,
      'memberKind',m.member_kind,
      'membershipState',m.membership_state,
      'roleKeys',to_jsonb(m.role_keys),
      'payload',m.payload,
      'provenance',m.provenance,
      'externalRelationshipId',m.external_relationship_id,
      'occurrenceBindingId',m.occurrence_binding_id,
      'temporalBindingId',m.temporal_binding_id,
      'canonicalEntity',case when m.member_kind='external_relationship' then (
        select jsonb_build_object(
          'entityId',e.id,'entityType',e.entity_type,'name',e.name,
          'websiteUrl',e.website_url,'phone',e.phone,'email',e.email,
          'city',e.city,'state',e.state
        )
        from atlas.external_relationships r
        join atlas.identity_subject_external_identifiers i
          on i.organization_id=r.organization_id
         and i.subject_id=r.subject_id
         and i.provider_key='local_intel'
         and i.identifier_type='entity_id'
         and i.is_current
        join local_intel.entities e on e.id::text=i.identifier_normalized
        where r.id=m.external_relationship_id
          and r.organization_id=m.organization_id
        order by i.priority,i.created_at,i.id
        limit 1
      ) else null end,
      'canonicalOccurrence',case when m.member_kind='occurrence_binding' then (
        select jsonb_build_object(
          'occurrenceId',o.id,'title',o.title,'occurrenceType',o.occurrence_type,
          'startAt',o.start_at,'endAt',o.end_at,'status',o.status,
          'venueName',o.venue_name,'city',o.city,'state',o.state,
          'hostEntityId',o.entity_id,'hostName',e.name
        )
        from atlas.organization_occurrence_bindings b
        join local_intel.occurrences o on o.id=b.occurrence_id
        left join local_intel.entities e on e.id=o.entity_id
        where b.id=m.occurrence_binding_id
          and b.organization_id=m.organization_id
      ) else null end,
      'canonicalTemporalMarker',case when m.member_kind='temporal_binding' then (
        select jsonb_build_object(
          'temporalMarkerId',t.id,
          'stableKey',t.stable_key,
          'title',t.title,
          'markerKind',t.marker_kind,
          'startDate',t.start_date,
          'endDate',t.end_date,
          'jurisdiction',t.jurisdiction,
          'recurrenceRule',t.recurrence_rule,
          'status',t.status,
          'lastVerifiedAt',t.last_verified_at,
          'metadata',t.metadata
        )
        from atlas.organization_temporal_bindings b
        join local_intel.temporal_markers t on t.id=b.temporal_marker_id
        where b.id=m.temporal_binding_id
          and b.organization_id=m.organization_id
      ) else null end
    )
    order by m.created_at,m.id
  ),'[]'::jsonb)
  into v_members
  from atlas.organization_purpose_context_memberships m
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id;

  return jsonb_build_object(
    'contractVersion','purpose_context_detail_v1',
    'context',jsonb_build_object(
      'contextId',v_context.id,
      'organizationId',v_context.organization_id,
      'stableKey',v_context.stable_key,
      'contextKind',v_context.context_kind,
      'title',v_context.title,
      'description',v_context.description,
      'contextState',v_context.context_state,
      'metadata',v_context.metadata
    ),
    'members',v_members
  );
end
$function$;

revoke all on function atlas.bind_canonical_temporal_marker_service_v1(uuid,uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function atlas.bind_canonical_temporal_marker_service_v1(uuid,uuid,jsonb,uuid) to service_role;

revoke all on function atlas.bind_canonical_temporal_marker_self_api_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function atlas.bind_canonical_temporal_marker_self_api_v1(uuid,uuid,jsonb) to authenticated;

revoke all on function atlas.add_temporal_marker_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function atlas.add_temporal_marker_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid) to service_role;

revoke all on function atlas.add_temporal_marker_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb) from public,anon;
grant execute on function atlas.add_temporal_marker_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb) to authenticated;

revoke all on function atlas.remove_temporal_marker_from_purpose_context_service_v1(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.remove_temporal_marker_from_purpose_context_service_v1(uuid,uuid,uuid) to service_role;

revoke all on function atlas.remove_temporal_marker_from_purpose_context_self_api_v1(uuid,uuid,uuid) from public,anon;
grant execute on function atlas.remove_temporal_marker_from_purpose_context_self_api_v1(uuid,uuid,uuid) to authenticated;

-- Initial concrete temporal reality for the Elm calendar.
insert into local_intel.temporal_markers(
  stable_key,title,marker_kind,start_date,end_date,jurisdiction,recurrence_rule,status,metadata
)
values
(
  'us-halloween-2026',
  'Halloween',
  'observance',
  date '2026-10-31',
  date '2026-10-31',
  '{"country":"US"}'::jsonb,
  '{"frequency":"yearly","month":10,"day":31}'::jsonb,
  'active',
  '{"basis":"operator_calendar_spec_2026","dateSemantics":"date_meaning_not_occurrence"}'::jsonb
),
(
  'us-thanksgiving-2026',
  'Thanksgiving',
  'holiday',
  date '2026-11-26',
  date '2026-11-26',
  '{"country":"US"}'::jsonb,
  '{"frequency":"yearly","month":11,"weekday":"thursday","ordinal":4}'::jsonb,
  'active',
  '{"basis":"operator_calendar_spec_2026","dateSemantics":"date_meaning_not_occurrence"}'::jsonb
),
(
  'us-christmas-2026',
  'Christmas',
  'holiday',
  date '2026-12-25',
  date '2026-12-25',
  '{"country":"US"}'::jsonb,
  '{"frequency":"yearly","month":12,"day":25}'::jsonb,
  'active',
  '{"basis":"operator_temporal_model_2026","dateSemantics":"date_meaning_not_occurrence"}'::jsonb
)
on conflict (stable_key) do update
set title=excluded.title,
    marker_kind=excluded.marker_kind,
    start_date=excluded.start_date,
    end_date=excluded.end_date,
    jurisdiction=excluded.jurisdiction,
    recurrence_rule=excluded.recurrence_rule,
    status=excluded.status,
    metadata=local_intel.temporal_markers.metadata || excluded.metadata,
    updated_at=now();

do $$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_context uuid;
  v_marker record;
  v_binding uuid;
begin
  select id into v_context
  from atlas.organization_purpose_contexts
  where organization_id=v_org
    and stable_key='community_calendar'
    and context_state='active';

  if v_context is null then
    raise exception 'Elm community_calendar context is missing.' using errcode='P0002';
  end if;

  for v_marker in
    select *
    from local_intel.temporal_markers
    where stable_key in (
      'us-halloween-2026',
      'us-thanksgiving-2026',
      'us-christmas-2026'
    )
    order by start_date
  loop
    v_binding := (
      atlas.bind_canonical_temporal_marker_service_v1(
        v_org,
        v_marker.id,
        jsonb_build_object(
          'basis','elm_calendar_temporal_marker_v1',
          'calendarContext','community_calendar'
        ),
        null
      )->>'bindingId'
    )::uuid;

    perform atlas.add_temporal_marker_to_purpose_context_service_v1(
      v_org,
      v_context,
      v_binding,
      case
        when v_marker.stable_key='us-halloween-2026'
          then array['calendar_date','observance']
        when v_marker.stable_key='us-thanksgiving-2026'
          then array['calendar_date','holiday','programming_closure']
        else array['calendar_date','holiday']
      end,
      case
        when v_marker.stable_key='us-thanksgiving-2026' then
          jsonb_build_object(
            'display',true,
            'calendarClassification','holiday',
            'programmingClosure',true,
            'calendarNote','No Thursday at Elm'
          )
        when v_marker.stable_key='us-halloween-2026' then
          jsonb_build_object(
            'display',true,
            'calendarClassification','observance'
          )
        else
          jsonb_build_object(
            'display',true,
            'calendarClassification','holiday'
          )
      end,
      jsonb_build_object(
        'basis','temporal_marker_kernel_v1',
        'canonicalTemporalMarkerId',v_marker.id
      ),
      null
    );
  end loop;
end
$$;

comment on column atlas.organization_purpose_context_memberships.temporal_binding_id is
  'Organization-bound canonical temporal marker. Used when a date/date range carries meaning independently of an occurrence.';
