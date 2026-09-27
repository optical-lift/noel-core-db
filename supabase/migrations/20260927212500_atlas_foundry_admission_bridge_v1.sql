-- Atlas Foundry -> Atlas Admission Bridge v1
--
-- Foundry establishes a sealed pre-Atlas candidate. This membrane stages that
-- candidate immutably, governs subject identity admission/binding, and hands the
-- candidate into ordinary practitioner onboarding. It does not activate a Ledger
-- and does not bulk-promote Foundry assertions into canonical Atlas truth.

create schema admission;

revoke all on schema admission from public,anon,authenticated;
grant usage on schema admission to service_role;


create table admission.foundry_packages (
  id uuid primary key default gen_random_uuid(),
  package_id text not null unique check (btrim(package_id)<>''),
  workspace_id text not null check (btrim(workspace_id)<>''),
  ledger_candidate_id text not null check (btrim(ledger_candidate_id)<>''),
  exchange_version text not null check (btrim(exchange_version)<>''),
  foundry_protocol_version text not null check (btrim(foundry_protocol_version)<>''),
  release_version text not null check (btrim(release_version)<>''),
  subject_name text not null check (btrim(subject_name)<>''),
  field_description text not null check (btrim(field_description)<>''),
  sealed_at timestamptz not null,
  integrity_hash text null,
  package_payload jsonb not null check (jsonb_typeof(package_payload)='object'),
  source_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(source_metadata)='object'),
  package_state text not null default 'staged'
    check (package_state in (
      'staged','reviewing','blocked','ready_for_handoff','handed_to_onboarding','rejected'
    )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index admission_foundry_packages_workspace_idx
  on admission.foundry_packages(workspace_id,ledger_candidate_id,created_at desc);


create table admission.foundry_admission_cases (
  id uuid primary key default gen_random_uuid(),
  foundry_package_id uuid not null unique
    references admission.foundry_packages(id) on delete restrict,
  case_state text not null default 'open'
    check (case_state in (
      'open','blocked','ready_for_handoff','handed_to_onboarding','rejected'
    )),
  subject_disposition text not null default 'unresolved'
    check (subject_disposition in (
      'unresolved','use_existing_entity','create_entity'
    )),
  selected_entity_id uuid null references reality.entities(id) on delete restrict,
  new_entity_spec jsonb not null default '{}'::jsonb
    check (jsonb_typeof(new_entity_spec)='object'),
  identity_collision_basis text null,
  desired_ledger_name text null,
  ledger_boundary_basis text null,
  plan_basis text null,
  impact_preview jsonb not null default '{}'::jsonb
    check (jsonb_typeof(impact_preview)='object'),
  blockers jsonb not null default '[]'::jsonb
    check (jsonb_typeof(blockers)='array'),
  planned_by_person_entity_id uuid null references reality.entities(id) on delete restrict,
  planning_responsibility_relation_id uuid null
    references reality.responsibility_relations(id) on delete restrict,
  planned_at timestamptz null,
  resolved_subject_entity_id uuid null references reality.entities(id) on delete restrict,
  onboarding_case_id uuid null references ledger.onboarding_cases(id) on delete restrict,
  handed_off_by_person_entity_id uuid null references reality.entities(id) on delete restrict,
  handoff_responsibility_relation_id uuid null
    references reality.responsibility_relations(id) on delete restrict,
  handoff_basis text null,
  execution_receipt jsonb not null default '{}'::jsonb
    check (jsonb_typeof(execution_receipt)='object'),
  handed_off_at timestamptz null,
  rejected_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index admission_foundry_cases_state_idx
  on admission.foundry_admission_cases(case_state,created_at desc);

alter table admission.foundry_packages enable row level security;
alter table admission.foundry_admission_cases enable row level security;

revoke all on table admission.foundry_packages
  from public,anon,authenticated,service_role;
revoke all on table admission.foundry_admission_cases
  from public,anon,authenticated,service_role;


create or replace function admission.guard_foundry_package_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='UPDATE' then
    if old.package_id is distinct from new.package_id
       or old.workspace_id is distinct from new.workspace_id
       or old.ledger_candidate_id is distinct from new.ledger_candidate_id
       or old.exchange_version is distinct from new.exchange_version
       or old.foundry_protocol_version is distinct from new.foundry_protocol_version
       or old.release_version is distinct from new.release_version
       or old.subject_name is distinct from new.subject_name
       or old.field_description is distinct from new.field_description
       or old.sealed_at is distinct from new.sealed_at
       or old.integrity_hash is distinct from new.integrity_hash
       or old.package_payload is distinct from new.package_payload
       or old.source_metadata is distinct from new.source_metadata then
      raise exception 'Staged Foundry package identity and payload are immutable.'
        using errcode='23514';
    end if;

    if old.package_state='handed_to_onboarding'
       and new.package_state<>old.package_state then
      raise exception 'A handed-off Foundry package is terminal.' using errcode='23514';
    end if;
    if old.package_state='rejected'
       and new.package_state<>old.package_state then
      raise exception 'A rejected Foundry package is terminal.' using errcode='23514';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger admission_foundry_package_guard_v1
before update on admission.foundry_packages
for each row execute function admission.guard_foundry_package_v1();


create or replace function atlas.stage_foundry_ledger_candidate_service_v1(
  p_package jsonb,
  p_integrity_hash text default null,
  p_source_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_required text;
  v_manifest jsonb;
  v_package_id text;
  v_workspace_id text;
  v_ledger_candidate_id text;
  v_exchange_version text;
  v_protocol_version text;
  v_release_version text;
  v_subject_name text;
  v_field_description text;
  v_blocking_unknown_count integer;
  v_sealed_at timestamptz;
  v_existing admission.foundry_packages%rowtype;
  v_package_row admission.foundry_packages%rowtype;
  v_case_id uuid;
begin
  if p_package is null or jsonb_typeof(p_package)<>'object' then
    raise exception 'Foundry exchange package must be a JSON object.' using errcode='22023';
  end if;
  if p_source_metadata is null or jsonb_typeof(p_source_metadata)<>'object' then
    raise exception 'Foundry source metadata must be a JSON object.' using errcode='22023';
  end if;

  foreach v_required in array array[
    'manifest','subject','sources','testimony','assertions','current_position',
    'standing_law','authority','commitments','unknowns','closure','ledger_topology',
    'acceptance','history','release'
  ] loop
    if not (p_package ? v_required) then
      raise exception 'Foundry package is missing required section: %',v_required
        using errcode='22023';
    end if;
  end loop;

  if jsonb_typeof(p_package->'manifest')<>'object'
     or jsonb_typeof(p_package->'release')<>'object' then
    raise exception 'Foundry manifest and release must be JSON objects.' using errcode='22023';
  end if;

  v_manifest:=p_package->'manifest';
  v_package_id:=nullif(btrim(v_manifest->>'package_id'),'');
  v_workspace_id:=nullif(btrim(v_manifest->>'workspace_id'),'');
  v_ledger_candidate_id:=nullif(btrim(v_manifest->>'ledger_candidate_id'),'');
  v_exchange_version:=nullif(btrim(v_manifest->>'exchange_version'),'');
  v_protocol_version:=nullif(btrim(v_manifest->>'foundry_protocol_version'),'');
  v_release_version:=nullif(btrim(v_manifest->>'release_version'),'');
  v_subject_name:=nullif(btrim(v_manifest->>'subject_name'),'');
  v_field_description:=nullif(btrim(v_manifest->>'field_description'),'');

  if v_package_id is null or v_workspace_id is null or v_ledger_candidate_id is null
     or v_exchange_version is null or v_protocol_version is null
     or v_release_version is null or v_subject_name is null
     or v_field_description is null then
    raise exception 'Foundry manifest is missing required admission identity fields.'
      using errcode='22023';
  end if;

  if v_exchange_version<>'0.1' or v_protocol_version<>'0.1' then
    raise exception 'Unsupported Foundry compatibility: exchange %, protocol %.',
      v_exchange_version,v_protocol_version using errcode='22023';
  end if;

  if coalesce(v_manifest->>'blocking_unknown_count','') !~ '^[0-9]+$' then
    raise exception 'Foundry manifest blocking_unknown_count is required.'
      using errcode='22023';
  end if;
  v_blocking_unknown_count:=(v_manifest->>'blocking_unknown_count')::integer;
  if v_blocking_unknown_count<>0 then
    raise exception 'A sealed candidate with blocking unknowns cannot enter Atlas admission.'
      using errcode='23514';
  end if;

  begin
    v_sealed_at:=(v_manifest->>'sealed_at')::timestamptz;
  exception when others then
    raise exception 'Foundry manifest sealed_at must be a valid timestamp.'
      using errcode='22023';
  end;
  if v_sealed_at is null then
    raise exception 'Foundry manifest sealed_at is required.' using errcode='22023';
  end if;

  select * into v_existing
  from admission.foundry_packages
  where package_id=v_package_id;

  if found then
    if v_existing.package_payload<>p_package
       or v_existing.integrity_hash is distinct from nullif(btrim(coalesce(p_integrity_hash,'')),'') then
      raise exception 'Foundry package ID was reused for different content.' using errcode='23505';
    end if;

    select id into v_case_id
    from admission.foundry_admission_cases
    where foundry_package_id=v_existing.id;

    return jsonb_build_object(
      'contractVersion','foundry_atlas_admission_v1',
      'state','already_staged',
      'foundryPackageId',v_existing.id,
      'admissionCaseId',v_case_id,
      'packageId',v_existing.package_id,
      'canonicalAtlasWriteOccurred',false
    );
  end if;

  insert into admission.foundry_packages(
    package_id,workspace_id,ledger_candidate_id,exchange_version,
    foundry_protocol_version,release_version,subject_name,field_description,
    sealed_at,integrity_hash,package_payload,source_metadata
  ) values (
    v_package_id,v_workspace_id,v_ledger_candidate_id,v_exchange_version,
    v_protocol_version,v_release_version,v_subject_name,v_field_description,
    v_sealed_at,nullif(btrim(coalesce(p_integrity_hash,'')),''),p_package,p_source_metadata
  ) returning * into v_package_row;

  insert into admission.foundry_admission_cases(foundry_package_id)
  values(v_package_row.id)
  returning id into v_case_id;

  return jsonb_build_object(
    'contractVersion','foundry_atlas_admission_v1',
    'state','staged',
    'foundryPackageId',v_package_row.id,
    'admissionCaseId',v_case_id,
    'packageId',v_package_row.package_id,
    'workspaceId',v_package_row.workspace_id,
    'ledgerCandidateId',v_package_row.ledger_candidate_id,
    'canonicalAtlasWriteOccurred',false,
    'ledgerActivated',false
  );
end
$function$;

revoke all on function atlas.stage_foundry_ledger_candidate_service_v1(
  jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.stage_foundry_ledger_candidate_service_v1(
  jsonb,text,jsonb
) to service_role;


create or replace function admission.foundry_admission_preview_internal_v1(
  p_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_case admission.foundry_admission_cases%rowtype;
  v_package admission.foundry_packages%rowtype;
  v_blockers jsonb:='[]'::jsonb;
  v_name_matches jsonb:='[]'::jsonb;
  v_active_ledgers jsonb:='[]'::jsonb;
  v_stable_key text;
  v_entity_kind text;
  v_display_name text;
  v_stable_collision uuid;
  v_selected_state text;
begin
  select * into v_case
  from admission.foundry_admission_cases
  where id=p_case_id;
  if not found then
    raise exception 'Foundry admission case not found.' using errcode='22023';
  end if;

  select * into v_package
  from admission.foundry_packages
  where id=v_case.foundry_package_id;

  if v_case.subject_disposition='unresolved' then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','SUBJECT_IDENTITY_UNRESOLVED',
      'message','Choose whether the Foundry subject binds to existing Reality or is admitted as a new Entity.'
    ));
  elsif v_case.subject_disposition='use_existing_entity' then
    select identity_state into v_selected_state
    from reality.entities where id=v_case.selected_entity_id;

    if v_selected_state is distinct from 'canonical' then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','CANONICAL_EXISTING_ENTITY_REQUIRED',
        'message','Selected existing subject must be a canonical Reality Entity.'
      ));
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
      'ledgerId',l.id,'stableKey',l.stable_key,'name',l.name,'state',l.ledger_state
    ) order by l.name,l.id),'[]'::jsonb)
    into v_active_ledgers
    from ledger.ledgers l
    where l.subject_entity_id=v_case.selected_entity_id
      and l.ledger_state='active';

    if jsonb_array_length(v_active_ledgers)>0
       and nullif(btrim(coalesce(v_case.ledger_boundary_basis,'')),'') is null then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','LEDGER_BOUNDARY_BASIS_REQUIRED',
        'message','The subject already has active Ledgers; explain why this Foundry candidate is a distinct governing field.'
      ));
    end if;
  elsif v_case.subject_disposition='create_entity' then
    v_stable_key:=nullif(btrim(v_case.new_entity_spec->>'stableKey'),'');
    v_entity_kind:=nullif(btrim(v_case.new_entity_spec->>'entityKind'),'');
    v_display_name:=nullif(btrim(v_case.new_entity_spec->>'displayName'),'');

    if v_stable_key is null or v_entity_kind is null or v_display_name is null then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','NEW_ENTITY_SPEC_INCOMPLETE',
        'message','New Reality Entity requires stableKey, entityKind, and displayName.'
      ));
    else
      select id into v_stable_collision
      from reality.entities
      where stable_key=v_stable_key
      limit 1;

      if v_stable_collision is not null then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'code','REALITY_STABLE_KEY_COLLISION',
          'entityId',v_stable_collision,
          'message','Proposed Reality stable key already exists.'
        ));
      end if;

      select coalesce(jsonb_agg(jsonb_build_object(
        'entityId',e.id,'stableKey',e.stable_key,'displayName',e.display_name,
        'entityKind',e.entity_kind,'identityState',e.identity_state
      ) order by e.stable_key,e.id),'[]'::jsonb)
      into v_name_matches
      from reality.entities e
      where e.identity_state='canonical'
        and lower(btrim(e.display_name))=lower(v_display_name)
        and e.entity_kind=v_entity_kind;

      if jsonb_array_length(v_name_matches)>0
         and nullif(btrim(coalesce(v_case.identity_collision_basis,'')),'') is null then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'code','IDENTITY_COLLISION_REVIEW_REQUIRED',
          'message','Reality contains canonical same-kind/same-name candidates; record why this is not one of them.'
        ));
      end if;
    end if;
  end if;

  if nullif(btrim(coalesce(v_case.desired_ledger_name,'')),'') is null then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','DESIRED_LEDGER_NAME_REQUIRED',
      'message','A Ledger candidate name is required for practitioner onboarding handoff.'
    ));
  end if;

  if nullif(btrim(coalesce(v_case.plan_basis,'')),'') is null then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','ADMISSION_PLAN_BASIS_REQUIRED',
      'message','Admission plan requires an explicit human-readable basis.'
    ));
  end if;

  return jsonb_build_object(
    'contractVersion','foundry_atlas_admission_v1',
    'caseId',v_case.id,
    'foundry',jsonb_build_object(
      'packageId',v_package.package_id,
      'workspaceId',v_package.workspace_id,
      'ledgerCandidateId',v_package.ledger_candidate_id,
      'protocolVersion',v_package.foundry_protocol_version,
      'exchangeVersion',v_package.exchange_version,
      'releaseVersion',v_package.release_version,
      'sealedAt',v_package.sealed_at,
      'subjectName',v_package.subject_name,
      'fieldDescription',v_package.field_description
    ),
    'subjectDisposition',v_case.subject_disposition,
    'selectedEntityId',v_case.selected_entity_id,
    'proposedNewEntity',v_case.new_entity_spec,
    'exactNameKindCandidates',v_name_matches,
    'existingActiveLedgers',v_active_ledgers,
    'identityCollisionBasis',v_case.identity_collision_basis,
    'ledgerBoundaryBasis',v_case.ledger_boundary_basis,
    'desiredLedgerName',v_case.desired_ledger_name,
    'blockers',v_blockers,
    'canHandoff',jsonb_array_length(v_blockers)=0,
    'truthBoundary',jsonb_build_object(
      'databaseCollisionPreviewIsNotOmniscientIdentityResolution',true,
      'foundryEstablishedIsPreAtlas',true,
      'foundrySealDoesNotActivateLedger',true,
      'baselinePromotionPendingPractitionerMapping',true
    )
  );
end
$function$;

revoke all on function admission.foundry_admission_preview_internal_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.foundry_admission_plan_self_api_v1(
  p_case_id uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality','admission'
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
  v_case admission.foundry_admission_cases%rowtype;
  v_disposition text;
  v_selected uuid;
  v_new_entity jsonb;
  v_plan_basis text;
  v_collision_basis text;
  v_boundary_basis text;
  v_ledger_name text;
  v_preview jsonb;
  v_ready boolean;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,'foundry_admission_governance','foundry_admission.plan',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  );
  if v_relation_id is null then
    raise exception 'Foundry admission planning responsibility required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Foundry admission plan must be a JSON object.' using errcode='22023';
  end if;

  select * into v_case
  from admission.foundry_admission_cases
  where id=p_case_id
  for update;
  if not found then
    raise exception 'Foundry admission case not found.' using errcode='22023';
  end if;
  if v_case.case_state in ('handed_to_onboarding','rejected') then
    raise exception 'Foundry admission case is terminal.' using errcode='22023';
  end if;

  v_disposition:=nullif(btrim(p_input->>'subjectDisposition'),'');
  if v_disposition not in ('use_existing_entity','create_entity') then
    raise exception 'subjectDisposition must be use_existing_entity or create_entity.'
      using errcode='22023';
  end if;

  v_plan_basis:=nullif(btrim(p_input->>'basis'),'');
  v_collision_basis:=nullif(btrim(p_input->>'identityCollisionBasis'),'');
  v_boundary_basis:=nullif(btrim(p_input->>'ledgerBoundaryBasis'),'');
  v_ledger_name:=nullif(btrim(p_input->>'desiredLedgerName'),'');
  v_new_entity:=coalesce(p_input->'newEntity','{}'::jsonb);

  if v_plan_basis is null then
    raise exception 'Admission plan basis is required.' using errcode='22023';
  end if;
  if length(v_plan_basis)>8000 then
    raise exception 'Admission plan basis is too long.' using errcode='22023';
  end if;
  if v_ledger_name is null then
    raise exception 'desiredLedgerName is required.' using errcode='22023';
  end if;

  if v_disposition='use_existing_entity' then
    begin
      v_selected:=nullif(btrim(p_input->>'subjectEntityId'),'')::uuid;
    exception when invalid_text_representation then
      raise exception 'Valid subjectEntityId is required for existing Reality binding.'
        using errcode='22023';
    end;
    if v_selected is null then
      raise exception 'Valid subjectEntityId is required for existing Reality binding.'
        using errcode='22023';
    end if;
    v_new_entity:='{}'::jsonb;
  else
    if jsonb_typeof(v_new_entity)<>'object' then
      raise exception 'newEntity must be a JSON object.' using errcode='22023';
    end if;
    v_selected:=null;
  end if;

  update admission.foundry_admission_cases
  set subject_disposition=v_disposition,
      selected_entity_id=v_selected,
      new_entity_spec=v_new_entity,
      identity_collision_basis=v_collision_basis,
      desired_ledger_name=v_ledger_name,
      ledger_boundary_basis=v_boundary_basis,
      plan_basis=v_plan_basis,
      planned_by_person_entity_id=v_person_id,
      planning_responsibility_relation_id=v_relation_id,
      planned_at=now(),
      updated_at=now()
  where id=p_case_id;

  update admission.foundry_packages p
  set package_state='reviewing'
  from admission.foundry_admission_cases c
  where c.id=p_case_id and p.id=c.foundry_package_id
    and p.package_state not in ('handed_to_onboarding','rejected');

  v_preview:=admission.foundry_admission_preview_internal_v1(p_case_id);
  v_ready:=coalesce((v_preview->>'canHandoff')::boolean,false);

  update admission.foundry_admission_cases
  set case_state=case when v_ready then 'ready_for_handoff' else 'blocked' end,
      impact_preview=v_preview,
      blockers=coalesce(v_preview->'blockers','[]'::jsonb),
      updated_at=now()
  where id=p_case_id;

  update admission.foundry_packages p
  set package_state=case when v_ready then 'ready_for_handoff' else 'blocked' end
  from admission.foundry_admission_cases c
  where c.id=p_case_id and p.id=c.foundry_package_id;

  return v_preview||jsonb_build_object(
    'plannedByPersonEntityId',v_person_id,
    'responsibilityRelationId',v_relation_id,
    'caseState',case when v_ready then 'ready_for_handoff' else 'blocked' end,
    'canonicalAtlasWriteOccurred',false
  );
end
$function$;

revoke all on function atlas.foundry_admission_plan_self_api_v1(uuid,jsonb)
  from public,anon,service_role;
grant execute on function atlas.foundry_admission_plan_self_api_v1(uuid,jsonb)
  to authenticated;


create or replace function atlas.foundry_admission_case_self_api_v1(
  p_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality','admission'
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
  v_case admission.foundry_admission_cases%rowtype;
  v_package admission.foundry_packages%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,'foundry_admission_governance','foundry_admission.read',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  );
  if v_relation_id is null then
    raise exception 'Foundry admission read responsibility required.' using errcode='42501';
  end if;

  select * into v_case
  from admission.foundry_admission_cases where id=p_case_id;
  if not found then
    raise exception 'Foundry admission case not found.' using errcode='22023';
  end if;
  select * into v_package
  from admission.foundry_packages where id=v_case.foundry_package_id;

  return jsonb_build_object(
    'contractVersion','foundry_atlas_admission_v1',
    'caseId',v_case.id,
    'caseState',v_case.case_state,
    'packageState',v_package.package_state,
    'foundry',jsonb_build_object(
      'packageId',v_package.package_id,
      'workspaceId',v_package.workspace_id,
      'ledgerCandidateId',v_package.ledger_candidate_id,
      'protocolVersion',v_package.foundry_protocol_version,
      'exchangeVersion',v_package.exchange_version,
      'releaseVersion',v_package.release_version,
      'subjectName',v_package.subject_name,
      'fieldDescription',v_package.field_description,
      'sealedAt',v_package.sealed_at
    ),
    'plan',jsonb_build_object(
      'subjectDisposition',v_case.subject_disposition,
      'selectedEntityId',v_case.selected_entity_id,
      'newEntity',v_case.new_entity_spec,
      'identityCollisionBasis',v_case.identity_collision_basis,
      'desiredLedgerName',v_case.desired_ledger_name,
      'ledgerBoundaryBasis',v_case.ledger_boundary_basis,
      'basis',v_case.plan_basis
    ),
    'impact',v_case.impact_preview,
    'blockers',v_case.blockers,
    'resolvedSubjectEntityId',v_case.resolved_subject_entity_id,
    'onboardingCaseId',v_case.onboarding_case_id,
    'executionReceipt',v_case.execution_receipt,
    'responsibilityRelationId',v_relation_id
  );
end
$function$;

revoke all on function atlas.foundry_admission_case_self_api_v1(uuid)
  from public,anon,service_role;
grant execute on function atlas.foundry_admission_case_self_api_v1(uuid)
  to authenticated;


create or replace function atlas.foundry_admission_handoff_self_api_v1(
  p_case_id uuid,
  p_confirmation_basis text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality','ledger','admission'
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
  v_case admission.foundry_admission_cases%rowtype;
  v_package admission.foundry_packages%rowtype;
  v_preview jsonb;
  v_subject uuid;
  v_onboarding uuid;
  v_receipt jsonb;
  v_stable_key text;
  v_entity_kind text;
  v_display_name text;
  v_basis text;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,'foundry_admission_governance','foundry_admission.execute',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  );
  if v_relation_id is null then
    raise exception 'Foundry admission execution responsibility required.' using errcode='42501';
  end if;

  v_basis:=nullif(btrim(coalesce(p_confirmation_basis,'')),'');
  if v_basis is null then
    raise exception 'Admission handoff confirmation basis is required.' using errcode='22023';
  end if;

  select * into v_case
  from admission.foundry_admission_cases
  where id=p_case_id
  for update;
  if not found then
    raise exception 'Foundry admission case not found.' using errcode='22023';
  end if;

  if v_case.case_state='handed_to_onboarding' then
    return v_case.execution_receipt;
  end if;
  if v_case.case_state<>'ready_for_handoff' then
    raise exception 'Foundry admission case must be ready_for_handoff.' using errcode='23514';
  end if;

  select * into v_package
  from admission.foundry_packages
  where id=v_case.foundry_package_id
  for update;

  v_preview:=admission.foundry_admission_preview_internal_v1(p_case_id);
  if not coalesce((v_preview->>'canHandoff')::boolean,false) then
    raise exception 'Foundry admission handoff is blocked: %',
      coalesce(v_preview->'blockers','[]'::jsonb)::text using errcode='23514';
  end if;

  if v_case.subject_disposition='use_existing_entity' then
    select e.id into v_subject
    from reality.entities e
    where e.id=v_case.selected_entity_id
      and e.identity_state='canonical';
    if v_subject is null then
      raise exception 'Selected canonical Reality Entity is no longer available.'
        using errcode='23514';
    end if;
  elsif v_case.subject_disposition='create_entity' then
    v_stable_key:=nullif(btrim(v_case.new_entity_spec->>'stableKey'),'');
    v_entity_kind:=nullif(btrim(v_case.new_entity_spec->>'entityKind'),'');
    v_display_name:=nullif(btrim(v_case.new_entity_spec->>'displayName'),'');

    insert into reality.entities(
      stable_key,entity_kind,display_name,identity_state,metadata
    ) values (
      v_stable_key,v_entity_kind,v_display_name,'canonical',
      jsonb_build_object(
        'admittedFrom','atlas-ledger-foundry',
        'foundryPackageId',v_package.package_id,
        'foundryWorkspaceId',v_package.workspace_id,
        'foundryLedgerCandidateId',v_package.ledger_candidate_id,
        'foundryProtocolVersion',v_package.foundry_protocol_version,
        'foundryExchangeVersion',v_package.exchange_version,
        'foundryReleaseVersion',v_package.release_version,
        'foundrySealedAt',v_package.sealed_at,
        'admissionCaseId',v_case.id,
        'admissionBasis',v_case.plan_basis,
        'identityCollisionBasis',v_case.identity_collision_basis,
        'admittedByPersonEntityId',v_person_id,
        'admissionResponsibilityRelationId',v_relation_id
      )
    ) returning id into v_subject;
  else
    raise exception 'Resolved subject disposition required.' using errcode='23514';
  end if;

  insert into ledger.onboarding_cases(
    subject_entity_id,
    requested_by_person_entity_id,
    desired_ledger_name,
    onboarding_state,
    case_kind,
    onboarding_basis
  ) values (
    v_subject,
    v_person_id,
    v_case.desired_ledger_name,
    'requested',
    'practitioner_onboarding',
    jsonb_build_object(
      'source','atlas_foundry_admission_bridge_v1',
      'foundryPackageId',v_package.package_id,
      'foundryWorkspaceId',v_package.workspace_id,
      'foundryLedgerCandidateId',v_package.ledger_candidate_id,
      'foundryProtocolVersion',v_package.foundry_protocol_version,
      'foundryExchangeVersion',v_package.exchange_version,
      'foundryReleaseVersion',v_package.release_version,
      'foundrySealedAt',v_package.sealed_at,
      'foundryPackageRecordId',v_package.id,
      'foundryAdmissionCaseId',v_case.id,
      'subjectDisposition',v_case.subject_disposition,
      'ledgerBoundaryBasis',v_case.ledger_boundary_basis,
      'sealedFoundryCandidate',true,
      'baselinePromotionState','pending_practitioner_mapping',
      'doesNotActivateLedger',true
    )
  ) returning id into v_onboarding;

  v_receipt:=jsonb_build_object(
    'contractVersion','foundry_atlas_admission_v1',
    'state','handed_to_onboarding',
    'admissionCaseId',v_case.id,
    'foundryPackageId',v_package.id,
    'packageId',v_package.package_id,
    'subjectEntityId',v_subject,
    'subjectDisposition',v_case.subject_disposition,
    'onboardingCaseId',v_onboarding,
    'onboardingState','requested',
    'ledgerActivated',false,
    'canonicalBaselineImported',false,
    'baselinePromotionState','pending_practitioner_mapping',
    'handedOffByPersonEntityId',v_person_id,
    'responsibilityRelationId',v_relation_id
  );

  update admission.foundry_admission_cases
  set case_state='handed_to_onboarding',
      impact_preview=v_preview,
      blockers='[]'::jsonb,
      resolved_subject_entity_id=v_subject,
      onboarding_case_id=v_onboarding,
      handed_off_by_person_entity_id=v_person_id,
      handoff_responsibility_relation_id=v_relation_id,
      handoff_basis=v_basis,
      execution_receipt=v_receipt,
      handed_off_at=now(),
      updated_at=now()
  where id=p_case_id;

  update admission.foundry_packages
  set package_state='handed_to_onboarding'
  where id=v_package.id;

  return v_receipt;
end
$function$;

revoke all on function atlas.foundry_admission_handoff_self_api_v1(uuid,text)
  from public,anon,service_role;
grant execute on function atlas.foundry_admission_handoff_self_api_v1(uuid,text)
  to authenticated;


-- Foundry becomes a first-class proposal provenance source for canonical
-- Reality reconciliation. Foundry may propose; only the existing human
-- canonical_merge.execute membrane may confirm.
alter table reality.entity_reconciliation_cases
  drop constraint if exists entity_reconciliation_cases_proposal_source_kind_check;
alter table reality.entity_reconciliation_cases
  drop constraint if exists reality_entity_reconciliation_cases_source_kind_check;
alter table reality.entity_reconciliation_cases
  add constraint reality_entity_reconciliation_cases_source_kind_check
  check (proposal_source_kind in ('human','foundry','shared_intelligence','system'));


create or replace function atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(
  p_survivor_entity_id uuid,
  p_superseded_entity_id uuid,
  p_foundry_context jsonb,
  p_basis text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_case_id uuid;
  v_impact jsonb;
  v_workspace_id text;
  v_foundry_case_id text;
  v_disposition_id text;
  v_type text;
  v_reason_code text;
  v_authority text;
  v_status text;
begin
  if p_foundry_context is null or jsonb_typeof(p_foundry_context)<>'object' then
    raise exception 'Foundry reconciliation context must be a JSON object.'
      using errcode='22023';
  end if;

  v_workspace_id:=nullif(btrim(p_foundry_context->>'workspace_id'),'');
  v_foundry_case_id:=nullif(btrim(p_foundry_context->>'case_id'),'');
  v_disposition_id:=nullif(btrim(p_foundry_context->>'disposition_id'),'');
  v_type:=nullif(btrim(p_foundry_context->>'type'),'');
  v_reason_code:=nullif(btrim(p_foundry_context->>'reason_code'),'');
  v_authority:=nullif(btrim(p_foundry_context->>'authority'),'');
  v_status:=nullif(btrim(p_foundry_context->>'status'),'');

  if v_workspace_id is null or v_foundry_case_id is null or v_disposition_id is null then
    raise exception 'Foundry workspace_id, case_id, and disposition_id are required.'
      using errcode='22023';
  end if;
  if v_type<>'MERGE' or v_reason_code<>'IDENTITY_MERGE' then
    raise exception 'Foundry Reality reconciliation proposal requires MERGE / IDENTITY_MERGE.'
      using errcode='22023';
  end if;
  if v_authority not in (
    'PRINCIPAL_CONFIRMATION','AUTHORITATIVE_SOURCE','GOVERNED_RECONCILIATION','SERVICE_RULE'
  ) then
    raise exception 'AI recommendation alone cannot open canonical Reality reconciliation.'
      using errcode='42501';
  end if;
  if v_status not in ('AUTHORIZED','APPLIED') then
    raise exception 'Foundry merge disposition must be AUTHORIZED or APPLIED before Atlas proposal.'
      using errcode='23514';
  end if;

  v_case_id:=reality.open_entity_reconciliation_case_internal_v1(
    p_survivor_entity_id,
    p_superseded_entity_id,
    'foundry',
    jsonb_build_object(
      'bridgeContract','foundry_atlas_admission_v1',
      'foundry',p_foundry_context
    ),
    p_basis,
    null,
    null
  );

  v_impact:=reality.entity_reconciliation_impact_internal_v1(v_case_id);

  return jsonb_build_object(
    'contractVersion','reality_entity_reconciliation_v1',
    'proposalSourceKind','foundry',
    'caseId',v_case_id,
    'state','proposed',
    'impact',v_impact,
    'canonicalMergeExecuted',false,
    'humanCanonicalConfirmationRequired',true
  );
end
$function$;

revoke all on function atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(
  uuid,uuid,jsonb,text
) from public,anon,authenticated;
grant execute on function atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(
  uuid,uuid,jsonb,text
) to service_role;


-- Admission authority is deliberately separate from Foundry ownership, identity
-- evidence adjudication, canonical merge execution, Seats, and legacy roles.
with operator_person as (
  select e.id
  from reality.entities e
  where e.stable_key='lex'
    and e.entity_kind='person'
    and e.identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,
  responsibility_key,
  title,
  relation_state,
  jurisdiction_kind,
  jurisdiction_domain,
  permitted_operations,
  scope,
  establishment_kind,
  establishment_basis
)
select
  op.id,
  'foundry_admission_governance',
  'Govern Foundry admission into Atlas',
  'active',
  'domain',
  'atlas.foundry_admission',
  array[
    'foundry_admission.read',
    'foundry_admission.plan',
    'foundry_admission.execute'
  ]::text[],
  jsonb_build_object(
    'foundryProtocolVersions',jsonb_build_array('0.1'),
    'ledgerExchangeVersions',jsonb_build_array('0.1')
  ),
  'architecture_adjudication',
  jsonb_build_object(
    'basis','Explicit authority to review a sealed Foundry candidate at the pre-Atlas/canonical-Atlas boundary.',
    'doesNotImply',jsonb_build_array(
      'Foundry carrier authority','canonical Reality merge authority',
      'Ledger activation','practitioner identity','generic Organization role'
    )
  )
from operator_person op
on conflict do nothing;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.foundry_admission_plan_self_api_v1(uuid, jsonb)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Plan subject identity and Ledger-boundary handoff for one immutable sealed Foundry candidate.',
    'authority','foundry_admission_governance / foundry_admission.plan'
  ),now(),false
),
(
  'atlas.foundry_admission_case_self_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Read one governed Foundry admission case projection.',
    'authority','foundry_admission_governance / foundry_admission.read'
  ),now(),false
),
(
  'atlas.foundry_admission_handoff_self_api_v1(uuid, text)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Bind/admit the Foundry subject and open ordinary practitioner onboarding without Ledger activation or bulk baseline promotion.',
    'authority','foundry_admission_governance / foundry_admission.execute',
    'doesNotActivateLedger',true,
    'baselinePromotionPending',true
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;


comment on schema admission is
  'Authority boundary between durable pre-Atlas candidate structures and canonical Atlas Reality/Ledger onboarding.';
comment on table admission.foundry_packages is
  'Immutable sealed Atlas Ledger Foundry exchange packages staged before canonical admission. Foundry ESTABLISHED remains pre-Atlas.';
comment on table admission.foundry_admission_cases is
  'Governed Atlas review of a sealed Foundry candidate: subject identity decision, collision/topology preview, and handoff to practitioner onboarding.';
comment on function atlas.stage_foundry_ledger_candidate_service_v1(jsonb,text,jsonb) is
  'Stage a compatible sealed Foundry package immutably. Creates no Reality Entity, onboarding case, or Ledger.';
comment on function atlas.foundry_admission_handoff_self_api_v1(uuid,text) is
  'Human-authorized Foundry admission handoff. Creates/binds the canonical subject and opens requested practitioner onboarding; never activates a Ledger or bulk-imports the sealed baseline.';
comment on function atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(uuid,uuid,jsonb,text) is
  'Translate an authorized Foundry MERGE / IDENTITY_MERGE disposition into a canonical Reality reconciliation proposal. Foundry cannot execute the merge.';


do $validation$
declare
  v_operator uuid;
  v_def text;
begin
  select id into v_operator
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical';

  if v_operator is null then
    raise exception 'Foundry admission operator Person is unavailable.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,'foundry_admission_governance','foundry_admission.execute',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  ) is null then
    raise exception 'Foundry admission execution responsibility did not resolve.';
  end if;

  if has_function_privilege(
    'service_role','atlas.foundry_admission_handoff_self_api_v1(uuid,text)','EXECUTE'
  ) then
    raise exception 'service_role must not execute Foundry canonical admission handoff.';
  end if;

  if not has_function_privilege(
    'service_role','atlas.stage_foundry_ledger_candidate_service_v1(jsonb,text,jsonb)','EXECUTE'
  ) then
    raise exception 'service_role cannot stage sealed Foundry candidates.';
  end if;

  if not has_function_privilege(
    'service_role','atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(uuid,uuid,jsonb,text)','EXECUTE'
  ) then
    raise exception 'service_role cannot submit authorized Foundry reconciliation proposals.';
  end if;

  if has_table_privilege('service_role','admission.foundry_packages','INSERT')
     or has_table_privilege('service_role','admission.foundry_admission_cases','UPDATE') then
    raise exception 'service_role has raw Foundry admission table mutation authority.';
  end if;

  select pg_get_functiondef(
    'atlas.stage_foundry_ledger_candidate_service_v1(jsonb,text,jsonb)'::regprocedure
  ) into v_def;
  if position('reality.entities' in lower(v_def))<>0
     or position('ledger.onboarding_cases' in lower(v_def))<>0
     or position('ledger.ledgers' in lower(v_def))<>0 then
    raise exception 'Foundry staging function improperly writes canonical Atlas structures.';
  end if;

  select pg_get_functiondef(
    'atlas.foundry_admission_handoff_self_api_v1(uuid,text)'::regprocedure
  ) into v_def;
  if position('insert into reality.entities' in lower(v_def))=0
     or position('insert into ledger.onboarding_cases' in lower(v_def))=0 then
    raise exception 'Foundry handoff does not terminate at Reality + practitioner onboarding.';
  end if;
  if position('insert into ledger.ledgers' in lower(v_def))<>0 then
    raise exception 'Foundry handoff improperly activates a Ledger.';
  end if;

  if not exists(
    select 1
    from pg_constraint con
    where con.conrelid='reality.entity_reconciliation_cases'::regclass
      and con.contype='c'
      and pg_get_constraintdef(con.oid) ilike '%foundry%'
      and pg_get_constraintdef(con.oid) ilike '%shared_intelligence%'
  ) then
    raise exception 'Reality reconciliation proposal provenance does not include Foundry.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,'reality_identity_adjudication','canonical_merge.execute',
    'domain',null,'reality.identity_resolution','{}'::jsonb
  ) is not null then
    raise exception 'Identity evidence adjudication improperly grants canonical merge execution.';
  end if;
end
$validation$;
