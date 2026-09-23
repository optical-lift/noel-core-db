-- Allow pre-contact/prospective Organization relationships to participate in
-- occurrence-specific planning. Event outreach candidates must not be forced
-- into generic relationship_state='active' before they can be invited.

create or replace function atlas.upsert_occurrence_relationship_link_service_v1(
  p_organization_id uuid,
  p_occurrence_binding_id uuid,
  p_external_relationship_id uuid,
  p_role_keys text[],
  p_engagement_state text default 'candidate',
  p_calendar_display_state text default 'hidden',
  p_public_label text default null,
  p_public_note text default null,
  p_display_order integer default 0,
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
  v_link atlas.organization_occurrence_relationship_links%rowtype;
begin
  if not exists(
    select 1
    from atlas.organization_occurrence_bindings b
    where b.id=p_occurrence_binding_id
      and b.organization_id=p_organization_id
      and b.binding_state='active'
  ) then
    raise exception 'Active occurrence binding is outside organization or missing.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.external_relationships r
    where r.id=p_external_relationship_id
      and r.organization_id=p_organization_id
      and r.relationship_state in ('prospective','active','unknown')
  ) then
    raise exception 'Usable external relationship is outside organization, missing, inactive, or ended.'
      using errcode='42501';
  end if;

  if p_engagement_state is null
     or lower(btrim(p_engagement_state)) !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Engagement state must be a normalized key.'
      using errcode='22023';
  end if;

  if p_calendar_display_state not in ('hidden','eligible','published') then
    raise exception 'Invalid calendar display state.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_provenance,'{}'::jsonb)) <> 'object' then
    raise exception 'Link payload and provenance must be JSON objects.'
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

  if cardinality(v_roles)=0 then
    raise exception 'At least one normalized occurrence relationship role is required.'
      using errcode='22023';
  end if;

  insert into atlas.organization_occurrence_relationship_links(
    organization_id,
    occurrence_binding_id,
    external_relationship_id,
    link_state,
    role_keys,
    engagement_state,
    calendar_display_state,
    public_label,
    public_note,
    display_order,
    payload,
    provenance,
    created_by_membership_id
  )
  values(
    p_organization_id,
    p_occurrence_binding_id,
    p_external_relationship_id,
    'active',
    v_roles,
    lower(btrim(p_engagement_state)),
    p_calendar_display_state,
    nullif(btrim(p_public_label),''),
    nullif(btrim(p_public_note),''),
    coalesce(p_display_order,0),
    coalesce(p_payload,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb),
    p_created_by_membership_id
  )
  on conflict (organization_id,occurrence_binding_id,external_relationship_id)
  do update set
    link_state='active',
    role_keys=excluded.role_keys,
    engagement_state=excluded.engagement_state,
    calendar_display_state=excluded.calendar_display_state,
    public_label=excluded.public_label,
    public_note=excluded.public_note,
    display_order=excluded.display_order,
    payload=excluded.payload,
    provenance=excluded.provenance,
    created_by_membership_id=coalesce(
      excluded.created_by_membership_id,
      atlas.organization_occurrence_relationship_links.created_by_membership_id
    ),
    updated_at=now()
  returning * into v_link;

  return jsonb_build_object(
    'contractVersion','organization_occurrence_relationship_link_v1',
    'linkId',v_link.id,
    'organizationId',v_link.organization_id,
    'occurrenceBindingId',v_link.occurrence_binding_id,
    'externalRelationshipId',v_link.external_relationship_id,
    'linkState',v_link.link_state,
    'roleKeys',to_jsonb(v_link.role_keys),
    'engagementState',v_link.engagement_state,
    'calendarDisplayState',v_link.calendar_display_state
  );
end
$function$;

create or replace function atlas.occurrence_published_relationships_projection_v1(
  p_organization_id uuid,
  p_occurrence_binding_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'linkId',l.id,
      'externalRelationshipId',l.external_relationship_id,
      'roleKeys',to_jsonb(l.role_keys),
      'publicLabel',l.public_label,
      'publicNote',l.public_note,
      'displayOrder',l.display_order,
      'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
        'entityId',e.id,
        'name',e.name,
        'entityType',e.entity_type,
        'websiteUrl',e.website_url,
        'city',e.city,
        'state',e.state
      ))
    ))
    order by l.display_order,coalesce(l.public_label,e.name),l.id
  ),'[]'::jsonb)
  from atlas.organization_occurrence_relationship_links l
  join atlas.external_relationships r
    on r.id=l.external_relationship_id
   and r.organization_id=l.organization_id
   and r.relationship_state in ('prospective','active','unknown')
  join atlas.identity_subject_external_identifiers i
    on i.organization_id=r.organization_id
   and i.subject_id=r.subject_id
   and i.provider_key='local_intel'
   and i.identifier_type='entity_id'
   and i.is_current
  join local_intel.entities e
    on e.id::text=i.identifier_normalized
  where l.organization_id=p_organization_id
    and l.occurrence_binding_id=p_occurrence_binding_id
    and l.link_state='active'
    and l.calendar_display_state='published';
$function$;

comment on function atlas.upsert_occurrence_relationship_link_service_v1(
  uuid,uuid,uuid,text[],text,text,text,text,integer,jsonb,jsonb,uuid
) is
  'Upserts an Organization-private occurrence↔external-relationship link. Prospective and unknown relationships are lawful planning/outreach candidates; inactive or ended relationships are rejected.';
