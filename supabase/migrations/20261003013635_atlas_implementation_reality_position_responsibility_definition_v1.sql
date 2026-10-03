begin;

-- Atlas Implementation Reality: Position -> Responsibility definition v1
--
-- Current canonical carrier:
--   atlas.organization_position_responsibilities
--
-- Operation semantics:
--   position_responsibility_definition.establish means the canonical Position
--   is accountable for the canonical Organization Responsibility.
--
-- This command does not create either endpoint identity. Both endpoints and
-- the governing Organization must already be canonical, active, in the same
-- Organization, and inside the current Implementation Case scope.

do $prerequisites$
begin
  if to_regclass('atlas.implementation_reality_candidates') is null
     or to_regclass('atlas.organization_positions') is null
     or to_regclass('atlas.organization_responsibilities') is null
     or to_regclass('atlas.organization_position_responsibilities') is null
     or to_regclass('atlas.ledger_entitlement_bindings') is null
     or to_regclass('atlas.ledger_organization_participations') is null then
    raise exception 'Position Responsibility definition substrate is unavailable.'
      using errcode='0A000';
  end if;

  if to_regprocedure('atlas.implementation_practitioner_assigned_to_case_self_v1(uuid)') is null
     or to_regprocedure('atlas.principal_has_ledger_authority_v1(uuid,uuid)') is null then
    raise exception 'Implementation authority substrate is unavailable.'
      using errcode='0A000';
  end if;
end;
$prerequisites$;

create or replace function atlas.render_organization_position_responsibility_definition_v1(
  p_position_id uuid,
  p_responsibility_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  select jsonb_build_object(
    'kind','organization_position_responsibility_definition',
    'organizationId',p.organization_id,
    'positionId',p.id,
    'positionTitle',p.display_title,
    'organizationUnitId',p.organization_unit_id,
    'responsibilityId',r.id,
    'responsibilityName',r.name,
    'relationshipKind',pr.relationship_kind,
    'createdAt',pr.created_at
  )
  from atlas.organization_position_responsibilities pr
  join atlas.organization_positions p
    on p.id=pr.position_id
  join atlas.organization_responsibilities r
    on r.id=pr.responsibility_id
  where pr.position_id=p_position_id
    and pr.responsibility_id=p_responsibility_id
    and p.organization_id=r.organization_id;
$function$;

revoke all on function atlas.render_organization_position_responsibility_definition_v1(uuid,uuid)
from public,anon,authenticated,service_role;

create or replace function atlas.preview_implementation_reality_position_responsibility_definition_v1(
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
  v_position atlas.organization_positions%rowtype;
  v_responsibility atlas.organization_responsibilities%rowtype;
  v_organization_id uuid;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_practitioner_participant_id uuid;
  v_sponsor_participant_id uuid;
  v_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_existing_kind text;
  v_basis_kind text;
  v_render jsonb;
  v_ref_parts text[];
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select c.* into v_candidate
  from atlas.implementation_reality_candidates c
  join atlas.implementation_cases ic
    on ic.id=c.implementation_case_id
   and ic.state not in ('closed','cancelled')
  where c.id=p_candidate_id;

  if v_candidate.id is null then
    raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;

  select cp.id into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=v_candidate.implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active
    and cp.ended_at is null
    and cp.human_user_id=v_uid
  order by cp.started_at,cp.id
  limit 1;

  if v_candidate.candidate_state='promoted' then
    if v_candidate.canonical_consequence_kind='organization_position_responsibility_definition'
       and nullif(v_candidate.canonical_consequence_ref,'') is not null then
      v_ref_parts:=string_to_array(v_candidate.canonical_consequence_ref,'|');
      if cardinality(v_ref_parts)=2 then
        begin
          v_render:=atlas.render_organization_position_responsibility_definition_v1(
            v_ref_parts[1]::uuid,v_ref_parts[2]::uuid
          );
        exception when invalid_text_representation then
          v_render:=null;
        end;
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
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','candidate_not_promotable','canPromote',false,
      'reason','candidate_state_'||v_candidate.candidate_state
    );
  end if;

  if v_candidate.operation_id<>'position_responsibility_definition.establish' then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','governed_command_unverified','canPromote',false,
      'reason','preview_supports_position_responsibility_definition_only'
    );
  end if;

  if v_candidate.subject_binding->>'kind'<>'organization_position'
     or v_candidate.subject_binding->>'resolution'<>'canonical'
     or nullif(btrim(coalesce(v_candidate.subject_binding->>'canonicalId','')),'') is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','identity_resolution_required','canPromote',false,'slot','subject'
    );
  end if;

  if v_candidate.object_binding is null
     or v_candidate.object_binding->>'kind'<>'organization_responsibility'
     or v_candidate.object_binding->>'resolution'<>'canonical'
     or nullif(btrim(coalesce(v_candidate.object_binding->>'canonicalId','')),'') is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','identity_resolution_required','canPromote',false,'slot','object'
    );
  end if;

  if v_candidate.context_binding is null
     or v_candidate.context_binding->>'kind'<>'organization'
     or v_candidate.context_binding->>'resolution'<>'canonical'
     or nullif(btrim(coalesce(v_candidate.context_binding->>'canonicalId','')),'') is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','identity_resolution_required','canPromote',false,'slot','context'
    );
  end if;

  begin
    select p.* into v_position
    from atlas.organization_positions p
    where p.id=(v_candidate.subject_binding->>'canonicalId')::uuid
      and p.status='active';

    select r.* into v_responsibility
    from atlas.organization_responsibilities r
    where r.id=(v_candidate.object_binding->>'canonicalId')::uuid
      and r.status='active';

    v_organization_id:=(v_candidate.context_binding->>'canonicalId')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_binding_invalid','canPromote',false
    );
  end;

  if v_position.id is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_position_unavailable','canPromote',false
    );
  end if;

  if v_responsibility.id is null then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_responsibility_unavailable','canPromote',false
    );
  end if;

  if not exists(
    select 1 from atlas.organizations o
    where o.id=v_organization_id and o.status='active'
  ) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_organization_unavailable','canPromote',false
    );
  end if;

  if v_position.organization_id<>v_organization_id
     or v_responsibility.organization_id<>v_organization_id then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_scope_conflict','canPromote',false,
      'reason','position_responsibility_and_context_must_share_one_organization'
    );
  end if;

  if v_candidate.semantic_payload is null
     or jsonb_typeof(v_candidate.semantic_payload)<>'object'
     or v_candidate.semantic_payload<>'{}'::jsonb then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','semantic_payload_invalid','canPromote',false,
      'reason','position_responsibility_definition_has_no_freeform_semantic_payload'
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
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','establishment_basis_required','canPromote',false
    );
  end if;

  select b.* into v_binding
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
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
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
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_scope_conflict','canPromote',false,
      'reason','organization_must_participate_in_bound_ledger'
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
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','setup_sponsor_authority_required','canPromote',false
    );
  end if;

  select pac.person_id into v_sponsor_person_id
  from atlas.person_auth_credentials pac
  join atlas.people p on p.id=pac.person_id and p.status='active'
  where pac.auth_user_id=v_sponsor_user_id
    and pac.status='active'
  order by pac.bound_at,pac.id
  limit 1;

  select p.id into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id=v_sponsor_person_id
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_sponsor_principal_id is null
     or not atlas.principal_has_ledger_authority_v1(v_sponsor_principal_id,v_binding.ledger_id) then
    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','setup_sponsor_authority_required','canPromote',false,
      'reason','verified_setup_sponsor_principal_must_govern_bound_ledger'
    );
  end if;

  select pr.relationship_kind into v_existing_kind
  from atlas.organization_position_responsibilities pr
  where pr.position_id=v_position.id
    and pr.responsibility_id=v_responsibility.id;

  if v_existing_kind is not null then
    v_render:=atlas.render_organization_position_responsibility_definition_v1(
      v_position.id,v_responsibility.id
    );

    if v_existing_kind='accountable' then
      return jsonb_build_object(
        'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
        'state','canonical_relation_exists','canPromote',false,
        'reason','position_is_already_accountable_for_responsibility',
        'existingRealityEntry',v_render
      );
    end if;

    return jsonb_build_object(
      'ok',true,'candidateId',v_candidate.id,'operationId',v_candidate.operation_id,
      'state','canonical_conflict','canPromote',false,
      'reason','position_responsibility_pair_exists_with_different_relationship_kind',
      'existingRelationshipKind',v_existing_kind,
      'existingRealityEntry',v_render
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
    'consequence',jsonb_build_object(
      'kind','organization_position_responsibility_definition',
      'mode','establish_accountability',
      'organizationId',v_organization_id,
      'positionId',v_position.id,
      'positionTitle',v_position.display_title,
      'responsibilityId',v_responsibility.id,
      'responsibilityName',v_responsibility.name,
      'relationshipKind','accountable'
    ),
    'truthBoundary',jsonb_build_object(
      'createsPositionIdentity',false,
      'createsResponsibilityIdentity',false,
      'createsOrganizationIdentity',false,
      'establishesAccountabilityDefinition',true
    )
  );
end;
$function$;

revoke all on function atlas.preview_implementation_reality_position_responsibility_definition_v1(uuid)
from public,anon,authenticated,service_role;

create or replace function atlas.establish_position_responsibility_definition_from_reality_v1(
  p_position_id uuid,
  p_responsibility_id uuid,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_position atlas.organization_positions%rowtype;
  v_responsibility atlas.organization_responsibilities%rowtype;
  v_existing_kind text;
  v_inserted boolean:=false;
begin
  if p_establishment_basis is null or jsonb_typeof(p_establishment_basis)<>'object' then
    raise exception 'Establishment basis must be a JSON object.' using errcode='22023';
  end if;

  select * into v_position
  from atlas.organization_positions
  where id=p_position_id and status='active';
  if v_position.id is null then
    raise exception 'Active canonical Organization Position required.' using errcode='P0002';
  end if;

  select * into v_responsibility
  from atlas.organization_responsibilities
  where id=p_responsibility_id and status='active';
  if v_responsibility.id is null then
    raise exception 'Active canonical Organization Responsibility required.' using errcode='P0002';
  end if;

  if v_position.organization_id<>v_responsibility.organization_id then
    raise exception 'Position and Responsibility must belong to the same Organization.' using errcode='23514';
  end if;

  insert into atlas.organization_position_responsibilities(
    position_id,responsibility_id,relationship_kind
  ) values (
    p_position_id,p_responsibility_id,'accountable'
  )
  on conflict (position_id,responsibility_id) do nothing;
  v_inserted:=found;

  select relationship_kind into v_existing_kind
  from atlas.organization_position_responsibilities
  where position_id=p_position_id
    and responsibility_id=p_responsibility_id;

  if v_existing_kind<>'accountable' then
    raise exception 'Existing Position Responsibility definition conflicts with accountable semantics.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','position_responsibility_definition_reality_establishment_v1',
    'organizationId',v_position.organization_id,
    'positionId',p_position_id,
    'responsibilityId',p_responsibility_id,
    'relationshipKind','accountable',
    'inserted',v_inserted,
    'establishmentBasis',p_establishment_basis,
    'realityEntry',atlas.render_organization_position_responsibility_definition_v1(
      p_position_id,p_responsibility_id
    )
  );
end;
$function$;

revoke all on function atlas.establish_position_responsibility_definition_from_reality_v1(uuid,uuid,jsonb)
from public,anon,authenticated,service_role;

create or replace function atlas.promote_implementation_reality_position_responsibility_definition_v1(
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
  v_position_id uuid;
  v_responsibility_id uuid;
  v_basis jsonb;
  v_receipt jsonb;
  v_ref text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select c.* into v_candidate
  from atlas.implementation_reality_candidates c
  join atlas.implementation_cases ic
    on ic.id=c.implementation_case_id
   and ic.state not in ('closed','cancelled')
  where c.id=p_candidate_id
  for update of c;

  if v_candidate.id is null then
    raise exception 'Open Implementation Reality Candidate not found.' using errcode='23503';
  end if;

  if not atlas.implementation_practitioner_assigned_to_case_self_v1(v_candidate.implementation_case_id) then
    raise exception 'Assigned practitioner authority required.' using errcode='42501';
  end if;

  if v_candidate.candidate_state='promoted' then
    return jsonb_build_object(
      'ok',true,
      'promoted',true,
      'alreadyPromoted',true,
      'candidateId',v_candidate.id,
      'canonicalConsequenceKind',v_candidate.canonical_consequence_kind,
      'canonicalConsequenceRef',v_candidate.canonical_consequence_ref,
      'preview',atlas.preview_implementation_reality_position_responsibility_definition_v1(v_candidate.id)
    );
  end if;

  v_preview:=atlas.preview_implementation_reality_position_responsibility_definition_v1(v_candidate.id);
  if v_preview->>'state'<>'ready' then
    if v_preview->>'state' in (
      'identity_resolution_required',
      'canonical_binding_invalid',
      'canonical_position_unavailable',
      'canonical_responsibility_unavailable',
      'canonical_organization_unavailable',
      'canonical_scope_conflict',
      'semantic_payload_invalid',
      'establishment_basis_required',
      'outside_implementation_scope',
      'setup_sponsor_authority_required',
      'canonical_relation_exists'
    ) then
      update atlas.implementation_reality_candidates
      set candidate_state='unresolved',updated_at=now()
      where id=v_candidate.id;
    end if;

    return jsonb_build_object(
      'ok',false,'promoted',false,'candidateId',v_candidate.id,'preview',v_preview
    );
  end if;

  v_position_id:=(v_candidate.subject_binding->>'canonicalId')::uuid;
  v_responsibility_id:=(v_candidate.object_binding->>'canonicalId')::uuid;

  v_basis:=v_candidate.establishment_basis
    || jsonb_build_object(
      'contractVersion','position_responsibility_definition_reality_promotion_v1',
      'source','implementation_reality_candidate',
      'implementationCaseId',v_candidate.implementation_case_id,
      'realityCandidateId',v_candidate.id,
      'candidateOrigin',v_candidate.origin_kind,
      'candidateAuthorUserId',v_candidate.author_user_id,
      'promotedByUserId',v_uid,
      'evidenceRefs',v_candidate.evidence_refs,
      'scope',v_preview->'scope'
    );

  v_receipt:=atlas.establish_position_responsibility_definition_from_reality_v1(
    v_position_id,v_responsibility_id,v_basis
  );
  v_ref:=v_position_id::text||'|'||v_responsibility_id::text;

  update atlas.implementation_reality_candidates
  set candidate_state='promoted',
      canonical_consequence_kind='organization_position_responsibility_definition',
      canonical_consequence_ref=v_ref,
      promoted_at=now(),
      promoted_by_user_id=v_uid,
      provenance=provenance || jsonb_build_object(
        'promotionContract','position_responsibility_definition_reality_promotion_v1',
        'promotionReceipt',v_receipt
      ),
      updated_at=now()
  where id=v_candidate.id;

  return jsonb_build_object(
    'ok',true,
    'promoted',true,
    'alreadyPromoted',false,
    'candidateId',v_candidate.id,
    'receipt',v_receipt,
    'canonicalConsequenceKind','organization_position_responsibility_definition',
    'canonicalConsequenceRef',v_ref,
    'realityEntry',v_receipt->'realityEntry'
  );
end;
$function$;

revoke all on function atlas.promote_implementation_reality_position_responsibility_definition_v1(uuid)
from public,anon,authenticated,service_role;

create or replace function public.preview_implementation_reality_position_responsibility_definition_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.preview_implementation_reality_position_responsibility_definition_v1(p_candidate_id);
$function$;

revoke all on function public.preview_implementation_reality_position_responsibility_definition_self_api_v1(uuid)
from public,anon,service_role;
grant execute on function public.preview_implementation_reality_position_responsibility_definition_self_api_v1(uuid)
to authenticated;

create or replace function public.promote_implementation_reality_position_responsibility_definition_self_api_v1(
  p_candidate_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.promote_implementation_reality_position_responsibility_definition_v1(p_candidate_id);
$function$;

revoke all on function public.promote_implementation_reality_position_responsibility_definition_self_api_v1(uuid)
from public,anon,service_role;
grant execute on function public.promote_implementation_reality_position_responsibility_definition_self_api_v1(uuid)
to authenticated;

comment on function public.preview_implementation_reality_position_responsibility_definition_self_api_v1(uuid) is
  'Assigned-practitioner preview for establishing canonical Position accountability for an existing canonical Organization Responsibility. No canonical mutation.';
comment on function public.promote_implementation_reality_position_responsibility_definition_self_api_v1(uuid) is
  'Assigned-practitioner promotion membrane for an explicitly previewable Position-to-Responsibility accountability definition. Requires verified setup-sponsor ledger authority.';

commit;
