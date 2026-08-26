do $$
declare
  v_case uuid;
  v_decision uuid;
  v_text_req uuid;
  v_illustration_req uuid;
  v_plan_req uuid;
  v_loc_source uuid;
  v_commons_source uuid;
  v_tail_state text;
begin
  select rc.id into strict v_case
  from wnph.recovery_cases rc
  where rc.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';

  select d.id into strict v_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case
    and d.decision_outcome='more_evidence_needed'
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id);

  select r.id into strict v_text_req
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id=v_decision
    and r.canonical_key='text-source-basis-diagnostic'
    and r.requirement_authority='evidence'
    and r.requirement_status='open'
    and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id);

  select r.id into strict v_illustration_req
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id=v_decision
    and r.canonical_key='illustration-source-basis-diagnostic'
    and r.requirement_authority='evidence'
    and r.requirement_status='open'
    and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id);

  select r.id into strict v_plan_req
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id=v_decision
    and r.canonical_key='intervention-scope-judgment'
    and r.requirement_authority='publishing_judgment'
    and r.requirement_status='open'
    and not exists(select 1 from wnph.recovery_decision_requirements n where n.supersedes_requirement_id=r.id);

  select es.id into strict v_loc_source
  from wnph.evidence_sources es
  where es.canonical_key='loc:item:22008427';

  select es.id into v_commons_source
  from wnph.evidence_sources es
  where es.canonical_key='wikimedia-commons:ia:wishfairydewydea00colv:index';

  if v_commons_source is null then
    insert into wnph.evidence_sources(
      canonical_key, source_type, title, repository_name, url, external_identifier,
      retrieved_at, rights_note, provenance_note, metadata
    ) values (
      'wikimedia-commons:ia:wishfairydewydea00colv:index',
      'modern_aggregator',
      'The Wish fairy and Dewy Dear (IA wishfairydewydea00colv).pdf',
      'Wikimedia Commons',
      'https://commons.wikimedia.org/wiki/Category:Illustrated_fairy_tale_books',
      'IA wishfairydewydea00colv',
      now(),
      'No rights conclusion is taken from this mirror index; rights remain governed by the existing Library of Congress and U.S. rights determination.',
      'Public mirror index corroborates a PDF under the exact Internet Archive identifier corresponding to the LOC digital-resource identifier. The index lists 72 pages at 931 x 1320 and 13.32 MB. This is access-mirror metadata, not a second independent historical witness, and no representative page-level visual diagnostic is claimed from this source.',
      jsonb_build_object(
        'listed_page_count',72,
        'listed_dimensions_px',jsonb_build_array(931,1320),
        'listed_file_size_mb',13.32,
        'internet_archive_identifier','wishfairydewydea00colv',
        'mirror_role','access_mirror_not_independent_witness',
        'diagnostic_status','metadata_only',
        'representative_page_inspection_completed',false
      )
    ) returning id into v_commons_source;
  end if;

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,evidence_source_id,basis_note)
  select v_text_req,'context',v_loc_source,
    'The LOC item/access page establishes that Complete Text, Complete PDF, and a 72-image sequence are exposed for the identified surrogate. This proves an inspectable source surface exists; it does not establish transcription fidelity, page-level legibility, OCR defect rate, or suitability as the governed transcription basis.'
  where not exists(
    select 1 from wnph.recovery_decision_requirement_bases b
    where b.requirement_id=v_text_req and b.evidence_source_id=v_loc_source and b.basis_role='context'
  );

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,evidence_source_id,basis_note)
  select v_text_req,'context',v_commons_source,
    'The Commons index corroborates a 72-page public mirror under the matching Internet Archive identifier. It is a convenience/access mirror of the same digitized witness, not independent textual evidence, and does not substitute for representative page-image versus text inspection.'
  where not exists(
    select 1 from wnph.recovery_decision_requirement_bases b
    where b.requirement_id=v_text_req and b.evidence_source_id=v_commons_source and b.basis_role='context'
  );

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,evidence_source_id,basis_note)
  select v_illustration_req,'context',v_loc_source,
    'The LOC item/access page establishes a 72-image sequence and downloadable page-image surfaces for the identified surrogate. This proves illustration-bearing source material is inspectable; it does not establish illustration completeness, cropping, resolution adequacy, color fidelity, damage state, or production suitability.'
  where not exists(
    select 1 from wnph.recovery_decision_requirement_bases b
    where b.requirement_id=v_illustration_req and b.evidence_source_id=v_loc_source and b.basis_role='context'
  );

  insert into wnph.recovery_decision_requirement_bases(requirement_id,basis_role,evidence_source_id,basis_note)
  select v_illustration_req,'context',v_commons_source,
    'The Commons index corroborates the same 72-page digitized witness at listed scan dimensions 931 x 1320. It is mirror metadata only and does not substitute for representative visual inspection of cropping, color, damage, obscuration, or restoration burden.'
  where not exists(
    select 1 from wnph.recovery_decision_requirement_bases b
    where b.requirement_id=v_illustration_req and b.evidence_source_id=v_commons_source and b.basis_role='context'
  );

  select e.to_state into strict v_tail_state
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);

  if v_tail_state <> 'MORE_EVIDENCE_NEEDED' then
    raise exception 'WNPH Dewy checkpoint: expected case to remain MORE_EVIDENCE_NEEDED, got %',v_tail_state;
  end if;

  if (select requirement_status from wnph.recovery_decision_requirements where id=v_text_req) <> 'open'
     or (select requirement_status from wnph.recovery_decision_requirements where id=v_illustration_req) <> 'open'
     or (select requirement_status from wnph.recovery_decision_requirements where id=v_plan_req) <> 'open' then
    raise exception 'WNPH Dewy checkpoint: all three decision requirements must remain open';
  end if;

  if exists(
    select 1 from wnph.recovery_case_events e
    where e.recovery_case_id=v_case and e.to_state in ('QUALIFIED','SELECTED_FOR_RECOVERY')
  ) then
    raise exception 'WNPH Dewy checkpoint: diagnostic access checkpoint may not qualify or select the case';
  end if;
end $$;