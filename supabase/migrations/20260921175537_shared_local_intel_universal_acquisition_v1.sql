begin;

create or replace function local_intel.ensure_entity_context_membership_from_research_v1(
  p_entity_id uuid,
  p_local_context_id uuid,
  p_basis text default 'research_relevance',
  p_source_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_id uuid;
  v_basis text:=coalesce(nullif(btrim(p_basis),''),'research_relevance');
begin
  if p_entity_id is null or not exists(
    select 1 from local_intel.entities e where e.id=p_entity_id
  ) then
    raise exception 'Existing canonical Shared Intelligence entity is required.' using errcode='P0002';
  end if;

  if p_local_context_id is null or not exists(
    select 1 from local_intel.local_contexts c
    where c.id=p_local_context_id and c.status='active'
  ) then
    raise exception 'Active research context is required.' using errcode='P0002';
  end if;

  if p_source_id is not null and not exists(
    select 1 from local_intel.sources s where s.id=p_source_id
  ) then
    raise exception 'Existing source is required when source_id is supplied.' using errcode='P0002';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Membership metadata must be a JSON object.' using errcode='22023';
  end if;

  insert into local_intel.entity_context_memberships(
    entity_id,local_context_id,membership_kind,status,basis,source_id,
    verification_state,metadata
  ) values (
    p_entity_id,p_local_context_id,'known_in','active',v_basis,p_source_id,
    case when p_source_id is null then 'derived' else 'source_observed' end,
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict(entity_id,local_context_id) do update
    set status='active',
        membership_kind='known_in',
        basis=case
          when local_intel.entity_context_memberships.basis in ('legacy_pointer','legacy_local_context_pointer')
            then excluded.basis
          else local_intel.entity_context_memberships.basis
        end,
        source_id=coalesce(local_intel.entity_context_memberships.source_id,excluded.source_id),
        verification_state=case
          when local_intel.entity_context_memberships.verification_state='derived'
               and excluded.verification_state='source_observed'
            then 'source_observed'
          else local_intel.entity_context_memberships.verification_state
        end,
        metadata=local_intel.entity_context_memberships.metadata||excluded.metadata,
        updated_at=now()
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function local_intel.ensure_entity_context_membership_from_research_v1(uuid,uuid,text,uuid,jsonb)
  from public,anon,authenticated,service_role;

comment on function local_intel.ensure_entity_context_membership_from_research_v1(uuid,uuid,text,uuid,jsonb) is
'Private Shared Intelligence consequence helper. Records nonexclusive contextual relevance to one canonical entity without changing the entity legacy discovery-origin pointer.';

create or replace function local_intel.enforce_search_entity_context_v1()
returns trigger
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $function$
declare
  v_context_id uuid;
begin
  select q.local_context_id into v_context_id
  from local_intel.search_queries q
  where q.id=new.search_query_id;

  if v_context_id is null then
    raise exception 'search_query_id % has no research context',new.search_query_id;
  end if;

  if new.entity_id is not null and not exists(
    select 1 from local_intel.entities e where e.id=new.entity_id
  ) then
    raise exception 'entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  return new;
end;
$function$;

comment on function local_intel.enforce_search_entity_context_v1() is
'Compatibility guard: search context is provenance/relevance, not identity ownership. Canonical entity may originate in another legacy Local context.';

create or replace function local_intel.enforce_search_evidence_context_v1()
returns trigger
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $function$
declare
  v_context_id uuid;
begin
  select q.local_context_id into v_context_id
  from local_intel.search_queries q
  where q.id=new.search_query_id;

  if v_context_id is null then
    raise exception 'search_query_id % has no research context',new.search_query_id;
  end if;

  if new.entity_id is not null and not exists(
    select 1 from local_intel.entities e where e.id=new.entity_id
  ) then
    raise exception 'entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  if new.organization_entity_id is not null and not exists(
    select 1 from local_intel.entities e where e.id=new.organization_entity_id
  ) then
    raise exception 'organization_entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  return new;
end;
$function$;

comment on function local_intel.enforce_search_evidence_context_v1() is
'Compatibility guard: evidence belongs to a research context, but its canonical subject and organization may be universal entities originating elsewhere.';

create or replace function local_intel.enforce_ingestion_candidate_local_context_v1()
returns trigger
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $function$
begin
  if new.local_context_id is null or not exists(
    select 1 from local_intel.local_contexts c
    where c.id=new.local_context_id and c.status='active'
  ) then
    raise exception 'active candidate research context is required';
  end if;

  if new.matched_entity_id is not null and not exists(
    select 1 from local_intel.entities e where e.id=new.matched_entity_id
  ) then
    raise exception 'matched_entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  if new.resolver_recommended_entity_id is not null and not exists(
    select 1 from local_intel.entities e where e.id=new.resolver_recommended_entity_id
  ) then
    raise exception 'resolver_recommended_entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  return new;
end;
$function$;

comment on function local_intel.enforce_ingestion_candidate_local_context_v1() is
'Compatibility guard: candidate local_context_id is intake/research provenance. Resolver recommendations and accepted matches target the universal canonical entity corpus.';

create or replace function local_intel.sync_search_evidence_context_memberships_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_context_id uuid;
begin
  select q.local_context_id into v_context_id
  from local_intel.search_queries q
  where q.id=new.search_query_id;

  if v_context_id is null then
    raise exception 'search_query_id % has no research context',new.search_query_id;
  end if;

  if new.entity_id is not null then
    perform local_intel.ensure_entity_context_membership_from_research_v1(
      new.entity_id,
      v_context_id,
      'search_discovery_evidence',
      new.source_id,
      jsonb_build_object(
        'searchQueryId',new.search_query_id,
        'searchDiscoveryEvidenceId',new.id,
        'role','subject'
      )
    );
  end if;

  if new.organization_entity_id is not null then
    perform local_intel.ensure_entity_context_membership_from_research_v1(
      new.organization_entity_id,
      v_context_id,
      'search_discovery_evidence',
      new.source_id,
      jsonb_build_object(
        'searchQueryId',new.search_query_id,
        'searchDiscoveryEvidenceId',new.id,
        'role','organization_context'
      )
    );
  end if;

  return new;
end;
$function$;

revoke all on function local_intel.sync_search_evidence_context_memberships_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists search_discovery_evidence_context_membership_v1
  on local_intel.search_discovery_evidence;
create trigger search_discovery_evidence_context_membership_v1
after insert or update of search_query_id,entity_id,organization_entity_id,source_id
on local_intel.search_discovery_evidence
for each row execute function local_intel.sync_search_evidence_context_memberships_v1();

create or replace function local_intel.sync_search_finding_context_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_context_id uuid;
begin
  if new.entity_id is null then
    return new;
  end if;

  select q.local_context_id into v_context_id
  from local_intel.search_queries q
  where q.id=new.search_query_id;

  if v_context_id is null then
    raise exception 'search_query_id % has no research context',new.search_query_id;
  end if;

  perform local_intel.ensure_entity_context_membership_from_research_v1(
    new.entity_id,
    v_context_id,
    'search_finding',
    new.source_id,
    jsonb_build_object(
      'searchQueryId',new.search_query_id,
      'searchFindingId',new.id
    )
  );

  return new;
end;
$function$;

revoke all on function local_intel.sync_search_finding_context_membership_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists search_findings_context_membership_v1
  on local_intel.search_findings;
create trigger search_findings_context_membership_v1
after insert or update of search_query_id,entity_id,source_id
on local_intel.search_findings
for each row execute function local_intel.sync_search_finding_context_membership_v1();

create or replace function local_intel.sync_ingestion_candidate_matched_context_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_source_id uuid;
begin
  if new.matched_entity_id is null
     or new.review_state not in ('matched_existing','promoted') then
    return new;
  end if;

  select i.source_id into v_source_id
  from local_intel.ingestion_sources i
  where i.id=new.ingestion_source_id;

  perform local_intel.ensure_entity_context_membership_from_research_v1(
    new.matched_entity_id,
    new.local_context_id,
    'ingestion_identity_resolution',
    v_source_id,
    jsonb_build_object(
      'ingestionCandidateId',new.id,
      'reviewState',new.review_state,
      'resolverAlgorithmKey',new.resolver_algorithm_key,
      'resolverAlgorithmVersion',new.resolver_algorithm_version
    )
  );

  return new;
end;
$function$;

revoke all on function local_intel.sync_ingestion_candidate_matched_context_membership_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists entity_ingestion_candidate_context_membership_v1
  on local_intel.entity_ingestion_candidates;
create trigger entity_ingestion_candidate_context_membership_v1
after insert or update of review_state,matched_entity_id,local_context_id
on local_intel.entity_ingestion_candidates
for each row execute function local_intel.sync_ingestion_candidate_matched_context_membership_v1();

create or replace function local_intel.ingest_search_discovery_evidence_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'local_intel','pg_catalog'
as $function$
declare
  v_query_id uuid := nullif(p_payload->>'search_query_id','')::uuid;
  v_context_id uuid;
  v_work_id uuid := nullif(p_payload->>'discovery_work_id','')::uuid;
  v_source_id uuid := nullif(p_payload->>'source_id','')::uuid;
  v_entity_id uuid := nullif(p_payload->>'entity_id','')::uuid;
  v_org_id uuid := nullif(p_payload->>'organization_entity_id','')::uuid;
  v_subject_kind text := btrim(coalesce(p_payload->>'subject_kind',''));
  v_source_record_key text := btrim(coalesce(p_payload->>'source_record_key',''));
  v_fields jsonb := case when jsonb_typeof(p_payload->'fields')='object' then p_payload->'fields' else '{}'::jsonb end;
  v_evidence_id uuid;
  v_ingestion_source_id uuid;
  v_candidate_id uuid;
  v_source_role text;
  v_apply jsonb;
  v_name text;
  v_email text;
  v_title text;
  v_role_function text;
  v_phone text;
  v_website text;
begin
  select q.local_context_id into v_context_id
  from local_intel.search_queries q
  where q.id=v_query_id and q.status='in_process';

  if v_context_id is null then
    raise exception 'active search_query_id is required';
  end if;

  if v_source_id is null or not exists(
    select 1 from local_intel.sources where id=v_source_id
  ) then
    raise exception 'existing source_id is required';
  end if;

  if v_subject_kind='' then
    raise exception 'subject_kind is required';
  end if;
  if v_source_record_key='' then
    raise exception 'source_record_key is required';
  end if;

  if v_entity_id is not null and not exists(
    select 1 from local_intel.entities where id=v_entity_id
  ) then
    raise exception 'entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  if v_org_id is not null and not exists(
    select 1 from local_intel.entities where id=v_org_id
  ) then
    raise exception 'organization_entity_id must identify an existing canonical Shared Intelligence entity';
  end if;

  v_name := coalesce(nullif(btrim(p_payload->>'observed_name'),''),nullif(btrim(v_fields->>'name'),''));
  v_email := coalesce(nullif(btrim(p_payload->>'email'),''),nullif(btrim(v_fields->>'email'),''));
  v_title := coalesce(nullif(btrim(p_payload->>'role_title'),''),nullif(btrim(v_fields->>'title'),''));
  v_role_function := coalesce(nullif(btrim(p_payload->>'role_function'),''),nullif(btrim(v_fields->>'role_function'),''));
  v_phone := coalesce(nullif(btrim(p_payload->>'phone'),''),nullif(btrim(v_fields->>'phone'),''));
  v_website := coalesce(nullif(btrim(p_payload->>'website_url'),''),nullif(btrim(v_fields->>'website'),''));

  if v_fields='{}'::jsonb
     and v_name is null
     and v_email is null
     and v_title is null
     and v_phone is null
     and v_website is null then
    raise exception 'at least one explicit observed field is required';
  end if;

  if v_work_id is null then
    select id into v_work_id
    from local_intel.search_discovery_queue
    where search_query_id=v_query_id and status='in_process'
    order by claimed_at desc nulls last,created_at desc
    limit 1;
  end if;

  insert into local_intel.search_discovery_evidence(
    search_query_id,discovery_work_id,source_id,source_record_key,subject_kind,subject_key,entity_id,
    organization_entity_id,organization_name,observed_name,role_title,role_function,email,phone,website_url,fields,evidence_payload
  ) values(
    v_query_id,v_work_id,v_source_id,v_source_record_key,v_subject_kind,nullif(btrim(p_payload->>'subject_key'),''),
    v_entity_id,v_org_id,nullif(btrim(p_payload->>'organization_name'),''),v_name,v_title,v_role_function,
    v_email,v_phone,v_website,v_fields,coalesce(p_payload->'metadata','{}'::jsonb)
  )
  on conflict(search_query_id,source_id,source_record_key) do update set
    discovery_work_id=coalesce(excluded.discovery_work_id,local_intel.search_discovery_evidence.discovery_work_id),
    subject_key=coalesce(excluded.subject_key,local_intel.search_discovery_evidence.subject_key),
    entity_id=coalesce(excluded.entity_id,local_intel.search_discovery_evidence.entity_id),
    organization_entity_id=coalesce(excluded.organization_entity_id,local_intel.search_discovery_evidence.organization_entity_id),
    organization_name=coalesce(excluded.organization_name,local_intel.search_discovery_evidence.organization_name),
    observed_name=coalesce(excluded.observed_name,local_intel.search_discovery_evidence.observed_name),
    role_title=coalesce(excluded.role_title,local_intel.search_discovery_evidence.role_title),
    role_function=coalesce(excluded.role_function,local_intel.search_discovery_evidence.role_function),
    email=coalesce(excluded.email,local_intel.search_discovery_evidence.email),
    phone=coalesce(excluded.phone,local_intel.search_discovery_evidence.phone),
    website_url=coalesce(excluded.website_url,local_intel.search_discovery_evidence.website_url),
    fields=local_intel.search_discovery_evidence.fields||excluded.fields,
    evidence_payload=local_intel.search_discovery_evidence.evidence_payload||excluded.evidence_payload,
    updated_at=now()
  returning id,entity_id into v_evidence_id,v_entity_id;

  if v_entity_id is not null then
    v_apply := local_intel.apply_search_discovery_evidence_v1(v_evidence_id,v_entity_id);
    return v_apply||jsonb_build_object(
      'research_context_id',v_context_id,
      'identity_scope','universal_shared_intelligence'
    );
  end if;

  v_source_role := case
    when v_subject_kind='person' then 'person_directory'
    when v_subject_kind in ('business','organization','nonprofit') then 'organization_directory'
    else 'other'
  end;

  select id into v_ingestion_source_id
  from local_intel.ingestion_sources
  where source_id=v_source_id and source_role=v_source_role;

  if v_ingestion_source_id is null then
    insert into local_intel.ingestion_sources(source_id,source_role,status,ingestion_priority,metadata)
    values(
      v_source_id,v_source_role,'active',50,
      jsonb_build_object(
        'origin','search_discovery',
        'search_query_id',v_query_id,
        'identity_scope','universal_shared_intelligence'
      )
    )
    on conflict(source_id,source_role) do update set updated_at=now()
    returning id into v_ingestion_source_id;
  end if;

  insert into local_intel.entity_ingestion_candidates(
    local_context_id,ingestion_source_id,source_record_key,proposed_entity_type,proposed_name,website_url,phone,email,
    proposed_relationship_target_name,proposed_role_title,confidence,review_state,metadata
  ) values(
    v_context_id,v_ingestion_source_id,v_source_record_key,v_subject_kind,coalesce(v_name,v_source_record_key),
    v_website,v_phone,v_email,nullif(btrim(p_payload->>'organization_name'),''),v_title,1.0,'pending',
    jsonb_build_object(
      'origin','search_discovery',
      'search_query_id',v_query_id,
      'search_discovery_evidence_id',v_evidence_id,
      'confidence_kind','explicit_extraction_not_identity_match',
      'fields',v_fields,
      'identity_scope','universal_shared_intelligence',
      'local_context_semantics','research_provenance'
    )||coalesce(p_payload->'metadata','{}'::jsonb)
  )
  on conflict(local_context_id,ingestion_source_id,source_record_key) do update set
    proposed_name=excluded.proposed_name,
    website_url=coalesce(excluded.website_url,local_intel.entity_ingestion_candidates.website_url),
    phone=coalesce(excluded.phone,local_intel.entity_ingestion_candidates.phone),
    email=coalesce(excluded.email,local_intel.entity_ingestion_candidates.email),
    proposed_relationship_target_name=coalesce(excluded.proposed_relationship_target_name,local_intel.entity_ingestion_candidates.proposed_relationship_target_name),
    proposed_role_title=coalesce(excluded.proposed_role_title,local_intel.entity_ingestion_candidates.proposed_role_title),
    metadata=local_intel.entity_ingestion_candidates.metadata||excluded.metadata,
    updated_at=now()
  returning id into v_candidate_id;

  update local_intel.search_discovery_evidence
     set ingestion_candidate_id=v_candidate_id,
         reconciliation_status='candidate',
         updated_at=now()
   where id=v_evidence_id;

  return jsonb_build_object(
    'evidence_id',v_evidence_id,
    'ingestion_candidate_id',v_candidate_id,
    'research_context_id',v_context_id,
    'identity_scope','universal_shared_intelligence',
    'status','candidate'
  );
end;
$function$;

revoke all on function local_intel.ingest_search_discovery_evidence_v1(jsonb)
  from public,anon,authenticated;
grant execute on function local_intel.ingest_search_discovery_evidence_v1(jsonb) to service_role;

comment on function local_intel.ingest_search_discovery_evidence_v1(jsonb) is
'Compatibility discovery intake using universal Shared Intelligence identity. Search local_context_id records why research occurred; it does not constrain which canonical entity may receive evidence.';

commit;
