begin;

create table if not exists atlas.contact_set_acquisition_attempts (
  id uuid primary key default gen_random_uuid(),
  execution_run_id uuid not null references atlas.contact_set_execution_runs(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid null,
  gap_fingerprint text not null,
  gap jsonb not null,
  local_context_id uuid not null references local_intel.local_contexts(id) on delete restrict,
  search_query_id uuid not null references local_intel.search_queries(id) on delete restrict,
  discovery_work_id uuid not null references local_intel.search_discovery_queue(id) on delete restrict,
  status text not null default 'queued',
  provider_key text null,
  model_ref text null,
  provider_response_id text null,
  source_set jsonb not null default '[]'::jsonb,
  result_summary jsonb not null default '{}'::jsonb,
  queued_at timestamptz not null default now(),
  started_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contact_set_acquisition_attempts_gap_fingerprint_nonblank check (btrim(gap_fingerprint)<>''),
  constraint contact_set_acquisition_attempts_gap_object check (jsonb_typeof(gap)='object'),
  constraint contact_set_acquisition_attempts_status_check check (
    status in ('queued','in_process','complete','failed','cancelled')
  ),
  constraint contact_set_acquisition_attempts_source_set_array check (jsonb_typeof(source_set)='array'),
  constraint contact_set_acquisition_attempts_result_summary_object check (jsonb_typeof(result_summary)='object'),
  constraint contact_set_acquisition_attempts_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  unique(execution_run_id,gap_fingerprint)
);

create index if not exists contact_set_acquisition_attempts_org_status_idx
  on atlas.contact_set_acquisition_attempts(organization_id,status,queued_at desc);

create index if not exists contact_set_acquisition_attempts_work_idx
  on atlas.contact_set_acquisition_attempts(discovery_work_id);

create index if not exists search_queries_atlas_contact_gap_idx
  on local_intel.search_queries(
    ((metadata->>'atlasExecutionRunId')),
    ((metadata->>'gapFingerprint'))
  )
  where metadata ? 'atlasExecutionRunId' and metadata ? 'gapFingerprint';

alter table atlas.contact_set_acquisition_attempts enable row level security;
revoke all on table atlas.contact_set_acquisition_attempts from public,anon,authenticated,service_role;

comment on table atlas.contact_set_acquisition_attempts is
'Organization-private durable bridge from one exact Atlas contact-set gap to one bounded Shared Intelligence research query/work item. Owns research provenance, not external-world truth.';
comment on column atlas.contact_set_acquisition_attempts.source_set is
'Machine-returned web source URLs and source metadata. Findings are accepted only when their sourceUrl occurs in this set.';

create or replace function local_intel.ensure_atlas_research_context_service_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_key text;
  v_name text;
  v_context local_intel.local_contexts%rowtype;
begin
  if not exists(
    select 1 from atlas.organizations o
    where o.id=p_organization_id and o.status='active'
  ) then
    raise exception 'Active Atlas Organization is required.' using errcode='P0002';
  end if;

  if p_organization_unit_id is not null and not exists(
    select 1 from atlas.organization_units u
    where u.id=p_organization_unit_id
      and u.organization_id=p_organization_id
      and u.status<>'archived'
  ) then
    raise exception 'Organization Unit is outside Organization or archived.' using errcode='23514';
  end if;

  v_key:='atlas-research-'||p_organization_id::text
    ||case when p_organization_unit_id is null then '' else '-unit-'||p_organization_unit_id::text end;

  select coalesce(o.name,'Atlas Organization')
    ||case
      when p_organization_unit_id is null then ' Shared Intelligence Research'
      else ' / '||coalesce(u.name,'Organization Unit')||' Shared Intelligence Research'
    end
  into v_name
  from atlas.organizations o
  left join atlas.organization_units u on u.id=p_organization_unit_id
  where o.id=p_organization_id;

  insert into local_intel.local_contexts(
    stable_key,organization_id,organization_unit_id,name,status,metadata
  ) values (
    v_key,p_organization_id,p_organization_unit_id,v_name,'active',
    jsonb_build_object(
      'purpose','atlas_shared_intelligence_research',
      'identitySemantics','research_provenance_not_identity_ownership',
      'managedBy','shared_atlas_contact_gap_acquisition_membrane_v1'
    )
  )
  on conflict(stable_key) do update
    set status='active',
        metadata=local_intel.local_contexts.metadata||excluded.metadata,
        updated_at=now();

  select * into v_context
  from local_intel.local_contexts c
  where c.stable_key=v_key;

  if v_context.organization_id is distinct from p_organization_id
     or v_context.organization_unit_id is distinct from p_organization_unit_id then
    raise exception 'Deterministic Atlas research context key is bound to different custody.' using errcode='23505';
  end if;

  return v_context.id;
end;
$function$;

revoke all on function local_intel.ensure_atlas_research_context_service_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

comment on function local_intel.ensure_atlas_research_context_service_v1(uuid,uuid) is
'Private Shared Intelligence helper establishing one deterministic research-provenance context per Atlas Organization/Unit. Context never owns canonical identity.';

create or replace function atlas.queue_contact_gap_acquisition_service_v1(
  p_execution_run_id uuid,
  p_gap jsonb
)
returns jsonb
language plpgsql
security definer
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

  if v_run.id is null then
    raise exception 'Contact-set execution run not found.' using errcode='P0002';
  end if;
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
  if v_gap_kind not in ('entity_field_gap','organization_person_gap','population_gap') then
    raise exception 'Unsupported contact gap kind.' using errcode='22023';
  end if;

  v_gap_fingerprint:=md5(p_gap::text);

  select * into v_attempt
  from atlas.contact_set_acquisition_attempts a
  where a.execution_run_id=v_run.id
    and a.gap_fingerprint=v_gap_fingerprint;

  if v_attempt.id is not null then
    return jsonb_build_object(
      'ok',true,
      'changed',false,
      'contractVersion','contact_gap_acquisition_queue_v1',
      'attemptId',v_attempt.id,
      'executionRunId',v_attempt.execution_run_id,
      'gapFingerprint',v_attempt.gap_fingerprint,
      'status',v_attempt.status,
      'localContextId',v_attempt.local_context_id,
      'searchQueryId',v_attempt.search_query_id,
      'discoveryWorkId',v_attempt.discovery_work_id
    );
  end if;

  v_context_id:=local_intel.ensure_atlas_research_context_service_v1(
    v_run.organization_id,
    v_run.organization_unit_id
  );

  if jsonb_typeof(p_gap->'missingFields')='array' then
    select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
      into v_missing_fields
    from jsonb_array_elements_text(p_gap->'missingFields') x;
  end if;
  if cardinality(v_missing_fields)=0 then
    v_missing_fields:=v_run.required_fields;
  end if;

  if v_gap_kind='entity_field_gap' then
    begin
      v_entity_id:=(p_gap->>'entityId')::uuid;
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
  else
    v_subject_kind:=case
      when jsonb_array_length(coalesce(v_request.interpretation#>'{target,personFunctions}','[]'::jsonb))>0
        or jsonb_array_length(coalesce(v_request.interpretation#>'{target,titles}','[]'::jsonb))>0
      then 'person'
      else 'organization'
    end;
  end if;

  v_query_text:='Atlas contact gap '||v_gap_fingerprint||': '
    ||coalesce(v_request.interpretation#>>'{target,description}',v_request.literal_request);

  insert into local_intel.search_queries(
    query_text,requested_fields,parameters,status,metadata,local_context_id
  ) values (
    v_query_text,
    v_missing_fields,
    jsonb_build_object(
      'acquisitionMode','gap_only',
      'gap',p_gap,
      'target',v_request.interpretation->'target',
      'geography',v_request.interpretation->'geography',
      'requiredFields',to_jsonb(v_run.required_fields),
      'organizationId',v_run.organization_id,
      'organizationUnitId',v_run.organization_unit_id
    ),
    'in_process',
    jsonb_build_object(
      'origin','atlas_contact_set',
      'atlasRequestId',v_request.id,
      'atlasExecutionRunId',v_run.id,
      'gapFingerprint',v_gap_fingerprint,
      'identityScope','universal_shared_intelligence',
      'localContextSemantics','research_provenance'
    ),
    v_context_id
  )
  returning id into v_query_id;

  insert into local_intel.search_discovery_queue(
    search_query_id,subject_kind,criteria,status,metadata
  ) values (
    v_query_id,
    v_subject_kind,
    jsonb_build_object(
      'gap',p_gap,
      'target',v_request.interpretation->'target',
      'geography',v_request.interpretation->'geography',
      'requestedFields',to_jsonb(v_missing_fields)
    ),
    'queued',
    jsonb_build_object(
      'origin','atlas_contact_set',
      'atlasExecutionRunId',v_run.id,
      'gapFingerprint',v_gap_fingerprint,
      'bounded',true
    )
  )
  returning id into v_work_id;

  insert into atlas.contact_set_acquisition_attempts(
    execution_run_id,organization_id,organization_unit_id,gap_fingerprint,gap,
    local_context_id,search_query_id,discovery_work_id,status
  ) values (
    v_run.id,v_run.organization_id,v_run.organization_unit_id,v_gap_fingerprint,p_gap,
    v_context_id,v_query_id,v_work_id,'queued'
  )
  returning * into v_attempt;

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','contact_gap_acquisition_queue_v1',
    'attemptId',v_attempt.id,
    'executionRunId',v_attempt.execution_run_id,
    'gapFingerprint',v_attempt.gap_fingerprint,
    'status',v_attempt.status,
    'localContextId',v_attempt.local_context_id,
    'searchQueryId',v_attempt.search_query_id,
    'discoveryWorkId',v_attempt.discovery_work_id,
    'subjectKind',v_subject_kind,
    'requestedFields',to_jsonb(v_missing_fields),
    'truthBoundary',jsonb_build_object(
      'queueCreatesCanonicalTruth',false,
      'contextOwnsIdentity',false,
      'communicationAuthorized',false
    )
  );
end;
$function$;

revoke all on function atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb)
  to service_role;

create or replace function local_intel.register_atlas_contact_web_source_v1(
  p_source jsonb,
  p_attempt_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_url text:=nullif(btrim(p_source->>'url'),'');
  v_kind text:=coalesce(nullif(btrim(p_source->>'sourceKind'),''),'web_search_result');
  v_publisher text:=nullif(btrim(p_source->>'publisher'),'');
  v_title text:=nullif(btrim(p_source->>'title'),'');
  v_source_date date;
  v_id uuid;
begin
  if v_url is null or v_url !~* '^https?://[^[:space:]]+$' then
    raise exception 'Web source URL must be absolute http/https.' using errcode='22023';
  end if;

  if nullif(p_source->>'sourceDate','') is not null then
    begin
      v_source_date:=(p_source->>'sourceDate')::date;
    exception when others then
      raise exception 'sourceDate must be YYYY-MM-DD when supplied.' using errcode='22023';
    end;
  end if;

  if not exists(
    select 1 from atlas.contact_set_acquisition_attempts a where a.id=p_attempt_id
  ) then
    raise exception 'Contact acquisition attempt not found.' using errcode='P0002';
  end if;

  insert into local_intel.sources(
    source_url,source_kind,publisher,title,source_date,retrieved_at,metadata
  ) values (
    v_url,v_kind,v_publisher,v_title,v_source_date,now(),
    jsonb_build_object(
      'origin','atlas_contact_gap_acquisition',
      'atlasAcquisitionAttemptId',p_attempt_id
    )
  )
  on conflict(source_url) do update
    set source_kind=coalesce(nullif(local_intel.sources.source_kind,''),excluded.source_kind),
        publisher=coalesce(local_intel.sources.publisher,excluded.publisher),
        title=coalesce(local_intel.sources.title,excluded.title),
        source_date=coalesce(local_intel.sources.source_date,excluded.source_date),
        retrieved_at=now(),
        metadata=local_intel.sources.metadata||excluded.metadata
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function local_intel.register_atlas_contact_web_source_v1(jsonb,uuid)
  from public,anon,authenticated,service_role;

create or replace function atlas.record_contact_gap_acquisition_service_v1(
  p_execution_run_id uuid,
  p_discovery_work_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_attempt atlas.contact_set_acquisition_attempts%rowtype;
  v_work local_intel.search_discovery_queue%rowtype;
  v_query local_intel.search_queries%rowtype;
  v_sources jsonb:=coalesce(p_payload->'sources','[]'::jsonb);
  v_findings jsonb:=coalesce(p_payload->'findings','[]'::jsonb);
  v_outcome text:=coalesce(nullif(btrim(p_payload->>'outcome'),''),'no_qualifying_public_evidence');
  v_provider text:=coalesce(nullif(btrim(p_payload->>'providerKey'),''),'ai_gateway');
  v_model text:=nullif(btrim(p_payload->>'modelRef'),'');
  v_response_id text:=nullif(btrim(p_payload->>'providerResponseId'),'');
  v_payload_hash text:=md5(coalesce(p_payload,'{}'::jsonb)::text);
  v_source jsonb;
  v_finding jsonb;
  v_source_id uuid;
  v_source_url text;
  v_subject_kind text;
  v_entity_id uuid;
  v_org_entity_id uuid;
  v_source_record_key text;
  v_ingest_payload jsonb;
  v_ingest_result jsonb;
  v_results jsonb:='[]'::jsonb;
  v_resolver jsonb;
  v_index integer:=0;
  v_gap_kind text;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Acquisition result payload must be an object.' using errcode='22023';
  end if;
  if jsonb_typeof(v_sources)<>'array' or jsonb_typeof(v_findings)<>'array' then
    raise exception 'sources and findings must be arrays.' using errcode='22023';
  end if;
  if jsonb_array_length(v_sources)>50 or jsonb_array_length(v_findings)>50 then
    raise exception 'One bounded acquisition attempt may include at most 50 sources/findings.' using errcode='22023';
  end if;
  if v_outcome not in ('evidence_found','no_qualifying_public_evidence','ambiguous','source_unavailable','blocked') then
    raise exception 'Unsupported acquisition outcome.' using errcode='22023';
  end if;
  if v_outcome='evidence_found' and jsonb_array_length(v_findings)=0 then
    raise exception 'evidence_found requires at least one source-backed finding.' using errcode='22023';
  end if;
  if v_outcome='no_qualifying_public_evidence' and jsonb_array_length(v_findings)>0 then
    raise exception 'no_qualifying_public_evidence cannot include findings.' using errcode='22023';
  end if;

  select * into v_attempt
  from atlas.contact_set_acquisition_attempts a
  where a.execution_run_id=p_execution_run_id
    and a.discovery_work_id=p_discovery_work_id
  for update;

  if v_attempt.id is null then
    raise exception 'Acquisition work is not bound to this execution run.' using errcode='P0002';
  end if;

  if v_attempt.status='complete' then
    if v_attempt.result_summary->>'payloadHash'=v_payload_hash then
      return jsonb_build_object(
        'ok',true,'changed',false,
        'contractVersion','contact_gap_acquisition_record_v1',
        'attemptId',v_attempt.id,
        'status',v_attempt.status,
        'resultSummary',v_attempt.result_summary
      );
    end if;
    raise exception 'Completed acquisition retry does not match immutable recorded result.' using errcode='23505';
  end if;
  if v_attempt.status in ('failed','cancelled') then
    raise exception 'Acquisition attempt is not recordable in status %',v_attempt.status using errcode='22023';
  end if;

  select * into v_work
  from local_intel.search_discovery_queue w
  where w.id=v_attempt.discovery_work_id
    and w.search_query_id=v_attempt.search_query_id
  for update;

  select * into v_query
  from local_intel.search_queries q
  where q.id=v_attempt.search_query_id
    and q.local_context_id=v_attempt.local_context_id
  for update;

  if v_work.id is null or v_query.id is null or v_query.status<>'in_process' then
    raise exception 'Bound Shared Intelligence research work/query is unavailable.' using errcode='23514';
  end if;

  update atlas.contact_set_acquisition_attempts
  set status='in_process',
      provider_key=v_provider,
      model_ref=v_model,
      provider_response_id=v_response_id,
      source_set=v_sources,
      started_at=coalesce(started_at,now()),
      updated_at=now()
  where id=v_attempt.id;

  update local_intel.search_discovery_queue
  set status='in_process',
      claimed_at=coalesce(claimed_at,now()),
      metadata=metadata||jsonb_build_object(
        'providerKey',v_provider,
        'modelRef',v_model,
        'providerResponseId',v_response_id,
        'sourceSet',v_sources
      ),
      updated_at=now()
  where id=v_work.id;

  for v_source in select value from jsonb_array_elements(v_sources)
  loop
    if jsonb_typeof(v_source)<>'object' then
      raise exception 'Every machine-returned source must be an object.' using errcode='22023';
    end if;
    perform local_intel.register_atlas_contact_web_source_v1(v_source,v_attempt.id);
  end loop;

  v_gap_kind:=v_attempt.gap->>'gapKind';

  for v_finding in select value from jsonb_array_elements(v_findings)
  loop
    v_index:=v_index+1;
    if jsonb_typeof(v_finding)<>'object' then
      raise exception 'Every finding must be an object.' using errcode='22023';
    end if;

    v_source_url:=nullif(btrim(v_finding->>'sourceUrl'),'');
    if v_source_url is null or not exists(
      select 1
      from jsonb_array_elements(v_sources) s(value)
      where s.value->>'url'=v_source_url
    ) then
      raise exception 'Finding sourceUrl must occur in the machine-returned source set.' using errcode='23514';
    end if;

    select s.id into v_source_id
    from local_intel.sources s
    where s.source_url=v_source_url;

    if v_source_id is null then
      raise exception 'Finding source could not be registered.' using errcode='23514';
    end if;

    v_subject_kind:=lower(nullif(btrim(v_finding->>'subjectKind'),''));
    if v_subject_kind not in ('business','government','nonprofit','organization','person','place') then
      raise exception 'Finding subjectKind is unsupported.' using errcode='22023';
    end if;

    begin
      v_entity_id:=nullif(v_finding->>'entityId','')::uuid;
      v_org_entity_id:=nullif(v_finding->>'organizationEntityId','')::uuid;
    exception when invalid_text_representation then
      raise exception 'Finding entity ids must be UUIDs when supplied.' using errcode='22023';
    end;

    if v_gap_kind='entity_field_gap' then
      if v_entity_id is null
         or v_entity_id is distinct from (v_attempt.gap->>'entityId')::uuid then
        raise exception 'entity_field_gap findings may enrich only the persisted canonical entity.' using errcode='23514';
      end if;
    elsif v_gap_kind='organization_person_gap' then
      if v_subject_kind<>'person'
         or v_org_entity_id is null
         or v_org_entity_id is distinct from (v_attempt.gap->>'organizationEntityId')::uuid then
        raise exception 'organization_person_gap findings must preserve the persisted canonical organization and identify a person.' using errcode='23514';
      end if;
    end if;

    v_source_record_key:=coalesce(
      nullif(btrim(v_finding->>'sourceRecordKey'),''),
      'atlas-gap:'||v_attempt.id::text||':'||v_index::text||':'||md5(v_finding::text)
    );

    v_ingest_payload:=jsonb_build_object(
      'search_query_id',v_attempt.search_query_id,
      'discovery_work_id',v_attempt.discovery_work_id,
      'source_id',v_source_id,
      'source_record_key',v_source_record_key,
      'subject_kind',v_subject_kind,
      'subject_key',nullif(btrim(v_finding->>'subjectKey'),''),
      'entity_id',v_entity_id,
      'organization_entity_id',v_org_entity_id,
      'organization_name',nullif(btrim(v_finding->>'organizationName'),''),
      'observed_name',nullif(btrim(v_finding->>'observedName'),''),
      'role_title',nullif(btrim(v_finding->>'roleTitle'),''),
      'role_function',nullif(btrim(v_finding->>'roleFunction'),''),
      'email',nullif(btrim(v_finding->>'email'),''),
      'phone',nullif(btrim(v_finding->>'phone'),''),
      'website_url',nullif(btrim(v_finding->>'websiteUrl'),''),
      'fields',coalesce(case when jsonb_typeof(v_finding->'fields')='object' then v_finding->'fields' end,'{}'::jsonb),
      'metadata',jsonb_build_object(
        'origin','atlas_contact_gap_acquisition',
        'atlasExecutionRunId',v_attempt.execution_run_id,
        'atlasAcquisitionAttemptId',v_attempt.id,
        'gapFingerprint',v_attempt.gap_fingerprint,
        'providerKey',v_provider,
        'modelRef',v_model,
        'providerResponseId',v_response_id,
        'machineSourceUrl',v_source_url
      )||coalesce(case when jsonb_typeof(v_finding->'metadata')='object' then v_finding->'metadata' end,'{}'::jsonb)
    );

    v_ingest_result:=local_intel.ingest_search_discovery_evidence_v1(v_ingest_payload);
    v_results:=v_results||jsonb_build_array(
      jsonb_build_object(
        'sourceUrl',v_source_url,
        'sourceId',v_source_id,
        'ingestResult',v_ingest_result
      )
    );
  end loop;

  v_resolver:=local_intel.refresh_entity_resolution_v2_2_review_recommendations();

  update local_intel.search_discovery_queue
  set status='complete',
      completed_at=now(),
      metadata=metadata||jsonb_build_object(
        'acquisitionOutcome',v_outcome,
        'findingCount',jsonb_array_length(v_findings),
        'resolverRefresh',v_resolver
      ),
      updated_at=now()
  where id=v_attempt.discovery_work_id;

  update local_intel.search_queries
  set status='complete',
      completed_at=now(),
      metadata=metadata||jsonb_build_object(
        'acquisitionOutcome',v_outcome,
        'findingCount',jsonb_array_length(v_findings),
        'providerResponseId',v_response_id
      ),
      updated_at=now()
  where id=v_attempt.search_query_id;

  update atlas.contact_set_acquisition_attempts
  set status='complete',
      provider_key=v_provider,
      model_ref=v_model,
      provider_response_id=v_response_id,
      source_set=v_sources,
      result_summary=jsonb_build_object(
        'payloadHash',v_payload_hash,
        'outcome',v_outcome,
        'sourceCount',jsonb_array_length(v_sources),
        'findingCount',jsonb_array_length(v_findings),
        'ingestionResults',v_results,
        'resolverRefresh',v_resolver
      ),
      completed_at=now(),
      updated_at=now()
  where id=v_attempt.id
  returning * into v_attempt;

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','contact_gap_acquisition_record_v1',
    'attemptId',v_attempt.id,
    'status',v_attempt.status,
    'resultSummary',v_attempt.result_summary,
    'truthBoundary',jsonb_build_object(
      'findingsRequiredMachineSourceUrl',true,
      'automaticIdentityApproval',false,
      'automaticMerge',false,
      'communicationAuthorized',false
    )
  );
end;
$function$;

revoke all on function atlas.record_contact_gap_acquisition_service_v1(uuid,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_contact_gap_acquisition_service_v1(uuid,uuid,jsonb)
  to service_role;

create or replace function atlas.refresh_contact_set_execution_after_acquisition_service_v1(
  p_execution_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_run atlas.contact_set_execution_runs%rowtype;
  v_request atlas.contact_set_intent_requests%rowtype;
  v_directory jsonb;
  v_gaps jsonb;
  v_gap jsonb;
  v_desired integer;
  v_selected integer;
  v_population_gap boolean;
  v_unattempted integer:=0;
  v_state text;
  v_attach boolean;
  v_role_key text;
  v_item jsonb;
  v_attach_result jsonb;
  v_ledger_results jsonb:='[]'::jsonb;
begin
  select * into v_run
  from atlas.contact_set_execution_runs r
  where r.id=p_execution_run_id
  for update;

  if v_run.id is null then
    raise exception 'Contact-set execution run not found.' using errcode='P0002';
  end if;

  select * into v_request
  from atlas.contact_set_intent_requests r
  where r.id=v_run.request_id;

  if v_request.id is null or v_request.request_state<>'ready' then
    raise exception 'Ready contact-set intent request is required.' using errcode='23514';
  end if;

  v_directory:=atlas.shared_directory_target_search_service_v1(
    v_run.organization_id,
    v_request.interpretation->'target',
    v_request.interpretation->'geography',
    v_run.required_fields,
    least(200,greatest(50,coalesce(v_run.desired_count,20)*5))
  );

  v_selected:=coalesce((v_directory->>'candidateCount')::integer,0);
  v_desired:=v_run.desired_count;
  v_population_gap:=v_desired is not null and v_selected<v_desired;
  v_gaps:=coalesce(v_directory->'researchTargets','[]'::jsonb);

  if v_population_gap then
    v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object(
      'gapKind','population_gap',
      'desiredCount',v_desired,
      'supportedCount',v_selected,
      'missingCount',v_desired-v_selected,
      'reason','The existing canonical directory does not yet support the requested population size.'
    ));
  end if;

  for v_gap in select value from jsonb_array_elements(v_gaps)
  loop
    if not exists(
      select 1
      from atlas.contact_set_acquisition_attempts a
      where a.execution_run_id=v_run.id
        and a.gap_fingerprint=md5(v_gap::text)
        and a.status='complete'
    ) then
      v_unattempted:=v_unattempted+1;
    end if;
  end loop;

  v_attach:=lower(coalesce(v_request.interpretation#>>'{ledgerEffect,attachToLedger}','false')) in ('true','1','yes');
  v_role_key:=coalesce(nullif(lower(btrim(v_request.interpretation#>>'{ledgerEffect,roleKey}')),''),'contact');

  if v_attach then
    for v_item in select value from jsonb_array_elements(coalesce(v_directory->'items','[]'::jsonb))
    loop
      v_attach_result:=atlas.attach_shared_directory_entity_service_v1(
        v_run.organization_id,
        (v_item->>'entityId')::uuid,
        v_role_key,
        v_run.organization_unit_id
      );
      v_ledger_results:=v_ledger_results||jsonb_build_array(
        jsonb_build_object(
          'entityId',v_item->>'entityId',
          'roleKey',v_role_key,
          'result',v_attach_result
        )
      );
    end loop;
  end if;

  v_state:=case
    when jsonb_array_length(v_gaps)=0 then 'ready'
    when v_unattempted>0 then 'needs_acquisition'
    else 'partial'
  end;

  update atlas.contact_set_execution_runs
  set execution_state=v_state,
      selected_count=v_selected,
      directory_snapshot=v_directory,
      gap_snapshot=jsonb_build_object(
        'contractVersion','contact_set_gap_snapshot_v1',
        'researchTargets',v_gaps,
        'gapCount',jsonb_array_length(v_gaps),
        'populationGap',v_population_gap,
        'unattemptedGapCount',v_unattempted
      ),
      ledger_effect_snapshot=jsonb_build_object(
        'attachToLedger',v_attach,
        'roleKey',case when v_attach then v_role_key else null end,
        'results',v_ledger_results,
        'communicationAuthorized',false
      ),
      updated_at=now()
  where id=v_run.id
  returning * into v_run;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','contact_set_execution_refresh_v1',
    'runId',v_run.id,
    'requestId',v_run.request_id,
    'executionState',v_run.execution_state,
    'selectedCount',v_run.selected_count,
    'directory',v_run.directory_snapshot,
    'gaps',v_run.gap_snapshot,
    'ledgerEffects',v_run.ledger_effect_snapshot
  );
end;
$function$;

revoke all on function atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid)
  to service_role;

create or replace function atlas.contact_set_acquisition_attempts_self_api_v1(
  p_execution_run_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_run atlas.contact_set_execution_runs%rowtype;
  v_attempts jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_run
  from atlas.contact_set_execution_runs r
  where r.id=p_execution_run_id;

  if v_run.id is null then
    raise exception 'Contact-set execution run not found.' using errcode='P0002';
  end if;
  if atlas.current_effective_organization_membership_v1(v_run.organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'attemptId',a.id,
      'gapFingerprint',a.gap_fingerprint,
      'gap',a.gap,
      'status',a.status,
      'providerKey',a.provider_key,
      'modelRef',a.model_ref,
      'providerResponseId',a.provider_response_id,
      'sourceSet',a.source_set,
      'resultSummary',a.result_summary,
      'queuedAt',a.queued_at,
      'startedAt',a.started_at,
      'completedAt',a.completed_at
    ) order by a.queued_at,a.id
  ),'[]'::jsonb)
  into v_attempts
  from atlas.contact_set_acquisition_attempts a
  where a.execution_run_id=v_run.id;

  return jsonb_build_object(
    'contractVersion','contact_set_acquisition_attempts_v1',
    'executionRunId',v_run.id,
    'executionState',v_run.execution_state,
    'attempts',v_attempts
  );
end;
$function$;

revoke all on function atlas.contact_set_acquisition_attempts_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.contact_set_acquisition_attempts_self_api_v1(uuid)
  to authenticated;

comment on function atlas.queue_contact_gap_acquisition_service_v1(uuid,jsonb) is
'Service-only Shared/Atlas bridge that queues one exact persisted contact-set gap as bounded Shared Intelligence research work. It creates no canonical truth.';
comment on function atlas.record_contact_gap_acquisition_service_v1(uuid,uuid,jsonb) is
'Service-only intake for machine-source-backed contact research. Every extracted finding must reference a URL in the recorded machine source set and then passes through universal Shared Intelligence ingestion/resolution.';
comment on function atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid) is
'Re-runs typed Shared Directory retrieval after bounded acquisition, reattaches qualifying canonical identities to the requesting Ledger, and deterministically sets ready/needs_acquisition/partial without authorizing communication.';

commit;
