do $$
declare
  v_case uuid;
  v_decision uuid;
  v_text_mode uuid;
  v_illustration_mode uuid;
  v_text_req uuid;
  v_illustration_req uuid;
  v_plan_req uuid;
begin
  select rc.id into strict v_case
  from wnph.recovery_cases rc
  where rc.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';

  select d.id into strict v_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case
    and d.decision_outcome='more_evidence_needed'
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id);

  select m.id into strict v_text_mode
  from wnph.recovery_case_modes m
  where m.recovery_case_id=v_case and m.recovery_mode='text'
    and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);

  select m.id into strict v_illustration_mode
  from wnph.recovery_case_modes m
  where m.recovery_case_id=v_case and m.recovery_mode='illustration'
    and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);

  insert into wnph.recovery_decision_requirements(
    recovery_decision_id,canonical_key,requirement_authority,requirement_scope,recovery_case_mode_id,question_text,completion_criterion
  ) values (
    v_decision,'text-source-basis-diagnostic','evidence','mode',v_text_mode,
    'What source-level intervention burden is required to produce a governed verified reading text from the identified Library of Congress surrogate?',
    'A bounded diagnostic compares LOC complete text against representative source page images across front matter, body text, and page transitions; records legibility and material transcription/OCR defects; and states whether the identified witness is sufficient as the transcription basis or another witness is required. This is diagnostic verification, not full source collation.'
  ) returning id into v_text_req;

  insert into wnph.recovery_decision_requirements(
    recovery_decision_id,canonical_key,requirement_authority,requirement_scope,recovery_case_mode_id,question_text,completion_criterion
  ) values (
    v_decision,'illustration-source-basis-diagnostic','evidence','mode',v_illustration_mode,
    'What source-level intervention burden is required to preserve or restore the historical illustration program from the identified Library of Congress surrogate?',
    'A bounded diagnostic inventories illustration-bearing pages and checks capture completeness, cropping, source resolution, color fidelity, damage or obscuration, and whether another witness is required. This diagnoses recovery feasibility and burden; it does not restore, redraw, or editorially alter any illustration.'
  ) returning id into v_illustration_req;

  insert into wnph.recovery_decision_requirements(
    recovery_decision_id,canonical_key,requirement_authority,requirement_scope,recovery_case_mode_id,question_text,completion_criterion
  ) values (
    v_decision,'intervention-scope-judgment','publishing_judgment','plan',null,
    'Given the evidenced condition of text and illustrations, which recovery modes should WNPH actually authorize for the recovered Expression?',
    'This is resolved only by a superseding Recovery Decision that explicitly binds the chosen recovery_case_mode rows through recovery_decision_plan_members. Evidence may constrain the choice, but additional searching cannot by itself decide text-only, illustration-only, or a combined text-plus-illustration plan.'
  ) returning id into v_plan_req;

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,recovery_condition_observation_id,basis_note)
  select v_text_req,'motivates',o.id,
    'Current text_integrity is unverified; this requirement narrows the needed evidence to transcription-basis quality and intervention burden.'
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_assessments a on a.id=o.assessment_id
  join wnph.recovery_condition_types ct on ct.id=o.condition_type_id
  where a.recovery_case_id=v_case and ct.canonical_key='text_integrity'
    and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,recovery_condition_observation_id,basis_note)
  select v_illustration_req,'motivates',o.id,
    'Current illustration_integrity is unverified; this requirement narrows the needed evidence to capture integrity and restoration burden.'
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_assessments a on a.id=o.assessment_id
  join wnph.recovery_condition_types ct on ct.id=o.condition_type_id
  where a.recovery_case_id=v_case and ct.canonical_key='illustration_integrity'
    and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,recovery_condition_observation_id,basis_note)
  select v_plan_req,'context',o.id,
    'Text and illustration condition constrain the publishing choice but do not make it.'
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_assessments a on a.id=o.assessment_id
  join wnph.recovery_condition_types ct on ct.id=o.condition_type_id
  where a.recovery_case_id=v_case and ct.canonical_key in ('text_integrity','illustration_integrity')
    and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);

  if (select count(*) from wnph.recovery_decision_requirement_bases where requirement_id=v_text_req)<>1 then
    raise exception 'WNPH Dewy reconciliation: expected exactly one text requirement basis';
  end if;
  if (select count(*) from wnph.recovery_decision_requirement_bases where requirement_id=v_illustration_req)<>1 then
    raise exception 'WNPH Dewy reconciliation: expected exactly one illustration requirement basis';
  end if;
  if (select count(*) from wnph.recovery_decision_requirement_bases where requirement_id=v_plan_req)<>2 then
    raise exception 'WNPH Dewy reconciliation: expected exactly two plan judgment context bases';
  end if;
end $$;