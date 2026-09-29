-- Versioned postconditions: Atlas Responsibility Applicability v1.
-- Read-only structural validation. No applicability, authority, Work, Principal,
-- or Clock truth is mutated by this validator.

do $block$
declare
  v_def text;
begin
  if to_regclass('atlas.responsibility_applicability_governance') is null then
    raise exception 'Responsibility applicability governance table is missing.';
  end if;

  if to_regprocedure('reality.responsibility_applicability_effective_at_v1(uuid,text,timestamptz)') is null then
    raise exception 'Strict responsibility applicability effective-at helper is missing.';
  end if;

  if to_regprocedure('atlas.responsibility_applicability_history_api_v1(uuid,uuid,text)') is null then
    raise exception 'Responsibility applicability exact-history read is missing.';
  end if;

  if has_table_privilege('authenticated','atlas.responsibility_applicability_governance','SELECT')
     or has_table_privilege('authenticated','atlas.responsibility_applicability_governance','INSERT')
     or has_table_privilege('authenticated','atlas.responsibility_applicability_governance','UPDATE')
     or has_table_privilege('authenticated','atlas.responsibility_applicability_governance','DELETE')
     or has_table_privilege('service_role','atlas.responsibility_applicability_governance','SELECT') then
    raise exception 'Applicability governance table is exposed as an application authority surface.';
  end if;

  select pg_get_functiondef(
    'reality.responsibility_applicability_effective_at_v1(uuid,text,timestamptz)'::regprocedure
  ) into v_def;

  if position('p_as_of is null' in lower(v_def))=0
     or position('p_operation_key is null' in lower(v_def))=0
     or position('relationship_kind = ''responsibility_applies_to''' in lower(v_def))=0
     or position('relationship_state = ''established''' in lower(v_def))=0
     or position('governance_state = ''established''' in lower(v_def))=0
     or position('valid_from <= p_as_of' in lower(v_def))=0
     or position('valid_until is null or er.valid_until > p_as_of' in lower(v_def))=0
     or position('valid_until is null or rag.valid_until > p_as_of' in lower(v_def))=0
     or position('now()' in lower(v_def))<>0
     or position('clock_timestamp' in lower(v_def))<>0
     or position('statement_timestamp' in lower(v_def))<>0 then
    raise exception 'Applicability effective-at helper does not enforce exact operation and deterministic half-open as_of semantics.';
  end if;

  if position('join atlas.responsibility_applicability_governance' in lower(v_def))=0
     or position('rag.operation_key = p_operation_key' in lower(v_def))=0 then
    raise exception 'Applicability relation is not resolved through separate exact-operation governance.';
  end if;

  if has_function_privilege(
    'authenticated',
    'reality.responsibility_applicability_effective_at_v1(uuid,text,timestamptz)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'reality.responsibility_applicability_effective_at_v1(uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'Internal applicability temporal helper is exposed as an application authority surface.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'atlas.responsibility_applicability_history_api_v1(uuid,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated exact applicability history read is unavailable.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.responsibility_applicability_history_api_v1(uuid,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'service_role received generic responsibility applicability history disclosure.';
  end if;

  select pg_get_functiondef(
    'atlas.responsibility_applicability_history_api_v1(uuid,uuid,text)'::regprocedure
  ) into v_def;

  if position('assert_canonical_entity_kind_v1' in v_def)=0
     or position('''responsibility''' in lower(v_def))=0
     or position('relationship_kind = ''responsibility_applies_to''' in lower(v_def))=0
     or position('subject_entity_id = p_responsibility_entity_id' in lower(v_def))=0
     or position('object_entity_id = p_target_entity_id' in lower(v_def))=0
     or position('rag.operation_key = p_operation_key' in lower(v_def))=0 then
    raise exception 'Applicability history is not bounded to an exact canonical Responsibility, target Reality Entity, operation, and relation family.';
  end if;

  if position('left join atlas.responsibility_applicability_governance' in lower(v_def))=0
     or position('when rag.id is null then null' in lower(v_def))=0
     or position('includesRelationsWithoutGovernance' in v_def)=0
     or position('''includesRelationsWithoutGovernance'',true' in replace(v_def,' ',''))=0 then
    raise exception 'Applicability history can erase a relation whose matching operation governance is missing.';
  end if;

  if position('includesAllRelationshipStates' in v_def)=0
     or position('includesAllMatchingOperationGovernanceStates' in v_def)=0
     or position('historicalIntervalsPreserved' in v_def)=0
     or position('exactResponsibilityEntityId' in v_def)=0
     or position('exactTargetEntityId' in v_def)=0
     or position('exactOperationKey' in v_def)=0
     or position('complete' in v_def)=0 then
    raise exception 'Applicability history lacks an explicit exact-history completeness boundary.';
  end if;

  if position('statement_timestamp()' in lower(v_def))=0
     or position('clock_timestamp()' in lower(v_def))<>0 then
    raise exception 'Applicability history capture provenance does not use statement-stable capture time.';
  end if;

  if position('insert into ' in lower(v_def))<>0
     or position('update ' in lower(v_def))<>0
     or position('delete from ' in lower(v_def))<>0
     or position('ledger.seats' in lower(v_def))<>0
     or position('organization_membership' in lower(v_def))<>0
     or position('principal_clock' in lower(v_def))<>0 then
    raise exception 'Applicability history leaks mutation, authority, access, or Clock semantics.';
  end if;

  if position('legacyOrganizationResponsibilityIdsAcceptedAsCanonical' in v_def)=0
     or position('''legacyOrganizationResponsibilityIdsAcceptedAsCanonical'',false' in replace(v_def,' ',''))=0
     or position('executionAuthorityCreated' in v_def)=0
     or position('''executionAuthorityCreated'',false' in replace(v_def,' ',''))=0
     or position('workAllocationCreated' in v_def)=0
     or position('''workAllocationCreated'',false' in replace(v_def,' ',''))=0
     or position('principalClaimCreated' in v_def)=0
     or position('''principalClaimCreated'',false' in replace(v_def,' ',''))=0
     or position('clockOrTodayStateCreated' in v_def)=0
     or position('''clockOrTodayStateCreated'',false' in replace(v_def,' ',''))=0 then
    raise exception 'Applicability history truth boundary is incomplete.';
  end if;
end
$block$;

select
  'responsibility_applicability_v1' as contract,
  'pass' as result,
  true as canonical_responsibility_required,
  true as exact_target_required,
  true as exact_operation_required,
  true as explicit_as_of_required,
  true as governance_separate,
  true as missing_governance_visible,
  true as exact_history_complete,
  false as legacy_organization_responsibility_ids_canonical,
  false as execution_authority_created,
  false as work_allocation_created,
  false as principal_claim_created,
  false as clock_state_created;
