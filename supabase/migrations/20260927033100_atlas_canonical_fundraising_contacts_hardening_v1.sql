-- Canonical fundraising contacts hardening v1.
-- Fail closed on non-canonical Reality identities and keep known-constituent Smart Contacts
-- behavior consistent with the V1 query's contact/type constraints.

create or replace function atlas.guard_fundraising_constituent_reality_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_fundraising_kind text;
  v_constituent_kind text;
begin
  select e.entity_kind into v_fundraising_kind
  from reality.entities e
  where e.id=new.fundraising_entity_id
    and e.identity_state='canonical';
  if v_fundraising_kind is null or v_fundraising_kind not in ('business','organization') then
    raise exception 'Fundraising entity must be a canonical Reality business or organization.' using errcode='23514';
  end if;

  select e.entity_kind into v_constituent_kind
  from reality.entities e
  where e.id=new.constituent_entity_id
    and e.identity_state='canonical';
  if v_constituent_kind is null or v_constituent_kind not in ('person','business','organization') then
    raise exception 'Constituent must be a canonical Reality person, business, or organization.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_fundraising_constituent_reality_v1()
  from public,anon,authenticated;

create or replace function atlas.smart_contacts_search_service_v2(
  p_organization_id uuid,
  p_query jsonb,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_base jsonb;
  v_item jsonb;
  v_source_id uuid;
  v_reality_id uuid;
  v_org_reality_id uuid;
  v_entity reality.entities%rowtype;
  v_routes jsonb;
  v_route_types text[];
  v_canonical_items jsonb:='[]'::jsonb;
  v_unresolved_items jsonb:='[]'::jsonb;
  v_seen uuid[]:='{}'::uuid[];
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
  v_text text:=nullif(lower(btrim(coalesce(p_query->>'text',''))),'');
  v_canonical_only boolean:=coalesce((p_query->>'canonicalOnly')::boolean,false);
  v_require_contactable boolean:=coalesce((p_query->>'requireContactable')::boolean,false);
  v_required_contact_types text[]:='{}'::text[];
  v_entity_types text[]:='{}'::text[];
  v_count integer:=0;
begin
  if p_query is null or jsonb_typeof(p_query)<>'object' then
    raise exception 'Smart Contacts query must be a JSON object.' using errcode='22023';
  end if;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_required_contact_types
  from jsonb_array_elements_text(coalesce(p_query->'requiredContactTypes','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_entity_types
  from jsonb_array_elements_text(coalesce(p_query->'entityTypes','[]'::jsonb)) x;

  v_base:=atlas.smart_contacts_search_service_v1(p_organization_id,p_query,v_limit);
  v_org_reality_id:=atlas.reality_entity_for_legacy_organization_internal_v1(p_organization_id);

  for v_item in select value from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb))
  loop
    begin v_source_id:=(v_item->>'entityId')::uuid;
    exception when others then v_source_id:=null; end;
    v_reality_id:=case when v_source_id is null then null else atlas.smart_contact_reality_entity_internal_v2(v_source_id) end;

    if v_reality_id is not null and not (v_reality_id=any(v_seen)) then
      select * into v_entity from reality.entities e
      where e.id=v_reality_id and e.identity_state='canonical';
      select
        coalesce(jsonb_agg(jsonb_build_object(
          'contactRouteId',cr.id,'routeKind',cr.route_kind,'routeValue',cr.route_value,
          'routeState',cr.route_state,'lastVerifiedAt',cr.last_verified_at
        ) order by case cr.route_state when 'verified' then 0 when 'observed' then 1 else 2 end,
                   cr.last_verified_at desc nulls last,cr.id),'[]'::jsonb),
        coalesce(array_agg(distinct lower(cr.route_kind)),'{}'::text[])
      into v_routes,v_route_types
      from reality.contact_routes cr
      where cr.entity_id=v_reality_id and cr.route_state in ('verified','observed');

      if (cardinality(v_entity_types)=0 or lower(v_entity.entity_kind)=any(v_entity_types))
         and (not v_require_contactable or cardinality(v_route_types)>0)
         and not exists(
           select 1 from unnest(v_required_contact_types) required
           where not (required=any(v_route_types))
         ) then
        v_canonical_items:=v_canonical_items||jsonb_build_array(
          (v_item-'entityId')||jsonb_build_object(
            'entityId',v_reality_id,
            'realityEntityId',v_reality_id,
            'sourceEntityId',v_source_id,
            'canonicalState','resolved',
            'canonicalIdentity',jsonb_build_object(
              'displayName',v_entity.display_name,'entityKind',v_entity.entity_kind,
              'contactRoutes',v_routes
            )
          )
        );
        v_seen:=array_append(v_seen,v_reality_id);
      end if;
    elsif not v_canonical_only then
      v_unresolved_items:=v_unresolved_items||jsonb_build_array(
        (v_item-'entityId')||jsonb_build_object(
          'entityId',null,
          'realityEntityId',null,
          'sourceEntityId',v_source_id,
          'canonicalState','unresolved',
          'researchGaps',coalesce(v_item->'researchGaps','[]'::jsonb)||jsonb_build_array('reality_identity_unresolved')
        )
      );
    end if;
  end loop;

  if v_org_reality_id is not null then
    for v_entity in
      select distinct e.*
      from atlas.fundraising_constituent_relationships r
      join reality.entities e on e.id=r.constituent_entity_id and e.identity_state='canonical'
      where r.fundraising_entity_id=v_org_reality_id
        and r.relationship_state='active'
        and r.ended_at is null
        and (v_text is null or lower(e.display_name) like '%'||v_text||'%')
        and (cardinality(v_entity_types)=0 or lower(e.entity_kind)=any(v_entity_types))
      order by e.display_name,e.id
    loop
      if not (v_entity.id=any(v_seen)) then
        select
          coalesce(jsonb_agg(jsonb_build_object(
            'contactRouteId',cr.id,'routeKind',cr.route_kind,'routeValue',cr.route_value,
            'routeState',cr.route_state,'lastVerifiedAt',cr.last_verified_at
          ) order by case cr.route_state when 'verified' then 0 when 'observed' then 1 else 2 end,
                     cr.last_verified_at desc nulls last,cr.id),'[]'::jsonb),
          coalesce(array_agg(distinct lower(cr.route_kind)),'{}'::text[])
        into v_routes,v_route_types
        from reality.contact_routes cr
        where cr.entity_id=v_entity.id and cr.route_state in ('verified','observed');

        if (not v_require_contactable or cardinality(v_route_types)>0)
           and not exists(
             select 1 from unnest(v_required_contact_types) required
             where not (required=any(v_route_types))
           ) then
          v_canonical_items:=v_canonical_items||jsonb_build_array(jsonb_build_object(
            'entityId',v_entity.id,
            'realityEntityId',v_entity.id,
            'sourceEntityId',null,
            'name',v_entity.display_name,
            'entityType',v_entity.entity_kind,
            'canonicalState','resolved',
            'canonicalIdentity',jsonb_build_object(
              'displayName',v_entity.display_name,'entityKind',v_entity.entity_kind,
              'contactRoutes',v_routes
            ),
            'match',jsonb_build_object(
              'relevanceScore',80,
              'signalKeys',jsonb_build_array('established_fundraising_constituent')
            ),
            'researchGaps','[]'::jsonb,
            'organizationOverlay',jsonb_build_object('fundraisingConstituent',true)
          ));
          v_seen:=array_append(v_seen,v_entity.id);
        end if;
      end if;
    end loop;
  end if;

  v_count:=least(v_limit,jsonb_array_length(v_canonical_items)+jsonb_array_length(v_unresolved_items));

  return jsonb_build_object(
    'contractVersion','atlas_smart_contacts_reality_v2',
    'productName','Atlas Smart Contacts',
    'organizationId',p_organization_id,
    'query',p_query,
    'resultCount',v_count,
    'canonicalCount',least(v_limit,jsonb_array_length(v_canonical_items)),
    'unresolvedCount',case when v_canonical_only then 0 else greatest(0,v_count-least(v_limit,jsonb_array_length(v_canonical_items))) end,
    'items',(
      select coalesce(jsonb_agg(value),'[]'::jsonb)
      from (
        select value,ord from jsonb_array_elements(v_canonical_items||v_unresolved_items) with ordinality x(value,ord)
        where ord<=v_limit
        order by ord
      ) limited
    ),
    'truthBoundary',jsonb_build_object(
      'canonicalReality','reality.entities',
      'localIntelRetainedAsResearchEvidence',true,
      'unresolvedResearchContactMayBecomeConstituent',false,
      'fundraisingConstituentsDiscoverableWithoutLocalIntelRecord',true,
      'queryContactAndEntityFiltersApplyToCanonicalConstituents',true,
      'searchCreatesRelationship',false,
      'searchAuthorizesCommunication',false
    )
  );
end;
$$;

revoke all on function atlas.smart_contacts_search_service_v2(uuid,jsonb,integer)
  from public,anon,authenticated;
grant execute on function atlas.smart_contacts_search_service_v2(uuid,jsonb,integer)
  to service_role;
