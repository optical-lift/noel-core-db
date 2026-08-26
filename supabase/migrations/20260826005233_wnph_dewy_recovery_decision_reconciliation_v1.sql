do $$
declare
  v_case uuid;
  v_prior uuid;
  v_review uuid;
  v_decision uuid;
  v_obs uuid;
  v_source_assessment uuid;
  v_rights uuid;
begin
  select c.id into v_case
  from wnph.recovery_cases c
  join wnph.historical_works w on w.id=c.work_id
  where c.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1'
    and w.canonical_key='wish-fairy-and-dewy-dear';
  if v_case is null then raise exception 'WNPH Dewy reconciliation: Recovery Case not found'; end if;

  select e.id into v_prior
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,selection_authorized)
  values(v_case,v_prior,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition','Move from factual Recovery Condition diagnosis into a separate WNPH publishing judgment. This does not qualify or select the Work.',false)
  returning id into v_review;

  insert into wnph.recovery_decisions(recovery_case_id,decision_outcome,decision_scope,decision_summary)
  values(
    v_case,
    'more_evidence_needed',
    'Decide whether WNPH should create a governed recovered Expression from the identified c.1922 textual/illustrated realization; do not require proof that all alternative modern recoveries are absent.',
    'The Work has an identified usable source and cleared U.S. rights, so recovery is possible. The bounded condition record does not yet establish which content-level intervention WNPH should commit to: verified reading text, illustration restoration, or a combined recovered Expression. Request only evidence that materially distinguishes those intervention choices; do not reopen an exhaustive market-gap search.'
  ) returning id into v_decision;

  select a.id into v_source_assessment
  from wnph.source_sufficiency_assessments a
  where a.recovery_case_id=v_case and a.result='sufficient'
    and not exists(select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id)
  order by a.created_at desc limit 1;
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note)
  values(v_decision,'supports',v_source_assessment,'Recovery is technically possible from the current identified source set.');

  select d.id into v_rights
  from wnph.rights_determinations d
  where d.recovery_case_id=v_case and d.overall_status='cleared'
    and not exists(select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id)
  order by d.created_at desc limit 1;
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,rights_determination_id,basis_note)
  values(v_decision,'supports',v_rights,'Current U.S. rights do not block a recovery decision.');

  for v_obs in
    select o.id
    from wnph.recovery_condition_observations o
    join wnph.recovery_condition_assessments a on a.id=o.assessment_id
    join wnph.recovery_condition_types ct on ct.id=o.condition_type_id
    where a.recovery_case_id=v_case
      and ct.canonical_key in ('digital_facsimile_survival','text_integrity','illustration_integrity','modern_reading_edition')
      and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id)
  loop
    insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note)
    select v_decision,
      case when ct.canonical_key='digital_facsimile_survival' then 'supports' else 'limits' end,
      o.id,
      case ct.canonical_key
        when 'digital_facsimile_survival' then 'A surviving digital facsimile means WNPH is not deciding from loss alone.'
        when 'text_integrity' then 'Text integrity remains unverified; this matters to whether a governed reading-text intervention is warranted.'
        when 'illustration_integrity' then 'Illustration integrity remains unverified; this matters to whether illustration restoration belongs in the recovered Expression.'
        else 'Modern reading-edition condition is unverified, but this is context rather than a requirement to prove literal absence.' end
    from wnph.recovery_condition_observations o
    join wnph.recovery_condition_types ct on ct.id=o.condition_type_id
    where o.id=v_obs;
  end loop;

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,selection_authorized)
  values(v_case,v_review,'DECISION_REVIEW','MORE_EVIDENCE_NEEDED','decision','The governed decision is neither qualification nor rejection. WNPH needs only bounded evidence that distinguishes the intervention it would actually undertake; unknown market conditions are not treated as gaps.',false);
end $$;