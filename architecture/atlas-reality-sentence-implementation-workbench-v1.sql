-- Atlas Reality Sentence Implementation Workbench v1
-- EXECUTABLE ARCHITECTURE CANDIDATE ONLY.
-- Depends on atlas-reality-sentence-establishment-kernel-v1.sql.

begin;

-- Exact case scope: first tranche requires a root Organization/Ledger binding.
-- Narrower unit-scoped implementation can be designed later; it is not inferred.
create or replace function atlas.implementation_reality_scope_self_v1(
  p_implementation_case_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_participant_id uuid;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select cp.id into v_participant_id
  from atlas.implementation_case_participants cp
  join atlas.implementation_cases c on c.id=cp.implementation_case_id
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active
    and cp.human_user_id=v_uid
    and c.state not in ('closed','cancelled')
  order by cp.started_at,cp.id
  limit 1;

  if v_participant_id is null then
    raise exception 'Current practitioner is not assigned to this open Implementation Case.'
      using errcode='42501';
  end if;

  if p_organization_id is null then
    return jsonb_build_object(
      'ok',false,'state','implementation_scope_unbound',
      'implementationCaseId',p_implementation_case_id,
      'practitionerParticipantId',v_participant_id
    );
  end if;

  select b.* into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.implementation_case_id=p_implementation_case_id
    and b.organization_id=p_organization_id
    and b.organization_unit_id is null
    and b.state in ('bound','activated')
    and b.ended_at is null
  order by case when b.state='activated' then 0 else 1 end,b.bound_at,b.id
  limit 1;

  if v_binding.id is null then
    return jsonb_build_object(
      'ok',false,'state','outside_implementation_scope',
      'implementationCaseId',p_implementation_case_id,
      'organizationId',p_organization_id,
      'reason','active_root_ledger_binding_required'
    );
  end if;

  if not exists(
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id=v_binding.ledger_id
      and p.organization_id=p_organization_id
      and p.status='active'
      and p.ended_at is null
  ) then
    return jsonb_build_object(
      'ok',false,'state','canonical_conflict',
      'implementationCaseId',p_implementation_case_id,
      'organizationId',p_organization_id,
      'ledgerId',v_binding.ledger_id,
      'reason','organization_not_active_in_bound_ledger'
    );
  end if;

  return jsonb_build_object(
    'ok',true,'state','ready',
    'implementationCaseId',p_implementation_case_id,
    'practitionerParticipantId',v_participant_id,
    'ledgerEntitlementBindingId',v_binding.id,
    'ledgerId',v_binding.ledger_id,
    'organizationId',p_organization_id
  );
end;
$function$;

revoke all on function atlas.implementation_reality_scope_self_v1(uuid,uuid)
  from public,anon,authenticated;

-- Implementation Finding adjudication is append-only evidence of the human
-- decision that allows a Finding to become governed source material.
create table atlas.implementation_finding_adjudications (
  id uuid primary key default gen_random_uuid(),
  implementation_finding_id uuid not null
    references atlas.implementation_findings(id) on delete restrict,
  decision text not null check (decision in ('govern','reject')),
  resulting_status text not null check (resulting_status in ('governed','rejected')),
  adjudicated_by_user_id uuid not null references auth.users(id) on delete restrict,
  basis text,
  created_at timestamptz not null default now(),
  unique (implementation_finding_id),
  check (basis is null or btrim(basis)<>'')
);

comment on table atlas.implementation_finding_adjudications is
  'Append-only practitioner adjudication receipt for implementation Findings. Governance makes a Finding eligible as Reality Sentence source evidence; it does not establish source-domain truth.';

alter table atlas.implementation_finding_adjudications enable row level security;
revoke all on table atlas.implementation_finding_adjudications
  from public,anon,authenticated,service_role;

create or replace function atlas.guard_implementation_finding_adjudication_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog
as $function$
begin
  raise exception 'Implementation Finding adjudication receipts are append-only.'
    using errcode='23514';
end;
$function$;

revoke all on function atlas.guard_implementation_finding_adjudication_immutable_v1()
  from public,anon,authenticated,service_role;

create trigger implementation_finding_adjudication_immutable_v1
before update or delete on atlas.implementation_finding_adjudications
for each row execute function atlas.guard_implementation_finding_adjudication_immutable_v1();

create or replace function atlas.adjudicate_implementation_finding_self_api_v1(
  p_implementation_finding_id uuid,
  p_decision text,
  p_basis text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_finding atlas.implementation_findings%rowtype;
  v_case_id uuid;
  v_result_status text;
  v_existing atlas.implementation_finding_adjudications%rowtype;
  v_receipt_id uuid;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  if p_decision not in ('govern','reject') then
    raise exception 'Finding adjudication decision must be govern or reject.'
      using errcode='22023';
  end if;

  select f.* into v_finding
  from atlas.implementation_findings f
  join atlas.implementation_threads t on t.id=f.implementation_thread_id
  join atlas.implementation_cases c on c.id=t.implementation_case_id
  where f.id=p_implementation_finding_id
    and c.state not in ('closed','cancelled')
  for update of f;

  if v_finding.id is null then
    raise exception 'Open implementation Finding not found.' using errcode='23503';
  end if;

  select t.implementation_case_id into strict v_case_id
  from atlas.implementation_threads t
  where t.id=v_finding.implementation_thread_id;

  if not exists(
    select 1
    from atlas.implementation_case_participants cp
    where cp.implementation_case_id=v_case_id
      and cp.relationship_kind='practitioner'
      and cp.active
      and cp.human_user_id=v_uid
  ) then
    raise exception 'Current practitioner is not assigned to this implementation case.'
      using errcode='42501';
  end if;

  v_result_status:=case p_decision when 'govern' then 'governed' else 'rejected' end;

  select * into v_existing
  from atlas.implementation_finding_adjudications a
  where a.implementation_finding_id=v_finding.id;

  if v_existing.id is not null then
    if v_existing.decision=p_decision
       and v_finding.status=v_existing.resulting_status then
      return jsonb_build_object(
        'ok',true,
        'alreadyAdjudicated',true,
        'implementationFindingId',v_finding.id,
        'adjudicationId',v_existing.id,
        'status',v_existing.resulting_status
      );
    end if;
    raise exception 'Implementation Finding already has a different adjudication.'
      using errcode='23505';
  end if;

  if v_finding.status not in ('proposed','unresolved') then
    raise exception 'Only proposed or unresolved Findings may be adjudicated.'
      using errcode='23514';
  end if;

  insert into atlas.implementation_finding_adjudications(
    implementation_finding_id,decision,resulting_status,
    adjudicated_by_user_id,basis
  ) values(
    v_finding.id,p_decision,v_result_status,v_uid,
    nullif(btrim(coalesce(p_basis,'')),'')
  )
  returning id into v_receipt_id;

  update atlas.implementation_findings
  set status=v_result_status,
      updated_at=now()
  where id=v_finding.id;

  return jsonb_build_object(
    'ok',true,
    'alreadyAdjudicated',false,
    'implementationFindingId',v_finding.id,
    'adjudicationId',v_receipt_id,
    'status',v_result_status
  );
end;
$function$;

revoke all on function atlas.adjudicate_implementation_finding_self_api_v1(uuid,text,text)
  from public,anon,authenticated,service_role;

-- Manual, machine-proposed, plain-language, and source-derived capture converge here.
-- No canonical domain truth is created.
create or replace function atlas.create_implementation_reality_sentence_self_api_v1(
  p_implementation_case_id uuid,
  p_sentence text,
  p_operation_key text,
  p_semantic_bindings jsonb,
  p_construction_mode text,
  p_source_finding_id uuid default null,
  p_detail text default ''
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_item_id uuid;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.implementation_case_participants cp
    join atlas.implementation_cases c on c.id=cp.implementation_case_id
    where cp.implementation_case_id=p_implementation_case_id
      and cp.relationship_kind='practitioner'
      and cp.active
      and cp.human_user_id=v_uid
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Current practitioner is not assigned to this open Implementation Case.'
      using errcode='42501';
  end if;

  if nullif(btrim(coalesce(p_sentence,'')),'') is null then
    raise exception 'Reality Sentence text required.' using errcode='22023';
  end if;
  if not atlas.reality_establishment_operation_exists_v1(p_operation_key) then
    raise exception 'Unsupported Reality Sentence operation.' using errcode='22023';
  end if;
  if p_semantic_bindings is null or jsonb_typeof(p_semantic_bindings)<>'object' then
    raise exception 'Semantic bindings must be a JSON object.' using errcode='22023';
  end if;
  if p_construction_mode not in (
    'manual_structured','manual_plain_language','machine_proposed','source_derived'
  ) then
    raise exception 'Unsupported Reality Sentence construction mode.' using errcode='22023';
  end if;

  if p_source_finding_id is not null and not exists(
    select 1
    from atlas.implementation_findings f
    join atlas.implementation_threads t on t.id=f.implementation_thread_id
    where f.id=p_source_finding_id
      and t.implementation_case_id=p_implementation_case_id
      and f.status='governed'
  ) then
    raise exception 'Source finding must be governed and belong to this Implementation Case.'
      using errcode='23514';
  end if;

  insert into atlas.implementation_establishment_items(
    implementation_case_id,category,title,detail,status,author_user_id,basis,
    source_finding_id,reality_operation_key,semantic_bindings,resolution_state
  ) values(
    p_implementation_case_id,'reality_sentence',btrim(p_sentence),coalesce(p_detail,''),
    'proposed',v_uid,
    jsonb_strip_nulls(jsonb_build_object(
      'source','reality_sentence_authoring',
      'constructionMode',p_construction_mode,
      'sourceFindingId',p_source_finding_id
    )),
    p_source_finding_id,p_operation_key,p_semantic_bindings,'draft'
  )
  returning id into v_item_id;

  return jsonb_build_object(
    'ok',true,'establishmentItemId',v_item_id,
    'state','draft','operationKey',p_operation_key,'sentence',btrim(p_sentence)
  );
end;
$function$;

revoke all on function atlas.create_implementation_reality_sentence_self_api_v1(
  uuid,text,text,jsonb,text,uuid,text
) from public,anon,authenticated;

-- Deterministic preview. It can inspect canonical reality but creates no domain truth.
create or replace function atlas.preview_implementation_reality_sentence_self_api_v1(
  p_establishment_item_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_item atlas.implementation_establishment_items%rowtype;
  v_b jsonb;
  v_op text;
  v_org uuid;
  v_unit uuid;
  v_position uuid;
  v_responsibility uuid;
  v_ipr uuid;
  v_person uuid;
  v_parent uuid;
  v_scope jsonb;
  v_existing uuid;
  v_existing_name text;
  v_existing_kind text;
  v_existing_status text;
  v_existing_parent uuid;
  v_existing_begins timestamptz;
  v_existing_ends timestamptz;
  v_relationship_kind text;
  v_begins timestamptz;
  v_ends timestamptz;
begin
  if auth.uid() is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select e.* into v_item
  from atlas.implementation_establishment_items e
  join atlas.implementation_case_participants cp
    on cp.implementation_case_id=e.implementation_case_id
   and cp.relationship_kind='practitioner'
   and cp.active
   and cp.human_user_id=auth.uid()
  join atlas.implementation_cases c
    on c.id=e.implementation_case_id
   and c.state not in ('closed','cancelled')
  where e.id=p_establishment_item_id
    and e.category='reality_sentence'
    and e.status in ('proposed','unresolved')
  limit 1;

  if v_item.id is null then
    raise exception 'Editable Reality Sentence candidate not found for current practitioner.'
      using errcode='23503';
  end if;

  v_b:=v_item.semantic_bindings;
  v_op:=v_item.reality_operation_key;

  if v_op='organization.establish.v1' then
    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','requires_principal_self_establishment',
      'executionClass','principal_self',
      'canonicalCommand','establish_organization_ledger_self_api_v1',
      'consequence',jsonb_build_object(
        'kind','organization_ledger',
        'creates',jsonb_build_array('organization','governing_ledger','principal_ledger_authority')
      )
    );
  end if;

  begin v_org:=nullif(v_b->>'organizationId','')::uuid;
  exception when invalid_text_representation then v_org:=null; end;

  if v_org is null then
    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','missing_required_binding',
      'missing',jsonb_build_array('organizationId')
    );
  end if;

  v_scope:=atlas.implementation_reality_scope_self_v1(v_item.implementation_case_id,v_org);
  if not coalesce((v_scope->>'ok')::boolean,false) then
    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state',v_scope->>'state','scope',v_scope
    );
  end if;

  if v_op='institutional_person.establish.v1' then
    if v_b->>'identityMode'='existing_person' then
      begin v_person:=nullif(v_b->>'personId','')::uuid;
      exception when invalid_text_representation then v_person:=null; end;

      if v_person is null or not exists(
        select 1 from atlas.people p where p.id=v_person and p.status='active'
      ) then
        return jsonb_build_object(
          'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
          'operationKey',v_op,'state','unresolved_identity',
          'reason','active_existing_person_required'
        );
      end if;

      select r.id,r.status into v_existing,v_existing_status
      from atlas.institutional_person_records r
      where r.organization_id=v_org and r.person_id=v_person
      limit 1;

      if v_existing is not null and v_existing_status<>'active' then
        return jsonb_build_object(
          'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
          'operationKey',v_op,'state','canonical_conflict',
          'reason','institutional_person_record_exists_but_is_not_active'
        );
      end if;

      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','ready','scope',v_scope,
        'consequence',jsonb_strip_nulls(jsonb_build_object(
          'kind','institutional_person_record',
          'mode',case when v_existing is null then 'create_relation' else 'reuse_existing' end,
          'personId',v_person,'institutionalPersonRecordId',v_existing
        ))
      );
    elsif v_b->>'identityMode'='new_person' then
      if nullif(btrim(coalesce(v_b->>'displayName','')),'') is null then
        return jsonb_build_object(
          'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
          'operationKey',v_op,'state','missing_required_binding',
          'missing',jsonb_build_array('displayName')
        );
      end if;

      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','ready','scope',v_scope,
        'consequence',jsonb_build_object(
          'kind','institutional_person_record',
          'mode','create_new_person_and_relation',
          'displayName',btrim(v_b->>'displayName'),
          'identityRule','display_name_is_not_identity_and_is_never_auto_merged'
        )
      );
    end if;

    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','unresolved_identity',
      'reason','explicit_identity_mode_required'
    );
  end if;

  if v_op='organization_unit.establish.v1' then
    if nullif(btrim(coalesce(v_b->>'stableKey','')),'') is null
       or nullif(btrim(coalesce(v_b->>'name','')),'') is null
       or nullif(btrim(coalesce(v_b->>'unitKind','')),'') is null then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','missing_required_binding',
        'missing',jsonb_build_array('stableKey','name','unitKind')
      );
    end if;

    begin v_parent:=nullif(v_b->>'parentUnitId','')::uuid;
    exception when invalid_text_representation then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict','reason','invalid_parent_unit_id'
      );
    end;

    if v_parent is not null and not exists(
      select 1 from atlas.organization_units u
      where u.id=v_parent and u.organization_id=v_org and u.status='active'
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'reason','parent_unit_not_active_in_target_organization'
      );
    end if;

    select u.id,u.name,u.unit_kind,u.parent_unit_id
      into v_existing,v_existing_name,v_existing_kind,v_existing_parent
    from atlas.organization_units u
    where u.organization_id=v_org and u.stable_key=btrim(v_b->>'stableKey')
    limit 1;

    if v_existing is not null
       and (
         v_existing_name<>btrim(v_b->>'name')
         or v_existing_kind<>btrim(v_b->>'unitKind')
         or v_existing_parent is distinct from v_parent
       ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'conflict',jsonb_build_object('kind','organization_unit_stable_key_collision',
          'organizationUnitId',v_existing)
      );
    end if;

    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','ready','scope',v_scope,
      'consequence',jsonb_strip_nulls(jsonb_build_object(
        'kind','organization_unit',
        'mode',case when v_existing is null then 'create' else 'reuse_existing' end,
        'organizationUnitId',v_existing,'stableKey',btrim(v_b->>'stableKey'),
        'name',btrim(v_b->>'name'),'unitKind',btrim(v_b->>'unitKind')
      ))
    );
  end if;

  if v_op='organization_position.establish.v1' then
    begin v_unit:=nullif(v_b->>'organizationUnitId','')::uuid;
    exception when invalid_text_representation then v_unit:=null; end;

    if v_unit is null
       or nullif(btrim(coalesce(v_b->>'stableKey','')),'') is null
       or nullif(btrim(coalesce(v_b->>'displayTitle','')),'') is null
       or nullif(btrim(coalesce(v_b->>'positionKind','')),'') is null then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','missing_required_binding',
        'missing',jsonb_build_array('organizationUnitId','stableKey','displayTitle','positionKind')
      );
    end if;

    if not exists(
      select 1 from atlas.organization_units u
      where u.id=v_unit and u.organization_id=v_org and u.status='active'
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'reason','organization_unit_not_active_in_target_organization'
      );
    end if;

    select p.id,p.display_title,p.position_kind
      into v_existing,v_existing_name,v_existing_kind
    from atlas.organization_positions p
    where p.organization_id=v_org
      and p.organization_unit_id=v_unit
      and p.stable_key=btrim(v_b->>'stableKey')
    limit 1;

    if v_existing is not null and (
      v_existing_name<>btrim(v_b->>'displayTitle')
      or v_existing_kind<>btrim(v_b->>'positionKind')
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'conflict',jsonb_build_object(
          'kind','organization_position_stable_key_collision','positionId',v_existing
        )
      );
    end if;

    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','ready','scope',v_scope,
      'consequence',jsonb_strip_nulls(jsonb_build_object(
        'kind','organization_position',
        'mode',case when v_existing is null then 'create' else 'reuse_existing' end,
        'positionId',v_existing,'organizationUnitId',v_unit,
        'displayTitle',btrim(v_b->>'displayTitle')
      ))
    );
  end if;

  if v_op='organization_responsibility.establish.v1' then
    if nullif(btrim(coalesce(v_b->>'stableKey','')),'') is null
       or nullif(btrim(coalesce(v_b->>'name','')),'') is null
       or nullif(btrim(coalesce(v_b->>'responsibilityKind','')),'') is null then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','missing_required_binding',
        'missing',jsonb_build_array('stableKey','name','responsibilityKind')
      );
    end if;

    select r.id,r.name,r.responsibility_kind
      into v_existing,v_existing_name,v_existing_kind
    from atlas.organization_responsibilities r
    where r.organization_id=v_org and r.stable_key=btrim(v_b->>'stableKey')
    limit 1;

    if v_existing is not null and (
      v_existing_name<>btrim(v_b->>'name')
      or v_existing_kind<>btrim(v_b->>'responsibilityKind')
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'conflict',jsonb_build_object(
          'kind','organization_responsibility_stable_key_collision',
          'responsibilityId',v_existing
        )
      );
    end if;

    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','ready','scope',v_scope,
      'consequence',jsonb_strip_nulls(jsonb_build_object(
        'kind','organization_responsibility',
        'mode',case when v_existing is null then 'create' else 'reuse_existing' end,
        'responsibilityId',v_existing,'name',btrim(v_b->>'name')
      ))
    );
  end if;

  if v_op='position_responsibility.establish.v1' then
    begin
      v_position:=nullif(v_b->>'positionId','')::uuid;
      v_responsibility:=nullif(v_b->>'responsibilityId','')::uuid;
    exception when invalid_text_representation then
      v_position:=null; v_responsibility:=null;
    end;
    v_relationship_kind:=nullif(btrim(coalesce(v_b->>'relationshipKind','')),'');

    if v_position is null or v_responsibility is null or v_relationship_kind is null then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','missing_required_binding',
        'missing',jsonb_build_array('positionId','responsibilityId','relationshipKind')
      );
    end if;

    if not exists(
      select 1 from atlas.organization_positions p
      where p.id=v_position and p.organization_id=v_org and p.status='active'
    ) or not exists(
      select 1 from atlas.organization_responsibilities r
      where r.id=v_responsibility and r.organization_id=v_org and r.status='active'
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'reason','position_and_responsibility_must_be_active_in_same_organization'
      );
    end if;

    if exists(
      select 1 from atlas.organization_position_responsibilities pr
      where pr.position_id=v_position and pr.responsibility_id=v_responsibility
        and pr.relationship_kind<>v_relationship_kind
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'reason','different_position_responsibility_relation_already_exists'
      );
    end if;

    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','ready','scope',v_scope,
      'consequence',jsonb_build_object(
        'kind','position_responsibility',
        'mode',case when exists(
          select 1 from atlas.organization_position_responsibilities pr
          where pr.position_id=v_position and pr.responsibility_id=v_responsibility
            and pr.relationship_kind=v_relationship_kind
        ) then 'reuse_existing' else 'create' end,
        'positionId',v_position,'responsibilityId',v_responsibility,
        'relationshipKind',v_relationship_kind
      )
    );
  end if;

  if v_op='position_appointment.establish.v1' then
    begin
      v_ipr:=nullif(v_b->>'institutionalPersonRecordId','')::uuid;
      v_position:=nullif(v_b->>'positionId','')::uuid;
    exception when invalid_text_representation then
      v_ipr:=null; v_position:=null;
    end;
    v_relationship_kind:=nullif(btrim(coalesce(v_b->>'appointmentKind','')),'');

    begin v_begins:=(v_b->>'beginsAt')::timestamptz;
    exception when others then v_begins:=null; end;
    begin
      if nullif(v_b->>'endsAt','') is not null then v_ends:=(v_b->>'endsAt')::timestamptz; end if;
    exception when others then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict','reason','invalid_appointment_end_time'
      );
    end;

    if v_ipr is null or v_position is null or v_relationship_kind is null or v_begins is null then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','missing_required_binding',
        'missing',jsonb_build_array(
          'institutionalPersonRecordId','positionId','appointmentKind','beginsAt'
        )
      );
    end if;
    if v_ends is not null and v_ends<v_begins then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict','reason','appointment_end_precedes_begin'
      );
    end if;

    if not exists(
      select 1 from atlas.institutional_person_records r
      where r.id=v_ipr and r.organization_id=v_org and r.status='active'
    ) or not exists(
      select 1 from atlas.organization_positions p
      where p.id=v_position and p.organization_id=v_org and p.status='active'
    ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'reason','institutional_person_and_position_must_be_active_in_same_organization'
      );
    end if;

    select a.id,a.appointment_kind,a.begins_at,a.ends_at
      into v_existing,v_existing_kind,v_existing_begins,v_existing_ends
    from atlas.organization_position_appointments a
    where a.organization_id=v_org
      and a.institutional_person_record_id=v_ipr
      and a.position_id=v_position
      and a.status='active' and a.ends_at is null
    limit 1;

    if v_existing is not null
       and (
         v_existing_kind<>v_relationship_kind
         or v_existing_begins<>v_begins
         or v_existing_ends is distinct from v_ends
       ) then
      return jsonb_build_object(
        'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
        'operationKey',v_op,'state','canonical_conflict',
        'reason','active_appointment_has_different_canonical_semantics',
        'appointmentId',v_existing
      );
    end if;

    return jsonb_build_object(
      'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
      'operationKey',v_op,'state','ready','scope',v_scope,
      'consequence',jsonb_strip_nulls(jsonb_build_object(
        'kind','organization_position_appointment',
        'mode',case when v_existing is null then 'create' else 'reuse_existing' end,
        'appointmentId',v_existing,'institutionalPersonRecordId',v_ipr,
        'positionId',v_position,'beginsAt',v_begins,'endsAt',v_ends
      ))
    );
  end if;

  return jsonb_build_object(
    'ok',true,'establishmentItemId',v_item.id,'sentence',v_item.title,
    'operationKey',v_op,'state','unsupported_operation'
  );
end;
$function$;

revoke all on function atlas.preview_implementation_reality_sentence_self_api_v1(uuid)
  from public,anon,authenticated;

-- Canonical rerender: established display is derived from live domain truth, not authored text.
create or replace function atlas.render_reality_consequence_v1(
  p_operation_key text,
  p_consequence jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_sentence text;
  v_state text:='current';
  v_targets jsonb:='[]'::jsonb;
begin
  if p_operation_key='institutional_person.establish.v1' then
    select
      coalesce(p.display_name,'Unnamed Person') || ' is known to ' || o.name || '.',
      case when r.status='active' and p.status='active' and o.status='active' then 'current' else 'historical' end,
      jsonb_build_array(
        jsonb_build_object('kind','person','id',p.id,'label',p.display_name),
        jsonb_build_object('kind','organization','id',o.id,'label',o.name),
        jsonb_build_object('kind','institutional_person_record','id',r.id)
      )
    into v_sentence,v_state,v_targets
    from atlas.institutional_person_records r
    join atlas.people p on p.id=r.person_id
    join atlas.organizations o on o.id=r.organization_id
    where r.id=(p_consequence->>'institutionalPersonRecordId')::uuid;

  elsif p_operation_key='organization_unit.establish.v1' then
    select
      o.name || ' has ' || u.name || '.',
      case when u.status='active' and o.status='active' then 'current' else 'historical' end,
      jsonb_build_array(
        jsonb_build_object('kind','organization','id',o.id,'label',o.name),
        jsonb_build_object('kind','organization_unit','id',u.id,'label',u.name)
      )
    into v_sentence,v_state,v_targets
    from atlas.organization_units u
    join atlas.organizations o on o.id=u.organization_id
    where u.id=(p_consequence->>'organizationUnitId')::uuid;

  elsif p_operation_key='organization_position.establish.v1' then
    select
      p.display_title || ' exists in ' || u.name || '.',
      case when p.status='active' and u.status='active' then 'current' else 'historical' end,
      jsonb_build_array(
        jsonb_build_object('kind','organization_position','id',p.id,'label',p.display_title),
        jsonb_build_object('kind','organization_unit','id',u.id,'label',u.name)
      )
    into v_sentence,v_state,v_targets
    from atlas.organization_positions p
    join atlas.organization_units u on u.id=p.organization_unit_id
    where p.id=(p_consequence->>'positionId')::uuid;

  elsif p_operation_key='organization_responsibility.establish.v1' then
    select
      r.name || ' is a responsibility of ' || o.name || '.',
      case when r.status='active' and o.status='active' then 'current' else 'historical' end,
      jsonb_build_array(
        jsonb_build_object('kind','organization_responsibility','id',r.id,'label',r.name),
        jsonb_build_object('kind','organization','id',o.id,'label',o.name)
      )
    into v_sentence,v_state,v_targets
    from atlas.organization_responsibilities r
    join atlas.organizations o on o.id=r.organization_id
    where r.id=(p_consequence->>'responsibilityId')::uuid;

  elsif p_operation_key='position_responsibility.establish.v1' then
    select
      p.display_title || ' carries ' || r.name || '.',
      case when p.status='active' and r.status='active' then 'current' else 'historical' end,
      jsonb_build_array(
        jsonb_build_object('kind','organization_position','id',p.id,'label',p.display_title),
        jsonb_build_object('kind','organization_responsibility','id',r.id,'label',r.name)
      )
    into v_sentence,v_state,v_targets
    from atlas.organization_position_responsibilities pr
    join atlas.organization_positions p on p.id=pr.position_id
    join atlas.organization_responsibilities r on r.id=pr.responsibility_id
    where pr.position_id=(p_consequence->>'positionId')::uuid
      and pr.responsibility_id=(p_consequence->>'responsibilityId')::uuid;

  elsif p_operation_key='position_appointment.establish.v1' then
    select
      coalesce(pe.display_name,'Unnamed Person') || ' occupies ' || p.display_title || '.',
      case when a.status='active' and (a.ends_at is null or a.ends_at>now())
        then 'current' else 'historical' end,
      jsonb_build_array(
        jsonb_build_object('kind','person','id',pe.id,'label',pe.display_name),
        jsonb_build_object('kind','institutional_person_record','id',ipr.id),
        jsonb_build_object('kind','organization_position','id',p.id,'label',p.display_title),
        jsonb_build_object('kind','organization_position_appointment','id',a.id)
      )
    into v_sentence,v_state,v_targets
    from atlas.organization_position_appointments a
    join atlas.institutional_person_records ipr on ipr.id=a.institutional_person_record_id
    join atlas.people pe on pe.id=ipr.person_id
    join atlas.organization_positions p on p.id=a.position_id
    where a.id=(p_consequence->>'appointmentId')::uuid;
  end if;

  if v_sentence is null then
    return jsonb_build_object(
      'state','unresolved','reason','canonical_consequence_not_renderable',
      'operationKey',p_operation_key
    );
  end if;

  return jsonb_build_object(
    'state',v_state,'operationKey',p_operation_key,
    'sentence',v_sentence,'targets',v_targets
  );
end;
$function$;

revoke all on function atlas.render_reality_consequence_v1(text,jsonb)
  from public,anon,authenticated;

-- Atomic promotion through the owning domain command.
create or replace function atlas.establish_implementation_reality_sentence_self_api_v1(
  p_establishment_item_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_item atlas.implementation_establishment_items%rowtype;
  v_preview jsonb;
  v_b jsonb;
  v_org uuid;
  v_receipt jsonb;
  v_basis jsonb;
  v_render jsonb;
begin
  if v_uid is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  select e.* into v_item
  from atlas.implementation_establishment_items e
  join atlas.implementation_case_participants cp
    on cp.implementation_case_id=e.implementation_case_id
   and cp.relationship_kind='practitioner'
   and cp.active
   and cp.human_user_id=v_uid
  join atlas.implementation_cases c
    on c.id=e.implementation_case_id
   and c.state not in ('closed','cancelled')
  where e.id=p_establishment_item_id
    and e.category='reality_sentence'
    and e.status in ('proposed','unresolved')
  for update of e;

  if v_item.id is null then
    raise exception 'Editable Reality Sentence candidate not found.' using errcode='23503';
  end if;

  v_preview:=atlas.preview_implementation_reality_sentence_self_api_v1(v_item.id);
  if v_preview->>'state'<>'ready' then
    update atlas.implementation_establishment_items
    set status=case when v_preview->>'state' in (
          'unresolved_identity','missing_required_binding','implementation_scope_unbound',
          'outside_implementation_scope','canonical_conflict','prerequisite_not_live'
        ) then 'unresolved' else status end,
        resolution_state=v_preview->>'state',
        updated_at=now()
    where id=v_item.id;

    return jsonb_build_object(
      'ok',false,'established',false,
      'establishmentItemId',v_item.id,'preview',v_preview
    );
  end if;

  v_b:=v_item.semantic_bindings;
  v_org:=(v_b->>'organizationId')::uuid;
  v_basis:=jsonb_build_object(
    'implementationCaseId',v_item.implementation_case_id,
    'establishmentItemId',v_item.id,
    'authoredByUserId',v_item.author_user_id,
    'establishedByUserId',v_uid,
    'authoredSentence',v_item.title
  );

  if v_item.reality_operation_key='institutional_person.establish.v1' then
    v_receipt:=atlas.establish_institutional_person_record_internal_v1(
      v_org,v_b->>'identityMode',
      case when nullif(v_b->>'personId','') is null then null else (v_b->>'personId')::uuid end,
      v_b->>'displayName',v_basis
    );
  elsif v_item.reality_operation_key='organization_unit.establish.v1' then
    v_receipt:=atlas.establish_organization_unit_internal_v1(
      v_org,
      case when nullif(v_b->>'parentUnitId','') is null then null else (v_b->>'parentUnitId')::uuid end,
      v_b->>'stableKey',v_b->>'name',v_b->>'unitKind',v_basis
    );
  elsif v_item.reality_operation_key='organization_position.establish.v1' then
    v_receipt:=atlas.establish_organization_position_internal_v1(
      v_org,(v_b->>'organizationUnitId')::uuid,
      v_b->>'stableKey',v_b->>'displayTitle',v_b->>'positionKind',v_basis
    );
  elsif v_item.reality_operation_key='organization_responsibility.establish.v1' then
    v_receipt:=atlas.establish_organization_responsibility_internal_v1(
      v_org,v_b->>'stableKey',v_b->>'name',v_b->>'responsibilityKind',v_basis
    );
  elsif v_item.reality_operation_key='position_responsibility.establish.v1' then
    v_receipt:=atlas.establish_position_responsibility_internal_v1(
      v_org,(v_b->>'positionId')::uuid,(v_b->>'responsibilityId')::uuid,
      v_b->>'relationshipKind',v_basis
    );
  elsif v_item.reality_operation_key='position_appointment.establish.v1' then
    v_receipt:=atlas.establish_position_appointment_internal_v1(
      v_org,(v_b->>'institutionalPersonRecordId')::uuid,(v_b->>'positionId')::uuid,
      v_b->>'appointmentKind',(v_b->>'beginsAt')::timestamptz,
      case when nullif(v_b->>'endsAt','') is null then null else (v_b->>'endsAt')::timestamptz end,
      v_basis
    );
  else
    raise exception 'Reality Sentence operation is not practitioner-executable.'
      using errcode='23514';
  end if;

  v_receipt:=v_receipt || jsonb_build_object(
    'operationKey',v_item.reality_operation_key,
    'projectionContract','reality_consequence_render_v1'
  );

  update atlas.implementation_establishment_items
  set status='established',
      resolution_state='established',
      canonical_consequence=v_receipt,
      established_by_user_id=v_uid,
      established_at=now(),
      updated_at=now()
  where id=v_item.id;

  v_render:=atlas.render_reality_consequence_v1(v_item.reality_operation_key,v_receipt);

  return jsonb_build_object(
    'ok',true,'established',true,
    'establishmentItemId',v_item.id,
    'receipt',v_receipt,
    'realityEntry',v_render
  );
end;
$function$;

revoke all on function atlas.establish_implementation_reality_sentence_self_api_v1(uuid)
  from public,anon,authenticated;

create or replace function atlas.implementation_reality_sentences_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_candidates jsonb;
  v_established jsonb;
begin
  if auth.uid() is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.implementation_case_participants cp
    join atlas.implementation_cases c on c.id=cp.implementation_case_id
    where cp.implementation_case_id=p_implementation_case_id
      and cp.relationship_kind='practitioner'
      and cp.active and cp.human_user_id=auth.uid()
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Current practitioner is not assigned to this open Implementation Case.'
      using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',e.id,'sentence',e.title,'detail',e.detail,'status',e.status,
    'constructionMode',e.basis->>'constructionMode',
    'operationKey',e.reality_operation_key,
    'resolutionState',e.resolution_state,
    'semanticBindings',e.semantic_bindings,
    'sourceFindingId',e.source_finding_id,
    'createdAt',e.created_at,'updatedAt',e.updated_at
  )) order by e.created_at,e.id),'[]'::jsonb)
  into v_candidates
  from atlas.implementation_establishment_items e
  where e.implementation_case_id=p_implementation_case_id
    and e.category='reality_sentence'
    and e.status in ('proposed','unresolved');

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',e.id,
    'authoredSentence',e.title,
    'operationKey',e.reality_operation_key,
    'canonicalConsequence',e.canonical_consequence,
    'establishedAt',e.established_at,
    'realityEntry',atlas.render_reality_consequence_v1(
      e.reality_operation_key,e.canonical_consequence
    )
  )) order by e.established_at,e.id),'[]'::jsonb)
  into v_established
  from atlas.implementation_establishment_items e
  where e.implementation_case_id=p_implementation_case_id
    and e.category='reality_sentence'
    and e.status='established';

  return jsonb_build_object(
    'ok',true,'contractVersion','implementation_reality_sentences_v1',
    'implementationCaseId',p_implementation_case_id,
    'candidates',v_candidates,'establishedReality',v_established
  );
end;
$function$;

revoke all on function atlas.implementation_reality_sentences_self_api_v1(uuid)
  from public,anon,authenticated;

-- Case-scoped semantic options for the human sentence builder.
-- Returns canonical identities already present inside the exact bound Organization.
-- It never performs fuzzy Person matching and never exposes cross-Organization options.
create or replace function atlas.implementation_reality_authoring_context_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_binding_count integer;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_organization atlas.organizations%rowtype;
  v_units jsonb;
  v_people jsonb;
  v_positions jsonb;
  v_responsibilities jsonb;
begin
  if auth.uid() is null or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.implementation_case_participants cp
    join atlas.implementation_cases c on c.id=cp.implementation_case_id
    where cp.implementation_case_id=p_implementation_case_id
      and cp.relationship_kind='practitioner'
      and cp.active
      and cp.human_user_id=auth.uid()
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Current practitioner is not assigned to this open Implementation Case.'
      using errcode='42501';
  end if;

  select count(*) into v_binding_count
  from atlas.ledger_entitlement_bindings b
  where b.implementation_case_id=p_implementation_case_id
    and b.organization_id is not null
    and b.organization_unit_id is null
    and b.state in ('bound','activated')
    and b.ended_at is null;

  if v_binding_count=0 then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_reality_authoring_context_v1',
      'implementationCaseId',p_implementation_case_id,
      'state','implementation_scope_unbound',
      'organization',null,
      'organizationUnits','[]'::jsonb,
      'institutionalPeople','[]'::jsonb,
      'positions','[]'::jsonb,
      'responsibilities','[]'::jsonb
    );
  elsif v_binding_count<>1 then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_reality_authoring_context_v1',
      'implementationCaseId',p_implementation_case_id,
      'state','canonical_conflict',
      'reason','multiple_active_root_implementation_bindings',
      'organization',null,
      'organizationUnits','[]'::jsonb,
      'institutionalPeople','[]'::jsonb,
      'positions','[]'::jsonb,
      'responsibilities','[]'::jsonb
    );
  end if;

  select b.* into strict v_binding
  from atlas.ledger_entitlement_bindings b
  where b.implementation_case_id=p_implementation_case_id
    and b.organization_id is not null
    and b.organization_unit_id is null
    and b.state in ('bound','activated')
    and b.ended_at is null;

  if not coalesce(
    (atlas.implementation_reality_scope_self_v1(
      p_implementation_case_id,
      v_binding.organization_id
    )->>'ok')::boolean,
    false
  ) then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','implementation_reality_authoring_context_v1',
      'implementationCaseId',p_implementation_case_id,
      'state','canonical_conflict',
      'reason','bound_scope_failed_revalidation',
      'organization',null,
      'organizationUnits','[]'::jsonb,
      'institutionalPeople','[]'::jsonb,
      'positions','[]'::jsonb,
      'responsibilities','[]'::jsonb
    );
  end if;

  select * into strict v_organization
  from atlas.organizations o
  where o.id=v_binding.organization_id
    and o.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,
    'parentUnitId',u.parent_unit_id,
    'stableKey',u.stable_key,
    'name',u.name,
    'unitKind',u.unit_kind
  ) order by u.name,u.id),'[]'::jsonb)
  into v_units
  from atlas.organization_units u
  where u.organization_id=v_organization.id
    and u.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'institutionalPersonRecordId',ipr.id,
    'personId',p.id,
    'displayName',p.display_name
  ) order by coalesce(p.display_name,''),p.id),'[]'::jsonb)
  into v_people
  from atlas.institutional_person_records ipr
  join atlas.people p on p.id=ipr.person_id
  where ipr.organization_id=v_organization.id
    and ipr.status='active'
    and p.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,
    'organizationUnitId',p.organization_unit_id,
    'stableKey',p.stable_key,
    'displayTitle',p.display_title,
    'positionKind',p.position_kind
  ) order by p.display_title,p.id),'[]'::jsonb)
  into v_positions
  from atlas.organization_positions p
  where p.organization_id=v_organization.id
    and p.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,
    'stableKey',r.stable_key,
    'name',r.name,
    'responsibilityKind',r.responsibility_kind
  ) order by r.name,r.id),'[]'::jsonb)
  into v_responsibilities
  from atlas.organization_responsibilities r
  where r.organization_id=v_organization.id
    and r.status='active';

  return jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_reality_authoring_context_v1',
    'implementationCaseId',p_implementation_case_id,
    'state','ready',
    'organization',jsonb_build_object(
      'id',v_organization.id,
      'stableKey',v_organization.stable_key,
      'name',v_organization.name,
      'ledgerId',v_binding.ledger_id
    ),
    'organizationUnits',v_units,
    'institutionalPeople',v_people,
    'positions',v_positions,
    'responsibilities',v_responsibilities
  );
end;
$function$;

revoke all on function atlas.implementation_reality_authoring_context_self_api_v1(uuid)
  from public,anon,authenticated,service_role;

-- Narrow browser membrane. All substantive authorization remains inside Atlas functions.
create or replace function public.adjudicate_implementation_finding_self_api_v1(
  p_implementation_finding_id uuid,
  p_decision text,
  p_basis text default null
)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
select atlas.adjudicate_implementation_finding_self_api_v1(
  p_implementation_finding_id,p_decision,p_basis
);
$function$;

create or replace function public.implementation_reality_authoring_context_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
select atlas.implementation_reality_authoring_context_self_api_v1(p_implementation_case_id);
$function$;

create or replace function public.implementation_reality_establishment_registry_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Practitioner authority required.' using errcode='42501';
  end if;
  return atlas.reality_establishment_registry_v1();
end;
$function$;

create or replace function public.create_implementation_reality_sentence_self_api_v1(
  p_implementation_case_id uuid,
  p_sentence text,
  p_operation_key text,
  p_semantic_bindings jsonb,
  p_construction_mode text,
  p_source_finding_id uuid default null,
  p_detail text default ''
)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
select atlas.create_implementation_reality_sentence_self_api_v1(
  p_implementation_case_id,p_sentence,p_operation_key,p_semantic_bindings,
  p_construction_mode,p_source_finding_id,p_detail
);
$function$;

create or replace function public.preview_implementation_reality_sentence_self_api_v1(
  p_establishment_item_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
select atlas.preview_implementation_reality_sentence_self_api_v1(p_establishment_item_id);
$function$;

create or replace function public.establish_implementation_reality_sentence_self_api_v1(
  p_establishment_item_id uuid
)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
select atlas.establish_implementation_reality_sentence_self_api_v1(p_establishment_item_id);
$function$;

create or replace function public.implementation_reality_sentences_self_api_v1(
  p_implementation_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
select atlas.implementation_reality_sentences_self_api_v1(p_implementation_case_id);
$function$;

revoke all on function public.adjudicate_implementation_finding_self_api_v1(uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.implementation_reality_authoring_context_self_api_v1(uuid)
  from public,anon,authenticated;
revoke all on function public.implementation_reality_establishment_registry_self_api_v1()
  from public,anon,authenticated;
revoke all on function public.create_implementation_reality_sentence_self_api_v1(
  uuid,text,text,jsonb,text,uuid,text
) from public,anon,authenticated;
revoke all on function public.preview_implementation_reality_sentence_self_api_v1(uuid)
  from public,anon,authenticated;
revoke all on function public.establish_implementation_reality_sentence_self_api_v1(uuid)
  from public,anon,authenticated;
revoke all on function public.implementation_reality_sentences_self_api_v1(uuid)
  from public,anon,authenticated;

grant execute on function public.adjudicate_implementation_finding_self_api_v1(uuid,text,text)
  to authenticated,service_role;
grant execute on function public.implementation_reality_authoring_context_self_api_v1(uuid)
  to authenticated,service_role;
grant execute on function public.implementation_reality_establishment_registry_self_api_v1()
  to authenticated,service_role;
grant execute on function public.create_implementation_reality_sentence_self_api_v1(
  uuid,text,text,jsonb,text,uuid,text
) to authenticated,service_role;
grant execute on function public.preview_implementation_reality_sentence_self_api_v1(uuid)
  to authenticated,service_role;
grant execute on function public.establish_implementation_reality_sentence_self_api_v1(uuid)
  to authenticated,service_role;
grant execute on function public.implementation_reality_sentences_self_api_v1(uuid)
  to authenticated,service_role;

commit;
