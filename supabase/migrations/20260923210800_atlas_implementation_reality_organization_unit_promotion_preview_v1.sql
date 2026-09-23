begin;

-- Atlas Implementation Reality Organization Unit Promotion Preview v1
--
-- First structural family after Institutional Person.
-- This tranche extends Reality Candidate grammar for Organization Unit and adds
-- read-only readiness + canonical rerender only.
--
-- It deliberately does NOT add Organization Unit mutation authority.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Reality Candidate custody must be live before Organization Unit promotion.'
      using errcode='0A000';
  end if;

  if to_regclass('atlas.organization_units') is null then
    raise exception 'Canonical Organization Unit custody must be live before promotion.'
      using errcode='0A000';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='implementation_reality_candidates'
      and column_name='semantic_payload'
      and is_nullable='NO'
  ) then
    raise exception 'Reality Candidate semantic payload v2 must be live before Organization Unit promotion.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)') is null then
    raise exception 'Implementation practitioner case authority is unavailable.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.principal_has_ledger_authority_v1(uuid,uuid)') is null then
    raise exception 'Principal Ledger authority resolver is unavailable.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;


-- Add the Organization Unit sentence family without changing existing families.
alter table atlas.implementation_reality_candidates
  drop constraint if exists implementation_reality_candidates_operation_check,
  add constraint implementation_reality_candidates_operation_check
    check (operation_id in (
      'organization.establish',
      'person.establish',
      'institutional_person_record.establish',
      'organization_unit.establish',
      'organization_position.establish',
      'organization_responsibility.establish',
      'position_responsibility_definition.establish',
      'person_position_appointment.establish'
    ));

alter table atlas.implementation_reality_candidates
  drop constraint if exists implementation_reality_candidates_operation_shape,
  add constraint implementation_reality_candidates_operation_shape
    check (
      case operation_id
        when 'organization.establish' then
          subject_binding->>'kind'='organization'
          and object_binding is null
          and context_binding is null

        when 'person.establish' then
          subject_binding->>'kind'='person'
          and object_binding is null
          and context_binding is null

        when 'institutional_person_record.establish' then
          subject_binding->>'kind'='person'
          and object_binding is not null
          and object_binding->>'kind'='organization'
          and context_binding is null

        when 'organization_unit.establish' then
          subject_binding->>'kind'='organization_unit'
          and object_binding is not null
          and object_binding->>'kind'='organization'
          and (
            context_binding is null
            or context_binding->>'kind'='organization_unit'
          )

        when 'organization_position.establish' then
          subject_binding->>'kind'='organization_position'
          and object_binding is not null
          and object_binding->>'kind'='organization'
          and context_binding is null

        when 'organization_responsibility.establish' then
          subject_binding->>'kind'='organization_responsibility'
          and object_binding is not null
          and object_binding->>'kind'='organization'
          and context_binding is null

        when 'position_responsibility_definition.establish' then
          subject_binding->>'kind'='organization_position'
          and object_binding is not null
          and object_binding->>'kind'='organization_responsibility'
          and context_binding is not null
          and context_binding->>'kind'='organization'

        when 'person_position_appointment.establish' then
          subject_binding->>'kind'='person'
          and object_binding is not null
          and object_binding->>'kind'='organization_position'
          and context_binding is not null
          and context_binding->>'kind'='organization'

        else false
      end
    );

comment on constraint implementation_reality_candidates_operation_shape
  on atlas.implementation_reality_candidates is
  'Typed Reality Sentence operation shape. organization_unit.establish uses proposed Organization Unit subject + canonical Organization object + optional canonical parent Organization Unit context.';


create or replace function atlas.render_organization_unit_reality_consequence_v1(
  p_organization_unit_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','organization_unit_reality_consequence_v1',
    'consequenceKind','organization_unit',
    'canonicalConsequenceRef',u.id::text,
    'sentence',
      o.name || ' has Organization Unit ' || u.name ||
      ' (' || u.unit_kind || ')' ||
      case when parent.id is null then '.' else ' inside ' || parent.name || '.' end,
    'subjectBinding',jsonb_build_object(
      'kind','organization_unit',
      'label',u.name,
      'resolution','canonical',
      'canonicalId',u.id
    ),
    'objectBinding',jsonb_build_object(
      'kind','organization',
      'label',o.name,
      'resolution','canonical',
      'canonicalId',o.id
    ),
    'contextBinding',
      case when parent.id is null then null else jsonb_build_object(
        'kind','organization_unit',
        'label',parent.name,
        'resolution','canonical',
        'canonicalId',parent.id
      ) end,
    'semanticPayload',jsonb_build_object('unitKind',u.unit_kind),
    'organizationUnitId',u.id,
    'organizationId',o.id,
    'parentUnitId',u.parent_unit_id,
    'unitKind',u.unit_kind,
    'status',u.status
  ))
  from atlas.organization_units u
  join atlas.organizations o
    on o.id=u.organization_id
  left join atlas.organization_units parent
    on parent.organization_id=u.organization_id
   and parent.id=u.parent_unit_id
  where u.id=p_organization_unit_id;
$function$;

revoke all on function atlas.render_organization_unit_reality_consequence_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.preview_implementation_reality_organization_unit_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_organization_id uuid;
  v_parent_unit_id uuid;
  v_unit_name text;
  v_unit_kind text;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_practitioner_participant_id uuid;
  v_sponsor_participant_id uuid;
  v_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_existing atlas.organization_units%rowtype;
  v_render jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select c.*
  into v_candidate
  from atlas.implementation_reality_candidates c
  join atlas.implementation_cases ic
    on ic.id=c.implementation_case_id
   and ic.state not in ('closed','cancelled')
  where c.id=p_candidate_id;

  if v_candidate.id is null then
    raise exception 'Open Implementation Reality Candidate not found.'
      using errcode='23503';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(
    v_candidate.implementation_case_id
  ) then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  select cp.id
  into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=v_candidate.implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active
    and cp.ended_at is null
    and cp.human_user_id=v_uid
  order by cp.started_at,cp.id
  limit 1;

  if v_candidate.candidate_state='promoted' then
    if v_candidate.canonical_consequence_kind='organization_unit'
       and nullif(v_candidate.canonical_consequence_ref,'') is not null then
      begin
        v_render:=atlas.render_organization_unit_reality_consequence_v1(
          v_candidate.canonical_consequence_ref::uuid
        );
      exception when invalid_text_representation then
        v_render:=null;
      end;
    end if;

    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','already_promoted',
      'canPromote',false,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref,
      'realityEntry',v_render
    );
  end if;

  if v_candidate.candidate_state not in ('proposed','unresolved') then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','candidate_not_promotable',
      'canPromote',false,
      'reason','candidate_state_' || v_candidate.candidate_state
    );
  end if;

  if v_candidate.operation_id<>'organization_unit.establish' then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','governed_command_unverified',
      'canPromote',false,
      'reason','organization_unit_preview_supports_organization_unit_establish_only'
    );
  end if;

  if v_candidate.subject_binding->>'kind'<>'organization_unit'
     or v_candidate.subject_binding->>'resolution'<>'proposed'
     or nullif(btrim(coalesce(v_candidate.subject_binding->>'canonicalId','')),'') is not null then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','proposed_identity_required',
      'canPromote',false,
      'slot','subject'
    );
  end if;

  v_unit_name:=btrim(coalesce(v_candidate.subject_binding->>'label',''));
  if v_unit_name='' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','unit_name_required','canPromote',false
    );
  end if;

  if v_candidate.object_binding is null
     or v_candidate.object_binding->>'kind'<>'organization'
     or v_candidate.object_binding->>'resolution'<>'canonical'
     or nullif(btrim(coalesce(v_candidate.object_binding->>'canonicalId','')),'') is null then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','identity_resolution_required',
      'canPromote',false,
      'slot','object'
    );
  end if;

  if v_candidate.context_binding is not null
     and (
       v_candidate.context_binding->>'kind'<>'organization_unit'
       or v_candidate.context_binding->>'resolution'<>'canonical'
       or nullif(btrim(coalesce(v_candidate.context_binding->>'canonicalId','')),'') is null
     ) then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','identity_resolution_required',
      'canPromote',false,
      'slot','context'
    );
  end if;

  begin
    v_organization_id:=(v_candidate.object_binding->>'canonicalId')::uuid;
    if v_candidate.context_binding is not null then
      v_parent_unit_id:=(v_candidate.context_binding->>'canonicalId')::uuid;
    end if;
  exception when invalid_text_representation then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_binding_invalid',
      'canPromote',false
    );
  end;

  if not exists(
    select 1
    from atlas.organizations o
    where o.id=v_organization_id
      and o.status='active'
  ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_organization_unavailable','canPromote',false
    );
  end if;

  if v_parent_unit_id is not null
     and not exists(
       select 1
       from atlas.organization_units u
       where u.id=v_parent_unit_id
         and u.organization_id=v_organization_id
         and u.status='active'
     ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_parent_unit_unavailable','canPromote',false
    );
  end if;

  if v_candidate.semantic_payload is null
     or jsonb_typeof(v_candidate.semantic_payload)<>'object' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','semantic_payload_invalid','canPromote',false
    );
  end if;

  v_unit_kind:=btrim(coalesce(v_candidate.semantic_payload->>'unitKind',''));
  if v_unit_kind='' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','semantic_payload_required','canPromote',false,
      'requiredKeys',jsonb_build_array('unitKind')
    );
  end if;

  if v_candidate.semantic_payload ? 'stableKey'
     or v_candidate.semantic_payload ? 'stable_key' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','technical_identifier_not_allowed','canPromote',false,
      'reason','stable_key_is_owned_by_organization_structure'
    );
  end if;

  select b.*
  into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.implementation_case_id=v_candidate.implementation_case_id
    and b.organization_id=v_organization_id
    and b.organization_unit_id is null
    and b.state in ('bound','activated')
    and b.ended_at is null
  order by case when b.state='activated' then 0 else 1 end,b.bound_at,b.id
  limit 1;

  if v_binding.id is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','outside_implementation_scope','canPromote',false,
      'reason','active_root_ledger_binding_required'
    );
  end if;

  if not exists(
    select 1
    from atlas.ledger_organization_participations p
    where p.ledger_id=v_binding.ledger_id
      and p.organization_id=v_organization_id
      and p.status='active'
      and p.ended_at is null
  ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_scope_conflict','canPromote',false,
      'reason','organization_not_active_in_bound_ledger'
    );
  end if;

  select cp.id,cp.human_user_id
  into v_sponsor_participant_id,v_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=v_candidate.implementation_case_id
    and cp.relationship_kind='setup_sponsor'
    and cp.active
    and cp.ended_at is null
    and cp.verified_at is not null
  order by cp.started_at,cp.id
  limit 1;

  if v_sponsor_participant_id is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','setup_sponsor_authority_required','canPromote',false
    );
  end if;

  select pac.person_id
  into v_sponsor_person_id
  from atlas.person_auth_credentials pac
  join atlas.people p
    on p.id=pac.person_id
   and p.status='active'
  where pac.auth_user_id=v_sponsor_user_id
    and pac.status='active'
  order by pac.bound_at,pac.id
  limit 1;

  select p.id
  into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id=v_sponsor_person_id
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_sponsor_principal_id is null
     or not atlas.principal_has_ledger_authority_v1(
       v_sponsor_principal_id,
       v_binding.ledger_id
     ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','setup_sponsor_authority_required','canPromote',false,
      'reason','verified_setup_sponsor_principal_must_govern_bound_ledger'
    );
  end if;

  select u.*
  into v_existing
  from atlas.organization_units u
  where u.organization_id=v_organization_id
    and lower(btrim(u.name))=lower(v_unit_name)
  order by
    case when u.status='active' then 0 else 1 end,
    u.created_at,
    u.id
  limit 1;

  if v_existing.id is not null then
    if v_existing.status='active'
       and v_existing.unit_kind=v_unit_kind
       and v_existing.parent_unit_id is not distinct from v_parent_unit_id then
      return jsonb_build_object(
        'ok',true,
        'candidateId',v_candidate.id,
        'operationId',v_candidate.operation_id,
        'state','canonical_identity_exists',
        'canPromote',false,
        'reason','bind_existing_organization_unit_instead_of_creating_duplicate',
        'existingOrganizationUnitId',v_existing.id,
        'existingRealityEntry',
          atlas.render_organization_unit_reality_consequence_v1(v_existing.id)
      );
    end if;

    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_conflict',
      'canPromote',false,
      'reason','same_name_organization_unit_exists_with_different_structure',
      'existingOrganizationUnitId',v_existing.id,
      'existingUnitKind',v_existing.unit_kind,
      'existingParentUnitId',v_existing.parent_unit_id
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'candidateId',v_candidate.id,
    'operationId',v_candidate.operation_id,
    'state','ready',
    'canPromote',true,
    'scope',jsonb_build_object(
      'implementationCaseId',v_candidate.implementation_case_id,
      'practitionerParticipantId',v_practitioner_participant_id,
      'setupSponsorParticipantId',v_sponsor_participant_id,
      'setupSponsorPrincipalId',v_sponsor_principal_id,
      'ledgerEntitlementBindingId',v_binding.id,
      'ledgerId',v_binding.ledger_id,
      'organizationId',v_organization_id
    ),
    'consequence',jsonb_strip_nulls(jsonb_build_object(
      'kind','organization_unit',
      'mode','create_unit',
      'name',v_unit_name,
      'unitKind',v_unit_kind,
      'organizationId',v_organization_id,
      'parentUnitId',v_parent_unit_id
    ))
  );
end;
$function$;

revoke all on function atlas.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function public.preview_implementation_reality_organization_unit_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $function$
declare
  v_result jsonb;
  v_promotion_proc regprocedure;
  v_promotion_command_available boolean:=false;
begin
  v_result:=atlas.preview_implementation_reality_organization_unit_promotion_self_api_v1(
    p_candidate_id
  );

  v_promotion_proc:=to_regprocedure(
    'public.promote_implementation_reality_organization_unit_self_api_v1(uuid)'
  );

  v_promotion_command_available:=
    v_promotion_proc is not null
    and has_function_privilege('authenticated',v_promotion_proc,'EXECUTE');

  return v_result || jsonb_build_object(
    'promotionCommandAvailable',v_promotion_command_available,
    'canExecutePromotion',
      v_promotion_command_available
      and coalesce((v_result->>'canPromote')::boolean,false)
  );
end;
$function$;

revoke all on function public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)
  from public,anon,service_role;

grant execute on function public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)
  to authenticated;

comment on function public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid) is
  'Read-only readiness membrane for organization_unit.establish. It validates proposed-unit grammar, unitKind semantic payload, optional canonical parent Unit, case root-Ledger scope, and setup-sponsor Principal authority. It never creates or mutates Organization Unit truth or Reality Candidate state.';

commit;
