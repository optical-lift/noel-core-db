-- Atlas Observation → Canonical Admission Gate v1.
-- Resolution chooses the referent; admission decides whether source testimony
-- may become canonical evidence.

create table if not exists local_intel.ingestion_source_entity_bindings (
  id uuid primary key default gen_random_uuid(),
  ingestion_source_id uuid not null
    references local_intel.ingestion_sources(id) on delete restrict,
  source_record_key text not null,
  canonical_entity_id uuid not null
    references local_intel.entities(id) on delete restrict,
  binding_state text not null default 'current',
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  binding_basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ingestion_source_entity_bindings_record_key_v1
    check (btrim(source_record_key) <> ''),
  constraint ingestion_source_entity_bindings_state_v1
    check (binding_state in ('current','retired')),
  constraint ingestion_source_entity_bindings_basis_v1
    check (jsonb_typeof(binding_basis)='object'),
  constraint ingestion_source_entity_bindings_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create unique index if not exists ingestion_source_entity_bindings_current_uq_v1
  on local_intel.ingestion_source_entity_bindings(
    ingestion_source_id,source_record_key
  )
  where binding_state='current';

create index if not exists ingestion_source_entity_bindings_entity_idx_v1
  on local_intel.ingestion_source_entity_bindings(
    canonical_entity_id,ingestion_source_id
  )
  where binding_state='current';

comment on table local_intel.ingestion_source_entity_bindings is
  'Durable continuity from one configured public ingestion source record to one canonical entity. Prevents recurring source refreshes from manufacturing duplicate canonical parties.';

create table if not exists local_intel.ingestion_observation_admissions (
  id uuid primary key default gen_random_uuid(),
  ingestion_observation_id uuid not null unique
    references local_intel.ingestion_observations(id) on delete restrict,
  canonical_entity_id uuid not null
    references local_intel.entities(id) on delete restrict,
  admission_state text not null,
  created_canonical_entity boolean not null default false,
  source_class_key text not null
    references local_intel.evidence_source_classes(source_class_key) on delete restrict,
  evidence_claim_ids uuid[] not null default '{}'::uuid[],
  evidence_claim_count integer not null default 0,
  approved_by text,
  admitted_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint ingestion_observation_admissions_state_v1
    check (admission_state in ('admitted_existing','created_and_admitted')),
  constraint ingestion_observation_admissions_count_v1
    check (
      evidence_claim_count >= 0
      and evidence_claim_count=cardinality(evidence_claim_ids)
    ),
  constraint ingestion_observation_admissions_creation_approval_v1
    check (
      (not created_canonical_entity)
      or
      (
        admission_state='created_and_admitted'
        and approved_by is not null
        and btrim(approved_by)<>''
      )
    ),
  constraint ingestion_observation_admissions_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

create index if not exists ingestion_observation_admissions_entity_idx_v1
  on local_intel.ingestion_observation_admissions(canonical_entity_id,admitted_at desc);

comment on table local_intel.ingestion_observation_admissions is
  'Immutable admission receipt for a bulk-ingestion observation. Records target entity, whether creation occurred, source classification, admitted evidence claims, and explicit approval for new canonical identity creation.';

alter table local_intel.ingestion_source_entity_bindings enable row level security;
alter table local_intel.ingestion_observation_admissions enable row level security;

revoke all on table local_intel.ingestion_source_entity_bindings
  from public,anon,authenticated;
revoke all on table local_intel.ingestion_observation_admissions
  from public,anon,authenticated;

grant select,insert,update,delete
  on table local_intel.ingestion_source_entity_bindings to service_role;
grant select,insert,update,delete
  on table local_intel.ingestion_observation_admissions to service_role;

create or replace function local_intel.set_ingestion_admission_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists ingestion_source_entity_bindings_updated_at_v1
  on local_intel.ingestion_source_entity_bindings;
create trigger ingestion_source_entity_bindings_updated_at_v1
before update on local_intel.ingestion_source_entity_bindings
for each row execute function local_intel.set_ingestion_admission_updated_at_v1();

create or replace function local_intel.bind_ingestion_source_record_entity_internal_v1(
  p_ingestion_source_id uuid,
  p_source_record_key text,
  p_canonical_entity_id uuid,
  p_basis jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_binding local_intel.ingestion_source_entity_bindings%rowtype;
begin
  select * into v_binding
  from local_intel.ingestion_source_entity_bindings b
  where b.ingestion_source_id=p_ingestion_source_id
    and b.source_record_key=btrim(p_source_record_key)
    and b.binding_state='current'
  limit 1;

  if v_binding.id is not null
     and v_binding.canonical_entity_id<>p_canonical_entity_id then
    raise exception 'Source record is already bound to a different canonical entity.'
      using errcode='23505';
  end if;

  if v_binding.id is null then
    insert into local_intel.ingestion_source_entity_bindings(
      ingestion_source_id,source_record_key,canonical_entity_id,
      binding_state,binding_basis
    )
    values(
      p_ingestion_source_id,btrim(p_source_record_key),p_canonical_entity_id,
      'current',coalesce(p_basis,'{}'::jsonb)
    )
    returning * into v_binding;
  else
    update local_intel.ingestion_source_entity_bindings
    set last_seen_at=now(),
        binding_basis=binding_basis || coalesce(p_basis,'{}'::jsonb),
        updated_at=now()
    where id=v_binding.id
    returning * into v_binding;
  end if;

  return v_binding.id;
end
$function$;

revoke all on function local_intel.bind_ingestion_source_record_entity_internal_v1(
  uuid,text,uuid,jsonb
) from public,anon,authenticated,service_role;

create or replace function local_intel.admit_ingestion_observation_claims_internal_v1(
  p_ingestion_observation_id uuid,
  p_canonical_entity_id uuid,
  p_source_id uuid,
  p_source_class_key text
)
returns uuid[]
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_observation local_intel.ingestion_observations%rowtype;
  v_class local_intel.evidence_source_classes%rowtype;
  v_claim jsonb;
  v_claim_kind text;
  v_value_text text;
  v_channel text;
  v_posture text;
  v_uses text[];
  v_intents text[];
  v_requested_intents text[];
  v_valid_from date;
  v_valid_until date;
  v_metadata jsonb;
  v_result jsonb;
  v_claim_ids uuid[]:='{}'::uuid[];
begin
  select * into v_observation
  from local_intel.ingestion_observations o
  where o.id=p_ingestion_observation_id;

  if v_observation.id is null then
    raise exception 'Ingestion observation not found.' using errcode='P0002';
  end if;

  select * into v_class
  from local_intel.evidence_source_classes c
  where c.source_class_key=p_source_class_key
    and c.class_state='active';

  if v_class.source_class_key is null then
    raise exception 'Evidence source class is missing or inactive.'
      using errcode='P0002';
  end if;

  for v_claim in
    select value
    from jsonb_array_elements(v_observation.extracted_claims)
  loop
    if jsonb_typeof(v_claim)<>'object' then
      raise exception 'Every extracted claim must be a JSON object.'
        using errcode='22023';
    end if;

    v_claim_kind:=lower(btrim(coalesce(v_claim->>'claimKind','')));
    v_value_text:=v_claim->>'valueText';

    if v_claim_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
       or btrim(coalesce(v_value_text,''))='' then
      raise exception 'Extracted claim requires normalized claimKind and nonblank valueText.'
        using errcode='22023';
    end if;

    v_channel:=nullif(lower(btrim(coalesce(v_claim->>'contactChannel',''))),'');
    if v_channel is null then
      if v_claim_kind='email' then
        v_channel:='email';
      elsif v_claim_kind='phone' then
        v_channel:='phone';
      end if;
    end if;

    if v_channel is not null
       and v_channel !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
      raise exception 'Extracted claim contactChannel must be normalized.'
        using errcode='22023';
    end if;

    if v_claim ? 'contactIntents' then
      if jsonb_typeof(v_claim->'contactIntents')<>'array' then
        raise exception 'Extracted claim contactIntents must be an array.'
          using errcode='22023';
      end if;

      select coalesce(array_agg(distinct lower(btrim(x)) order by lower(btrim(x))),'{}'::text[])
      into v_requested_intents
      from jsonb_array_elements_text(v_claim->'contactIntents') t(x)
      where lower(btrim(x)) ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$';
    else
      v_requested_intents:='{}'::text[];
    end if;

    begin
      v_valid_from:=nullif(v_claim->>'validFrom','')::date;
      v_valid_until:=nullif(v_claim->>'validUntil','')::date;
    exception when others then
      raise exception 'Extracted claim validity dates are invalid.'
        using errcode='22023';
    end;

    if v_valid_until is not null
       and v_valid_from is not null
       and v_valid_until<v_valid_from then
      raise exception 'Extracted claim validity end precedes start.'
        using errcode='22023';
    end if;

    if v_claim ? 'metadata' then
      if jsonb_typeof(v_claim->'metadata')<>'object' then
        raise exception 'Extracted claim metadata must be an object.'
          using errcode='22023';
      end if;
      v_metadata:=v_claim->'metadata';
    else
      v_metadata:='{}'::jsonb;
    end if;

    if v_channel is not null
       and 'outreach'=any(v_class.allowed_uses)
       and local_intel.disclosure_posture_rank_v1(
             v_class.maximum_disclosure_posture
           ) >= local_intel.disclosure_posture_rank_v1('public_contactable') then
      v_posture:='public_contactable';
      v_uses:=v_class.allowed_uses;
      v_intents:=case
        when cardinality(v_requested_intents)>0 then v_requested_intents
        else v_class.default_contact_intents
      end;
    elsif 'directory_display'=any(v_class.allowed_uses)
          and local_intel.disclosure_posture_rank_v1(
                v_class.maximum_disclosure_posture
              ) >= local_intel.disclosure_posture_rank_v1('public_directory') then
      v_posture:='public_directory';
      select coalesce(array_agg(u order by u),'{}'::text[])
      into v_uses
      from unnest(v_class.allowed_uses) u
      where u in ('identity_resolution','directory_display');
      v_intents:='{}'::text[];
    else
      v_posture:='resolution_only';
      v_uses:=case
        when 'identity_resolution'=any(v_class.allowed_uses)
          then array['identity_resolution']::text[]
        else '{}'::text[]
      end;
      v_intents:='{}'::text[];
    end if;

    v_result:=local_intel.record_entity_evidence_claim_service_v1(
      p_canonical_entity_id,
      v_claim_kind,
      v_value_text,
      p_source_class_key,
      v_posture,
      v_uses,
      p_source_id,
      null,
      v_channel,
      v_intents,
      v_observation.observed_at,
      v_valid_from,
      v_valid_until,
      v_observation.observed_at,
      v_metadata || jsonb_build_object(
        'ingestionObservationId',v_observation.id,
        'ingestionRunId',v_observation.ingestion_run_id,
        'sourceRecordKey',v_observation.source_record_key,
        'sourceLocator',v_observation.source_locator
      )
    );

    v_claim_ids:=array_append(
      v_claim_ids,
      (v_result->>'evidenceClaimId')::uuid
    );
  end loop;

  return v_claim_ids;
end
$function$;

revoke all on function local_intel.admit_ingestion_observation_claims_internal_v1(
  uuid,uuid,uuid,text
) from public,anon,authenticated,service_role;

create or replace function local_intel.admit_ingestion_observation_service_v1(
  p_ingestion_observation_id uuid,
  p_create_new_entity boolean default false,
  p_local_context_id uuid default null,
  p_approved_by text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_observation local_intel.ingestion_observations%rowtype;
  v_run local_intel.ingestion_runs%rowtype;
  v_ingestion_source local_intel.ingestion_sources%rowtype;
  v_source local_intel.sources%rowtype;
  v_resolution local_intel.ingestion_observation_resolutions%rowtype;
  v_existing_admission local_intel.ingestion_observation_admissions%rowtype;
  v_binding local_intel.ingestion_source_entity_bindings%rowtype;
  v_entity local_intel.entities%rowtype;
  v_source_class_key text;
  v_stable_key text;
  v_claim_ids uuid[];
  v_admission local_intel.ingestion_observation_admissions%rowtype;
  v_created boolean:=false;
begin
  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Admission metadata must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_existing_admission
  from local_intel.ingestion_observation_admissions a
  where a.ingestion_observation_id=p_ingestion_observation_id;

  if v_existing_admission.id is not null then
    return jsonb_build_object(
      'contractVersion','ingestion_observation_admission_v1',
      'admissionId',v_existing_admission.id,
      'ingestionObservationId',v_existing_admission.ingestion_observation_id,
      'canonicalEntityId',v_existing_admission.canonical_entity_id,
      'admissionState',v_existing_admission.admission_state,
      'createdCanonicalEntity',v_existing_admission.created_canonical_entity,
      'sourceClassKey',v_existing_admission.source_class_key,
      'evidenceClaimCount',v_existing_admission.evidence_claim_count,
      'idempotentReplay',true
    );
  end if;

  select * into v_observation
  from local_intel.ingestion_observations o
  where o.id=p_ingestion_observation_id;

  if v_observation.id is null then
    raise exception 'Ingestion observation not found.' using errcode='P0002';
  end if;

  if v_observation.observation_state not in ('resolved','extracted') then
    raise exception 'Observation is not eligible for canonical admission.'
      using errcode='22023';
  end if;

  select * into v_run
  from local_intel.ingestion_runs r
  where r.id=v_observation.ingestion_run_id;

  select * into v_ingestion_source
  from local_intel.ingestion_sources s
  where s.id=v_run.ingestion_source_id;

  select * into v_source
  from local_intel.sources s
  where s.id=v_ingestion_source.source_id;

  if v_source.id is null then
    raise exception 'Configured ingestion source has no canonical source provenance.'
      using errcode='P0002';
  end if;

  v_source_class_key:=coalesce(v_source.source_class_key,'legacy_unclassified');

  if not exists(
    select 1
    from local_intel.evidence_source_classes c
    where c.source_class_key=v_source_class_key
      and c.class_state='active'
  ) then
    raise exception 'Ingestion source classification is missing or inactive.'
      using errcode='P0002';
  end if;

  select * into v_resolution
  from local_intel.ingestion_observation_resolutions r
  where r.ingestion_observation_id=v_observation.id
    and r.is_current
  limit 1;

  if v_resolution.id is null then
    raise exception 'Observation has no current resolution decision.'
      using errcode='22023';
  end if;

  select * into v_binding
  from local_intel.ingestion_source_entity_bindings b
  where b.ingestion_source_id=v_ingestion_source.id
    and b.source_record_key=v_observation.source_record_key
    and b.binding_state='current'
  limit 1;

  if v_resolution.resolution_state='resolved_existing' then
    if p_create_new_entity then
      raise exception 'Resolved-existing observation cannot create a new entity.'
        using errcode='22023';
    end if;

    select * into v_entity
    from local_intel.entities e
    where e.id=v_resolution.canonical_entity_id;

    if v_entity.id is null then
      raise exception 'Resolved canonical entity no longer exists.'
        using errcode='P0002';
    end if;

    if v_binding.id is not null
       and v_binding.canonical_entity_id<>v_entity.id then
      raise exception 'Source-record continuity conflicts with current resolution.'
        using errcode='23505';
    end if;

    perform local_intel.bind_ingestion_source_record_entity_internal_v1(
      v_ingestion_source.id,
      v_observation.source_record_key,
      v_entity.id,
      jsonb_build_object(
        'basis','resolved_existing_admission',
        'ingestionObservationId',v_observation.id,
        'resolutionId',v_resolution.id
      )
    );

  elsif v_resolution.resolution_state='new_entity_candidate' then
    if not p_create_new_entity then
      raise exception 'New entity candidate requires explicit create_new_entity approval.'
        using errcode='22023';
    end if;

    if btrim(coalesce(p_approved_by,''))='' then
      raise exception 'New canonical entity creation requires explicit approver identity.'
        using errcode='22023';
    end if;

    if p_local_context_id is null
       or not exists(
         select 1
         from local_intel.local_contexts c
         where c.id=p_local_context_id and c.status='active'
       ) then
      raise exception 'Active local context is required for new canonical entity creation.'
        using errcode='22023';
    end if;

    if v_binding.id is not null then
      raise exception 'Source record is already bound; resolver must resolve the existing entity.'
        using errcode='23505';
    end if;

    if v_observation.proposed_entity_type is null
       or btrim(coalesce(v_observation.proposed_display_name,''))='' then
      raise exception 'New entity candidate requires proposed entity type and display name.'
        using errcode='22023';
    end if;

    v_stable_key:='ingested_' || substr(
      md5(v_ingestion_source.id::text || ':' || v_observation.source_record_key),
      1,24
    );

    insert into local_intel.entities(
      stable_key,entity_type,name,status,verification_state,
      last_verified_at,metadata,local_context_id
    )
    values(
      v_stable_key,
      v_observation.proposed_entity_type,
      btrim(v_observation.proposed_display_name),
      'active',
      'public_indexed',
      v_observation.observed_at,
      jsonb_build_object(
        'canonicalOrigin','bulk_ingestion_admission_v1',
        'ingestionSourceId',v_ingestion_source.id,
        'sourceRecordKey',v_observation.source_record_key,
        'ingestionObservationId',v_observation.id,
        'approvedBy',btrim(p_approved_by)
      ),
      p_local_context_id
    )
    returning * into v_entity;

    v_created:=true;

    perform local_intel.bind_ingestion_source_record_entity_internal_v1(
      v_ingestion_source.id,
      v_observation.source_record_key,
      v_entity.id,
      jsonb_build_object(
        'basis','new_entity_admission',
        'ingestionObservationId',v_observation.id,
        'resolutionId',v_resolution.id,
        'approvedBy',btrim(p_approved_by)
      )
    );

  elsif v_resolution.resolution_state='ambiguous' then
    raise exception 'Ambiguous observation cannot be canonically admitted.'
      using errcode='22023';
  elsif v_resolution.resolution_state='rejected' then
    raise exception 'Rejected observation cannot be canonically admitted.'
      using errcode='22023';
  else
    raise exception 'Unsupported observation resolution state.'
      using errcode='22023';
  end if;

  v_claim_ids:=local_intel.admit_ingestion_observation_claims_internal_v1(
    v_observation.id,
    v_entity.id,
    v_source.id,
    v_source_class_key
  );

  insert into local_intel.ingestion_observation_admissions(
    ingestion_observation_id,canonical_entity_id,admission_state,
    created_canonical_entity,source_class_key,evidence_claim_ids,
    evidence_claim_count,approved_by,metadata
  )
  values(
    v_observation.id,
    v_entity.id,
    case when v_created then 'created_and_admitted' else 'admitted_existing' end,
    v_created,
    v_source_class_key,
    coalesce(v_claim_ids,'{}'::uuid[]),
    cardinality(coalesce(v_claim_ids,'{}'::uuid[])),
    case when v_created then btrim(p_approved_by) else null end,
    coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_admission;

  update local_intel.ingestion_observations
  set observation_state='admitted'
  where id=v_observation.id;

  return jsonb_build_object(
    'contractVersion','ingestion_observation_admission_v1',
    'admissionId',v_admission.id,
    'ingestionObservationId',v_admission.ingestion_observation_id,
    'canonicalEntityId',v_admission.canonical_entity_id,
    'admissionState',v_admission.admission_state,
    'createdCanonicalEntity',v_admission.created_canonical_entity,
    'sourceClassKey',v_admission.source_class_key,
    'evidenceClaimCount',v_admission.evidence_claim_count,
    'evidenceClaimIds',to_jsonb(v_admission.evidence_claim_ids),
    'idempotentReplay',false
  );
end
$function$;

revoke all on function local_intel.admit_ingestion_observation_service_v1(
  uuid,boolean,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.admit_ingestion_observation_service_v1(
  uuid,boolean,uuid,text,jsonb
) to service_role;
