-- Atlas Universal Temporal Adapter Protocol v1
-- Candidate only. No persisted Temporal Field state is created.

create or replace function atlas.organization_context_temporal_overlay_adapter_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_context atlas.organization_purpose_contexts%rowtype;
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_members jsonb := '[]'::jsonb;
  v_supported_returned integer := 0;
  v_supported_total integer := 0;
  v_unsupported_count integer := 0;
begin
  select * into v_context
  from atlas.organization_purpose_contexts c
  where c.id=p_context_id
    and c.organization_id=p_organization_id;

  if v_context.id is null then
    raise exception 'Purpose context is outside Organization or missing.' using errcode='42501';
  end if;

  select count(*)::integer
  into v_supported_total
  from atlas.organization_purpose_context_memberships m
  left join atlas.organization_occurrence_bindings ob
    on m.member_kind='occurrence_binding'
   and ob.id=m.occurrence_binding_id
   and ob.organization_id=m.organization_id
   and ob.binding_state='active'
  left join atlas.organization_temporal_bindings tb
    on m.member_kind='temporal_binding'
   and tb.id=m.temporal_binding_id
   and tb.organization_id=m.organization_id
   and tb.binding_state='active'
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id
    and m.membership_state='active'
    and m.member_kind in ('occurrence_binding','temporal_binding')
    and (
      (m.member_kind='occurrence_binding' and ob.id is not null)
      or
      (m.member_kind='temporal_binding' and tb.id is not null)
    );

  with routed as (
    select
      m.id as membership_id,
      m.member_kind,
      m.role_keys,
      m.payload,
      m.provenance,
      m.created_at,
      case when m.member_kind='occurrence_binding' then ob.id else tb.id end as binding_id,
      case when m.member_kind='occurrence_binding' then 'occurrence' else 'temporal_marker' end as source_kind,
      case when m.member_kind='occurrence_binding' then ob.occurrence_id else tb.temporal_marker_id end as source_id
    from atlas.organization_purpose_context_memberships m
    left join atlas.organization_occurrence_bindings ob
      on m.member_kind='occurrence_binding'
     and ob.id=m.occurrence_binding_id
     and ob.organization_id=m.organization_id
     and ob.binding_state='active'
    left join atlas.organization_temporal_bindings tb
      on m.member_kind='temporal_binding'
     and tb.id=m.temporal_binding_id
     and tb.organization_id=m.organization_id
     and tb.binding_state='active'
    where m.organization_id=p_organization_id
      and m.context_id=p_context_id
      and m.membership_state='active'
      and m.member_kind in ('occurrence_binding','temporal_binding')
      and (
        (m.member_kind='occurrence_binding' and ob.id is not null)
        or
        (m.member_kind='temporal_binding' and tb.id is not null)
      )
    order by m.created_at,m.id
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'membershipId',r.membership_id,
        'memberKind',r.member_kind,
        'bindingId',r.binding_id,
        'sourceRef',jsonb_build_object(
          'authority','local_intel',
          'kind',r.source_kind,
          'id',r.source_id
        ),
        'roleKeys',to_jsonb(r.role_keys),
        'payload',r.payload,
        'provenance',r.provenance
      )
      order by r.created_at,r.membership_id
    ),
    '[]'::jsonb
  ), count(*)::integer
  into v_members,v_supported_returned
  from routed r;

  select count(*)::integer
  into v_unsupported_count
  from atlas.organization_purpose_context_memberships m
  where m.organization_id=p_organization_id
    and m.context_id=p_context_id
    and m.membership_state='active'
    and m.member_kind not in ('occurrence_binding','temporal_binding');

  return jsonb_build_object(
    'contractVersion','organization_context_temporal_overlay_adapter_v1',
    'organizationId',p_organization_id,
    'context',jsonb_build_object(
      'contextId',v_context.id,
      'stableKey',v_context.stable_key,
      'contextKind',v_context.context_kind,
      'title',v_context.title,
      'contextState',v_context.context_state,
      'metadata',v_context.metadata
    ),
    'members',v_members,
    'coverage',jsonb_build_object(
      'returnedSupportedMemberships',v_supported_returned,
      'supportedActiveMembershipsTotal',v_supported_total,
      'unsupportedActiveMemberships',v_unsupported_count,
      'truncated',(v_supported_returned < v_supported_total),
      'supportedMemberKinds',jsonb_build_array('occurrence_binding','temporal_binding')
    )
  );
end
$function$;

create or replace function atlas.canonical_occurrence_temporal_adapter_v1(
  p_occurrence_ids uuid[],
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, local_intel
as $function$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_timezone text := nullif(btrim(p_timezone_name),'');
  v_items jsonb := '[]'::jsonb;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid occurrence adapter date window is required.' using errcode='22023';
  end if;

  if v_timezone is null or not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Valid occurrence adapter timezone is required.' using errcode='22023';
  end if;

  if coalesce(cardinality(p_occurrence_ids),0)=0 then
    return jsonb_build_object(
      'contractVersion','canonical_occurrence_temporal_adapter_v1',
      'contributions','[]'::jsonb
    );
  end if;

  with rows as (
    select
      o.*,
      he.name as host_name,
      he.entity_type as host_entity_type,
      (o.start_at at time zone v_timezone)::date as local_date
    from local_intel.occurrences o
    left join local_intel.entities he on he.id=o.entity_id
    where o.id=any(p_occurrence_ids)
      and (o.start_at at time zone v_timezone)::date <= p_end_date
      and (coalesce(o.end_at,o.start_at) at time zone v_timezone)::date >= p_start_date
    order by o.start_at,o.title,o.id
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'projectionKey','canonical_occurrence:'||r.id::text,
        'sourceRef',jsonb_build_object(
          'authority','local_intel',
          'kind','occurrence',
          'id',r.id
        ),
        'standing','scheduled',
        'coordinate',jsonb_strip_nulls(jsonb_build_object(
          'dateKey',r.local_date,
          'startsAt',r.start_at,
          'endsAt',r.end_at,
          'precision',case when r.end_at is null then 'instant' else 'interval' end,
          'timezoneName',v_timezone
        )),
        'display',jsonb_strip_nulls(jsonb_build_object(
          'title',r.title,
          'secondary',r.venue_name
        )),
        'epistemic',jsonb_strip_nulls(jsonb_build_object(
          'state','established',
          'sourceStatus',r.status,
          'lastVerifiedAt',r.last_verified_at
        )),
        'encounter',jsonb_build_object(
          'kind','canonical_occurrence',
          'id',r.id
        ),
        'sourceSnapshot',jsonb_strip_nulls(jsonb_build_object(
          'occurrenceType',r.occurrence_type,
          'status',r.status,
          'venueName',r.venue_name,
          'address',jsonb_strip_nulls(jsonb_build_object(
            'line1',r.address_line1,
            'city',r.city,
            'state',r.state,
            'postalCode',r.postal_code
          )),
          'price',r.price,
          'audience',r.audience,
          'publicUrl',r.public_url,
          'hostEntity',case when r.entity_id is null then null else jsonb_strip_nulls(jsonb_build_object(
            'entityId',r.entity_id,
            'name',r.host_name,
            'entityType',r.host_entity_type
          )) end
        )),
        'contexts','[]'::jsonb
      )
      order by r.start_at,r.title,r.id
    ),
    '[]'::jsonb
  )
  into v_items
  from rows r;

  return jsonb_build_object(
    'contractVersion','canonical_occurrence_temporal_adapter_v1',
    'contributions',v_items
  );
end
$function$;

create or replace function atlas.canonical_temporal_marker_temporal_adapter_v1(
  p_temporal_marker_ids uuid[],
  p_start_date date,
  p_end_date date,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, local_intel
as $function$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_items jsonb := '[]'::jsonb;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid temporal-marker adapter date window is required.' using errcode='22023';
  end if;

  if coalesce(cardinality(p_temporal_marker_ids),0)=0 then
    return jsonb_build_object(
      'contractVersion','canonical_temporal_marker_temporal_adapter_v1',
      'contributions','[]'::jsonb
    );
  end if;

  with rows as (
    select t.*
    from local_intel.temporal_markers t
    where t.id=any(p_temporal_marker_ids)
      and t.status='active'
      and t.start_date <= p_end_date
      and coalesce(t.end_date,t.start_date) >= p_start_date
    order by t.start_date,t.title,t.id
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'projectionKey','canonical_temporal_marker:'||r.id::text,
        'sourceRef',jsonb_build_object(
          'authority','local_intel',
          'kind','temporal_marker',
          'id',r.id
        ),
        'standing','meaning_bearing',
        'coordinate',jsonb_strip_nulls(jsonb_build_object(
          'dateKey',r.start_date,
          'startDate',r.start_date,
          'endDate',r.end_date,
          'precision',case when r.end_date is null or r.end_date=r.start_date then 'civil_date' else 'civil_date_range' end
        )),
        'display',jsonb_build_object('title',r.title),
        'epistemic',jsonb_strip_nulls(jsonb_build_object(
          'state','established',
          'sourceStatus',r.status,
          'lastVerifiedAt',r.last_verified_at
        )),
        'encounter',jsonb_build_object(
          'kind','temporal_marker',
          'id',r.id
        ),
        'sourceSnapshot',jsonb_build_object(
          'stableKey',r.stable_key,
          'markerKind',r.marker_kind,
          'jurisdiction',r.jurisdiction,
          'recurrenceRule',r.recurrence_rule,
          'metadata',r.metadata
        ),
        'contexts','[]'::jsonb
      )
      order by r.start_date,r.title,r.id
    ),
    '[]'::jsonb
  )
  into v_items
  from rows r;

  return jsonb_build_object(
    'contractVersion','canonical_temporal_marker_temporal_adapter_v1',
    'contributions',v_items
  );
end
$function$;

create or replace function atlas.organization_context_temporal_composer_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text default null,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_timezone text := nullif(btrim(p_timezone_name),'');
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_overlay jsonb;
  v_occurrence_ids uuid[] := '{}';
  v_marker_ids uuid[] := '{}';
  v_occurrences jsonb;
  v_markers jsonb;
  v_contributions jsonb := '[]'::jsonb;
  v_context jsonb;
  v_partial boolean;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid temporal composer date window is required.' using errcode='22023';
  end if;

  if p_end_date-p_start_date > 3660 then
    raise exception 'Temporal composer window may not exceed 3660 days.' using errcode='22023';
  end if;

  if v_timezone is null then
    select c.timezone_name
    into v_timezone
    from atlas.organization_membership_calendar_context_current_v1(p_organization_id) c
    limit 1;
  end if;

  if v_timezone is null or not exists(select 1 from pg_timezone_names z where z.name=v_timezone) then
    raise exception 'Temporal composer requires a valid timezone.' using errcode='22023';
  end if;

  v_overlay:=atlas.organization_context_temporal_overlay_adapter_v1(
    p_organization_id,p_context_id,v_limit
  );
  v_context:=v_overlay->'context';

  select coalesce(array_agg(distinct nullif(member#>>'{sourceRef,id}','')::uuid),'{}'::uuid[])
  into v_occurrence_ids
  from jsonb_array_elements(v_overlay->'members') as x(member)
  where member#>>'{sourceRef,kind}'='occurrence';

  select coalesce(array_agg(distinct nullif(member#>>'{sourceRef,id}','')::uuid),'{}'::uuid[])
  into v_marker_ids
  from jsonb_array_elements(v_overlay->'members') as x(member)
  where member#>>'{sourceRef,kind}'='temporal_marker';

  v_occurrences:=atlas.canonical_occurrence_temporal_adapter_v1(
    v_occurrence_ids,p_start_date,p_end_date,v_timezone,v_limit
  );

  v_markers:=atlas.canonical_temporal_marker_temporal_adapter_v1(
    v_marker_ids,p_start_date,p_end_date,v_limit
  );

  with source_contributions as (
    select value as contribution
    from jsonb_array_elements(v_markers->'contributions')
    union all
    select value as contribution
    from jsonb_array_elements(v_occurrences->'contributions')
  ), enriched as (
    select
      s.contribution || jsonb_build_object(
        'contexts',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'organizationId',p_organization_id,
              'contextId',v_context->>'contextId',
              'stableKey',v_context->>'stableKey',
              'contextKind',v_context->>'contextKind',
              'title',v_context->>'title',
              'membershipId',member->>'membershipId',
              'memberKind',member->>'memberKind',
              'bindingId',member->>'bindingId',
              'roleKeys',member->'roleKeys',
              'payload',member->'payload',
              'provenance',member->'provenance'
            )
            order by member->>'membershipId'
          )
          from jsonb_array_elements(v_overlay->'members') as x(member)
          where member#>>'{sourceRef,kind}'=s.contribution#>>'{sourceRef,kind}'
            and member#>>'{sourceRef,id}'=s.contribution#>>'{sourceRef,id}'
        ),'[]'::jsonb)
      ) as contribution
    from source_contributions s
  ), ordered as (
    select
      contribution,
      nullif(contribution#>>'{coordinate,dateKey}','')::date as sort_date,
      case contribution->>'standing'
        when 'meaning_bearing' then 0
        when 'scheduled' then 2
        else 5
      end as sort_priority,
      nullif(contribution#>>'{coordinate,startsAt}','')::timestamptz as sort_at,
      contribution#>>'{display,title}' as sort_title,
      contribution->>'projectionKey' as sort_key
    from enriched
    order by
      nullif(contribution#>>'{coordinate,dateKey}','')::date,
      case contribution->>'standing'
        when 'meaning_bearing' then 0
        when 'scheduled' then 2
        else 5
      end,
      nullif(contribution#>>'{coordinate,startsAt}','')::timestamptz nulls first,
      contribution#>>'{display,title}',
      contribution->>'projectionKey'
    limit v_limit
  )
  select coalesce(
    jsonb_agg(contribution order by sort_date,sort_priority,sort_at nulls first,sort_title,sort_key),
    '[]'::jsonb
  )
  into v_contributions
  from ordered;

  v_partial:=
    coalesce((v_overlay#>>'{coverage,unsupportedActiveMemberships}')::integer,0)>0
    or coalesce((v_overlay#>>'{coverage,truncated}')::boolean,false);

  return jsonb_build_object(
    'contractVersion','organization_context_temporal_composer_v1',
    'organizationId',p_organization_id,
    'context',v_context,
    'timezoneName',v_timezone,
    'window',jsonb_build_object(
      'startDate',p_start_date,
      'endDate',p_end_date
    ),
    'coverage',jsonb_build_object(
      'partial',v_partial,
      'returnedSupportedMemberships',coalesce((v_overlay#>>'{coverage,returnedSupportedMemberships}')::integer,0),
      'supportedActiveMembershipsTotal',coalesce((v_overlay#>>'{coverage,supportedActiveMembershipsTotal}')::integer,0),
      'unsupportedActiveMemberships',coalesce((v_overlay#>>'{coverage,unsupportedActiveMemberships}')::integer,0),
      'truncated',coalesce((v_overlay#>>'{coverage,truncated}')::boolean,false),
      'adapters',jsonb_build_array(
        'organization_context_temporal_overlay_adapter_v1',
        'canonical_occurrence_temporal_adapter_v1',
        'canonical_temporal_marker_temporal_adapter_v1'
      ),
      'unsupportedMemberKinds',coalesce((
        select jsonb_agg(jsonb_build_object('memberKind',x.member_kind,'count',x.member_count) order by x.member_kind)
        from (
          select m.member_kind,count(*)::integer as member_count
          from atlas.organization_purpose_context_memberships m
          where m.organization_id=p_organization_id
            and m.context_id=p_context_id
            and m.membership_state='active'
            and m.member_kind not in ('occurrence_binding','temporal_binding')
          group by m.member_kind
        ) x
      ),'[]'::jsonb)
    ),
    'contributions',v_contributions
  );
end
$function$;

create or replace function atlas.organization_context_temporal_composer_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text default null,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas, auth
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;

  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.organization_context_temporal_composer_service_v1(
    p_organization_id,
    p_context_id,
    p_start_date,
    p_end_date,
    p_timezone_name,
    p_limit
  );
end
$function$;

revoke all on function atlas.organization_context_temporal_overlay_adapter_v1(uuid,uuid,integer) from public,anon,authenticated;
revoke all on function atlas.canonical_occurrence_temporal_adapter_v1(uuid[],date,date,text,integer) from public,anon,authenticated;
revoke all on function atlas.canonical_temporal_marker_temporal_adapter_v1(uuid[],date,date,integer) from public,anon,authenticated;
revoke all on function atlas.organization_context_temporal_composer_service_v1(uuid,uuid,date,date,text,integer) from public,anon,authenticated;
revoke all on function atlas.organization_context_temporal_composer_self_api_v1(uuid,uuid,date,date,text,integer) from public,anon;

grant execute on function atlas.organization_context_temporal_overlay_adapter_v1(uuid,uuid,integer) to service_role;
grant execute on function atlas.canonical_occurrence_temporal_adapter_v1(uuid[],date,date,text,integer) to service_role;
grant execute on function atlas.canonical_temporal_marker_temporal_adapter_v1(uuid[],date,date,integer) to service_role;
grant execute on function atlas.organization_context_temporal_composer_service_v1(uuid,uuid,date,date,text,integer) to service_role;
grant execute on function atlas.organization_context_temporal_composer_self_api_v1(uuid,uuid,date,date,text,integer) to authenticated;

comment on function atlas.organization_context_temporal_overlay_adapter_v1(uuid,uuid,integer)
is 'Internal adapter: Organization-private purpose-context memberships -> canonical temporal source refs + private overlays. Creates no temporal identity.';

comment on function atlas.canonical_occurrence_temporal_adapter_v1(uuid[],date,date,text,integer)
is 'Internal adapter: canonical local_intel occurrences -> source-preserving Temporal Contributions. Context-free; callable only behind governed composition.';

comment on function atlas.canonical_temporal_marker_temporal_adapter_v1(uuid[],date,date,integer)
is 'Internal adapter: canonical local_intel temporal markers -> source-preserving Temporal Contributions. Does not invent occurrences.';

comment on function atlas.organization_context_temporal_composer_service_v1(uuid,uuid,date,date,text,integer)
is 'Internal tiny composer: combines context-admitted canonical occurrence + temporal-marker contributions and attaches Organization-private overlays. Reports partial coverage.';

comment on function atlas.organization_context_temporal_composer_self_api_v1(uuid,uuid,date,date,text,integer)
is 'Authenticated read membrane for adapter-first Temporal Contributions within one authorized Organization purpose context.';
