-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: extend bounded acquisition to geography/topology gaps.

create or replace function atlas.queue_contact_gap_acquisition_service_v1(
  p_execution_run_id uuid,
  p_gap jsonb
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_run atlas.contact_set_execution_runs%rowtype;
  v_request atlas.contact_set_intent_requests%rowtype;
  v_gap_kind text;
  v_gap_fingerprint text;
  v_attempt atlas.contact_set_acquisition_attempts%rowtype;
  v_context_id uuid;
  v_subject_kind text;
  v_entity_id uuid;
  v_missing_fields text[]:='{}'::text[];
  v_query_id uuid;
  v_work_id uuid;
  v_query_text text;
begin
  if p_gap is null or jsonb_typeof(p_gap)<>'object' then
    raise exception 'Exact contact gap object is required.' using errcode='22023';
  end if;

  select * into v_run
  from atlas.contact_set_execution_runs r
  where r.id=p_execution_run_id;
  if v_run.id is null then raise exception 'Contact-set execution run not found.' using errcode='P0002'; end if;
  if v_run.execution_state not in ('needs_acquisition','partial') then
    raise exception 'Contact-set execution run does not currently require acquisition.' using errcode='22023';
  end if;

  select * into v_request
  from atlas.contact_set_intent_requests r
  where r.id=v_run.request_id;
  if v_request.id is null or v_request.request_state<>'ready' then
    raise exception 'Ready contact-set intent request is required.' using errcode='23514';
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(coalesce(v_run.gap_snapshot->'researchTargets','[]'::jsonb)) g(value)
    where g.value=p_gap
  ) then
    raise exception 'Acquisition may be queued only for an exact persisted run gap.' using errcode='23514';
  end if;

  v_gap_kind:=nullif(btrim(p_gap->>'gapKind'),'');
  if v_gap_kind not in (
    'entity_field_gap','organization_person_gap','population_gap',
    'geography_resolution_gap','paired_operating_presence_gap'
  ) then
    raise exception 'Unsupported contact gap kind.' using errcode='22023';
  end if;

  v_gap_fingerprint:=md5(p_gap::text);
  select * into v_attempt
  from atlas.contact_set_acquisition_attempts a
  where a.execution_run_id=v_run.id and a.gap_fingerprint=v_gap_fingerprint;
  if v_attempt.id is not null then
    return jsonb_build_object(
      'ok',true,'changed',false,'contractVersion','contact_gap_acquisition_queue_v2',
      'attemptId',v_attempt.id,'executionRunId',v_attempt.execution_run_id,
      'gapKind',v_gap_kind,'gapFingerprint',v_attempt.gap_fingerprint,'status',v_attempt.status,
      'localContextId',v_attempt.local_context_id,'searchQueryId',v_attempt.search_query_id,
      'discoveryWorkId',v_attempt.discovery_work_id
    );
  end if;

  v_context_id:=local_intel.ensure_atlas_research_context_service_v1(v_run.organization_id,v_run.organization_unit_id);

  if jsonb_typeof(p_gap->'missingFields')='array' then
    select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
      into v_missing_fields
    from jsonb_array_elements_text(p_gap->'missingFields') x;
  end if;

  if cardinality(v_missing_fields)=0 then
    v_missing_fields:=case v_gap_kind
      when 'geography_resolution_gap' then array[
        'name','state','country_code','area_type','source_identity_namespace','source_identity_key'
      ]::text[]
      when 'paired_operating_presence_gap' then array[
        'name','website','operating_locations','organization_relationships'
      ]::text[]
      else v_run.required_fields
    end;
  end if;

  if v_gap_kind='entity_field_gap' then
    begin v_entity_id:=(p_gap->>'entityId')::uuid;
    exception when invalid_text_representation then
      raise exception 'entity_field_gap entityId must be UUID.' using errcode='22023';
    end;
    select e.entity_type into v_subject_kind
    from local_intel.entities e
    where e.id=v_entity_id and e.status='active';
    if v_subject_kind is null then
      raise exception 'entity_field_gap must identify an active canonical Shared Intelligence entity.' using errcode='P0002';
    end if;
  elsif v_gap_kind='organization_person_gap' then
    v_subject_kind:='person';
  elsif v_gap_kind='geography_resolution_gap' then
    v_subject_kind:='place';
  elsif v_gap_kind='paired_operating_presence_gap' then
    v_subject_kind:='organization';
  else
    v_subject_kind:=case
      when jsonb_array_length(coalesce(v_request.interpretation#>'{target,personFunctions}','[]'::jsonb))>0
        or jsonb_array_length(coalesce(v_request.interpretation#>'{target,titles}','[]'::jsonb))>0
      then 'person' else 'organization' end;
  end if;

  v_query_text:=case v_gap_kind
    when 'geography_resolution_gap' then
      'Atlas unresolved Place reference '||v_gap_fingerprint||': '||coalesce((p_gap->'placeReference')::text,'{}')
    when 'paired_operating_presence_gap' then
      'Atlas paired operating-presence gap '||v_gap_fingerprint||': '
      ||coalesce(v_request.interpretation#>>'{target,description}',v_request.literal_request)
    else
      'Atlas contact gap '||v_gap_fingerprint||': '
      ||coalesce(v_request.interpretation#>>'{target,description}',v_request.literal_request)
  end;

  insert into local_intel.search_queries(
    query_text,requested_fields,parameters,status,metadata,local_context_id
  ) values (
    v_query_text,v_missing_fields,
    jsonb_build_object(
      'acquisitionMode','gap_only','gap',p_gap,
      'target',v_request.interpretation->'target','geography',v_request.interpretation->'geography',
      'requiredFields',to_jsonb(v_run.required_fields),
      'organizationId',v_run.organization_id,'organizationUnitId',v_run.organization_unit_id
    ),
    'in_process',
    jsonb_build_object(
      'origin','atlas_contact_set','atlasRequestId',v_request.id,'atlasExecutionRunId',v_run.id,
      'gapKind',v_gap_kind,'gapFingerprint',v_gap_fingerprint,
      'identityScope','universal_shared_intelligence','localContextSemantics','research_provenance'
    ),
    v_context_id
  ) returning id into v_query_id;

  insert into local_intel.search_discovery_queue(
    search_query_id,subject_kind,criteria,status,metadata
  ) values (
    v_query_id,v_subject_kind,
    jsonb_build_object(
      'gap',p_gap,'target',v_request.interpretation->'target',
      'geography',v_request.interpretation->'geography','requestedFields',to_jsonb(v_missing_fields)
    ),
    'queued',
    jsonb_build_object(
      'origin','atlas_contact_set','atlasExecutionRunId',v_run.id,'gapKind',v_gap_kind,
      'gapFingerprint',v_gap_fingerprint,'bounded',true
    )
  ) returning id into v_work_id;

  insert into atlas.contact_set_acquisition_attempts(
    execution_run_id,organization_id,organization_unit_id,gap_fingerprint,gap,
    local_context_id,search_query_id,discovery_work_id,status
  ) values (
    v_run.id,v_run.organization_id,v_run.organization_unit_id,v_gap_fingerprint,p_gap,
    v_context_id,v_query_id,v_work_id,'queued'
  ) returning * into v_attempt;

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','contact_gap_acquisition_queue_v2',
    'attemptId',v_attempt.id,'executionRunId',v_attempt.execution_run_id,'gapKind',v_gap_kind,
    'gapFingerprint',v_attempt.gap_fingerprint,'status',v_attempt.status,
    'localContextId',v_attempt.local_context_id,'searchQueryId',v_attempt.search_query_id,
    'discoveryWorkId',v_attempt.discovery_work_id,'subjectKind',v_subject_kind,
    'requestedFields',to_jsonb(v_missing_fields),
    'truthBoundary',jsonb_build_object(
      'queueCreatesCanonicalTruth',false,'contextOwnsIdentity',false,'communicationAuthorized',false,
      'placeResearchRequiresExplicitPromotion',v_gap_kind='geography_resolution_gap'
    )
  );
end
$function$;

revoke all on function atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb) to service_role;
