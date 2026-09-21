begin;

-- Atlas Shared Directory / Ledger Overlay v1
--
-- Shared Intelligence owns canonical external-world identity and public contact reality.
-- Atlas owns organization-scoped relationship state, roles, interactions, preferences,
-- commercial context, and other private Ledger reality.
--
-- This package does not clone local_intel entities into Atlas. It promotes the existing
-- provider_key='local_intel', identifier_type='entity_id' identity seam into the canonical
-- Atlas<->Shared Intelligence binding and exposes governed composition APIs.

create unique index if not exists identity_subject_external_identifiers_local_intel_entity_org_uq
  on atlas.identity_subject_external_identifiers(organization_id, identifier_normalized)
  where is_current
    and provider_key='local_intel'
    and identifier_type='entity_id';

comment on index atlas.identity_subject_external_identifiers_local_intel_entity_org_uq is
  'One current Atlas identity subject per Organization may bind to a given canonical Shared Intelligence entity. The Shared Intelligence UUID is identity; Organization relationship reality remains private overlay.';

create or replace function atlas.shared_directory_entity_overlay_service_v1(
  p_organization_id uuid,
  p_entity_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'local_intel'
as $function$
  with binding as (
    select i.subject_id
    from atlas.identity_subject_external_identifiers i
    where i.organization_id=p_organization_id
      and i.provider_key='local_intel'
      and i.identifier_type='entity_id'
      and i.identifier_normalized=p_entity_id::text
      and i.is_current
    order by i.created_at,i.id
    limit 1
  ), relationships as (
    select r.*
    from atlas.external_relationships r
    join binding b on b.subject_id=r.subject_id
    where r.organization_id=p_organization_id
  ), relationship_rows as (
    select
      r.id,
      jsonb_build_object(
        'externalRelationshipId',r.id,
        'organizationUnitId',r.organization_unit_id,
        'relationshipState',r.relationship_state,
        'roles',coalesce((
          select jsonb_agg(rr.role_key order by rr.role_key)
          from atlas.external_relationship_roles rr
          where rr.external_relationship_id=r.id
            and rr.role_state='active'
        ),'[]'::jsonb),
        'commercialProfile',(
          select (to_jsonb(cp)-'id'-'organization_id'-'external_relationship_id'-'metadata'-'created_at'-'updated_at')
          from atlas.external_relationship_commercial_profiles cp
          where cp.organization_id=p_organization_id
            and cp.external_relationship_id=r.id
          order by cp.updated_at desc,cp.id
          limit 1
        ),
        'itemPreferences',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'itemLabel',ip.item_label,
              'preferenceState',ip.preference_state,
              'usualQuantity',ip.usual_quantity,
              'unit',ip.unit,
              'acceptedUnitPrice',ip.accepted_unit_price,
              'currency',ip.currency,
              'note',ip.note,
              'lastObservedAt',ip.last_observed_at
            ) order by ip.item_label,ip.id
          )
          from atlas.external_relationship_item_preferences ip
          where ip.organization_id=p_organization_id
            and ip.external_relationship_id=r.id
        ),'[]'::jsonb),
        'latestInteraction',(
          select jsonb_build_object(
            'interactionId',x.id,
            'occurredAt',x.occurred_at,
            'interactionKind',x.interaction_kind,
            'channel',x.channel,
            'outcome',x.outcome,
            'contactLabel',x.contact_label,
            'followUp',x.follow_up,
            'note',x.note
          )
          from atlas.external_relationship_interactions x
          where x.organization_id=p_organization_id
            and x.external_relationship_id=r.id
          order by x.occurred_at desc,x.created_at desc,x.id desc
          limit 1
        )
      ) as payload
    from relationships r
  )
  select jsonb_build_object(
    'contractVersion','shared_directory_entity_overlay_v1',
    'organizationId',p_organization_id,
    'sharedEntityId',p_entity_id,
    'subjectId',(select subject_id from binding),
    'isRelated',exists(select 1 from relationships),
    'roleKeys',coalesce((
      select jsonb_agg(distinct rr.role_key order by rr.role_key)
      from relationships r
      join atlas.external_relationship_roles rr on rr.external_relationship_id=r.id
      where rr.role_state='active'
    ),'[]'::jsonb),
    'relationships',coalesce((select jsonb_agg(payload order by id) from relationship_rows),'[]'::jsonb)
  )
$function$;

revoke all on function atlas.shared_directory_entity_overlay_service_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function atlas.shared_directory_entity_overlay_service_v1(uuid,uuid) to service_role;

create or replace function atlas.shared_directory_search_service_v1(
  p_organization_id uuid,
  p_query text default null,
  p_related_only boolean default false,
  p_role_key text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'local_intel'
as $function$
declare
  v_query text:=nullif(lower(btrim(coalesce(p_query,''))), '');
  v_role_key text:=nullif(lower(btrim(coalesce(p_role_key,''))), '');
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),100));
  v_items jsonb;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;
  if v_role_key is not null and v_role_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Invalid relationship role key.' using errcode='22023';
  end if;

  with candidates as (
    select
      e.id,
      e.entity_type,
      e.name,
      e.description,
      e.website_url,
      e.phone,
      e.email,
      e.address_line1,
      e.city,
      e.state,
      e.postal_code,
      e.verification_state,
      e.last_verified_at,
      exists(
        select 1
        from atlas.identity_subject_external_identifiers i
        where i.organization_id=p_organization_id
          and i.provider_key='local_intel'
          and i.identifier_type='entity_id'
          and i.identifier_normalized=e.id::text
          and i.is_current
      ) as is_related,
      case
        when v_query is null then 3
        when lower(e.name)=v_query then 0
        when lower(e.name) like v_query||'%' then 1
        else 2
      end as match_rank
    from local_intel.entities e
    where e.status='active'
      and (
        v_query is null
        or lower(e.name) like '%'||v_query||'%'
        or lower(coalesce(e.city,'')) like '%'||v_query||'%'
        or lower(coalesce(e.email,'')) like '%'||v_query||'%'
        or lower(coalesce(e.phone,'')) like '%'||v_query||'%'
        or exists(
          select 1
          from local_intel.entity_aliases a
          where a.entity_id=e.id
            and a.is_current
            and lower(a.alias) like '%'||v_query||'%'
        )
        or exists(
          select 1
          from local_intel.v_best_entity_contact_route_v1 cr
          where cr.entity_id=e.id
            and lower(cr.contact_value) like '%'||v_query||'%'
        )
      )
      and (
        not coalesce(p_related_only,false)
        or exists(
          select 1
          from atlas.identity_subject_external_identifiers i
          where i.organization_id=p_organization_id
            and i.provider_key='local_intel'
            and i.identifier_type='entity_id'
            and i.identifier_normalized=e.id::text
            and i.is_current
        )
      )
      and (
        v_role_key is null
        or exists(
          select 1
          from atlas.identity_subject_external_identifiers i
          join atlas.external_relationships r
            on r.organization_id=i.organization_id
           and r.subject_id=i.subject_id
          join atlas.external_relationship_roles rr
            on rr.external_relationship_id=r.id
           and rr.role_key=v_role_key
           and rr.role_state='active'
          where i.organization_id=p_organization_id
            and i.provider_key='local_intel'
            and i.identifier_type='entity_id'
            and i.identifier_normalized=e.id::text
            and i.is_current
        )
      )
    order by is_related desc,match_rank,e.name,e.id
    limit v_limit
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'entityId',c.id,
      'entityType',c.entity_type,
      'name',c.name,
      'description',c.description,
      'websiteUrl',c.website_url,
      'phone',c.phone,
      'email',c.email,
      'address',jsonb_strip_nulls(jsonb_build_object(
        'line1',c.address_line1,
        'city',c.city,
        'state',c.state,
        'postalCode',c.postal_code
      )),
      'verificationState',c.verification_state,
      'lastVerifiedAt',c.last_verified_at,
      'aliases',coalesce((
        select jsonb_agg(a.alias order by a.alias)
        from local_intel.entity_aliases a
        where a.entity_id=c.id and a.is_current
      ),'[]'::jsonb),
      'bestContactRoutes',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'contactType',cr.contact_type,
            'contactValue',cr.contact_value,
            'routeEntityId',cr.route_entity_id,
            'routeEntityName',cr.route_entity_name,
            'routeKind',cr.route_kind,
            'hierarchyHops',cr.hierarchy_hops,
            'contactScope',cr.contact_scope,
            'verificationState',cr.verification_state,
            'deliverabilityState',cr.deliverability_state,
            'marketingStatus',cr.marketing_status,
            'contactability',cr.effective_contactability,
            'channelPreference',cr.explicit_channel_preference,
            'lastCheckedAt',cr.last_checked_at
          ) order by cr.contact_type,cr.hierarchy_hops,cr.route_entity_name
        )
        from local_intel.v_best_entity_contact_route_v1 cr
        where cr.entity_id=c.id
      ),'[]'::jsonb),
      'overlay',atlas.shared_directory_entity_overlay_service_v1(p_organization_id,c.id)
    ) order by c.is_related desc,c.match_rank,c.name,c.id
  ),'[]'::jsonb)
  into v_items
  from candidates c;

  return jsonb_build_object(
    'contractVersion','shared_directory_search_v1',
    'organizationId',p_organization_id,
    'query',v_query,
    'relatedOnly',coalesce(p_related_only,false),
    'roleKey',v_role_key,
    'items',v_items,
    'retrievalPolicy','shared_directory_first'
  );
end;
$function$;

revoke all on function atlas.shared_directory_search_service_v1(uuid,text,boolean,text,integer) from public, anon, authenticated;
grant execute on function atlas.shared_directory_search_service_v1(uuid,text,boolean,text,integer) to service_role;

create or replace function atlas.shared_directory_search_self_api_v1(
  p_organization_id uuid,
  p_query text default null,
  p_related_only boolean default false,
  p_role_key text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'local_intel', 'auth'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.shared_directory_search_service_v1(
    p_organization_id,p_query,p_related_only,p_role_key,p_limit
  );
end;
$function$;

revoke all on function atlas.shared_directory_search_self_api_v1(uuid,text,boolean,text,integer) from public, anon;
grant execute on function atlas.shared_directory_search_self_api_v1(uuid,text,boolean,text,integer) to authenticated;

create or replace function atlas.attach_shared_directory_entity_service_v1(
  p_organization_id uuid,
  p_entity_id uuid,
  p_role_key text default 'contact',
  p_organization_unit_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'local_intel'
as $function$
declare
  v_entity local_intel.entities%rowtype;
  v_identifiers jsonb;
  v_result jsonb;
begin
  select * into v_entity
  from local_intel.entities e
  where e.id=p_entity_id and e.status='active';
  if v_entity.id is null then
    raise exception 'Shared Intelligence entity not found or inactive.' using errcode='P0002';
  end if;

  v_identifiers:=jsonb_build_array(
    jsonb_build_object(
      'providerKey','local_intel',
      'type','entity_id',
      'value',v_entity.id::text,
      'normalized',v_entity.id::text,
      'identityScoped',true,
      'matchStrength','strong'
    )
  );

  if nullif(btrim(coalesce(v_entity.email,'')),'') is not null then
    v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object(
      'type','email','value',v_entity.email,'identityScoped',true,'matchStrength','strong'
    ));
  end if;
  if nullif(btrim(coalesce(v_entity.phone,'')),'') is not null then
    v_identifiers:=v_identifiers||jsonb_build_array(jsonb_build_object(
      'type','phone','value',v_entity.phone,'identityScoped',true,'matchStrength','strong'
    ));
  end if;

  v_result:=atlas.resolve_external_relationship_service_v1(
    p_organization_id=>p_organization_id,
    p_organization_unit_id=>p_organization_unit_id,
    p_role_key=>p_role_key,
    p_display_name=>v_entity.name,
    p_subject_kind=>case when v_entity.entity_type in ('person','organization','place') then v_entity.entity_type else 'unknown' end,
    p_identifiers=>v_identifiers,
    p_source_system_key=>'shared_intelligence',
    p_source_record_kind=>'canonical_entity_reference',
    p_source_record_key=>'entity:'||v_entity.id::text,
    p_source_observed_at=>coalesce(v_entity.last_verified_at,v_entity.updated_at),
    p_source_authority=>'authoritative_source',
    p_custody_ref=>jsonb_build_object('schema','local_intel','table','entities','entityId',v_entity.id),
    p_basis=>jsonb_build_object(
      'sharedDirectory',true,
      'canonicalEntityId',v_entity.id,
      'identityOwner','Shared Intelligence',
      'overlayOwner','Atlas Organization'
    ),
    p_allow_create=>true,
    p_new_relationship_state=>'prospective'
  );

  return v_result||jsonb_build_object(
    'sharedEntityId',v_entity.id,
    'sharedEntityName',v_entity.name,
    'sharedEntityType',v_entity.entity_type,
    'identityDisposition','canonical_shared_identity_with_private_organization_overlay'
  );
end;
$function$;

revoke all on function atlas.attach_shared_directory_entity_service_v1(uuid,uuid,text,uuid) from public, anon, authenticated;
grant execute on function atlas.attach_shared_directory_entity_service_v1(uuid,uuid,text,uuid) to service_role;

create or replace function atlas.attach_shared_directory_entity_self_api_v1(
  p_organization_id uuid,
  p_entity_id uuid,
  p_role_key text default 'contact',
  p_organization_unit_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'local_intel', 'auth'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.attach_shared_directory_entity_service_v1(
    p_organization_id,p_entity_id,p_role_key,p_organization_unit_id
  );
end;
$function$;

revoke all on function atlas.attach_shared_directory_entity_self_api_v1(uuid,uuid,text,uuid) from public, anon;
grant execute on function atlas.attach_shared_directory_entity_self_api_v1(uuid,uuid,text,uuid) to authenticated;

create or replace function atlas.record_shared_directory_interaction_service_v1(
  p_organization_id uuid,
  p_external_relationship_id uuid,
  p_interaction_kind text,
  p_occurred_at timestamptz default now(),
  p_channel text default null,
  p_outcome text default null,
  p_contact_label text default null,
  p_follow_up text default null,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_relationship atlas.external_relationships%rowtype;
  v_interaction atlas.external_relationship_interactions%rowtype;
  v_kind text:=lower(btrim(coalesce(p_interaction_kind,'')));
begin
  if v_kind='' then
    raise exception 'Interaction kind is required.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Interaction metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_relationship
  from atlas.external_relationships r
  where r.id=p_external_relationship_id
    and r.organization_id=p_organization_id;
  if v_relationship.id is null then
    raise exception 'External relationship is outside organization or missing.' using errcode='42501';
  end if;

  insert into atlas.external_relationship_interactions(
    organization_id,organization_unit_id,external_relationship_id,occurred_at,
    interaction_kind,channel,outcome,contact_label,follow_up,note,metadata
  ) values (
    p_organization_id,v_relationship.organization_unit_id,p_external_relationship_id,
    coalesce(p_occurred_at,now()),v_kind,nullif(btrim(coalesce(p_channel,'')),''),
    nullif(btrim(coalesce(p_outcome,'')),''),nullif(btrim(coalesce(p_contact_label,'')),''),
    nullif(btrim(coalesce(p_follow_up,'')),''),nullif(btrim(coalesce(p_note,'')),''),
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('sharedDirectoryOverlay',true)
  ) returning * into v_interaction;

  return jsonb_build_object(
    'contractVersion','record_shared_directory_interaction_v1',
    'organizationId',p_organization_id,
    'externalRelationshipId',p_external_relationship_id,
    'interactionId',v_interaction.id,
    'occurredAt',v_interaction.occurred_at,
    'interactionKind',v_interaction.interaction_kind
  );
end;
$function$;

revoke all on function atlas.record_shared_directory_interaction_service_v1(uuid,uuid,text,timestamptz,text,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function atlas.record_shared_directory_interaction_service_v1(uuid,uuid,text,timestamptz,text,text,text,text,text,jsonb) to service_role;

create or replace function atlas.record_shared_directory_interaction_self_api_v1(
  p_organization_id uuid,
  p_external_relationship_id uuid,
  p_interaction_kind text,
  p_occurred_at timestamptz default now(),
  p_channel text default null,
  p_outcome text default null,
  p_contact_label text default null,
  p_follow_up text default null,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='28000';
  end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.record_shared_directory_interaction_service_v1(
    p_organization_id,p_external_relationship_id,p_interaction_kind,p_occurred_at,
    p_channel,p_outcome,p_contact_label,p_follow_up,p_note,p_metadata
  );
end;
$function$;

revoke all on function atlas.record_shared_directory_interaction_self_api_v1(uuid,uuid,text,timestamptz,text,text,text,text,text,jsonb) from public, anon;
grant execute on function atlas.record_shared_directory_interaction_self_api_v1(uuid,uuid,text,timestamptz,text,text,text,text,text,jsonb) to authenticated;

comment on function atlas.shared_directory_search_service_v1(uuid,text,boolean,text,integer) is
  'Service read: universal Shared Intelligence directory first, composed with exactly one Atlas Organization private relationship overlay. No external web acquisition occurs here.';
comment on function atlas.shared_directory_search_self_api_v1(uuid,text,boolean,text,integer) is
  'Authenticated Organization-scoped Shared Directory read. Canonical identity/public contacts are shared; Atlas relationship state and notes are visible only through the caller Organization overlay.';
comment on function atlas.attach_shared_directory_entity_service_v1(uuid,uuid,text,uuid) is
  'Service writer: attach an Atlas Organization relationship/role to an existing canonical Shared Intelligence entity without cloning the entity.';
comment on function atlas.record_shared_directory_interaction_service_v1(uuid,uuid,text,timestamptz,text,text,text,text,text,jsonb) is
  'Service writer for Organization-private relationship effort/note history against a canonical Shared Directory identity.';

commit;
