create or replace function atlas.resolve_connected_source_external_relationship_service_v1(
  p_connected_source_id uuid,
  p_organization_unit_id uuid default null,
  p_display_name text default null,
  p_subject_kind text default 'unknown',
  p_identifiers jsonb default '[]'::jsonb,
  p_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_identifiers jsonb := coalesce(p_identifiers, '[]'::jsonb);
  v_identifier jsonb;
  v_provider_key text;
  v_type text;
  v_value text;
  v_normalized text;
  v_checkout_session_id text;
  v_candidates uuid[];
  v_subject_id uuid;
  v_relationship_id uuid;
  v_match_state text := 'created_unresolved';
  v_stable_key text;
begin
  select * into v_source from atlas.connected_sources where id = p_connected_source_id;
  if v_source.id is null or v_source.custodian_organization_id is null or v_source.authorization_state <> 'connected' then
    raise exception 'A connected organization source is required.' using errcode='55000';
  end if;
  if jsonb_typeof(v_identifiers) <> 'array' then
    raise exception 'Identifiers must be an array.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_basis, '{}'::jsonb)) <> 'object' then
    raise exception 'Relationship basis must be an object.' using errcode='22023';
  end if;
  if p_organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units ou
    where ou.organization_id = v_source.custodian_organization_id and ou.id = p_organization_unit_id
  ) then
    raise exception 'Organization unit is outside connected source organization.' using errcode='23514';
  end if;

  v_checkout_session_id := nullif(btrim(p_basis->>'checkoutSessionId'), '');
  if v_source.provider_key = 'stripe' and v_checkout_session_id is not null then
    v_identifiers := v_identifiers || jsonb_build_array(jsonb_build_object(
      'providerKey','stripe','type','checkout_session_id','value',v_checkout_session_id,'normalized',v_checkout_session_id
    ));
  end if;

  select array_agg(distinct i.subject_id)
  into v_candidates
  from atlas.identity_subject_external_identifiers i
  join jsonb_array_elements(v_identifiers) x on true
  where i.organization_id = v_source.custodian_organization_id
    and i.is_current
    and i.identifier_type = nullif(btrim(x->>'type'), '')
    and i.identifier_normalized = coalesce(nullif(btrim(x->>'normalized'), ''), lower(btrim(x->>'value')))
    and coalesce(i.provider_key, '') = coalesce(nullif(btrim(x->>'providerKey'), ''), '');

  if coalesce(array_length(v_candidates, 1), 0) = 1 then
    v_subject_id := v_candidates[1];
    v_match_state := 'matched_exact_identifier';
  else
    insert into atlas.identity_subjects(organization_id, state, creation_basis)
    values (v_source.custodian_organization_id,'active',jsonb_build_object(
      'source','connected_source_commercial_interpretation','connectedSourceId',v_source.id,
      'matchState',case when coalesce(array_length(v_candidates, 1), 0) > 1 then 'ambiguous_identifier_candidates' else 'no_identifier_match' end,
      'candidateSubjectIds',coalesce(to_jsonb(v_candidates),'[]'::jsonb)) || coalesce(p_basis,'{}'::jsonb))
    returning id into v_subject_id;

    insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,aliases,contact_points,unresolved_identity,confidence,projection_basis)
    values (v_subject_id,v_source.custodian_organization_id,coalesce(nullif(btrim(p_subject_kind),''),'unknown'),nullif(btrim(p_display_name),''),'[]','[]',true,null,
      jsonb_build_object('source','connected_source_commercial_interpretation','connectedSourceId',v_source.id));
    if coalesce(array_length(v_candidates, 1), 0) > 1 then v_match_state := 'created_ambiguous'; end if;
  end if;

  select r.id into v_relationship_id from atlas.external_relationships r
  where r.organization_id=v_source.custodian_organization_id and r.subject_id=v_subject_id
    and r.relationship_state in ('active','prospective','unknown')
    and ((p_organization_unit_id is null and r.organization_unit_id is null) or r.organization_unit_id=p_organization_unit_id)
  order by case r.relationship_state when 'active' then 0 when 'prospective' then 1 else 2 end,r.created_at limit 1;

  if v_relationship_id is null then
    v_stable_key := 'connected-source:' || v_source.id::text || ':subject:' || v_subject_id::text;
    insert into atlas.external_relationships(organization_id,organization_unit_id,subject_id,stable_key,relationship_state,metadata)
    values (v_source.custodian_organization_id,p_organization_unit_id,v_subject_id,v_stable_key,'active',
      jsonb_build_object('source','connected_source_commercial_interpretation','connectedSourceId',v_source.id) || coalesce(p_basis,'{}'::jsonb))
    returning id into v_relationship_id;
  end if;

  insert into atlas.external_relationship_roles(external_relationship_id,role_key,role_state,basis)
  values (v_relationship_id,'customer','active',jsonb_build_object('source','connected_source_commercial_interpretation','connectedSourceId',v_source.id))
  on conflict (external_relationship_id,role_key) do nothing;

  for v_identifier in select value from jsonb_array_elements(v_identifiers) loop
    v_provider_key := nullif(btrim(v_identifier->>'providerKey'),'');
    v_type := nullif(btrim(v_identifier->>'type'),'');
    v_value := nullif(btrim(v_identifier->>'value'),'');
    v_normalized := coalesce(nullif(btrim(v_identifier->>'normalized'),''),lower(v_value));
    if v_type is not null and v_value is not null and v_normalized is not null then
      insert into atlas.identity_subject_external_identifiers(organization_id,subject_id,provider_key,identifier_type,identifier_value,identifier_normalized,is_current,priority,metadata)
      values (v_source.custodian_organization_id,v_subject_id,v_provider_key,v_type,v_value,v_normalized,true,
        case when v_type='checkout_session_id' then 9 else 5 end,
        jsonb_build_object('source','connected_source_commercial_interpretation','connectedSourceId',v_source.id,'transactionScoped',v_type='checkout_session_id'))
      on conflict do nothing;
    end if;
  end loop;

  if nullif(btrim(p_display_name),'') is not null then
    update atlas.identity_subject_projections set display_name=coalesce(display_name,nullif(btrim(p_display_name),'')),
      projection_basis=projection_basis || jsonb_build_object('connectedSourceId',v_source.id) where subject_id=v_subject_id;
  end if;

  return jsonb_build_object('organizationId',v_source.custodian_organization_id,'subjectId',v_subject_id,'externalRelationshipId',v_relationship_id,'matchState',v_match_state);
end;
$function$;
revoke all on function atlas.resolve_connected_source_external_relationship_service_v1(uuid,uuid,text,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.resolve_connected_source_external_relationship_service_v1(uuid,uuid,text,text,jsonb,jsonb) to service_role;