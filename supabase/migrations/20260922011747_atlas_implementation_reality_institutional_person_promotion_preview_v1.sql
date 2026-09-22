begin;

-- Atlas Implementation Reality Institutional Person Promotion Preview v1
--
-- Additive read-only readiness membrane for the first Reality Candidate
-- promotion family. This release deliberately contains no Institutional Person
-- mutation command and no candidate-state mutation.
--
-- Semantic/authority readiness and executable mutation authority are distinct:
--
--   canPromote
--     = this candidate is lawful and ready for the owning-domain command
--
--   promotionCommandAvailable
--     = the exact public promote RPC exists and authenticated may EXECUTE it
--
--   canExecutePromotion
--     = both conditions are true
--
-- The Workbench can therefore ship/read readiness before promotion authority is
-- released, then self-activate the final establishment affordance later.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Reality Candidate custody must be live before Institutional Person promotion.'
      using errcode='0A000';
  end if;

  if to_regclass('atlas.institutional_person_records') is null then
    raise exception 'Institutional Person Record must be live before Reality Candidate promotion.'
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



create or replace function atlas.render_institutional_person_reality_consequence_v1(
  p_institutional_person_record_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select jsonb_build_object(
    'contractVersion','institutional_person_reality_consequence_v1',
    'consequenceKind','institutional_person_record',
    'canonicalConsequenceRef',ipr.id::text,
    'sentence',
      o.name || ' knows ' ||
      coalesce(nullif(btrim(p.display_name),''),'Person ' || left(p.id::text,8)) ||
      ' as an institutional Person.',
    'subjectBinding',jsonb_build_object(
      'kind','person',
      'label',coalesce(nullif(btrim(p.display_name),''),'Person ' || left(p.id::text,8)),
      'resolution','canonical',
      'canonicalId',p.id
    ),
    'objectBinding',jsonb_build_object(
      'kind','organization',
      'label',o.name,
      'resolution','canonical',
      'canonicalId',o.id
    ),
    'institutionalPersonRecordId',ipr.id,
    'organizationId',o.id,
    'personId',p.id,
    'status',ipr.status
  )
  from atlas.institutional_person_records ipr
  join atlas.organizations o
    on o.id=ipr.organization_id
  join atlas.people p
    on p.id=ipr.person_id
  where ipr.id=p_institutional_person_record_id;
$function$;

revoke all on function atlas.render_institutional_person_reality_consequence_v1(uuid)
  from public, anon, authenticated, service_role;



create or replace function atlas.preview_implementation_reality_candidate_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_person_id uuid;
  v_organization_id uuid;
  v_basis_kind text;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_practitioner_participant_id uuid;
  v_sponsor_participant_id uuid;
  v_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_existing atlas.institutional_person_records%rowtype;
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
    if v_candidate.canonical_consequence_kind='institutional_person_record'
       and nullif(v_candidate.canonical_consequence_ref,'') is not null then
      begin
        v_existing.id:=v_candidate.canonical_consequence_ref::uuid;
      exception when invalid_text_representation then
        v_existing.id:=null;
      end;

      if v_existing.id is not null then
        v_render:=atlas.render_institutional_person_reality_consequence_v1(v_existing.id);
      end if;
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

  if v_candidate.operation_id<>'institutional_person_record.establish' then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','governed_command_unverified',
      'canPromote',false,
      'reason','first_promotion_slice_supports_institutional_person_record_only'
    );
  end if;

  if v_candidate.subject_binding->>'kind'<>'person'
     or v_candidate.subject_binding->>'resolution'<>'canonical'
     or nullif(btrim(coalesce(v_candidate.subject_binding->>'canonicalId','')),'') is null then
    return jsonb_build_object(
      'ok',true,
      'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','identity_resolution_required',
      'canPromote',false,
      'slot','subject'
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

  begin
    v_person_id:=(v_candidate.subject_binding->>'canonicalId')::uuid;
    v_organization_id:=(v_candidate.object_binding->>'canonicalId')::uuid;
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
    select 1 from atlas.people p
    where p.id=v_person_id and p.status='active'
  ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_person_unavailable','canPromote',false
    );
  end if;

  if not exists(
    select 1 from atlas.organizations o
    where o.id=v_organization_id and o.status='active'
  ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_organization_unavailable','canPromote',false
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

  v_basis_kind:=v_candidate.establishment_basis->>'kind';

  if v_candidate.establishment_basis is null
     or jsonb_typeof(v_candidate.establishment_basis)<>'object'
     or v_basis_kind not in (
       'explicit_acceptance',
       'standing_intake',
       'reconstruction_of_existing_reality',
       'adjudicated_existing_reality',
       'other_governed_basis'
     ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','establishment_basis_required','canPromote',false,
      'allowedBasisKinds',jsonb_build_array(
        'explicit_acceptance',
        'standing_intake',
        'reconstruction_of_existing_reality',
        'adjudicated_existing_reality',
        'other_governed_basis'
      )
    );
  end if;

  select *
  into v_existing
  from atlas.institutional_person_records ipr
  where ipr.organization_id=v_organization_id
    and ipr.person_id=v_person_id;

  if v_existing.id is not null and v_existing.status<>'active' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,
      'operationId',v_candidate.operation_id,
      'state','canonical_conflict','canPromote',false,
      'reason','institutional_person_record_exists_but_is_not_active',
      'institutionalPersonRecordId',v_existing.id
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
      'kind','institutional_person_record',
      'mode',case when v_existing.id is null then 'create_relation' else 'reuse_existing' end,
      'personId',v_person_id,
      'organizationId',v_organization_id,
      'institutionalPersonRecordId',v_existing.id
    ))
  );
end;
$function$;

revoke all on function atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
  from public, anon, authenticated, service_role;



create or replace function public.preview_implementation_reality_candidate_promotion_self_api_v1(
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
  v_promotion_command_available boolean := false;
begin
  v_result := atlas.preview_implementation_reality_candidate_promotion_self_api_v1(
    p_candidate_id
  );

  v_promotion_proc := to_regprocedure(
    'public.promote_implementation_reality_candidate_self_api_v1(uuid)'
  );

  v_promotion_command_available :=
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



revoke all on function public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
  from public, anon, service_role;

grant execute on function public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
  to authenticated;

comment on function public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid) is
  'Read-only promotion readiness membrane for institutional_person_record.establish. It validates case scope, sponsor-governed Ledger authority, canonical Person/Organization bindings, and establishment basis. promotionCommandAvailable/canExecutePromotion remain false until the exact governed mutation RPC is separately released.';

commit;
