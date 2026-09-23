-- Atlas combined temporal projection v1
-- Route recurrence rules through purpose contexts and compose occurrences,
-- temporal markers, and recurrence expectations into one typed read stream.

alter table atlas.organization_purpose_context_memberships
  add column if not exists recurrence_rule_id uuid;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='atlas.organization_purpose_context_memberships'::regclass
      and conname='organization_purpose_context_memberships_recurrence_rule_org_fk'
  ) then
    alter table atlas.organization_purpose_context_memberships
      add constraint organization_purpose_context_memberships_recurrence_rule_org_fk
      foreign key (organization_id,recurrence_rule_id)
      references atlas.organization_recurrence_rules(organization_id,id)
      on delete restrict;
  end if;
end
$$;

alter table atlas.organization_purpose_context_memberships
  drop constraint if exists organization_purpose_context_memberships_member_kind_check;

alter table atlas.organization_purpose_context_memberships
  add constraint organization_purpose_context_memberships_member_kind_check
  check (member_kind in (
    'external_relationship',
    'occurrence_binding',
    'temporal_binding',
    'recurrence_rule'
  ));

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
      and recurrence_rule_id is null
    )
    or
    (
      member_kind='occurrence_binding'
      and occurrence_binding_id is not null
      and external_relationship_id is null
      and temporal_binding_id is null
      and recurrence_rule_id is null
    )
    or
    (
      member_kind='temporal_binding'
      and temporal_binding_id is not null
      and external_relationship_id is null
      and occurrence_binding_id is null
      and recurrence_rule_id is null
    )
    or
    (
      member_kind='recurrence_rule'
      and recurrence_rule_id is not null
      and external_relationship_id is null
      and occurrence_binding_id is null
      and temporal_binding_id is null
    )
  );

create unique index if not exists organization_purpose_context_memberships_recurrence_rule_uq
  on atlas.organization_purpose_context_memberships(context_id,recurrence_rule_id)
  where recurrence_rule_id is not null;

create or replace function atlas.add_recurrence_rule_to_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_recurrence_rule_id uuid,
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
    select 1
    from atlas.organization_purpose_contexts c
    where c.id=p_context_id
      and c.organization_id=p_organization_id
      and c.context_state='active'
  ) then
    raise exception 'Active purpose context is outside organization or missing.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.organization_recurrence_rules r
    where r.id=p_recurrence_rule_id
      and r.organization_id=p_organization_id
      and r.rule_state='active'
  ) then
    raise exception 'Active recurrence rule is outside organization or missing.'
      using errcode='42501';
  end if;

  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object' then
    raise exception 'Membership payload and provenance must be JSON objects.'
      using errcode='22023';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1
    from atlas.organization_memberships om
    where om.id=p_created_by_membership_id
      and om.organization_id=p_organization_id
  ) then
    raise exception 'Creator membership is outside organization.'
      using errcode='42501';
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
    organization_id,
    context_id,
    member_kind,
    recurrence_rule_id,
    membership_state,
    role_keys,
    payload,
    provenance,
    created_by_membership_id
  )
  values(
    p_organization_id,
    p_context_id,
    'recurrence_rule',
    p_recurrence_rule_id,
    'active',
    v_roles,
    coalesce(p_payload,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb),
    p_created_by_membership_id
  )
  on conflict (context_id,recurrence_rule_id)
    where recurrence_rule_id is not null
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
    'recurrenceRuleId',v_membership.recurrence_rule_id,
    'membershipState',v_membership.membership_state,
    'roleKeys',to_jsonb(v_membership.role_keys),
    'payload',v_membership.payload
  );
end
$function$;

create or replace function atlas.add_recurrence_rule_to_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_recurrence_rule_id uuid,
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

  return atlas.add_recurrence_rule_to_purpose_context_service_v1(
    p_organization_id,
    p_context_id,
    p_recurrence_rule_id,
    p_role_keys,
    p_payload,
    p_provenance,
    v_membership_id
  );
end
$function$;

create or replace function atlas.remove_recurrence_rule_from_purpose_context_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_recurrence_rule_id uuid
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
  set membership_state='archived',
      updated_at=now()
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id
    and m.recurrence_rule_id=p_recurrence_rule_id
  returning * into v_membership;

  return jsonb_build_object(
    'contractVersion','remove_purpose_context_membership_v1',
    'removed',v_membership.id is not null,
    'membershipId',v_membership.id,
    'contextId',p_context_id,
    'recurrenceRuleId',p_recurrence_rule_id
  );
end
$function$;

create or replace function atlas.remove_recurrence_rule_from_purpose_context_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_recurrence_rule_id uuid
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

  return atlas.remove_recurrence_rule_from_purpose_context_service_v1(
    p_organization_id,p_context_id,p_recurrence_rule_id
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
  where c.id=p_context_id
    and c.organization_id=p_organization_id;

  if v_context.id is null then
    raise exception 'Purpose context is outside organization or missing.'
      using errcode='42501';
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
      'recurrenceRuleId',m.recurrence_rule_id,
      'canonicalEntity',case when m.member_kind='external_relationship' then (
        select jsonb_build_object(
          'entityId',e.id,
          'entityType',e.entity_type,
          'name',e.name,
          'websiteUrl',e.website_url,
          'phone',e.phone,
          'email',e.email,
          'city',e.city,
          'state',e.state
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
          'occurrenceId',o.id,
          'title',o.title,
          'occurrenceType',o.occurrence_type,
          'startAt',o.start_at,
          'endAt',o.end_at,
          'status',o.status,
          'venueName',o.venue_name,
          'city',o.city,
          'state',o.state,
          'hostEntityId',o.entity_id,
          'hostName',e.name
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
      ) else null end,
      'organizationRecurrenceRule',case when m.member_kind='recurrence_rule' then (
        select jsonb_build_object(
          'recurrenceRuleId',r.id,
          'stableKey',r.stable_key,
          'title',r.title,
          'frequency',r.frequency,
          'intervalCount',r.interval_count,
          'timezoneName',r.timezone_name,
          'effectiveStartDate',r.effective_start_date,
          'effectiveEndDate',r.effective_end_date,
          'weekdays',to_jsonb(r.weekdays),
          'monthOrdinals',to_jsonb(r.month_ordinals),
          'localStartTime',r.local_start_time,
          'localEndTime',r.local_end_time,
          'ruleState',r.rule_state,
          'payload',r.payload,
          'metadata',r.metadata
        )
        from atlas.organization_recurrence_rules r
        where r.id=m.recurrence_rule_id
          and r.organization_id=m.organization_id
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

create or replace function atlas.organization_context_temporal_projection_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text default null,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_context atlas.organization_purpose_contexts%rowtype;
  v_timezone text;
  v_limit integer:=greatest(1,least(coalesce(p_limit,1000),5000));
  v_items jsonb;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid temporal projection date window is required.'
      using errcode='22023';
  end if;

  if p_end_date-p_start_date > 3660 then
    raise exception 'Temporal projection window may not exceed 3660 days.'
      using errcode='22023';
  end if;

  select * into v_context
  from atlas.organization_purpose_contexts c
  where c.id=p_context_id
    and c.organization_id=p_organization_id;

  if v_context.id is null then
    raise exception 'Purpose context is outside Organization or missing.'
      using errcode='42501';
  end if;

  v_timezone:=nullif(btrim(p_timezone_name),'');

  if v_timezone is null then
    select c.timezone_name
    into v_timezone
    from atlas.organization_membership_calendar_context_current_v1(p_organization_id) c
    limit 1;
  end if;

  if v_timezone is null then
    raise exception 'Temporal projection requires a timezone or Organization calendar timezone.'
      using errcode='22023';
  end if;

  if not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Unknown temporal projection timezone: %',v_timezone
      using errcode='22023';
  end if;

  with routed_rules as (
    select
      m.id as membership_id,
      m.role_keys,
      m.payload as context_payload,
      m.provenance,
      r.*
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_recurrence_rules r
      on r.id=m.recurrence_rule_id
     and r.organization_id=m.organization_id
    where m.organization_id=p_organization_id
      and m.context_id=p_context_id
      and m.member_kind='recurrence_rule'
      and m.membership_state='active'
      and r.rule_state='active'
  ),
  recurrence_rows as (
    select
      'recurrence_instance'::text as item_type,
      i.local_date as sort_date,
      i.expected_start_at as sort_at,
      1::integer as sort_priority,
      rr.title as sort_title,
      i.id as sort_id,
      jsonb_build_object(
        'itemType','recurrence_instance',
        'sortDate',i.local_date,
        'membershipId',rr.membership_id,
        'roleKeys',to_jsonb(rr.role_keys),
        'contextPayload',rr.context_payload,
        'provenance',rr.provenance,
        'recurrenceRule',jsonb_build_object(
          'recurrenceRuleId',rr.id,
          'stableKey',rr.stable_key,
          'title',rr.title,
          'frequency',rr.frequency,
          'intervalCount',rr.interval_count,
          'timezoneName',rr.timezone_name,
          'weekdays',to_jsonb(rr.weekdays),
          'monthOrdinals',to_jsonb(rr.month_ordinals),
          'localStartTime',rr.local_start_time,
          'localEndTime',rr.local_end_time
        ),
        'recurrenceInstance',jsonb_build_object(
          'recurrenceInstanceId',i.id,
          'sourceLocalDate',i.source_local_date,
          'localDate',i.local_date,
          'expectedStartAt',i.expected_start_at,
          'expectedEndAt',i.expected_end_at,
          'scheduleState',i.schedule_state,
          'realizationState',i.realization_state
        ),
        'exception',case when e.id is null then null else jsonb_build_object(
          'exceptionId',e.id,
          'action',e.exception_action,
          'reason',e.reason,
          'replacementDate',e.replacement_date,
          'overrideStartTime',e.override_start_time,
          'overrideEndTime',e.override_end_time,
          'temporalBindingId',e.temporal_binding_id,
          'temporalMarker',case when t.id is null then null else jsonb_build_object(
            'temporalMarkerId',t.id,
            'stableKey',t.stable_key,
            'title',t.title,
            'markerKind',t.marker_kind,
            'startDate',t.start_date,
            'endDate',t.end_date
          ) end
        ) end,
        'canonicalOccurrence',case when o.id is null then null else
          jsonb_strip_nulls(jsonb_build_object(
            'occurrenceBindingId',ob.id,
            'occurrenceId',o.id,
            'title',o.title,
            'occurrenceType',o.occurrence_type,
            'startAt',o.start_at,
            'endAt',o.end_at,
            'status',o.status,
            'venueName',o.venue_name,
            'city',o.city,
            'state',o.state,
            'hostEntityId',o.entity_id,
            'hostName',he.name
          ))
        end
      ) as item
    from routed_rules rr
    join atlas.organization_recurrence_instances i
      on i.organization_id=rr.organization_id
     and i.recurrence_rule_id=rr.id
     and i.schedule_state<>'retired'
    left join atlas.organization_recurrence_exceptions e
      on e.id=i.exception_id
    left join atlas.organization_temporal_bindings tb
      on tb.id=e.temporal_binding_id
     and tb.organization_id=e.organization_id
    left join local_intel.temporal_markers t
      on t.id=tb.temporal_marker_id
    left join atlas.organization_occurrence_bindings ob
      on ob.id=i.occurrence_binding_id
     and ob.organization_id=i.organization_id
    left join local_intel.occurrences o
      on o.id=ob.occurrence_id
    left join local_intel.entities he
      on he.id=o.entity_id
    where i.local_date between p_start_date and p_end_date
  ),
  temporal_rows as (
    select
      'temporal_marker'::text as item_type,
      t.start_date as sort_date,
      null::timestamptz as sort_at,
      0::integer as sort_priority,
      t.title as sort_title,
      t.id as sort_id,
      jsonb_build_object(
        'itemType','temporal_marker',
        'sortDate',t.start_date,
        'membershipId',m.id,
        'temporalBindingId',b.id,
        'roleKeys',to_jsonb(m.role_keys),
        'contextPayload',m.payload,
        'provenance',m.provenance,
        'canonicalTemporalMarker',jsonb_build_object(
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
      ) as item
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_temporal_bindings b
      on b.id=m.temporal_binding_id
     and b.organization_id=m.organization_id
     and b.binding_state='active'
    join local_intel.temporal_markers t
      on t.id=b.temporal_marker_id
     and t.status='active'
    where m.organization_id=p_organization_id
      and m.context_id=p_context_id
      and m.member_kind='temporal_binding'
      and m.membership_state='active'
      and t.start_date <= p_end_date
      and coalesce(t.end_date,t.start_date) >= p_start_date
  ),
  occurrence_rows as (
    select
      'occurrence'::text as item_type,
      (o.start_at at time zone v_timezone)::date as sort_date,
      o.start_at as sort_at,
      2::integer as sort_priority,
      o.title as sort_title,
      o.id as sort_id,
      jsonb_build_object(
        'itemType','occurrence',
        'sortDate',(o.start_at at time zone v_timezone)::date,
        'membershipId',m.id,
        'occurrenceBindingId',b.id,
        'roleKeys',to_jsonb(m.role_keys),
        'contextPayload',m.payload,
        'provenance',m.provenance,
        'canonicalOccurrence',jsonb_strip_nulls(jsonb_build_object(
          'occurrenceId',o.id,
          'title',o.title,
          'occurrenceType',o.occurrence_type,
          'startAt',o.start_at,
          'endAt',o.end_at,
          'status',o.status,
          'venueName',o.venue_name,
          'address',jsonb_strip_nulls(jsonb_build_object(
            'line1',o.address_line1,
            'city',o.city,
            'state',o.state,
            'postalCode',o.postal_code
          )),
          'price',o.price,
          'audience',o.audience,
          'publicUrl',o.public_url,
          'lastVerifiedAt',o.last_verified_at
        )),
        'hostEntity',case when o.entity_id is null then null else
          jsonb_strip_nulls(jsonb_build_object(
            'entityId',o.entity_id,
            'name',he.name,
            'entityType',he.entity_type,
            'websiteUrl',he.website_url,
            'phone',he.phone,
            'email',he.email
          ))
        end,
        'operationalOverlays',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'communityEventId',ce.id,
              'programId',ce.program_id,
              'eventKind',ce.event_kind,
              'status',ce.status,
              'visibilityScope',ce.visibility_scope,
              'capacity',ce.capacity,
              'metadata',ce.metadata
            )
            order by ce.created_at,ce.id
          )
          from atlas.community_events ce
          join atlas.farms f on f.id=ce.farm_id
          where ce.occurrence_binding_id=b.id
            and f.organization_id=p_organization_id
        ),'[]'::jsonb)
      ) as item
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_occurrence_bindings b
      on b.id=m.occurrence_binding_id
     and b.organization_id=m.organization_id
     and b.binding_state='active'
    join local_intel.occurrences o
      on o.id=b.occurrence_id
    left join local_intel.entities he
      on he.id=o.entity_id
    where m.organization_id=p_organization_id
      and m.context_id=p_context_id
      and m.member_kind='occurrence_binding'
      and m.membership_state='active'
      and (o.start_at at time zone v_timezone)::date <= p_end_date
      and (coalesce(o.end_at,o.start_at) at time zone v_timezone)::date >= p_start_date
      and not exists(
        select 1
        from atlas.organization_recurrence_instances ri
        join atlas.organization_purpose_context_memberships rm
          on rm.organization_id=ri.organization_id
         and rm.context_id=p_context_id
         and rm.member_kind='recurrence_rule'
         and rm.recurrence_rule_id=ri.recurrence_rule_id
         and rm.membership_state='active'
        where ri.organization_id=p_organization_id
          and ri.occurrence_binding_id=b.id
          and ri.local_date between p_start_date and p_end_date
          and ri.schedule_state<>'retired'
          and ri.realization_state in ('materialized','cancelled')
      )
  ),
  combined as (
    select * from temporal_rows
    union all
    select * from recurrence_rows
    union all
    select * from occurrence_rows
  ),
  limited as (
    select *
    from combined
    order by sort_date,sort_priority,sort_at nulls first,sort_title,sort_id
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      item
      order by sort_date,sort_priority,sort_at nulls first,sort_title,sort_id
    ),
    '[]'::jsonb
  )
  into v_items
  from limited;

  return jsonb_build_object(
    'contractVersion','organization_context_temporal_projection_v1',
    'organizationId',p_organization_id,
    'context',jsonb_build_object(
      'contextId',v_context.id,
      'stableKey',v_context.stable_key,
      'contextKind',v_context.context_kind,
      'title',v_context.title,
      'contextState',v_context.context_state,
      'metadata',v_context.metadata
    ),
    'timezoneName',v_timezone,
    'window',jsonb_build_object(
      'startDate',p_start_date,
      'endDate',p_end_date
    ),
    'items',v_items
  );
end
$function$;

create or replace function atlas.organization_context_temporal_projection_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text default null,
  p_limit integer default 1000
)
returns jsonb
language plpgsql
stable
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

  return atlas.organization_context_temporal_projection_service_v1(
    p_organization_id,
    p_context_id,
    p_start_date,
    p_end_date,
    p_timezone_name,
    p_limit
  );
end
$function$;

revoke all on function atlas.add_recurrence_rule_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid)
  from public,anon,authenticated;
grant execute on function atlas.add_recurrence_rule_to_purpose_context_service_v1(uuid,uuid,uuid,text[],jsonb,jsonb,uuid)
  to service_role;

revoke all on function atlas.add_recurrence_rule_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb)
  from public,anon;
grant execute on function atlas.add_recurrence_rule_to_purpose_context_self_api_v1(uuid,uuid,uuid,text[],jsonb,jsonb)
  to authenticated;

revoke all on function atlas.remove_recurrence_rule_from_purpose_context_service_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.remove_recurrence_rule_from_purpose_context_service_v1(uuid,uuid,uuid)
  to service_role;

revoke all on function atlas.remove_recurrence_rule_from_purpose_context_self_api_v1(uuid,uuid,uuid)
  from public,anon;
grant execute on function atlas.remove_recurrence_rule_from_purpose_context_self_api_v1(uuid,uuid,uuid)
  to authenticated;

revoke all on function atlas.organization_context_temporal_projection_service_v1(uuid,uuid,date,date,text,integer)
  from public,anon,authenticated;
grant execute on function atlas.organization_context_temporal_projection_service_v1(uuid,uuid,date,date,text,integer)
  to service_role;

revoke all on function atlas.organization_context_temporal_projection_self_api_v1(uuid,uuid,date,date,text,integer)
  from public,anon;
grant execute on function atlas.organization_context_temporal_projection_self_api_v1(uuid,uuid,date,date,text,integer)
  to authenticated;

-- Route Elm's two recurrence laws into the community calendar context.
do $$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_context uuid;
  v_rule record;
begin
  select id into v_context
  from atlas.organization_purpose_contexts
  where organization_id=v_org
    and stable_key='community_calendar'
    and context_state='active';

  if v_context is null then
    raise exception 'Elm community_calendar context is missing.' using errcode='P0002';
  end if;

  for v_rule in
    select id,stable_key
    from atlas.organization_recurrence_rules
    where organization_id=v_org
      and stable_key in (
        'thursdays_community_mornings',
        'thursdays_seasonal_evenings'
      )
      and rule_state='active'
  loop
    perform atlas.add_recurrence_rule_to_purpose_context_service_v1(
      v_org,
      v_context,
      v_rule.id,
      array['calendar_schedule'],
      jsonb_build_object(
        'display',true,
        'routingSource','elm_recurrence_authority_v1'
      ),
      jsonb_build_object(
        'basis','combined_temporal_projection_v1',
        'recurrenceRuleKey',v_rule.stable_key
      ),
      null
    );
  end loop;
end
$$;

comment on column atlas.organization_purpose_context_memberships.recurrence_rule_id is
  'Organization recurrence law routed into a purpose context. Recurrence rule membership does not create canonical event identity.';

comment on function atlas.organization_context_temporal_projection_service_v1(uuid,uuid,date,date,text,integer) is
  'Typed chronological read projection across context-routed canonical occurrences, temporal markers, and Organization recurrence instances. Cleanly realized recurrence occurrences are nested under recurrence items to avoid duplicate calendar cards; conflicts remain separately visible.';
