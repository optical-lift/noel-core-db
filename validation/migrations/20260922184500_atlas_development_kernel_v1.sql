begin;

do $validation$
declare
  v jsonb;
  v_replay jsonb;
  v_release jsonb;
  v_knowledge_id uuid := 'd5e00000-0000-4000-8000-000000000150'::uuid;
begin
  -- -----------------------------------------------------------------------
  -- CI Standard: Playable / Buildable / Fundable
  -- -----------------------------------------------------------------------

  insert into atlas.development_standard_versions(
    id,organization_id,ledger_id,stable_key,version,title,purpose,
    eligible_subject_kinds,status,provenance,metadata
  ) values (
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'd5e00000-0000-4000-8000-000000000001'::uuid,
    'd5e00000-0000-4000-8000-000000000002'::uuid,
    'ci_activity_development',
    1,
    'CI Activity Development Standard',
    'Validation proof for developing mobile, inexpensive, newly learned camp activities.',
    array['activity']::text[],
    'draft',
    '{"source":"development_kernel_validation"}'::jsonb,
    '{"validationFixture":true}'::jsonb
  );

  insert into atlas.development_standard_criteria(
    id,standard_version_id,criterion_key,question,rationale,
    base_score,consequence_value,information_gain,expected_friction
  ) values
  (
    'd5e00000-0000-4000-8000-000000000211'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'player_capacity',
    'Is the supported player/group shape established?',
    'Playable use requires a known group shape.',
    20,50,30,1
  ),
  (
    'd5e00000-0000-4000-8000-000000000212'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'construction_specification',
    'Can another party construct a compliant set?',
    'Buildability requires a reproducible construction specification.',
    20,80,70,8
  ),
  (
    'd5e00000-0000-4000-8000-000000000213'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'current_cost',
    'Is the current real-world cost basis established?',
    'Fundable projections require current cost evidence.',
    20,60,50,4
  );

  insert into atlas.development_standard_gates(
    id,standard_version_id,gate_key,label,description
  ) values
  (
    'd5e00000-0000-4000-8000-000000000221'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'playable','Playable','Enough is established to play the activity.'
  ),
  (
    'd5e00000-0000-4000-8000-000000000222'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'buildable','Buildable','Another party can construct a compliant activity set.'
  ),
  (
    'd5e00000-0000-4000-8000-000000000223'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'fundable','Fundable','A current cost basis exists.'
  );

  insert into atlas.development_standard_gate_requirements(
    gate_id,criterion_id,accepted_resolution_kinds
  ) values
  (
    'd5e00000-0000-4000-8000-000000000221'::uuid,
    'd5e00000-0000-4000-8000-000000000211'::uuid,
    array['established','inherited']::text[]
  ),
  (
    'd5e00000-0000-4000-8000-000000000222'::uuid,
    'd5e00000-0000-4000-8000-000000000212'::uuid,
    array['established','inherited']::text[]
  ),
  (
    'd5e00000-0000-4000-8000-000000000223'::uuid,
    'd5e00000-0000-4000-8000-000000000213'::uuid,
    array['established','inherited']::text[]
  );

  update atlas.development_standard_versions
  set status='established',
      established_by_label='CI Development validation authority'
  where id='d5e00000-0000-4000-8000-000000000201'::uuid;

  insert into atlas.development_cases(
    id,organization_id,ledger_id,standard_version_id,case_key,
    target_domain,target_kind,target_ref,purpose,opened_by_label,metadata
  ) values (
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'd5e00000-0000-4000-8000-000000000001'::uuid,
    'd5e00000-0000-4000-8000-000000000002'::uuid,
    'd5e00000-0000-4000-8000-000000000201'::uuid,
    'ci-washers-development-proof',
    'ci_activity',
    'activity',
    'washers',
    'Develop Washers as a reproducible mobile/inexpensive/newly learned camp activity.',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  perform atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'player_capacity',
    'established',
    'source_artifact',
    'ci_activity',
    'washers-script-v1.00',
    'The source establishes supported player counts for the activity.',
    'ci-player-capacity-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  perform atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'construction_specification',
    'unresolved',
    'development_assessment',
    'development',
    null,
    'The current source is insufficient to reproduce the construction specification.',
    'ci-construction-unresolved-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  perform atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'current_cost',
    'needs_evidence',
    'development_assessment',
    'development',
    null,
    'Current cost requires external pricing evidence.',
    'ci-current-cost-needs-evidence-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,'playable'
  );
  if v->>'state'<>'satisfied' or (v->>'blockedCount')::integer<>0 then
    raise exception 'CI Playable gate should be satisfied: %',v;
  end if;

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,'buildable'
  );
  if v->>'state'<>'blocked'
     or v#>>'{blockers,0,criterionKey}'<>'construction_specification' then
    raise exception 'CI Buildable gate should be blocked only by construction: %',v;
  end if;

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,'fundable'
  );
  if v->>'state'<>'blocked'
     or v#>>'{blockers,0,resolutionKind}'<>'needs_evidence' then
    raise exception 'CI Fundable gate should preserve needs_evidence blocker: %',v;
  end if;

  begin
    perform atlas.release_development_case_internal_v1(
      'd5e00000-0000-4000-8000-000000000230'::uuid,
      'ci_activity:washers:v3',
      array['playable','buildable']::text[],
      'blocked release must fail',
      'ci-release-blocked-v1',
      'CI Development validation authority',
      '{"validationFixture":true}'::jsonb
    );
    raise exception 'Blocked CI Development gate was released.';
  exception when sqlstate '23514' then
    null;
  end;

  v:=atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'construction_specification',
    'established',
    'institutional_decision',
    'ci_activity',
    'washers-construction-spec-v1',
    'CI accepts the fixture construction specification for this proof.',
    'ci-construction-established-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  if v->>'state'<>'recorded' then
    raise exception 'CI construction resolution was not recorded: %',v;
  end if;

  v_replay:=atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'construction_specification',
    'established',
    'institutional_decision',
    'ci_activity',
    'washers-construction-spec-v1',
    'CI accepts the fixture construction specification for this proof.',
    'ci-construction-established-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  if v_replay->>'state'<>'unchanged'
     or v_replay->>'resolutionEventId' is distinct from v->>'resolutionEventId' then
    raise exception 'Criterion Resolution idempotent replay failed: % / %',v,v_replay;
  end if;

  begin
    perform atlas.record_development_criterion_resolution_internal_v1(
      'd5e00000-0000-4000-8000-000000000230'::uuid,
      'construction_specification',
      'unresolved',
      'institutional_decision',
      'ci_activity',
      'washers-construction-spec-v1',
      'Contradictory replay must fail.',
      'ci-construction-established-v1',
      'CI Development validation authority',
      '{"validationFixture":true}'::jsonb
    );
    raise exception 'Criterion Resolution idempotency contradiction was accepted.';
  exception when sqlstate '23505' then
    null;
  end;

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,'buildable'
  );
  if v->>'state'<>'satisfied' then
    raise exception 'CI Buildable gate did not converge after construction resolution: %',v;
  end if;

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,'fundable'
  );
  if v->>'state'<>'blocked' then
    raise exception 'Unrelated CI Fundable gate should remain blocked: %',v;
  end if;

  v_release:=atlas.release_development_case_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'ci_activity:washers:v3',
    array['playable','buildable']::text[],
    'Playable and Buildable criteria have converged under the fixture Standard.',
    'ci-release-playable-buildable-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  if v_release->>'state'<>'released'
     or jsonb_array_length(v_release->'gateKeys')<>2 then
    raise exception 'CI Development Release failed: %',v_release;
  end if;

  v_replay:=atlas.release_development_case_internal_v1(
    'd5e00000-0000-4000-8000-000000000230'::uuid,
    'ci_activity:washers:v3',
    array['buildable','playable']::text[],
    'Playable and Buildable criteria have converged under the fixture Standard.',
    'ci-release-playable-buildable-v1',
    'CI Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  if v_replay->>'state'<>'unchanged'
     or v_replay->>'releaseId' is distinct from v_release->>'releaseId' then
    raise exception 'Development Release idempotent replay failed: % / %',v_release,v_replay;
  end if;

  -- -----------------------------------------------------------------------
  -- Elm Standard: inherited Operating Knowledge + unresolved quality
  -- -----------------------------------------------------------------------

  insert into atlas.development_standard_versions(
    id,organization_id,ledger_id,stable_key,version,title,purpose,
    eligible_subject_kinds,status,provenance,metadata
  ) values (
    'd5e00000-0000-4000-8000-000000000301'::uuid,
    'd5e00000-0000-4000-8000-000000000101'::uuid,
    'd5e00000-0000-4000-8000-000000000102'::uuid,
    'elm_procedure_development',
    1,
    'Elm Procedure Development Standard',
    'Validation proof for making an operating procedure delegable.',
    array['procedure_family']::text[],
    'draft',
    '{"source":"development_kernel_validation"}'::jsonb,
    '{"validationFixture":true}'::jsonb
  );

  insert into atlas.development_standard_criteria(
    id,standard_version_id,criterion_key,question,rationale
  ) values
  (
    'd5e00000-0000-4000-8000-000000000311'::uuid,
    'd5e00000-0000-4000-8000-000000000301'::uuid,
    'default_bunch_quantity',
    'Is the default bunch quantity governed?',
    'A worker needs deterministic output quantity.'
  ),
  (
    'd5e00000-0000-4000-8000-000000000312'::uuid,
    'd5e00000-0000-4000-8000-000000000301'::uuid,
    'quality_acceptance',
    'Can a worker determine whether the finished output meets the accepted quality standard?',
    'Delegation requires completion/quality semantics.'
  );

  insert into atlas.development_standard_gates(
    id,standard_version_id,gate_key,label,description
  ) values (
    'd5e00000-0000-4000-8000-000000000321'::uuid,
    'd5e00000-0000-4000-8000-000000000301'::uuid,
    'delegable',
    'Delegable',
    'Ordinary workers can execute the procedure without repeated owner reconstruction.'
  );

  insert into atlas.development_standard_gate_requirements(
    gate_id,criterion_id,accepted_resolution_kinds
  ) values
  (
    'd5e00000-0000-4000-8000-000000000321'::uuid,
    'd5e00000-0000-4000-8000-000000000311'::uuid,
    array['established','inherited']::text[]
  ),
  (
    'd5e00000-0000-4000-8000-000000000321'::uuid,
    'd5e00000-0000-4000-8000-000000000312'::uuid,
    array['established','inherited']::text[]
  );

  update atlas.development_standard_versions
  set status='established',
      established_by_label='Elm Development validation authority'
  where id='d5e00000-0000-4000-8000-000000000301'::uuid;

  insert into atlas.development_cases(
    id,organization_id,ledger_id,standard_version_id,case_key,
    target_domain,target_kind,target_ref,purpose,opened_by_label,metadata
  ) values (
    'd5e00000-0000-4000-8000-000000000330'::uuid,
    'd5e00000-0000-4000-8000-000000000101'::uuid,
    'd5e00000-0000-4000-8000-000000000102'::uuid,
    'd5e00000-0000-4000-8000-000000000301'::uuid,
    'elm-flower-preparation-development-proof',
    'flower_preparation',
    'procedure_family',
    'cut_flower_bunch_preparation',
    'Make bunch preparation sufficiently explicit and governed for ordinary worker execution.',
    'Elm Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  perform atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000330'::uuid,
    'default_bunch_quantity',
    'inherited',
    'company_operating_knowledge',
    'operating_knowledge',
    v_knowledge_id::text,
    'The established Elm bunch default governs this criterion.',
    'elm-default-bunch-inherited-v1',
    'Elm Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  perform atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000330'::uuid,
    'quality_acceptance',
    'unresolved',
    'development_assessment',
    'development',
    null,
    'The bunch-size rule alone does not establish full quality acceptance semantics.',
    'elm-quality-unresolved-v1',
    'Elm Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000330'::uuid,'delegable'
  );

  if v->>'state'<>'blocked'
     or (v->>'blockedCount')::integer<>1
     or v#>>'{blockers,0,criterionKey}'<>'quality_acceptance' then
    raise exception 'Elm Delegable gate did not preserve one unresolved criterion: %',v;
  end if;

  perform atlas.record_development_criterion_resolution_internal_v1(
    'd5e00000-0000-4000-8000-000000000330'::uuid,
    'quality_acceptance',
    'established',
    'institutional_decision',
    'flower_preparation',
    'elm-quality-acceptance-v1',
    'Elm accepts the fixture quality/completion rule for this proof.',
    'elm-quality-established-v1',
    'Elm Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  v:=atlas.development_gate_position_v1(
    'd5e00000-0000-4000-8000-000000000330'::uuid,'delegable'
  );

  if v->>'state'<>'satisfied' then
    raise exception 'Elm Delegable gate did not converge: %',v;
  end if;

  v_release:=atlas.release_development_case_internal_v1(
    'd5e00000-0000-4000-8000-000000000330'::uuid,
    'elm_flower_preparation:v2',
    array['delegable']::text[],
    'Inherited quantity plus established quality semantics satisfy the fixture gate.',
    'elm-release-delegable-v1',
    'Elm Development validation authority',
    '{"validationFixture":true}'::jsonb
  );

  if v_release->>'state'<>'released' then
    raise exception 'Elm Development Release failed: %',v_release;
  end if;

  -- -----------------------------------------------------------------------
  -- Cross-domain and immutability boundaries
  -- -----------------------------------------------------------------------

  begin
    insert into atlas.development_cases(
      organization_id,ledger_id,standard_version_id,case_key,
      target_domain,target_kind,target_ref,purpose,opened_by_label
    ) values (
      'd5e00000-0000-4000-8000-000000000001'::uuid,
      'd5e00000-0000-4000-8000-000000000002'::uuid,
      'd5e00000-0000-4000-8000-000000000301'::uuid,
      'cross-org-standard-must-fail',
      'ci_activity','procedure_family','bad','must fail','validation'
    );
    raise exception 'Cross-Organization Development Standard was accepted by a Case.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    perform atlas.record_development_criterion_resolution_internal_v1(
      'd5e00000-0000-4000-8000-000000000230'::uuid,
      'current_cost',
      'inherited',
      'company_operating_knowledge',
      'operating_knowledge',
      v_knowledge_id::text,
      'Cross-Organization inheritance must fail.',
      'ci-cross-org-knowledge-must-fail',
      'validation',
      '{"validationFixture":true}'::jsonb
    );
    raise exception 'Cross-Organization Operating Knowledge was inherited.';
  exception when sqlstate '23514' then
    null;
  end;

  begin
    update atlas.development_cases
    set target_ref='rewritten-target'
    where id='d5e00000-0000-4000-8000-000000000230'::uuid;
    raise exception 'Development Case target identity was mutated.';
  exception when sqlstate '55000' then
    null;
  end;

  begin
    update atlas.development_standard_criteria
    set question='mutated after establishment'
    where id='d5e00000-0000-4000-8000-000000000211'::uuid;
    raise exception 'Established Development Standard criterion was mutated.';
  exception when sqlstate '55000' then
    null;
  end;

  begin
    update atlas.development_criterion_resolution_events
    set statement='history rewrite'
    where development_case_id='d5e00000-0000-4000-8000-000000000230'::uuid
      and idempotency_key='ci-player-capacity-v1';
    raise exception 'Development Criterion Resolution history was mutated.';
  exception when sqlstate '55000' then
    null;
  end;

  begin
    update atlas.development_releases
    set release_basis='history rewrite'
    where development_case_id='d5e00000-0000-4000-8000-000000000330'::uuid
      and idempotency_key='elm-release-delegable-v1';
    raise exception 'Development Release history was mutated.';
  exception when sqlstate '55000' then
    null;
  end;

  if has_table_privilege('authenticated','atlas.development_cases','SELECT')
     or has_table_privilege('authenticated','atlas.development_cases','INSERT')
     or has_table_privilege('authenticated','atlas.development_criterion_resolution_events','SELECT')
     or has_table_privilege('authenticated','atlas.development_criterion_resolution_events','INSERT')
     or has_table_privilege('authenticated','atlas.development_releases','SELECT')
     or has_table_privilege('anon','atlas.development_cases','SELECT') then
    raise exception 'Development kernel tables leaked to browser roles.';
  end if;

  if has_table_privilege('service_role','atlas.development_criterion_resolution_events','INSERT')
     or has_table_privilege('service_role','atlas.development_releases','INSERT')
     or has_table_privilege('service_role','atlas.development_release_gates','INSERT') then
    raise exception 'Development history bypasses its service command membrane.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.record_development_criterion_resolution_internal_v1(uuid,text,text,text,text,text,text,text,text,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.release_development_case_internal_v1(uuid,text,text[],text,text,text,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.development_gate_position_v1(uuid,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'atlas.development_gate_position_v1(uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'Development kernel function privilege boundary is incorrect.';
  end if;
end;
$validation$;

rollback;
