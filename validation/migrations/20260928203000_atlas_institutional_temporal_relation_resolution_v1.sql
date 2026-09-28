-- Versioned postconditions: Atlas Institutional Temporal Relation Resolution v1.
-- Read-only structural validation. No institutional truth is mutated.

do $block$
declare
  v_def text;
begin
  if to_regprocedure('reality.institution_relation_effective_at_v1(uuid,timestamptz)') is null then
    raise exception 'Strict institutional effective-at helper is missing.';
  end if;

  if to_regprocedure('atlas.institutional_relation_history_self_api_v1(uuid)') is null then
    raise exception 'Institutional relation history self read is missing.';
  end if;

  select pg_get_functiondef(
    'reality.institution_relation_effective_at_v1(uuid,timestamptz)'::regprocedure
  ) into v_def;

  if position('p_as_of is null' in lower(v_def))=0
     or position('valid_from' in v_def)=0
     or position('valid_until' in v_def)=0
     or position('relationship_state = ''established''' in v_def)=0
     or position('now()' in lower(v_def))<>0
     or position('clock_timestamp' in lower(v_def))<>0
     or position('statement_timestamp' in lower(v_def))<>0 then
    raise exception 'Effective-at helper does not enforce explicit deterministic as_of semantics.';
  end if;

  if has_function_privilege(
    'authenticated',
    'reality.institution_relation_effective_at_v1(uuid,timestamptz)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'reality.institution_relation_effective_at_v1(uuid,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'Internal temporal helper is exposed as an application authority surface.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'atlas.institutional_relation_history_self_api_v1(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated self history read is unavailable.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.institutional_relation_history_self_api_v1(uuid)',
    'EXECUTE'
  ) then
    raise exception 'service_role received generic human institutional history disclosure.';
  end if;

  select pg_get_functiondef(
    'atlas.institutional_relation_history_self_api_v1(uuid)'::regprocedure
  ) into v_def;

  if position('atlas.current_person_id_v1' in v_def)=0
     or position('assert_institution_subject_v1' in v_def)=0
     or position('institutional_standing' in v_def)=0
     or position('institution_has_position' in v_def)=0
     or position('institution_has_responsibility' in v_def)=0
     or position('occupies_position' in v_def)=0
     or position('position_carries_responsibility' in v_def)=0 then
    raise exception 'History read is not bounded to the canonical self/institution spine.';
  end if;

  if position('person_position_ids' in v_def)=0
     or position('person_responsibility_ids' in v_def)=0
     or position('personPathComplete' in v_def)=0
     or position('institutionWideStructure' in v_def)=0
     or position('''institutionWideStructure'',false' in replace(v_def,' ',''))=0
     or position('readDoesNotEnumerateInstitutionWideStructure' in v_def)=0 then
    raise exception 'Self history read is not explicitly Person-path bounded.';
  end if;

  if position('includesAllRelationshipStates' in v_def)=0
     or position('historicalIntervalsPreserved' in v_def)=0
     or position('complete' in v_def)=0 then
    raise exception 'History read lacks an explicit completeness boundary.';
  end if;

  if position('statement_timestamp()' in lower(v_def))=0
     or position('clock_timestamp()' in lower(v_def))<>0 then
    raise exception 'History capture provenance does not use statement-stable capture time.';
  end if;

  if position('insert into ' in lower(v_def))<>0
     or position('update ' in lower(v_def))<>0
     or position('delete from ' in lower(v_def))<>0
     or position('reality.responsibility_relations' in lower(v_def))<>0
     or position('ledger.seats' in lower(v_def))<>0
     or position('organization_membership' in lower(v_def))<>0
     or position('principal_clock' in lower(v_def))<>0 then
    raise exception 'Institutional history read leaks mutation, authority, access, or Clock semantics.';
  end if;

  if position('positionDoesNotGrantExecutionAuthority' in v_def)=0
     or position('responsibilityDefinitionDoesNotGrantExecutionAuthority' in v_def)=0
     or position('principalClaimCreated' in v_def)=0
     or position('clockOrTodayStateCreated' in v_def)=0 then
    raise exception 'History read truth boundary is incomplete.';
  end if;
end
$block$;

select
  'institutional_temporal_relation_resolution_v1' as contract,
  'pass' as result,
  true as explicit_as_of_required,
  true as person_path_history_complete,
  false as institution_wide_structure_disclosed,
  true as missing_fetch_is_not_negative_truth,
  false as execution_authority_created,
  false as applicability_created,
  false as principal_or_clock_state_created;
