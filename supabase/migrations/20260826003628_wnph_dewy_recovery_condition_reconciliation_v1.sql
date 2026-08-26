do $$
declare
  v_case uuid;
  v_work uuid;
  v_item uuid;
  v_surrogate uuid;
  v_source uuid;
  v_assessment uuid;
  v_obs uuid;
  v_prior_event uuid;
begin
  select rc.id, rc.work_id into v_case, v_work from wnph.recovery_cases rc where rc.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';
  select i.id into v_item from wnph.items i where i.canonical_key='wish-fairy-dewy-dear:loc-item';
  select s.id into v_surrogate from wnph.surrogates s where s.canonical_key='wish-fairy-dewy-dear:loc-digital';
  select es.id into v_source from wnph.evidence_sources es where es.canonical_key='loc:item:22008427' and not exists (select 1 from wnph.evidence_sources n where n.supersedes_source_id=es.id);

  insert into wnph.recovery_condition_assessments(recovery_case_id,assessment_status,scope_note,confidence)
  values (v_case,'bounded_complete','Bounded diagnosis from the currently established WNPH graph and the Library of Congress witness/Surrogate. This assessment records what is known, limited, or unverified without claiming an exhaustive search of all modern editions, platforms, libraries, or audio channels.','medium')
  returning id into v_assessment;

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,surrogate_id,observation_text,confidence)
  select v_assessment,id,'present','evidence',v_surrogate,'An identified Library of Congress digital facsimile/PDF of the c.1922 manifestation survives and is accessible.','high'
  from wnph.recovery_condition_types where canonical_key='digital_facsimile_survival'
  returning id into v_obs;
  insert into wnph.evidence_links(source_id,support_role,recovery_condition_observation_id,confidence,note)
  values (v_source,'supports',v_obs,'high','LOC item 22008427 directly supports the observed survival of the digital facsimile.');

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,item_id,observation_text,confidence)
  select v_assessment,id,'present','evidence',v_item,'A specifically identified surviving Library of Congress Item is already represented in the WNPH bibliographic graph.','high'
  from wnph.recovery_condition_types where canonical_key='identified_surviving_witness'
  returning id into v_obs;
  insert into wnph.evidence_links(source_id,support_role,recovery_condition_observation_id,confidence,note)
  values (v_source,'supports',v_obs,'high','LOC item 22008427 directly supports the identified surviving witness.');

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'Complete searchable text is exposed by LOC, but its transcription/reconstruction quality has not yet been verified as a governed reading text.','medium'
  from wnph.recovery_condition_types where canonical_key='text_integrity';

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'Historical illustrations are present in the digitized witness, but restoration quality, completeness, and suitability for a recovered edition have not yet been adjudicated.','medium'
  from wnph.recovery_condition_types where canonical_key='illustration_integrity';

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'The bounded evidence set does not yet establish the condition or adequacy of any modern reading edition.','unknown'
  from wnph.recovery_condition_types where canonical_key='modern_reading_edition';

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'The bounded evidence set does not yet establish modern reflowable ebook availability or adequacy.','unknown'
  from wnph.recovery_condition_types where canonical_key='reflowable_ebook_availability';

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'Modern accessibility condition has not yet been assessed.','unknown'
  from wnph.recovery_condition_types where canonical_key='accessibility';

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'Audio availability and adequacy have not yet been assessed.','unknown'
  from wnph.recovery_condition_types where canonical_key='audio_availability';

  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  select v_assessment,id,'unverified','bounded_unknown',v_work,'Modern library lending/distribution condition has not yet been assessed beyond the known Library of Congress access point.','unknown'
  from wnph.recovery_condition_types where canonical_key='library_access';

  select e.id into v_prior_event
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case and not exists (select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
  limit 1;

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (v_case,v_prior_event,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition','Recovery Gap is retired as an authoritative concept. A bounded Recovery Condition diagnosis now records the Work''s mixed present, limited, and unverified conditions without requiring proof of literal absence or a meaningful gap.','WNPH recovery condition reconciliation v1');
end
$$;