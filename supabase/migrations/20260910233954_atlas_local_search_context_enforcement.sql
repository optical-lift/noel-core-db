-- Keep legacy single-Local writers working until they are updated, but never guess with >1 active Local.
drop trigger if exists market_origins_single_context_stamp on local_intel.market_origins;
create trigger market_origins_single_context_stamp
before insert on local_intel.market_origins
for each row execute function local_intel.stamp_single_active_local_context_v1();

drop trigger if exists regional_ingestion_targets_single_context_stamp on local_intel.regional_ingestion_targets;
create trigger regional_ingestion_targets_single_context_stamp
before insert on local_intel.regional_ingestion_targets
for each row execute function local_intel.stamp_single_active_local_context_v1();

-- Search-side entity references must belong to the same Local as the search query.
create or replace function local_intel.enforce_search_entity_context_v1()
returns trigger
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $$
declare
  v_context_id uuid;
begin
  select q.local_context_id into v_context_id
  from local_intel.search_queries q where q.id=new.search_query_id;
  if v_context_id is null then raise exception 'search_query_id % has no Local context', new.search_query_id; end if;
  if new.entity_id is not null and not exists (
    select 1 from local_intel.entities e where e.id=new.entity_id and e.local_context_id=v_context_id
  ) then raise exception 'entity_id must belong to search query Local context'; end if;
  return new;
end;
$$;

create or replace function local_intel.enforce_search_evidence_context_v1()
returns trigger
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $$
declare
  v_context_id uuid;
begin
  select q.local_context_id into v_context_id
  from local_intel.search_queries q where q.id=new.search_query_id;
  if v_context_id is null then raise exception 'search_query_id % has no Local context', new.search_query_id; end if;
  if new.entity_id is not null and not exists (
    select 1 from local_intel.entities e where e.id=new.entity_id and e.local_context_id=v_context_id
  ) then raise exception 'entity_id must belong to search query Local context'; end if;
  if new.organization_entity_id is not null and not exists (
    select 1 from local_intel.entities e where e.id=new.organization_entity_id and e.local_context_id=v_context_id
  ) then raise exception 'organization_entity_id must belong to search query Local context'; end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('local_intel.search_discovery_subject_work') is not null then
    execute 'drop trigger if exists search_discovery_subject_context_guard_v1 on local_intel.search_discovery_subject_work';
    execute 'create trigger search_discovery_subject_context_guard_v1 before insert or update of search_query_id,entity_id on local_intel.search_discovery_subject_work for each row execute function local_intel.enforce_search_entity_context_v1()';
  end if;
  if to_regclass('local_intel.search_findings') is not null then
    execute 'drop trigger if exists search_findings_context_guard_v1 on local_intel.search_findings';
    execute 'create trigger search_findings_context_guard_v1 before insert or update of search_query_id,entity_id on local_intel.search_findings for each row execute function local_intel.enforce_search_entity_context_v1()';
  end if;
  if to_regclass('local_intel.search_field_holds') is not null then
    execute 'drop trigger if exists search_field_holds_context_guard_v1 on local_intel.search_field_holds';
    execute 'create trigger search_field_holds_context_guard_v1 before insert or update of search_query_id,entity_id on local_intel.search_field_holds for each row execute function local_intel.enforce_search_entity_context_v1()';
  end if;
end $$;

drop trigger if exists search_discovery_evidence_context_guard_v1 on local_intel.search_discovery_evidence;
create trigger search_discovery_evidence_context_guard_v1
before insert or update of search_query_id,entity_id,organization_entity_id
on local_intel.search_discovery_evidence
for each row execute function local_intel.enforce_search_evidence_context_v1();

-- Existing API shape remains unchanged. local_context_id is accepted in parameters/metadata and is explicit at insert.
create or replace function local_intel.start_search_query_v1(
  p_query_text text,
  p_requested_fields text[] default '{}'::text[],
  p_parameters jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $$
declare
  v_id uuid;
  v_context_id uuid;
  v_context_count integer;
begin
  if nullif(btrim(p_query_text),'') is null then raise exception 'query_text is required'; end if;

  begin
    v_context_id := nullif(coalesce(p_parameters->>'local_context_id',p_metadata->>'local_context_id'),'')::uuid;
  exception when invalid_text_representation then
    raise exception 'local_context_id must be UUID';
  end;

  if v_context_id is null then
    select count(*),min(id::text)::uuid into v_context_count,v_context_id
    from local_intel.local_contexts where status='active';
    if v_context_count <> 1 or v_context_id is null then
      raise exception 'local_context_id is required when Atlas Local has % active contexts',v_context_count;
    end if;
  elsif not exists(select 1 from local_intel.local_contexts where id=v_context_id and status='active') then
    raise exception 'active local_context_id is required';
  end if;

  insert into local_intel.search_queries(local_context_id,query_text,requested_fields,parameters,metadata)
  values(v_context_id,btrim(p_query_text),coalesce(p_requested_fields,'{}'::text[]),coalesce(p_parameters,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end;
$$;

-- Search discovery always inherits candidate ownership from its search query.
create or replace function local_intel.ingest_search_discovery_evidence_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'local_intel','pg_catalog'
as $$
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
  select q.local_context_id into v_context_id from local_intel.search_queries q where q.id=v_query_id and q.status='in_process';
  if v_context_id is null then raise exception 'active search_query_id is required'; end if;
  if v_source_id is null or not exists(select 1 from local_intel.sources where id=v_source_id) then raise exception 'existing source_id is required'; end if;
  if v_subject_kind='' then raise exception 'subject_kind is required'; end if;
  if v_source_record_key='' then raise exception 'source_record_key is required'; end if;
  if v_entity_id is not null and not exists(select 1 from local_intel.entities where id=v_entity_id and local_context_id=v_context_id) then raise exception 'entity_id does not belong to search Local context'; end if;
  if v_org_id is not null and not exists(select 1 from local_intel.entities where id=v_org_id and local_context_id=v_context_id) then raise exception 'organization_entity_id does not belong to search Local context'; end if;

  v_name := coalesce(nullif(btrim(p_payload->>'observed_name'),''),nullif(btrim(v_fields->>'name'),''));
  v_email := coalesce(nullif(btrim(p_payload->>'email'),''),nullif(btrim(v_fields->>'email'),''));
  v_title := coalesce(nullif(btrim(p_payload->>'role_title'),''),nullif(btrim(v_fields->>'title'),''));
  v_role_function := coalesce(nullif(btrim(p_payload->>'role_function'),''),nullif(btrim(v_fields->>'role_function'),''));
  v_phone := coalesce(nullif(btrim(p_payload->>'phone'),''),nullif(btrim(v_fields->>'phone'),''));
  v_website := coalesce(nullif(btrim(p_payload->>'website_url'),''),nullif(btrim(v_fields->>'website'),''));
  if v_fields='{}'::jsonb and v_name is null and v_email is null and v_title is null and v_phone is null and v_website is null then raise exception 'at least one explicit observed field is required'; end if;

  if v_work_id is null then
    select id into v_work_id from local_intel.search_discovery_queue where search_query_id=v_query_id and status='in_process' order by claimed_at desc nulls last,created_at desc limit 1;
  end if;

  insert into local_intel.search_discovery_evidence(
    search_query_id,discovery_work_id,source_id,source_record_key,subject_kind,subject_key,entity_id,
    organization_entity_id,organization_name,observed_name,role_title,role_function,email,phone,website_url,fields,evidence_payload
  ) values(
    v_query_id,v_work_id,v_source_id,v_source_record_key,v_subject_kind,nullif(btrim(p_payload->>'subject_key'),''),v_entity_id,
    v_org_id,nullif(btrim(p_payload->>'organization_name'),''),v_name,v_title,v_role_function,v_email,v_phone,v_website,v_fields,
    coalesce(p_payload->'metadata','{}'::jsonb)
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
    return v_apply;
  end if;

  v_source_role := case when v_subject_kind='person' then 'person_directory' when v_subject_kind in ('business','organization','nonprofit') then 'organization_directory' else 'other' end;
  select id into v_ingestion_source_id from local_intel.ingestion_sources where source_id=v_source_id and source_role=v_source_role;
  if v_ingestion_source_id is null then
    insert into local_intel.ingestion_sources(source_id,source_role,status,ingestion_priority,metadata)
    values(v_source_id,v_source_role,'active',50,jsonb_build_object('origin','search_discovery','search_query_id',v_query_id))
    on conflict(source_id,source_role) do update set updated_at=now()
    returning id into v_ingestion_source_id;
  end if;

  insert into local_intel.entity_ingestion_candidates(
    local_context_id,ingestion_source_id,source_record_key,proposed_entity_type,proposed_name,website_url,phone,email,
    proposed_relationship_target_name,proposed_role_title,confidence,review_state,metadata
  ) values(
    v_context_id,v_ingestion_source_id,v_source_record_key,v_subject_kind,coalesce(v_name,v_source_record_key),v_website,v_phone,v_email,
    nullif(btrim(p_payload->>'organization_name'),''),v_title,1.0,'pending',
    jsonb_build_object('origin','search_discovery','search_query_id',v_query_id,'search_discovery_evidence_id',v_evidence_id,'confidence_kind','explicit_extraction_not_identity_match','fields',v_fields)||coalesce(p_payload->'metadata','{}'::jsonb)
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

  update local_intel.search_discovery_evidence set ingestion_candidate_id=v_candidate_id,reconciliation_status='candidate',updated_at=now() where id=v_evidence_id;
  return jsonb_build_object('evidence_id',v_evidence_id,'ingestion_candidate_id',v_candidate_id,'local_context_id',v_context_id,'status','candidate');
end;
$$;
