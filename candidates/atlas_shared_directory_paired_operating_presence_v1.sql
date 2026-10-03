-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: organization-first directory projection over canonical paired proofs.

create or replace function atlas.shared_directory_paired_operating_presence_search_service_v1(
  p_organization_id uuid,
  p_target jsonb,
  p_resolved_geography jsonb,
  p_required_fields text[] default '{}'::text[],
  p_limit integer default 100
) returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare
  v_org_kinds text[]:='{}'::text[];
  v_named_orgs text[]:='{}'::text[];
  v_required text[]:='{}'::text[];
  v_side_a uuid[];
  v_side_b uuid[];
  v_max_operating_depth integer;
  v_max_spatial_depth integer;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),200));
  v_items jsonb:='[]'::jsonb;
  v_research jsonb:='[]'::jsonb;
  v_candidate_count integer:=0;
  v_ready_count integer:=0;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then raise exception 'Organization not found or inactive.' using errcode='P0002'; end if;
  if p_target is null or jsonb_typeof(p_target)<>'object' then raise exception 'Target must be a JSON object.' using errcode='22023'; end if;
  if p_resolved_geography is null or jsonb_typeof(p_resolved_geography)<>'object' or p_resolved_geography->>'state'<>'resolved' or p_resolved_geography->>'mode'<>'paired_operating_presence' then raise exception 'Resolved paired operating geography is required.' using errcode='22023'; end if;
  if jsonb_array_length(coalesce(p_target->'personFunctions','[]'::jsonb))>0 or jsonb_array_length(coalesce(p_target->'titles','[]'::jsonb))>0 then raise exception 'Paired operating presence v1 qualifies organizations before person discovery.' using errcode='22023'; end if;

  select coalesce(array_agg((x#>>'{}')::uuid),'{}'::uuid[]) into v_side_a from jsonb_array_elements(coalesce(p_resolved_geography#>'{sideA,placeEntityIds}','[]'::jsonb)) x;
  select coalesce(array_agg((x#>>'{}')::uuid),'{}'::uuid[]) into v_side_b from jsonb_array_elements(coalesce(p_resolved_geography#>'{sideB,placeEntityIds}','[]'::jsonb)) x;
  if cardinality(v_side_a)=0 or cardinality(v_side_b)=0 then raise exception 'Resolved paired geography must contain both canonical Place sets.' using errcode='23514'; end if;
  v_max_operating_depth:=coalesce((p_resolved_geography->>'maxOperatingDepth')::integer,8);
  v_max_spatial_depth:=coalesce((p_resolved_geography->>'maxSpatialDepth')::integer,8);

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[]) into v_org_kinds from jsonb_array_elements_text(coalesce(p_target->'organizationKinds','[]'::jsonb)) x;
  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[]) into v_named_orgs from jsonb_array_elements_text(coalesce(p_target->'namedOrganizations','[]'::jsonb)) x;
  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[]) into v_required from unnest(coalesce(p_required_fields,'{}'::text[])) x;
  if cardinality(v_required)=0 then raise exception 'At least one required field is required.' using errcode='22023'; end if;

  with spanning as (
    select * from reality.operating_roots_spanning_place_sets_service_v1(v_side_a,v_side_b,v_max_operating_depth,v_max_spatial_depth,now(),v_limit)
  ), candidates as (
    select s.*,e.website_url,e.phone,e.email,e.description,e.metadata,e.verification_state,e.last_verified_at,
      (exists(select 1 from unnest(v_named_orgs) q where lower(s.root_display_name) like '%'||q||'%'))::int*10
      +(exists(select 1 from unnest(v_org_kinds) q where lower(concat_ws(' ',s.root_display_name,coalesce(e.description,''),coalesce(e.metadata::text,''))) like '%'||replace(q,'_',' ')||'%' or lower(concat_ws(' ',s.root_display_name,coalesce(e.description,''),coalesce(e.metadata::text,''))) like '%'||q||'%'))::int*5 as target_score
    from spanning s
    join local_intel.entities e on e.id=s.root_entity_id and e.status='active'
    where (cardinality(v_named_orgs)=0 or exists(select 1 from unnest(v_named_orgs) q where lower(s.root_display_name) like '%'||q||'%'))
      and (cardinality(v_org_kinds)=0 or exists(select 1 from unnest(v_org_kinds) q where lower(concat_ws(' ',s.root_display_name,coalesce(e.description,''),coalesce(e.metadata::text,''))) like '%'||replace(q,'_',' ')||'%' or lower(concat_ws(' ',s.root_display_name,coalesce(e.description,''),coalesce(e.metadata::text,''))) like '%'||q||'%'))
  ), bounded as (
    select * from candidates order by target_score desc,root_display_name,root_entity_id limit v_limit
  ), detailed as (
    select b.*,
      coalesce((select array_agg(f order by f) from unnest(v_required) f where case f
        when 'email' then nullif(btrim(coalesce(b.email,'')),'') is null and not exists(select 1 from local_intel.v_best_entity_contact_route_v1 cr where cr.entity_id=b.root_entity_id and cr.contact_type='email' and coalesce(cr.effective_contactability,'')<>'blocked')
        when 'phone' then nullif(btrim(coalesce(b.phone,'')),'') is null and not exists(select 1 from local_intel.v_best_entity_contact_route_v1 cr where cr.entity_id=b.root_entity_id and cr.contact_type='phone' and coalesce(cr.effective_contactability,'')<>'blocked')
        when 'name' then nullif(btrim(coalesce(b.root_display_name,'')),'') is null
        when 'website' then nullif(btrim(coalesce(b.website_url,'')),'') is null
        else true end),'{}'::text[]) as missing_fields,
      coalesce((select jsonb_agg(jsonb_build_object('contactType',cr.contact_type,'contactValue',cr.contact_value,'routeEntityId',cr.route_entity_id,'routeEntityName',cr.route_entity_name,'routeKind',cr.route_kind,'contactScope',cr.contact_scope,'verificationState',cr.verification_state,'deliverabilityState',cr.deliverability_state,'contactability',cr.effective_contactability,'lastCheckedAt',cr.last_checked_at) order by cr.contact_type,cr.hierarchy_hops,cr.route_entity_name) from local_intel.v_best_entity_contact_route_v1 cr where cr.entity_id=b.root_entity_id),'[]'::jsonb) as contact_routes
    from bounded b
  ), item_payloads as (
    select d.root_entity_id,d.missing_fields,
      jsonb_build_object(
        'entityId',d.root_entity_id,'name',d.root_display_name,'entityType',d.root_entity_kind,
        'qualificationStage','organization','qualificationMode','paired_operating_presence',
        'pairedPresenceProof',jsonb_build_object('sideA',d.side_a_proofs,'sideB',d.side_b_proofs),
        'websiteUrl',d.website_url,'verificationState',d.verification_state,'lastVerifiedAt',d.last_verified_at,
        'bestContactRoutes',d.contact_routes,'requiredFields',to_jsonb(v_required),'missingFields',to_jsonb(d.missing_fields),
        'fieldCoverageState',case when cardinality(d.missing_fields)=0 then 'complete' else 'gap' end,
        'overlay',atlas.shared_directory_entity_overlay_service_v1(p_organization_id,d.root_entity_id)
      ) as payload
    from detailed d
  ), field_gaps as (
    select jsonb_build_object('gapKind','entity_field_gap','entityId',i.root_entity_id,'organizationEntityId',i.root_entity_id,'missingFields',to_jsonb(i.missing_fields),'reason','Qualified paired-presence organization exists but one or more requested enrichment fields are missing.') as payload
    from item_payloads i where cardinality(i.missing_fields)>0
  )
  select coalesce((select jsonb_agg(i.payload order by i.payload->>'name') from item_payloads i),'[]'::jsonb),
         coalesce((select jsonb_agg(g.payload) from field_gaps g),'[]'::jsonb),
         (select count(*)::integer from item_payloads),
         (select count(*)::integer from item_payloads where cardinality(missing_fields)=0)
  into v_items,v_research,v_candidate_count,v_ready_count;

  return jsonb_build_object(
    'contractVersion','shared_directory_paired_operating_presence_search_v1','organizationId',p_organization_id,
    'target',p_target,'geography',p_resolved_geography,'requiredFields',to_jsonb(v_required),
    'candidateCount',v_candidate_count,'completeCandidateCount',v_ready_count,'items',v_items,'researchTargets',v_research,
    'qualificationStage','organization','retrievalPolicy','canonical_paired_operating_presence_first','communicationAuthorized',false
  );
end
$function$;

revoke all on function atlas.shared_directory_paired_operating_presence_search_service_v1(uuid,jsonb,jsonb,text[],integer) from public,anon,authenticated;
grant execute on function atlas.shared_directory_paired_operating_presence_search_service_v1(uuid,jsonb,jsonb,text[],integer) to service_role;
