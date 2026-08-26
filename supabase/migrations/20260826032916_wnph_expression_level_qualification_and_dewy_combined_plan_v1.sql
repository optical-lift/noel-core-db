-- WNPH Expression-level qualification boundary + Dewy combined illustrated recovery judgment v1
--
-- Architectural correction:
--   QUALIFIED is an Expression/recovery-plan judgment. It must bind a governed scope
--   and at least one recovery mode, but it must not require a Manifestation output.
--   Concrete output selection remains downstream: SELECTED_FOR_RECOVERY already
--   requires an explicit preferred source and first-target manifestation.
--
-- Dewy bounded judgment:
--   * supersedes the current more_evidence_needed decision with qualify;
--   * binds exactly the text + illustration recovery modes as one combined plan;
--   * binds the existing restored_textual_and_illustrated_realization scope;
--   * does not bind web/EPUB/print output, does not select the Work, and does not begin
--     transcription, image cleanup, reconstruction, or production.

create or replace function wnph.validate_recovery_case_event()
returns trigger language plpgsql set search_path to 'pg_catalog' as $$
declare
  p wnph.recovery_case_events%rowtype;
  allowed boolean := false;
  gate_ok boolean := false;
  expected_outcome text;
begin
  if new.prior_event_id is null then
    if new.from_state is not null or new.to_state <> 'IDENTITY_ESTABLISHED' or new.event_kind <> 'state_transition' then raise exception 'WNPH Recovery custody: first event must establish inherited IDENTITY_ESTABLISHED state'; end if;
    select exists (select 1 from wnph.recovery_cases c join wnph.historical_works w on w.id=c.work_id where c.id=new.recovery_case_id and w.status='established' and exists (select 1 from wnph.work_identity_adjudications a where a.result_work_id=w.id and a.result in ('ESTABLISHES_WORK','SAME_WORK'))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: initial IDENTITY_ESTABLISHED requires an established Work with identity adjudication'; end if;
    return new;
  end if;
  select * into p from wnph.recovery_case_events where id=new.prior_event_id;
  if not found then raise exception 'WNPH Recovery custody: prior event % does not exist',new.prior_event_id; end if;
  if p.recovery_case_id<>new.recovery_case_id then raise exception 'WNPH Recovery custody: prior event belongs to a different Recovery Case'; end if;
  if new.from_state is distinct from p.to_state then raise exception 'WNPH Recovery custody: from_state % must equal prior to_state %',new.from_state,p.to_state; end if;
  if exists(select 1 from wnph.recovery_case_events e where e.prior_event_id=p.id) then raise exception 'WNPH Recovery custody: event history may not fork'; end if;

  allowed :=
    (new.from_state='IDENTITY_ESTABLISHED' and new.to_state='SOURCE_RESEARCH') or
    (new.from_state='SOURCE_RESEARCH' and new.to_state in ('SOURCE_SUFFICIENT','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_RESEARCH')) or
    (new.from_state='SOURCE_SUFFICIENT' and new.to_state='RIGHTS_RESEARCH') or
    (new.from_state='RIGHTS_RESEARCH' and new.to_state in ('RIGHTS_CLEARED','REJECTED_RIGHTS','DEFERRED_RIGHTS','DEFERRED_RESEARCH')) or
    (new.from_state='RIGHTS_CLEARED' and new.to_state='RECOVERY_AUDIT') or
    (new.from_state='RECOVERY_AUDIT' and new.to_state in ('CONDITION_ASSESSED','DEFERRED_RESEARCH')) or
    (new.from_state='CONDITION_ASSESSED' and new.to_state='DECISION_REVIEW') or
    (new.from_state='DECISION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED')) or
    (new.from_state='QUALIFIED' and new.to_state in ('SELECTED_FOR_RECOVERY','DEFERRED_CAPACITY','DEFERRED_LOW_VALUE')) or
    (new.from_state in ('SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') and new.to_state='REOPENED') or
    (new.from_state='REOPENED' and new.to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','RIGHTS_RESEARCH','RECOVERY_AUDIT','CONDITION_ASSESSED','DECISION_REVIEW','QUALIFIED'));
  if not allowed then raise exception 'WNPH Recovery custody: forbidden transition % -> %',new.from_state,new.to_state; end if;

  if new.to_state like 'REJECTED_%' and new.event_kind<>'reject' then raise exception 'WNPH Recovery custody: rejected states require event_kind=reject'; end if;
  if new.to_state in ('DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH') and new.event_kind<>'defer' then raise exception 'WNPH Recovery custody: deferred states require event_kind=defer'; end if;
  if new.to_state='REOPENED' and new.event_kind<>'reopen' then raise exception 'WNPH Recovery custody: REOPENED requires event_kind=reopen'; end if;
  if new.to_state='SELECTED_FOR_RECOVERY' and new.event_kind<>'selection' then raise exception 'WNPH Recovery custody: selection requires event_kind=selection'; end if;
  if new.to_state in ('QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') and new.from_state='DECISION_REVIEW' and new.event_kind<>'decision' then raise exception 'WNPH Recovery custody: Recovery Decision outcomes require event_kind=decision'; end if;
  if new.to_state not like 'REJECTED_%' and new.to_state not in ('DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','REOPENED','SELECTED_FOR_RECOVERY','QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') and new.event_kind<>'state_transition' then raise exception 'WNPH Recovery custody: ordinary progression requires event_kind=state_transition'; end if;

  if new.to_state='SOURCE_SUFFICIENT' then
    select exists (select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id) and exists(select 1 from wnph.source_sufficiency_members m where m.assessment_id=a.id and m.member_result='usable' and not exists(select 1 from wnph.source_sufficiency_members mn where mn.supersedes_member_id=m.id))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: SOURCE_SUFFICIENT requires a current sufficient assessment with a usable source member'; end if;
  end if;
  if new.to_state='RIGHTS_CLEARED' then
    select exists (select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id) and exists(select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_type='underlying_work' and c.component_status in ('public_domain','reuse_permitted','licensed')) and not exists(select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_status not in ('public_domain','reuse_permitted','licensed','not_applicable'))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: RIGHTS_CLEARED requires a current cleared determination with resolved components'; end if;
  end if;
  if new.to_state in ('CONDITION_ASSESSED','DECISION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (select 1 from wnph.recovery_condition_assessments a where a.recovery_case_id=new.recovery_case_id and a.assessment_status='bounded_complete' and not exists(select 1 from wnph.recovery_condition_assessments n where n.supersedes_assessment_id=a.id) and exists(select 1 from wnph.recovery_condition_observations o where o.assessment_id=a.id and not exists(select 1 from wnph.recovery_condition_observations onew where onew.supersedes_observation_id=o.id)) and not exists(select 1 from wnph.recovery_condition_observations o where o.assessment_id=a.id and o.epistemic_status='evidence' and not exists(select 1 from wnph.recovery_condition_observations onew where onew.supersedes_observation_id=o.id) and not exists(select 1 from wnph.evidence_links el where el.recovery_condition_observation_id=o.id and el.support_role in ('supports','contradicts','context') and not exists(select 1 from wnph.evidence_links eln where eln.supersedes_evidence_link_id=el.id)))) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: condition progression requires a current bounded-complete condition assessment with observations and evidence links for evidence-status observations'; end if;
  end if;

  if new.from_state='DECISION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_RECOVERY','DECLINED_RECOVERY','MORE_EVIDENCE_NEEDED') then
    expected_outcome := case new.to_state when 'QUALIFIED' then 'qualify' when 'DEFERRED_RECOVERY' then 'defer' when 'DECLINED_RECOVERY' then 'decline' when 'MORE_EVIDENCE_NEEDED' then 'more_evidence_needed' end;
    select exists(
      select 1 from wnph.recovery_decisions d
      where d.recovery_case_id=new.recovery_case_id and d.decision_outcome=expected_outcome
        and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
        and exists(select 1 from wnph.recovery_decision_bases b where b.recovery_decision_id=d.id)
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: decision outcome requires a current Recovery Decision with matching outcome and relational basis'; end if;
  end if;

  if new.to_state='QUALIFIED' then
    select exists(
      select 1 from wnph.recovery_decisions d
      where d.recovery_case_id=new.recovery_case_id and d.decision_outcome='qualify'
        and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
        and exists(select 1 from wnph.recovery_decision_plan_members pm where pm.recovery_decision_id=d.id and pm.member_role='scope')
        and exists(select 1 from wnph.recovery_decision_plan_members pm where pm.recovery_decision_id=d.id and pm.member_role='mode')
    ) and exists(select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id))
      and exists(select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id)) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: QUALIFIED requires a current qualifying Recovery Decision bound to scope and mode, source sufficiency and cleared rights; Manifestation output remains a downstream selection decision'; end if;
  end if;

  if new.to_state='SELECTED_FOR_RECOVERY' then
    select new.selection_authorized and exists(select 1 from wnph.recovery_case_targets t where t.recovery_case_id=new.recovery_case_id and t.target_role='preferred_source' and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id)) and exists(select 1 from wnph.recovery_case_outputs o where o.recovery_case_id=new.recovery_case_id and o.plan_role='first_target' and not exists(select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id)) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: selection requires explicit authorization, a preferred source, and a first target manifestation'; end if;
  end if;
  return new;
end $$;

comment on function wnph.validate_recovery_case_event() is
  'Recovery state transition guard. QUALIFIED is Expression/recovery-plan level and therefore requires scope + recovery mode(s), not a Manifestation output. SELECTED_FOR_RECOVERY remains the boundary that requires explicit authorization, preferred source, and first-target Manifestation.';

do $$
declare
  v_case uuid;
  v_prior_event uuid;
  v_reopened_event uuid;
  v_review_event uuid;
  v_old_decision uuid;
  v_new_decision uuid;
  v_scope uuid;
  v_text_mode uuid;
  v_illustration_mode uuid;
  v_source_assessment uuid;
  v_rights uuid;
  v_text_source uuid;
  v_illustration_source uuid;
  v_candidate_target uuid;
begin
  select c.id into v_case
  from wnph.recovery_cases c
  join wnph.historical_works w on w.id=c.work_id
  where c.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1'
    and w.canonical_key='wish-fairy-and-dewy-dear';
  if v_case is null then raise exception 'WNPH Dewy combined plan: Recovery Case not found'; end if;

  select e.id into v_prior_event
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
    and e.to_state='MORE_EVIDENCE_NEEDED';
  if v_prior_event is null then raise exception 'WNPH Dewy combined plan: current case state must be MORE_EVIDENCE_NEEDED'; end if;

  select d.id into v_old_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case
    and d.decision_outcome='more_evidence_needed'
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  order by d.created_at desc limit 1;
  if v_old_decision is null then raise exception 'WNPH Dewy combined plan: current more_evidence_needed decision not found'; end if;

  if exists(
    select 1 from wnph.recovery_decision_requirements r
    where r.recovery_decision_id=v_old_decision
      and r.requirement_authority='evidence'
      and r.requirement_status='open'
      and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id)
  ) then
    raise exception 'WNPH Dewy combined plan: evidence requirements must be satisfied before qualification';
  end if;

  if not exists(
    select 1 from wnph.recovery_decision_requirements r
    where r.recovery_decision_id=v_old_decision
      and r.canonical_key='intervention-scope-judgment'
      and r.requirement_authority='publishing_judgment'
      and r.requirement_status='open'
      and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id)
  ) then
    raise exception 'WNPH Dewy combined plan: expected open publishing-judgment requirement not found';
  end if;

  select b.id into v_scope
  from wnph.recovery_case_briefs b
  where b.recovery_case_id=v_case
    and b.proposed_expression_type='restored_textual_and_illustrated_realization'
    and not exists(select 1 from wnph.recovery_case_briefs n where n.supersedes_brief_id=b.id)
  order by b.created_at desc limit 1;
  if v_scope is null then raise exception 'WNPH Dewy combined plan: restored textual/illustrated scope not found'; end if;

  select m.id into v_text_mode
  from wnph.recovery_case_modes m
  where m.recovery_case_id=v_case and m.recovery_mode='text'
    and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
  order by m.created_at desc limit 1;
  select m.id into v_illustration_mode
  from wnph.recovery_case_modes m
  where m.recovery_case_id=v_case and m.recovery_mode='illustration'
    and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
  order by m.created_at desc limit 1;
  if v_text_mode is null or v_illustration_mode is null then raise exception 'WNPH Dewy combined plan: text and illustration modes must both exist'; end if;

  select a.id into v_source_assessment
  from wnph.source_sufficiency_assessments a
  where a.recovery_case_id=v_case and a.result='sufficient'
    and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id)
  order by a.created_at desc limit 1;
  if v_source_assessment is null then raise exception 'WNPH Dewy combined plan: current sufficient source assessment not found'; end if;

  select d.id into v_rights
  from wnph.rights_determinations d
  where d.recovery_case_id=v_case and d.overall_status='cleared'
    and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id)
  order by d.created_at desc limit 1;
  if v_rights is null then raise exception 'WNPH Dewy combined plan: current cleared rights determination not found'; end if;

  select es.id into v_text_source
  from wnph.evidence_sources es
  where es.canonical_key='internet-archive:ia:wishfairydewydea00colv:djvu-text';
  select es.id into v_illustration_source
  from wnph.evidence_sources es
  where es.canonical_key='wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic';
  if v_text_source is null or v_illustration_source is null then raise exception 'WNPH Dewy combined plan: diagnostic evidence sources not found'; end if;

  select t.id into v_candidate_target
  from wnph.recovery_case_targets t
  where t.recovery_case_id=v_case and t.target_role='candidate'
    and t.expression_id is not null
    and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id)
  order by t.created_at desc limit 1;
  if v_candidate_target is null then raise exception 'WNPH Dewy combined plan: candidate Expression target not found'; end if;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,selection_authorized
  ) values(
    v_case,v_prior_event,'MORE_EVIDENCE_NEEDED','REOPENED','reopen',
    'Both evidence-authority source-basis diagnostics are now satisfied. Reopen only to return the case to governed publishing judgment; do not reopen source, rights, or market-gap research.',false
  ) returning id into v_reopened_event;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,selection_authorized
  ) values(
    v_case,v_reopened_event,'REOPENED','DECISION_REVIEW','state_transition',
    'Return to Decision Review because the remaining question is publishing scope. Evidence is sufficient to choose among the already-proposed recovery modes.',false
  ) returning id into v_review_event;

  insert into wnph.recovery_decisions(
    recovery_case_id,decision_outcome,decision_scope,decision_summary,supersedes_decision_id
  ) values(
    v_case,
    'qualify',
    'Qualify a governed recovered Expression that combines verified text recovery with preservation/recovery of the complete evidenced interior illustration program. This judgment is Expression-level and does not yet choose a publication Manifestation.',
    'WNPH chooses the combined illustrated work: recover the text and the seven evidenced interior color plates together as one governed textual-and-illustrated Expression. The identified LOC/IA witness is sufficient as the recovery basis. OCR may accelerate transcription but is not publication-ready; text must be verified against page images. Illustration recovery may preserve surviving color relationships and perform non-inventive cleanup, but exact historical colorimetry is not claimed. Cover/endpaper design and concrete web, EPUB, print, or other Manifestation choices remain outside this qualification judgment.',
    v_old_decision
  ) returning id into v_new_decision;

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note
  ) values(
    v_new_decision,'supports',v_source_assessment,
    'The current identified source set is sufficient to support a governed recovery without requiring another historical witness.'
  );

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,rights_determination_id,basis_note
  ) values(
    v_new_decision,'supports',v_rights,
    'Current U.S. rights are cleared for the underlying recovery decision.'
  );

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,evidence_source_id,basis_note
  ) values(
    v_new_decision,'limits',v_text_source,
    'The OCR derivative is not a governed reading text. It may accelerate recovery, but the qualified text mode requires verification against the historical page images and correction of OCR/page-transition artifacts.'
  );

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,evidence_source_id,basis_note
  ) values(
    v_new_decision,'supports',v_illustration_source,
    'The complete evidenced interior color-plate program is recoverable from the identified witness without material crop or loss. Exact calibrated historical color is not claimed.'
  );

  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_brief_id)
  values(v_new_decision,'scope',v_scope);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_mode_id)
  values(v_new_decision,'mode',v_text_mode);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_mode_id)
  values(v_new_decision,'mode',v_illustration_mode);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_target_id)
  values(v_new_decision,'source_target',v_candidate_target);

  if exists(
    select 1 from wnph.recovery_decision_plan_members pm
    where pm.recovery_decision_id=v_new_decision and pm.member_role='output'
  ) then
    raise exception 'WNPH Dewy combined plan: qualification must not smuggle in a Manifestation output';
  end if;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,selection_authorized
  ) values(
    v_case,v_review_event,'DECISION_REVIEW','QUALIFIED','decision',
    'Publishing judgment resolved: WNPH qualifies the combined text-plus-illustration recovered Expression. This is not selection for production and does not authorize a first target Manifestation.',false
  );

  if not exists(
    select 1 from wnph.recovery_decisions d
    where d.id=v_new_decision and d.decision_outcome='qualify'
      and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  ) then raise exception 'WNPH Dewy combined plan: qualifying decision is not current'; end if;

  if (select count(*) from wnph.recovery_decision_plan_members pm where pm.recovery_decision_id=v_new_decision and pm.member_role='mode') <> 2 then
    raise exception 'WNPH Dewy combined plan: qualifying plan must contain exactly two recovery modes';
  end if;
  if not exists(select 1 from wnph.recovery_decision_plan_members pm join wnph.recovery_case_modes m on m.id=pm.recovery_case_mode_id where pm.recovery_decision_id=v_new_decision and pm.member_role='mode' and m.recovery_mode='text')
     or not exists(select 1 from wnph.recovery_decision_plan_members pm join wnph.recovery_case_modes m on m.id=pm.recovery_case_mode_id where pm.recovery_decision_id=v_new_decision and pm.member_role='mode' and m.recovery_mode='illustration') then
    raise exception 'WNPH Dewy combined plan: qualifying plan must bind text and illustration';
  end if;
  if exists(select 1 from wnph.recovery_decision_plan_members pm join wnph.recovery_case_modes m on m.id=pm.recovery_case_mode_id where pm.recovery_decision_id=v_new_decision and pm.member_role='mode' and m.recovery_mode not in ('text','illustration')) then
    raise exception 'WNPH Dewy combined plan: qualification may not bind unchosen recovery modes';
  end if;
  if exists(select 1 from wnph.recovery_decision_plan_members pm where pm.recovery_decision_id=v_new_decision and pm.member_role='output') then
    raise exception 'WNPH Dewy combined plan: no Manifestation output may be bound at qualification';
  end if;
  if (select e.to_state from wnph.recovery_case_events e where e.recovery_case_id=v_case and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id) order by e.created_at desc limit 1) is distinct from 'QUALIFIED' then
    raise exception 'WNPH Dewy combined plan: case did not reach QUALIFIED';
  end if;
  if exists(select 1 from wnph.recovery_case_events e where e.recovery_case_id=v_case and e.to_state='SELECTED_FOR_RECOVERY' and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)) then
    raise exception 'WNPH Dewy combined plan: this step must not select the Work for recovery';
  end if;
end $$;