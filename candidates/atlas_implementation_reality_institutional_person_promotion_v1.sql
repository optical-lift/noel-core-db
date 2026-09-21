begin;

-- Atlas Implementation Reality Institutional Person Promotion v1
--
-- First executable Reality Candidate promotion path:
--
--   typed candidate
--   -> canonical Person + canonical Organization
--   -> sponsor-governed Implementation scope
--   -> owning Identity-domain command
--   -> Institutional Person Record
--   -> canonical consequence receipt
--   -> candidate promoted
--
-- This migration does NOT create a Person, Organization, Membership, Position,
-- employee seat, responsibility, login, permission, or Work. It only establishes
-- the Organization-scoped fact that an already-canonical Person is known to an
-- already-canonical Organization.

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


create or replace function atlas.establish_institutional_person_from_reality_internal_v1(
  p_organization_id uuid,
  p_person_id uuid,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_record atlas.institutional_person_records%rowtype;
begin
  if p_organization_id is null or p_person_id is null then
    raise exception 'Canonical Organization and Person are required.'
      using errcode='22023';
  end if;

  if p_establishment_basis is null
     or jsonb_typeof(p_establishment_basis)<>'object' then
    raise exception 'Institutional Person establishment basis must be a JSON object.'
      using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.organizations o
    where o.id=p_organization_id
      and o.status='active'
  ) then
    raise exception 'Active canonical Organization required.'
      using errcode='23503';
  end if;

  if not exists(
    select 1
    from atlas.people p
    where p.id=p_person_id
      and p.status='active'
  ) then
    raise exception 'Active canonical Person required.'
      using errcode='23503';
  end if;

  select *
  into v_record
  from atlas.institutional_person_records ipr
  where ipr.organization_id=p_organization_id
    and ipr.person_id=p_person_id
  for update;

  if v_record.id is not null then
    if v_record.status<>'active' then
      raise exception 'Institutional Person Record exists but is not active.'
        using errcode='23514';
    end if;

    return jsonb_build_object(
      'state','unchanged',
      'consequenceKind','institutional_person_record',
      'institutionalPersonRecordId',v_record.id,
      'organizationId',p_organization_id,
      'personId',p_person_id
    );
  end if;

  insert into atlas.institutional_person_records(
    organization_id,
    person_id,
    status,
    establishment_basis
  ) values (
    p_organization_id,
    p_person_id,
    'active',
    p_establishment_basis || jsonb_build_object(
      'source','establish_institutional_person_from_reality_internal_v1',
      'contractVersion','institutional_person_reality_promotion_v1'
    )
  )
  on conflict (organization_id,person_id) do nothing
  returning * into v_record;

  if v_record.id is null then
    select *
    into v_record
    from atlas.institutional_person_records ipr
    where ipr.organization_id=p_organization_id
      and ipr.person_id=p_person_id;

    if v_record.id is null or v_record.status<>'active' then
      raise exception 'Concurrent Institutional Person establishment did not resolve to an active canonical record.'
        using errcode='23514';
    end if;

    return jsonb_build_object(
      'state','unchanged',
      'consequenceKind','institutional_person_record',
      'institutionalPersonRecordId',v_record.id,
      'organizationId',p_organization_id,
      'personId',p_person_id
    );
  end if;

  return jsonb_build_object(
    'state','established',
    'consequenceKind','institutional_person_record',
    'institutionalPersonRecordId',v_record.id,
    'organizationId',p_organization_id,
    'personId',p_person_id
  );
end;
$function$;

revoke all on function atlas.establish_institutional_person_from_reality_internal_v1(
  uuid,uuid,jsonb
) from public, anon, authenticated, service_role;


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


create or replace function atlas.promote_implementation_reality_candidate_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_candidate atlas.implementation_reality_candidates%rowtype;
  v_preview jsonb;
  v_person_id uuid;
  v_organization_id uuid;
  v_receipt jsonb;
  v_record_id uuid;
  v_basis jsonb;
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
  where c.id=p_candidate_id
  for update of c;

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

  if v_candidate.candidate_state='promoted' then
    if v_candidate.canonical_consequence_kind='institutional_person_record' then
      begin
        v_record_id:=v_candidate.canonical_consequence_ref::uuid;
      exception when invalid_text_representation then
        v_record_id:=null;
      end;
    end if;

    if v_record_id is not null then
      v_render:=atlas.render_institutional_person_reality_consequence_v1(v_record_id);
    end if;

    return jsonb_build_object(
      'ok',true,
      'promoted',true,
      'alreadyPromoted',true,
      'candidateId',v_candidate.id,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref,
      'realityEntry',v_render
    );
  end if;

  v_preview:=atlas.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate.id
  );

  if v_preview->>'state'<>'ready' then
    if v_preview->>'state' in (
      'identity_resolution_required',
      'canonical_binding_invalid',
      'canonical_person_unavailable',
      'canonical_organization_unavailable',
      'outside_implementation_scope',
      'canonical_scope_conflict',
      'setup_sponsor_authority_required',
      'establishment_basis_required',
      'canonical_conflict'
    ) then
      update atlas.implementation_reality_candidates
      set candidate_state='unresolved',
          updated_at=now()
      where id=v_candidate.id;
    end if;

    return jsonb_build_object(
      'ok',false,
      'promoted',false,
      'candidateId',v_candidate.id,
      'preview',v_preview
    );
  end if;

  v_person_id:=(v_candidate.subject_binding->>'canonicalId')::uuid;
  v_organization_id:=(v_candidate.object_binding->>'canonicalId')::uuid;

  v_basis:=v_candidate.establishment_basis
    || jsonb_build_object(
      'contractVersion','institutional_person_reality_promotion_v1',
      'source','implementation_reality_candidate',
      'implementationCaseId',v_candidate.implementation_case_id,
      'realityCandidateId',v_candidate.id,
      'candidateOrigin',v_candidate.origin_kind,
      'candidateAuthorUserId',v_candidate.author_user_id,
      'promotedByUserId',v_uid,
      'evidenceRefs',v_candidate.evidence_refs,
      'scope',v_preview->'scope'
    );

  v_receipt:=atlas.establish_institutional_person_from_reality_internal_v1(
    v_organization_id,
    v_person_id,
    v_basis
  );

  v_record_id:=(v_receipt->>'institutionalPersonRecordId')::uuid;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',
      canonical_consequence_kind='institutional_person_record',
      canonical_consequence_ref=v_record_id::text,
      promoted_at=now(),
      promoted_by_user_id=v_uid,
      provenance=provenance || jsonb_build_object(
        'promotionContract','institutional_person_reality_promotion_v1',
        'promotionReceipt',v_receipt
      ),
      updated_at=now()
  where id=v_candidate.id;

  v_render:=atlas.render_institutional_person_reality_consequence_v1(v_record_id);

  return jsonb_build_object(
    'ok',true,
    'promoted',true,
    'alreadyPromoted',false,
    'candidateId',v_candidate.id,
    'receipt',v_receipt,
    'canonicalConsequenceKind','institutional_person_record',
    'canonicalConsequenceRef',v_record_id::text,
    'realityEntry',v_render
  );
end;
$function$;

revoke all on function atlas.promote_implementation_reality_candidate_self_api_v1(uuid)
  from public, anon, authenticated, service_role;


create or replace function public.preview_implementation_reality_candidate_promotion_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.preview_implementation_reality_candidate_promotion_self_api_v1(
    p_candidate_id
  );
$function$;

create or replace function public.promote_implementation_reality_candidate_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.promote_implementation_reality_candidate_self_api_v1(
    p_candidate_id
  );
$function$;

revoke all on function public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
  from public, anon, service_role;

revoke all on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
  from public, anon, service_role;

grant execute on function public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)
  to authenticated;

grant execute on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
  to authenticated;

comment on function public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid) is
  'Read-only promotion preview for the first Reality Candidate command. It validates case scope, sponsor-governed Ledger authority, canonical Person/Organization bindings, and establishment basis without mutating truth.';

comment on function public.promote_implementation_reality_candidate_self_api_v1(uuid) is
  'First executable Reality Candidate promotion path. An assigned practitioner may promote only an institutional_person_record.establish candidate within sponsor-governed Implementation scope. The owning Identity-domain command establishes/reuses the Institutional Person Record; candidate text itself never becomes canonical truth.';

commit;
