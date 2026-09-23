-- Atlas organization context-driven occurrence projection v1
-- Private governed read: canonical occurrence truth + one Organization's
-- purpose membership + optional Atlas operational overlays.

create or replace function atlas.organization_context_occurrence_projection_service_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_window_start timestamptz default null,
  p_window_end timestamptz default null,
  p_limit integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_context atlas.organization_purpose_contexts%rowtype;
  v_limit integer:=greatest(1,least(coalesce(p_limit,500),1000));
  v_items jsonb;
begin
  if p_window_start is not null
     and p_window_end is not null
     and p_window_end <= p_window_start then
    raise exception 'Projection window end must be after window start.'
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

  with members as (
    select
      m.id as membership_id,
      m.role_keys,
      m.payload,
      m.provenance,
      m.created_at as membership_created_at,
      b.id as occurrence_binding_id,
      b.binding_state,
      b.metadata as binding_metadata,
      o.id as occurrence_id,
      o.entity_id,
      o.title,
      o.occurrence_type,
      o.start_at,
      o.end_at,
      o.venue_name,
      o.address_line1,
      o.city,
      o.state,
      o.postal_code,
      o.price,
      o.audience,
      o.status,
      o.public_url,
      o.last_verified_at,
      e.name as host_name,
      e.entity_type as host_entity_type,
      e.website_url as host_website_url,
      e.phone as host_phone,
      e.email as host_email
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_occurrence_bindings b
      on b.id=m.occurrence_binding_id
     and b.organization_id=m.organization_id
     and b.binding_state='active'
    join local_intel.occurrences o
      on o.id=b.occurrence_id
    left join local_intel.entities e
      on e.id=o.entity_id
    where m.organization_id=p_organization_id
      and m.context_id=p_context_id
      and m.member_kind='occurrence_binding'
      and m.membership_state='active'
      and (p_window_start is null or coalesce(o.end_at,o.start_at) >= p_window_start)
      and (p_window_end is null or o.start_at < p_window_end)
    order by o.start_at,o.title,o.id,m.id
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'membershipId',x.membership_id,
        'occurrenceBindingId',x.occurrence_binding_id,
        'roleKeys',to_jsonb(x.role_keys),
        'contextPayload',x.payload,
        'provenance',x.provenance,
        'canonicalOccurrence',jsonb_strip_nulls(jsonb_build_object(
          'occurrenceId',x.occurrence_id,
          'title',x.title,
          'occurrenceType',x.occurrence_type,
          'startAt',x.start_at,
          'endAt',x.end_at,
          'status',x.status,
          'venueName',x.venue_name,
          'address',jsonb_strip_nulls(jsonb_build_object(
            'line1',x.address_line1,
            'city',x.city,
            'state',x.state,
            'postalCode',x.postal_code
          )),
          'price',x.price,
          'audience',x.audience,
          'publicUrl',x.public_url,
          'lastVerifiedAt',x.last_verified_at
        )),
        'hostEntity',case when x.entity_id is null then null else
          jsonb_strip_nulls(jsonb_build_object(
            'entityId',x.entity_id,
            'name',x.host_name,
            'entityType',x.host_entity_type,
            'websiteUrl',x.host_website_url,
            'phone',x.host_phone,
            'email',x.host_email
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
          where ce.occurrence_binding_id=x.occurrence_binding_id
            and f.organization_id=p_organization_id
        ),'[]'::jsonb)
      )
      order by x.start_at,x.title,x.occurrence_id,x.membership_id
    ),
    '[]'::jsonb
  )
  into v_items
  from members x;

  return jsonb_build_object(
    'contractVersion','organization_context_occurrence_projection_v1',
    'organizationId',p_organization_id,
    'context',jsonb_build_object(
      'contextId',v_context.id,
      'stableKey',v_context.stable_key,
      'contextKind',v_context.context_kind,
      'title',v_context.title,
      'contextState',v_context.context_state,
      'metadata',v_context.metadata
    ),
    'window',jsonb_strip_nulls(jsonb_build_object(
      'startAt',p_window_start,
      'endAt',p_window_end
    )),
    'items',v_items
  );
end
$function$;

revoke all on function atlas.organization_context_occurrence_projection_service_v1(
  uuid,uuid,timestamptz,timestamptz,integer
) from public,anon,authenticated;

grant execute on function atlas.organization_context_occurrence_projection_service_v1(
  uuid,uuid,timestamptz,timestamptz,integer
) to service_role;

create or replace function atlas.organization_context_occurrence_projection_self_api_v1(
  p_organization_id uuid,
  p_context_id uuid,
  p_window_start timestamptz default null,
  p_window_end timestamptz default null,
  p_limit integer default 500
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

  return atlas.organization_context_occurrence_projection_service_v1(
    p_organization_id,
    p_context_id,
    p_window_start,
    p_window_end,
    p_limit
  );
end
$function$;

revoke all on function atlas.organization_context_occurrence_projection_self_api_v1(
  uuid,uuid,timestamptz,timestamptz,integer
) from public,anon;

grant execute on function atlas.organization_context_occurrence_projection_self_api_v1(
  uuid,uuid,timestamptz,timestamptz,integer
) to authenticated;

comment on function atlas.organization_context_occurrence_projection_service_v1(
  uuid,uuid,timestamptz,timestamptz,integer
) is
  'Private Organization-scoped calendar/read projection: active purpose-context occurrence memberships composed with canonical Shared Intelligence occurrence/host truth and optional Atlas community-event operational overlays. A context selects use; it does not own event identity.';

comment on function atlas.organization_context_occurrence_projection_self_api_v1(
  uuid,uuid,timestamptz,timestamptz,integer
) is
  'Authenticated Organization-scoped wrapper for the context-driven occurrence projection service.';
