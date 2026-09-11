BEGIN;

-- Atlas Organization Expense Evidence Intake v1 schema proof.
-- Development proof only. NOT a canonical migration.
-- Reuses atlas.evidence_records and ends in ROLLBACK.

create table atlas.organization_evidence_inbox_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid references atlas.organization_units(id) on delete restrict,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  capture_kind text not null check (capture_kind in ('receipt','factura','invoice','supporting_document')),
  captured_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  context_note text,
  intake_state text not null default 'received'
    check (intake_state in ('received','extracted','needs_review','ready_to_admit','admitted','ignored')),
  admitted_source_authority text,
  admitted_source_ref text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (context_note is null or btrim(context_note)<>''),
  check (
    (intake_state='admitted' and nullif(btrim(coalesce(admitted_source_authority,'')),'') is not null and nullif(btrim(coalesce(admitted_source_ref,'')),'') is not null)
    or intake_state<>'admitted'
  ),
  unique (evidence_record_id),
  unique (id, organization_id)
);

create table atlas.organization_evidence_extraction_candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  inbox_item_id uuid not null,
  evidence_record_id uuid not null references atlas.evidence_records(id) on delete restrict,
  extractor_kind text not null check (btrim(extractor_kind)<>''),
  extractor_key text not null check (btrim(extractor_key)<>''),
  extractor_version text not null check (btrim(extractor_version)<>''),
  attempt_key text not null check (btrim(attempt_key)<>''),
  input_sha256 text not null check (input_sha256 ~ '^[0-9a-f]{64}$'),
  candidate jsonb not null check (jsonb_typeof(candidate)='object'),
  field_confidence jsonb not null default '{}'::jsonb check (jsonb_typeof(field_confidence)='object'),
  overall_confidence numeric check (overall_confidence is null or (overall_confidence>=0 and overall_confidence<=1)),
  created_at timestamptz not null default now(),
  foreign key (inbox_item_id, organization_id)
    references atlas.organization_evidence_inbox_items(id, organization_id)
    on delete cascade,
  unique (inbox_item_id, extractor_kind, extractor_key, extractor_version, attempt_key)
);

create index organization_evidence_inbox_org_state_idx
  on atlas.organization_evidence_inbox_items (organization_id,intake_state,created_at desc,id);

create index organization_evidence_extraction_inbox_idx
  on atlas.organization_evidence_extraction_candidates (inbox_item_id,created_at desc,id);

create or replace function atlas.guard_organization_evidence_inbox_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  if new.organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units u
    where u.id=new.organization_unit_id and u.organization_id=new.organization_id
  ) then
    raise exception 'Evidence organization unit must belong to organization.' using errcode='23503';
  end if;

  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=new.captured_by_membership_id and m.organization_id=new.organization_id
  ) then
    raise exception 'Evidence capturing membership must belong to organization.' using errcode='23503';
  end if;

  if not exists (
    select 1 from atlas.evidence_records e
    where e.id=new.evidence_record_id and e.scope_kind='organization' and e.scope_id=new.organization_id
  ) then
    raise exception 'Evidence record must be organization-scoped to this organization.' using errcode='23503';
  end if;

  return new;
end;
$function$;

create trigger guard_organization_evidence_inbox_v1
before insert or update on atlas.organization_evidence_inbox_items
for each row execute function atlas.guard_organization_evidence_inbox_v1();

create or replace function atlas.prevent_organization_evidence_extraction_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog
as $function$
begin
  raise exception 'Organization evidence extraction attempts are append-only.' using errcode='55000';
end;
$function$;

create trigger prevent_organization_evidence_extraction_update_v1
before update or delete on atlas.organization_evidence_extraction_candidates
for each row execute function atlas.prevent_organization_evidence_extraction_mutation_v1();

create or replace function atlas.register_organization_expense_document_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_capture_kind text,
  p_source_key text,
  p_bucket text,
  p_object_path text,
  p_mime_type text,
  p_byte_size bigint,
  p_sha256 text,
  p_original_filename text,
  p_context_note text default null,
  p_observed_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_membership_id uuid;
  v_evidence atlas.evidence_records%rowtype;
  v_inbox atlas.organization_evidence_inbox_items%rowtype;
  v_value jsonb;
  v_existing_value jsonb;
  v_created boolean := false;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_membership_id := atlas.current_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;

  if p_organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units u
    where u.id=p_organization_unit_id and u.organization_id=p_organization_id
  ) then
    raise exception 'Organization unit does not belong to organization.' using errcode='23503';
  end if;

  if p_capture_kind not in ('receipt','factura','invoice','supporting_document') then
    raise exception 'Unsupported expense evidence capture kind.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_source_key,'')),'') is null then raise exception 'source key is required.' using errcode='22023'; end if;
  if p_bucket<>'atlas-organization-evidence' then raise exception 'Unexpected evidence storage bucket.' using errcode='22023'; end if;
  if nullif(btrim(coalesce(p_object_path,'')),'') is null then raise exception 'object path is required.' using errcode='22023'; end if;
  if p_mime_type not in ('image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf') then
    raise exception 'Unsupported expense evidence MIME type.' using errcode='22023';
  end if;
  if p_byte_size is null or p_byte_size<=0 or p_byte_size>20971520 then raise exception 'Expense evidence file size is invalid.' using errcode='22023'; end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'Valid lowercase SHA-256 is required.' using errcode='22023'; end if;

  v_value := jsonb_build_object(
    'storage',jsonb_build_object('bucket',p_bucket,'objectPath',p_object_path),
    'mimeType',p_mime_type,
    'byteSize',p_byte_size,
    'sha256',p_sha256,
    'originalFilename',nullif(btrim(coalesce(p_original_filename,'')),'')
  );

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    evidence_kind,source_kind,source_key,actor_user_id,value,observed_at,provenance,metadata
  ) values (
    'organization',p_organization_id,'organization_finance','expense_document_capture',p_source_key,
    p_capture_kind,'atlas_storage_object',p_source_key,v_user_id,v_value,p_observed_at,
    jsonb_build_object('capture','atlas_expense_evidence_intake_v1'),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (scope_kind,scope_id,source_kind,source_key) do nothing
  returning * into v_evidence;

  if v_evidence.id is not null then
    v_created := true;
  else
    select * into v_evidence
    from atlas.evidence_records e
    where e.scope_kind='organization' and e.scope_id=p_organization_id
      and e.source_kind='atlas_storage_object' and e.source_key=p_source_key;

    if v_evidence.id is null or v_evidence.subject_domain<>'organization_finance'
       or v_evidence.subject_kind<>'expense_document_capture'
       or v_evidence.evidence_kind<>p_capture_kind
       or v_evidence.value is distinct from v_value then
      raise exception 'source key retry does not match existing expense evidence.' using errcode='23505';
    end if;
  end if;

  insert into atlas.organization_evidence_inbox_items(
    organization_id,organization_unit_id,evidence_record_id,capture_kind,captured_by_membership_id,context_note,metadata
  ) values (
    p_organization_id,p_organization_unit_id,v_evidence.id,p_capture_kind,v_membership_id,
    nullif(btrim(coalesce(p_context_note,'')),''),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (evidence_record_id) do update
    set context_note=coalesce(atlas.organization_evidence_inbox_items.context_note,excluded.context_note)
  returning * into v_inbox;

  return jsonb_build_object(
    'contractVersion','register_organization_expense_document_api_v1',
    'state',case when v_created then 'admitted' else 'already_in_custody' end,
    'evidenceRecordId',v_evidence.id,
    'inboxItemId',v_inbox.id,
    'intakeState',v_inbox.intake_state,
    'safeFile',jsonb_build_object(
      'mimeType',p_mime_type,
      'byteSize',p_byte_size,
      'sha256',p_sha256,
      'originalFilename',nullif(btrim(coalesce(p_original_filename,'')),'')
    )
  );
end;
$function$;

create or replace function atlas.record_organization_evidence_extraction_internal_v1(
  p_inbox_item_id uuid,
  p_extractor_kind text,
  p_extractor_key text,
  p_extractor_version text,
  p_attempt_key text,
  p_input_sha256 text,
  p_candidate jsonb,
  p_field_confidence jsonb default '{}'::jsonb,
  p_overall_confidence numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_inbox atlas.organization_evidence_inbox_items%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_row atlas.organization_evidence_extraction_candidates%rowtype;
  v_existing atlas.organization_evidence_extraction_candidates%rowtype;
  v_expected_hash text;
begin
  select * into v_inbox from atlas.organization_evidence_inbox_items where id=p_inbox_item_id;
  if not found then raise exception 'Evidence inbox item not found.' using errcode='23503'; end if;
  select * into v_evidence from atlas.evidence_records where id=v_inbox.evidence_record_id;
  v_expected_hash := v_evidence.value->>'sha256';

  if p_input_sha256 is distinct from v_expected_hash then
    raise exception 'Extraction input hash does not match evidence file hash.' using errcode='23514';
  end if;
  if jsonb_typeof(p_candidate)<>'object' or jsonb_typeof(coalesce(p_field_confidence,'{}'::jsonb))<>'object' then
    raise exception 'Extraction candidate/confidence must be JSON objects.' using errcode='22023';
  end if;
  if p_overall_confidence is not null and (p_overall_confidence<0 or p_overall_confidence>1) then
    raise exception 'Overall confidence must be between 0 and 1.' using errcode='22023';
  end if;

  insert into atlas.organization_evidence_extraction_candidates(
    organization_id,inbox_item_id,evidence_record_id,extractor_kind,extractor_key,extractor_version,
    attempt_key,input_sha256,candidate,field_confidence,overall_confidence
  ) values (
    v_inbox.organization_id,v_inbox.id,v_inbox.evidence_record_id,btrim(p_extractor_kind),btrim(p_extractor_key),btrim(p_extractor_version),
    btrim(p_attempt_key),p_input_sha256,p_candidate,coalesce(p_field_confidence,'{}'::jsonb),p_overall_confidence
  )
  on conflict (inbox_item_id,extractor_kind,extractor_key,extractor_version,attempt_key) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_existing
    from atlas.organization_evidence_extraction_candidates x
    where x.inbox_item_id=v_inbox.id and x.extractor_kind=btrim(p_extractor_kind)
      and x.extractor_key=btrim(p_extractor_key) and x.extractor_version=btrim(p_extractor_version)
      and x.attempt_key=btrim(p_attempt_key);
    if v_existing.candidate is distinct from p_candidate
       or v_existing.field_confidence is distinct from coalesce(p_field_confidence,'{}'::jsonb)
       or v_existing.overall_confidence is distinct from p_overall_confidence
       or v_existing.input_sha256 is distinct from p_input_sha256 then
      raise exception 'Extraction attempt replay does not match existing candidate.' using errcode='23505';
    end if;
    v_row := v_existing;
  end if;

  update atlas.organization_evidence_inbox_items
  set intake_state=case when intake_state='received' then 'extracted' else intake_state end,updated_at=now()
  where id=v_inbox.id;

  return jsonb_build_object(
    'contractVersion','record_organization_evidence_extraction_internal_v1',
    'extractionCandidateId',v_row.id,
    'inboxItemId',v_inbox.id,
    'candidate',v_row.candidate,
    'overallConfidence',v_row.overall_confidence,
    'authority','suggestion_only'
  );
end;
$function$;

create or replace function atlas.organization_expense_evidence_inbox_self_api_v1(
  p_organization_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_membership uuid;
begin
  v_membership := atlas.current_organization_membership_v1(p_organization_id);
  if v_membership is null then raise exception 'Active organization membership required.' using errcode='42501'; end if;

  return jsonb_build_object(
    'contractVersion','organization_expense_evidence_inbox_self_api_v1',
    'organizationId',p_organization_id,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'inboxItemId',i.id,
        'evidenceRecordId',i.evidence_record_id,
        'organizationUnitId',i.organization_unit_id,
        'captureKind',i.capture_kind,
        'contextNote',i.context_note,
        'intakeState',i.intake_state,
        'capturedAt',i.created_at,
        'file',jsonb_build_object(
          'mimeType',e.value->>'mimeType',
          'byteSize',e.value->'byteSize',
          'sha256',e.value->>'sha256',
          'originalFilename',e.value->>'originalFilename'
        ),
        'latestExtraction',(
          select jsonb_build_object(
            'candidate',x.candidate,
            'fieldConfidence',x.field_confidence,
            'overallConfidence',x.overall_confidence,
            'extractorKind',x.extractor_kind,
            'extractorKey',x.extractor_key,
            'extractorVersion',x.extractor_version,
            'createdAt',x.created_at,
            'authority','suggestion_only'
          )
          from atlas.organization_evidence_extraction_candidates x
          where x.inbox_item_id=i.id order by x.created_at desc,x.id desc limit 1
        ),
        'admittedSource',case when i.admitted_source_authority is null then null else jsonb_build_object(
          'authority',i.admitted_source_authority,'ref',i.admitted_source_ref
        ) end
      ) order by i.created_at desc,i.id desc)
      from (
        select * from atlas.organization_evidence_inbox_items
        where organization_id=p_organization_id
        order by created_at desc,id desc
        limit greatest(1,least(coalesce(p_limit,50),200))
      ) i
      join atlas.evidence_records e on e.id=i.evidence_record_id
    ),'[]'::jsonb)
  );
end;
$function$;

-- Candidate direct-table posture: applications use RPC membranes.
revoke all on atlas.organization_evidence_inbox_items from anon,authenticated;
revoke all on atlas.organization_evidence_extraction_candidates from anon,authenticated;
revoke all on function atlas.register_organization_expense_document_api_v1(uuid,uuid,text,text,text,text,text,bigint,text,text,text,timestamptz,jsonb) from public,anon;
grant execute on function atlas.register_organization_expense_document_api_v1(uuid,uuid,text,text,text,text,text,bigint,text,text,text,timestamptz,jsonb) to authenticated;
revoke all on function atlas.organization_expense_evidence_inbox_self_api_v1(uuid,integer) from public,anon;
grant execute on function atlas.organization_expense_evidence_inbox_self_api_v1(uuid,integer) to authenticated;
revoke all on function atlas.record_organization_evidence_extraction_internal_v1(uuid,text,text,text,text,text,jsonb,jsonb,numeric) from public,anon,authenticated;

ROLLBACK;
