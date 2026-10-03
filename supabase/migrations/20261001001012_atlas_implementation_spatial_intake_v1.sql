-- Atlas Implementation Spatial Intake v1
-- Extends the existing Reality Candidate membrane so governed implementation
-- sentences can establish operational spatial context without bypassing Reality.

alter table atlas.implementation_reality_candidates
  drop constraint if exists implementation_reality_candidates_operation_check;

alter table atlas.implementation_reality_candidates
  add constraint implementation_reality_candidates_operation_check
  check (operation_id = any(array[
    'organization.establish'::text,
    'person.establish'::text,
    'institutional_person_record.establish'::text,
    'organization_unit.establish'::text,
    'organization_position.establish'::text,
    'organization_responsibility.establish'::text,
    'position_responsibility_definition.establish'::text,
    'person_position_appointment.establish'::text,
    'spatial_context.establish'::text
  ]));

alter table atlas.implementation_reality_candidates
  drop constraint if exists implementation_reality_candidates_operation_shape;

alter table atlas.implementation_reality_candidates
  add constraint implementation_reality_candidates_operation_shape
  check (
    case operation_id
      when 'organization.establish' then
        subject_binding->>'kind'='organization' and object_binding is null and context_binding is null
      when 'person.establish' then
        subject_binding->>'kind'='person' and object_binding is null and context_binding is null
      when 'institutional_person_record.establish' then
        subject_binding->>'kind'='person' and object_binding is not null and object_binding->>'kind'='organization' and context_binding is null
      when 'organization_unit.establish' then
        subject_binding->>'kind'='organization_unit' and object_binding is not null and object_binding->>'kind'='organization'
        and (context_binding is null or context_binding->>'kind'='organization_unit')
      when 'organization_position.establish' then
        subject_binding->>'kind'='organization_position' and object_binding is not null and object_binding->>'kind'='organization_unit' and context_binding is null
      when 'organization_responsibility.establish' then
        subject_binding->>'kind'='organization_responsibility' and object_binding is not null and object_binding->>'kind'='organization' and context_binding is null
      when 'position_responsibility_definition.establish' then
        subject_binding->>'kind'='organization_position' and object_binding is not null and object_binding->>'kind'='organization_responsibility'
        and context_binding is not null and context_binding->>'kind'='organization'
      when 'person_position_appointment.establish' then
        subject_binding->>'kind'='person' and object_binding is not null and object_binding->>'kind'='organization_position'
        and context_binding is not null and context_binding->>'kind'='organization'
      when 'spatial_context.establish' then
        subject_binding->>'kind' = any(array['work_item','organization_responsibility','ledger','organization_ledger_entry'])
        and (object_binding is null or object_binding->>'kind'='place')
        and context_binding is null
      else false
    end
  );

alter table atlas.implementation_reality_candidates
  add constraint implementation_reality_candidates_spatial_semantics_v1
  check (
    operation_id <> 'spatial_context.establish'
    or (
      jsonb_typeof(semantic_payload->'spatialContext')='object'
      and semantic_payload->'spatialContext'->>'contextKind' = any(array[
        'required_at','occurs_at','observed_at','origin','destination','service_area','jurisdiction','preferred_near','base_at','location_flexibility'
      ])
      and semantic_payload->'spatialContext'->>'presenceMode' = any(array['physical','remote','either','unknown'])
      and (
        (semantic_payload->'spatialContext'->>'contextKind'='location_flexibility'
          and object_binding is null
          and semantic_payload->'spatialContext'->>'presenceMode' = any(array['remote','either']))
        or
        (semantic_payload->'spatialContext'->>'contextKind'<>'location_flexibility'
          and object_binding is not null
          and object_binding->>'kind'='place'
          and object_binding->>'resolution'='canonical'
          and nullif(btrim(coalesce(object_binding->>'canonicalId','')),'') is not null)
      )
      and (
        (subject_binding->>'kind'='work_item' and semantic_payload->'spatialContext'->>'contextKind' = any(array['required_at','occurs_at','origin','destination','preferred_near','location_flexibility']))
        or
        (subject_binding->>'kind'='organization_responsibility' and semantic_payload->'spatialContext'->>'contextKind' = any(array['required_at','service_area','jurisdiction','preferred_near','location_flexibility']))
        or
        (subject_binding->>'kind'='ledger' and semantic_payload->'spatialContext'->>'contextKind' = any(array['service_area','jurisdiction','base_at','preferred_near','location_flexibility']))
        or
        (subject_binding->>'kind'='organization_ledger_entry' and semantic_payload->'spatialContext'->>'contextKind' = any(array['observed_at','occurs_at','origin','destination']))
      )
      and (
        not (semantic_payload->'spatialContext' ? 'distanceLimitMeters')
        or semantic_payload->'spatialContext'->'distanceLimitMeters'='null'::jsonb
        or (
          semantic_payload->'spatialContext'->>'contextKind' = any(array['service_area','preferred_near'])
          and jsonb_typeof(semantic_payload->'spatialContext'->'distanceLimitMeters')='number'
          and (semantic_payload->'spatialContext'->>'distanceLimitMeters')::double precision between 0 and 25000000
        )
      )
    )
  );

create or replace function atlas.implementation_spatial_subject_scope_internal_v1(
  p_implementation_case_id uuid,
  p_subject_kind text,
  p_subject_id uuid
)
returns table(
  binding_id uuid,
  ledger_id uuid,
  organization_id uuid,
  organization_unit_id uuid,
  subject_label text,
  subject_state text
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
begin
  if p_subject_kind='work_item' then
    return query
    select b.id,b.ledger_id,b.organization_id,b.organization_unit_id,wi.title,wi.work_state
    from atlas.ledger_entitlement_bindings b
    join atlas.work_items wi
      on wi.id=p_subject_id
     and wi.organization_id=b.organization_id
     and (b.organization_unit_id is null or wi.organization_unit_id=b.organization_unit_id)
    where b.implementation_case_id=p_implementation_case_id
      and b.state in ('bound','activated') and b.ended_at is null
    order by case when b.state='activated' then 0 else 1 end,b.bound_at,b.id
    limit 1;
    return;
  end if;

  if p_subject_kind='organization_responsibility' then
    return query
    select b.id,b.ledger_id,b.organization_id,b.organization_unit_id,r.name,r.status
    from atlas.ledger_entitlement_bindings b
    join atlas.organization_responsibilities r
      on r.id=p_subject_id and r.organization_id=b.organization_id
    where b.implementation_case_id=p_implementation_case_id
      and b.state in ('bound','activated') and b.ended_at is null
    order by case when b.state='activated' then 0 else 1 end,
             case when b.organization_unit_id is null then 0 else 1 end,
             b.bound_at,b.id
    limit 1;
    return;
  end if;

  if p_subject_kind='ledger' then
    return query
    select b.id,b.ledger_id,b.organization_id,b.organization_unit_id,l.name,l.status
    from atlas.ledger_entitlement_bindings b
    join atlas.ledgers l on l.id=p_subject_id and l.id=b.ledger_id
    where b.implementation_case_id=p_implementation_case_id
      and b.state in ('bound','activated') and b.ended_at is null
    order by case when b.state='activated' then 0 else 1 end,b.bound_at,b.id
    limit 1;
    return;
  end if;

  if p_subject_kind='organization_ledger_entry' then
    return query
    select b.id,b.ledger_id,b.organization_id,b.organization_unit_id,le.title,le.truth_status
    from atlas.ledger_entitlement_bindings b
    join atlas.organization_ledger_entries le
      on le.id=p_subject_id
     and le.ledger_id=b.ledger_id
     and le.organization_id=b.organization_id
     and (b.organization_unit_id is null or le.organization_unit_id=b.organization_unit_id)
    where b.implementation_case_id=p_implementation_case_id
      and b.state in ('bound','activated') and b.ended_at is null
    order by case when b.state='activated' then 0 else 1 end,b.bound_at,b.id
    limit 1;
    return;
  end if;
end
$function$;

create or replace function atlas.implementation_spatial_semantics_check_v1(
  p_subject_kind text,
  p_context_kind text,
  p_place_entity_id uuid,
  p_presence_mode text,
  p_distance_limit_meters double precision
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','reality'
as $function$
declare
  v_kind atlas.spatial_context_kinds%rowtype;
  v_allowed boolean:=false;
begin
  select * into v_kind
  from atlas.spatial_context_kinds
  where context_kind=p_context_kind and kind_state='active';

  if v_kind.context_kind is null then
    return jsonb_build_object('ok',false,'code','spatial_context_kind_unavailable');
  end if;

  if p_presence_mode not in ('physical','remote','either','unknown') then
    return jsonb_build_object('ok',false,'code','presence_mode_invalid');
  end if;

  v_allowed:=case p_subject_kind
    when 'work_item' then p_context_kind=any(array['required_at','occurs_at','origin','destination','preferred_near','location_flexibility'])
    when 'organization_responsibility' then p_context_kind=any(array['required_at','service_area','jurisdiction','preferred_near','location_flexibility'])
    when 'ledger' then p_context_kind=any(array['service_area','jurisdiction','base_at','preferred_near','location_flexibility'])
    when 'organization_ledger_entry' then p_context_kind=any(array['observed_at','occurs_at','origin','destination'])
    else false
  end;

  if not v_allowed then
    return jsonb_build_object('ok',false,'code','subject_context_pair_not_supported');
  end if;

  if v_kind.requires_place and p_place_entity_id is null then
    return jsonb_build_object('ok',false,'code','canonical_place_required');
  end if;
  if not v_kind.requires_place and p_place_entity_id is not null then
    return jsonb_build_object('ok',false,'code','place_not_permitted_for_context');
  end if;
  if p_context_kind='location_flexibility' and p_presence_mode not in ('remote','either') then
    return jsonb_build_object('ok',false,'code','location_flexibility_requires_remote_or_either');
  end if;
  if p_context_kind in ('required_at','occurs_at','observed_at','origin','destination','base_at') and p_presence_mode='remote' then
    return jsonb_build_object('ok',false,'code','physical_context_cannot_be_remote_only');
  end if;
  if p_distance_limit_meters is not null and not v_kind.allows_distance_limit then
    return jsonb_build_object('ok',false,'code','distance_limit_not_permitted');
  end if;
  if p_distance_limit_meters is not null and (p_distance_limit_meters<0 or p_distance_limit_meters>25000000) then
    return jsonb_build_object('ok',false,'code','distance_limit_out_of_range');
  end if;

  if p_place_entity_id is not null and not exists(
    select 1 from reality.entities e
    join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
    where e.id=p_place_entity_id and e.entity_kind='place' and e.identity_state='canonical'
  ) then
    return jsonb_build_object('ok',false,'code','canonical_place_unavailable');
  end if;

  return jsonb_build_object('ok',true,'code','ready');
end
$function$;

create or replace function atlas.implementation_spatial_subject_options_self_api_v1(
  p_implementation_case_id uuid,
  p_subject_kind text,
  p_query text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_items jsonb;
  v_q text:=lower(btrim(coalesce(p_query,'')));
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(p_implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;
  if p_subject_kind not in ('work_item','organization_responsibility','ledger','organization_ledger_entry') then
    raise exception 'Unsupported spatial sentence subject kind.' using errcode='22023';
  end if;
  if p_limit<1 or p_limit>100 then raise exception 'Limit must be between 1 and 100.' using errcode='22023'; end if;

  with active_bindings as (
    select b.* from atlas.ledger_entitlement_bindings b
    where b.implementation_case_id=p_implementation_case_id
      and b.state in ('bound','activated') and b.ended_at is null
  ), options as (
    select 'work_item'::text subject_kind,wi.id subject_id,wi.title label,
           coalesce(wi.operation_class,'work') detail,wi.organization_id,b.ledger_id,wi.work_state subject_state
    from active_bindings b join atlas.work_items wi
      on wi.organization_id=b.organization_id
     and (b.organization_unit_id is null or wi.organization_unit_id=b.organization_unit_id)
    where p_subject_kind='work_item' and wi.work_state='open'

    union all

    select 'organization_responsibility',r.id,r.name,coalesce(r.responsibility_kind,'responsibility'),r.organization_id,b.ledger_id,r.status
    from active_bindings b join atlas.organization_responsibilities r on r.organization_id=b.organization_id
    where p_subject_kind='organization_responsibility' and r.status='active'

    union all

    select 'ledger',l.id,l.name,l.ledger_kind,b.organization_id,l.id,l.status
    from active_bindings b join atlas.ledgers l on l.id=b.ledger_id
    where p_subject_kind='ledger' and l.status='active'

    union all

    select 'organization_ledger_entry',le.id,le.title,coalesce(le.semantic_type,'ledger entry'),le.organization_id,le.ledger_id,le.truth_status
    from active_bindings b join atlas.organization_ledger_entries le
      on le.ledger_id=b.ledger_id and le.organization_id=b.organization_id
     and (b.organization_unit_id is null or le.organization_unit_id=b.organization_unit_id)
    where p_subject_kind='organization_ledger_entry'
  ), deduped as (
    select distinct on (subject_kind,subject_id) * from options
    where v_q='' or lower(label) like '%'||v_q||'%' or lower(detail) like '%'||v_q||'%'
    order by subject_kind,subject_id,label
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'subjectKind',subject_kind,'subjectId',subject_id,'label',label,'detail',detail,
    'organizationId',organization_id,'ledgerId',ledger_id,'state',subject_state
  ) order by label,subject_id),'[]'::jsonb)
  into v_items
  from (select * from deduped order by label,subject_id limit p_limit) x;

  return jsonb_build_object('ok',true,'contractVersion','implementation_spatial_subject_options_v1','items',v_items);
end
$function$;

create or replace function atlas.implementation_place_options_self_api_v1(
  p_implementation_case_id uuid,
  p_query text,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','reality','geography','auth'
as $function$
declare
  v_q text:=lower(btrim(coalesce(p_query,'')));
  v_items jsonb;
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(p_implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;
  if char_length(v_q)<2 then
    return jsonb_build_object('ok',true,'contractVersion','implementation_place_options_v1','items','[]'::jsonb,'queryState','more_characters_required');
  end if;
  if p_limit<1 or p_limit>50 then raise exception 'Limit must be between 1 and 50.' using errcode='22023'; end if;

  with places as (
    select distinct on (e.id)
      e.id,e.display_name,pp.place_kind,pp.country_code,
      g.dataset_key,g.source_feature_key,g.administrative_codes
    from reality.entities e
    join reality.place_profiles pp on pp.entity_id=e.id and pp.profile_state='active'
    left join geography.v_canonical_place_geometry_v1 g on g.place_entity_id=e.id
    where e.entity_kind='place' and e.identity_state='canonical'
      and lower(e.display_name) like '%'||v_q||'%'
    order by e.id,g.geometry_priority nulls last,g.source_vintage desc nulls last,g.source_feature_key
    limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'placeEntityId',id,'displayName',display_name,'placeKind',place_kind,'countryCode',country_code,
    'datasetKey',dataset_key,'sourceFeatureKey',source_feature_key,'administrativeCodes',coalesce(administrative_codes,'{}'::jsonb)
  ) order by display_name,id),'[]'::jsonb)
  into v_items from places;

  return jsonb_build_object('ok',true,'contractVersion','implementation_place_options_v1','items',v_items,'queryState','ready');
end
$function$;

create or replace function atlas.create_implementation_spatial_candidate_self_api_v1(
  p_implementation_case_id uuid,
  p_subject_kind text,
  p_subject_id uuid,
  p_context_kind text,
  p_place_entity_id uuid default null,
  p_presence_mode text default 'physical',
  p_distance_limit_meters double precision default null,
  p_literal_statement text default null,
  p_implementation_thread_id uuid default null,
  p_basis_kind text default 'reconstruction_of_existing_reality'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','reality','auth'
as $function$
declare
  v_scope record;
  v_semantics jsonb;
  v_place reality.entities%rowtype;
  v_object jsonb;
  v_statement text;
  v_phrase text;
  v_result jsonb;
begin
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(p_implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;

  select * into v_scope
  from atlas.implementation_spatial_subject_scope_internal_v1(p_implementation_case_id,p_subject_kind,p_subject_id)
  limit 1;
  if v_scope.binding_id is null then raise exception 'Spatial subject is outside the active Implementation scope.' using errcode='42501'; end if;

  v_semantics:=atlas.implementation_spatial_semantics_check_v1(p_subject_kind,p_context_kind,p_place_entity_id,p_presence_mode,p_distance_limit_meters);
  if coalesce((v_semantics->>'ok')::boolean,false)=false then
    raise exception 'Spatial sentence is not valid: %',v_semantics->>'code' using errcode='22023';
  end if;

  if p_basis_kind not in ('explicit_acceptance','standing_intake','reconstruction_of_existing_reality','adjudicated_existing_reality','other_governed_basis') then
    raise exception 'Unsupported establishment basis.' using errcode='22023';
  end if;

  if p_place_entity_id is not null then
    select * into v_place from reality.entities where id=p_place_entity_id and entity_kind='place' and identity_state='canonical';
    v_object:=jsonb_build_object('kind','place','label',v_place.display_name,'resolution','canonical','canonicalId',v_place.id);
  else
    v_object:=null;
  end if;

  v_phrase:=case p_context_kind
    when 'required_at' then 'must happen at'
    when 'occurs_at' then 'happens at'
    when 'observed_at' then 'was observed at'
    when 'origin' then 'starts at'
    when 'destination' then 'goes to'
    when 'service_area' then 'covers'
    when 'jurisdiction' then 'is governed in'
    when 'preferred_near' then 'should happen near'
    when 'base_at' then 'operates from'
    when 'location_flexibility' then 'can happen anywhere'
    else p_context_kind
  end;

  v_statement:=nullif(btrim(coalesce(p_literal_statement,'')),'');
  if v_statement is null then
    v_statement:=v_scope.subject_label || ' ' || v_phrase || case when v_place.id is null then '' else ' '||v_place.display_name end || '.';
  end if;

  v_result:=atlas.create_implementation_reality_candidate_self_api_v2(
    p_implementation_case_id,
    'spatial_context.establish',
    'manual_semantic_construction',
    v_statement,
    jsonb_build_object('kind',p_subject_kind,'label',v_scope.subject_label,'resolution','canonical','canonicalId',p_subject_id),
    p_implementation_thread_id,
    v_object,
    null,
    jsonb_build_object(
      'spatialContext',jsonb_strip_nulls(jsonb_build_object(
        'contextKind',p_context_kind,
        'presenceMode',p_presence_mode,
        'distanceLimitMeters',p_distance_limit_meters
      )),
      'scope',jsonb_build_object(
        'ledgerEntitlementBindingId',v_scope.binding_id,
        'ledgerId',v_scope.ledger_id,
        'organizationId',v_scope.organization_id,
        'organizationUnitId',v_scope.organization_unit_id
      ),
      'truthBoundary',jsonb_build_object(
        'operationalSpatialContextOnly',true,
        'entityLocationNotEstablished',true,
        'candidateDoesNotMutateOperationalState',true
      )
    ),
    '[]'::jsonb,
    jsonb_build_object('kind',p_basis_kind,'source','implementation_spatial_sentence_builder_v1'),
    'proposed'
  );

  return v_result || jsonb_build_object('operationId','spatial_context.establish','literalStatement',v_statement);
end
$function$;

create or replace function atlas.preview_implementation_spatial_candidate_promotion_self_api_v1(p_candidate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','reality','auth'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_subject_id uuid;
  v_place_id uuid;
  v_scope record;
  v_semantics jsonb;
  v_context jsonb;
  v_context_kind text;
  v_presence_mode text;
  v_distance double precision;
  v_sponsor_participant_id uuid;
  v_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_place_name text;
  v_basis_kind text;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select c.* into v_candidate
  from atlas.implementation_reality_candidates c
  join atlas.implementation_cases ic on ic.id=c.implementation_case_id and ic.state not in ('closed','cancelled')
  where c.id=p_candidate_id;
  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;
  if v_candidate.operation_id<>'spatial_context.establish' then
    raise exception 'Spatial Reality Candidate required.' using errcode='22023';
  end if;

  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,'state','already_promoted','canPromote',false,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,'canonicalConsequenceRef',v_candidate.canonical_consequence_ref);
  end if;
  if v_candidate.candidate_state not in ('proposed','unresolved') then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,'state','candidate_not_promotable','canPromote',false,'reason','candidate_state_'||v_candidate.candidate_state);
  end if;

  begin v_subject_id:=(v_candidate.subject_binding->>'canonicalId')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_binding_invalid','canPromote',false,'slot','subject');
  end;

  select * into v_scope from atlas.implementation_spatial_subject_scope_internal_v1(v_candidate.implementation_case_id,v_candidate.subject_binding->>'kind',v_subject_id) limit 1;
  if v_scope.binding_id is null then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','outside_implementation_scope','canPromote',false);
  end if;

  v_context:=v_candidate.semantic_payload->'spatialContext';
  v_context_kind:=v_context->>'contextKind';
  v_presence_mode:=v_context->>'presenceMode';
  if v_context ? 'distanceLimitMeters' and v_context->'distanceLimitMeters'<>'null'::jsonb then v_distance:=(v_context->>'distanceLimitMeters')::double precision; end if;

  if v_candidate.object_binding is not null then
    begin v_place_id:=(v_candidate.object_binding->>'canonicalId')::uuid;
    exception when invalid_text_representation then
      return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','canonical_binding_invalid','canPromote',false,'slot','object');
    end;
    select display_name into v_place_name from reality.entities where id=v_place_id and entity_kind='place' and identity_state='canonical';
  end if;

  v_semantics:=atlas.implementation_spatial_semantics_check_v1(v_candidate.subject_binding->>'kind',v_context_kind,v_place_id,v_presence_mode,v_distance);
  if coalesce((v_semantics->>'ok')::boolean,false)=false then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','spatial_semantics_invalid','canPromote',false,'reason',v_semantics->>'code');
  end if;

  select cp.id,cp.human_user_id into v_sponsor_participant_id,v_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=v_candidate.implementation_case_id
    and cp.relationship_kind='setup_sponsor' and cp.active and cp.ended_at is null and cp.verified_at is not null
  order by cp.started_at,cp.id limit 1;
  if v_sponsor_participant_id is null then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','setup_sponsor_authority_required','canPromote',false);
  end if;

  select pac.person_id into v_sponsor_person_id
  from atlas.person_auth_credentials pac join atlas.people p on p.id=pac.person_id and p.status='active'
  where pac.auth_user_id=v_sponsor_user_id and pac.status='active'
  order by pac.bound_at,pac.id limit 1;
  select p.id into v_sponsor_principal_id from atlas.principals p where p.person_id=v_sponsor_person_id and p.status='active' order by p.created_at,p.id limit 1;
  if v_sponsor_principal_id is null or not atlas.principal_has_ledger_authority_v1(v_sponsor_principal_id,v_scope.ledger_id) then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','setup_sponsor_authority_required','canPromote',false,'reason','verified_setup_sponsor_principal_must_govern_bound_ledger');
  end if;

  v_basis_kind:=v_candidate.establishment_basis->>'kind';
  if v_candidate.establishment_basis is null or jsonb_typeof(v_candidate.establishment_basis)<>'object'
     or v_basis_kind not in ('explicit_acceptance','standing_intake','reconstruction_of_existing_reality','adjudicated_existing_reality','other_governed_basis') then
    return jsonb_build_object('ok',true,'candidateId',v_candidate.id,'state','establishment_basis_required','canPromote',false);
  end if;

  return jsonb_build_object(
    'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,'state','ready','canPromote',true,
    'literalStatement',v_candidate.literal_statement,
    'scope',jsonb_build_object(
      'implementationCaseId',v_candidate.implementation_case_id,
      'setupSponsorParticipantId',v_sponsor_participant_id,
      'setupSponsorPrincipalId',v_sponsor_principal_id,
      'ledgerEntitlementBindingId',v_scope.binding_id,
      'ledgerId',v_scope.ledger_id,
      'organizationId',v_scope.organization_id,
      'organizationUnitId',v_scope.organization_unit_id
    ),
    'consequence',jsonb_strip_nulls(jsonb_build_object(
      'kind','atlas_spatial_context','subjectKind',v_candidate.subject_binding->>'kind','subjectId',v_subject_id,'subjectLabel',v_scope.subject_label,
      'contextKind',v_context_kind,'placeEntityId',v_place_id,'placeName',v_place_name,'presenceMode',v_presence_mode,'distanceLimitMeters',v_distance
    )),
    'truthBoundary',jsonb_build_object(
      'candidateDoesNotMutateOperationalState',true,
      'entityLocationNotEstablished',true,
      'geodesicDistanceDoesNotMeanTravelTime',true,
      'promotionEstablishesAtlasOperationalContext',true
    )
  );
end
$function$;

create or replace function atlas.promote_implementation_spatial_candidate_self_api_v1(p_candidate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_context jsonb;
  v_receipt jsonb;
  v_context_id uuid;
  v_subject_id uuid;
  v_place_id uuid;
  v_distance double precision;
  v_basis jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select c.* into v_candidate
  from atlas.implementation_reality_candidates c
  join atlas.implementation_cases ic on ic.id=c.implementation_case_id and ic.state not in ('closed','cancelled')
  where c.id=p_candidate_id for update of c;
  if v_candidate.id is null then raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503'; end if;
  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;
  if v_candidate.operation_id<>'spatial_context.establish' then raise exception 'Spatial Reality Candidate required.' using errcode='22023'; end if;

  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object('ok',true,'promoted',true,'alreadyPromoted',true,'candidateId',v_candidate.id,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,'canonicalConsequenceRef',v_candidate.canonical_consequence_ref);
  end if;

  v_preview:=atlas.preview_implementation_spatial_candidate_promotion_self_api_v1(v_candidate.id);
  if v_preview->>'state'<>'ready' then
    if v_preview->>'state' in ('canonical_binding_invalid','outside_implementation_scope','spatial_semantics_invalid','setup_sponsor_authority_required','establishment_basis_required') then
      update atlas.implementation_reality_candidates set candidate_state='unresolved',updated_at=now() where id=v_candidate.id;
    end if;
    return jsonb_build_object('ok',false,'promoted',false,'candidateId',v_candidate.id,'preview',v_preview);
  end if;

  v_subject_id:=(v_candidate.subject_binding->>'canonicalId')::uuid;
  v_context:=v_candidate.semantic_payload->'spatialContext';
  if v_candidate.object_binding is not null then v_place_id:=(v_candidate.object_binding->>'canonicalId')::uuid; end if;
  if v_context ? 'distanceLimitMeters' and v_context->'distanceLimitMeters'<>'null'::jsonb then v_distance:=(v_context->>'distanceLimitMeters')::double precision; end if;

  v_basis:=v_candidate.establishment_basis || jsonb_build_object(
    'contractVersion','implementation_spatial_context_promotion_v1',
    'source','implementation_reality_candidate',
    'implementationCaseId',v_candidate.implementation_case_id,
    'realityCandidateId',v_candidate.id,
    'candidateOrigin',v_candidate.origin_kind,
    'candidateAuthorUserId',v_candidate.author_user_id,
    'promotedByUserId',v_uid,
    'literalStatement',v_candidate.literal_statement,
    'scope',v_preview->'scope'
  );

  v_receipt:=atlas.put_spatial_context_service_v1(
    'implementation.spatial:'||v_candidate.id::text,
    v_candidate.subject_binding->>'kind',v_subject_id,v_context->>'contextKind',v_place_id,v_context->>'presenceMode',v_distance,
    null,null,(v_preview->'scope'->>'organizationId')::uuid,v_basis,
    jsonb_build_object('implementationRealityCandidateId',v_candidate.id,'literalStatement',v_candidate.literal_statement)
  );
  v_context_id:=(v_receipt->>'contextId')::uuid;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',canonical_consequence_kind='atlas_spatial_context',canonical_consequence_ref=v_context_id::text,
      promoted_at=now(),promoted_by_user_id=v_uid,
      provenance=provenance||jsonb_build_object('promotionContract','implementation_spatial_context_promotion_v1','promotionReceipt',v_receipt),
      updated_at=now()
  where id=v_candidate.id;

  return jsonb_build_object(
    'ok',true,'promoted',true,'alreadyPromoted',false,'candidateId',v_candidate.id,'receipt',v_receipt,
    'canonicalConsequenceKind','atlas_spatial_context','canonicalConsequenceRef',v_context_id::text,
    'truthBoundary',jsonb_build_object('realityEntityTruthMutated',false,'atlasOperationalSpatialTruthEstablished',true)
  );
end
$function$;

create or replace function atlas.preview_implementation_reality_candidate_promotion_self_api_v2(p_candidate_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare v_operation text;
begin
  select operation_id into v_operation from atlas.implementation_reality_candidates where id=p_candidate_id;
  if v_operation='spatial_context.establish' then return atlas.preview_implementation_spatial_candidate_promotion_self_api_v1(p_candidate_id); end if;
  return atlas.preview_implementation_reality_candidate_promotion_self_api_v1(p_candidate_id);
end
$function$;

create or replace function atlas.promote_implementation_reality_candidate_self_api_v2(p_candidate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare v_operation text;
begin
  select operation_id into v_operation from atlas.implementation_reality_candidates where id=p_candidate_id;
  if v_operation='spatial_context.establish' then return atlas.promote_implementation_spatial_candidate_self_api_v1(p_candidate_id); end if;
  return atlas.promote_implementation_reality_candidate_self_api_v1(p_candidate_id);
end
$function$;

revoke all on function atlas.implementation_spatial_subject_scope_internal_v1(uuid,text,uuid) from public,anon,authenticated;
revoke all on function atlas.implementation_spatial_semantics_check_v1(text,text,uuid,text,double precision) from public,anon,authenticated;
revoke all on function atlas.implementation_spatial_subject_options_self_api_v1(uuid,text,text,integer) from public,anon;
revoke all on function atlas.implementation_place_options_self_api_v1(uuid,text,integer) from public,anon;
revoke all on function atlas.create_implementation_spatial_candidate_self_api_v1(uuid,text,uuid,text,uuid,text,double precision,text,uuid,text) from public,anon;
revoke all on function atlas.preview_implementation_spatial_candidate_promotion_self_api_v1(uuid) from public,anon;
revoke all on function atlas.promote_implementation_spatial_candidate_self_api_v1(uuid) from public,anon;
revoke all on function atlas.preview_implementation_reality_candidate_promotion_self_api_v2(uuid) from public,anon;
revoke all on function atlas.promote_implementation_reality_candidate_self_api_v2(uuid) from public,anon;

grant execute on function atlas.implementation_spatial_subject_scope_internal_v1(uuid,text,uuid) to service_role;
grant execute on function atlas.implementation_spatial_semantics_check_v1(text,text,uuid,text,double precision) to service_role;
grant execute on function atlas.implementation_spatial_subject_options_self_api_v1(uuid,text,text,integer) to authenticated,service_role;
grant execute on function atlas.implementation_place_options_self_api_v1(uuid,text,integer) to authenticated,service_role;
grant execute on function atlas.create_implementation_spatial_candidate_self_api_v1(uuid,text,uuid,text,uuid,text,double precision,text,uuid,text) to authenticated,service_role;
grant execute on function atlas.preview_implementation_spatial_candidate_promotion_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.promote_implementation_spatial_candidate_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.preview_implementation_reality_candidate_promotion_self_api_v2(uuid) to authenticated,service_role;
grant execute on function atlas.promote_implementation_reality_candidate_self_api_v2(uuid) to authenticated,service_role;
