-- WNPH Dewy Dear text source-basis diagnostic v1
--
-- Bounded empirical step:
--   * records exact page-render and OCR derivative access surfaces for the already
--     identified LOC/IA digitized witness;
--   * supersedes the metadata-only Commons index source with the exact Commons
--     PDF file/page-render surface (same digitized witness, not a second witness);
--   * records representative front-matter, body-text, and page-transition
--     comparison findings;
--   * satisfies ONLY the evidence-authority text-source-basis diagnostic;
--   * leaves the illustration diagnostic and publishing judgment OPEN;
--   * leaves the Recovery Case in MORE_EVIDENCE_NEEDED.
--
-- This is diagnostic verification, not full collation, reconstruction, copy-editing,
-- illustration restoration, qualification, selection, or publishing authorization.

do $$
declare
  v_case_id uuid;
  v_decision_id uuid;
  v_decision_outcome text;
  v_case_state text;
  v_old_text_requirement_id uuid;
  v_new_text_requirement_id uuid;
  v_illustration_requirement_id uuid;
  v_judgment_requirement_id uuid;
  v_old_commons_source_id uuid;
  v_commons_page_source_id uuid;
  v_ia_ocr_source_id uuid;
begin
  select rc.id
    into v_case_id
  from wnph.recovery_cases rc
  where rc.canonical_key = 'wish-fairy-and-dewy-dear:recovery-evaluation-1';

  if v_case_id is null then
    raise exception 'WNPH Dewy text diagnostic: recovery case not found';
  end if;

  select rd.id, rd.decision_outcome
    into v_decision_id, v_decision_outcome
  from wnph.recovery_decisions rd
  where rd.recovery_case_id = v_case_id
    and not exists (
      select 1
      from wnph.recovery_decisions newer
      where newer.supersedes_decision_id = rd.id
    )
  order by rd.created_at desc
  limit 1;

  if v_decision_id is null or v_decision_outcome <> 'more_evidence_needed' then
    raise exception 'WNPH Dewy text diagnostic: current decision must remain more_evidence_needed';
  end if;

  select e.to_state
    into v_case_state
  from wnph.recovery_case_events e
  where e.recovery_case_id = v_case_id
    and not exists (
      select 1
      from wnph.recovery_case_events newer
      where newer.prior_event_id = e.id
    )
  order by e.created_at desc
  limit 1;

  if v_case_state is distinct from 'MORE_EVIDENCE_NEEDED' then
    raise exception 'WNPH Dewy text diagnostic: recovery case must remain MORE_EVIDENCE_NEEDED';
  end if;

  select r.id
    into v_old_text_requirement_id
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id = v_decision_id
    and r.canonical_key = 'text-source-basis-diagnostic'
    and r.requirement_authority = 'evidence'
    and r.requirement_scope = 'mode'
    and r.requirement_status = 'open'
    and not exists (
      select 1
      from wnph.recovery_decision_requirements newer
      where newer.supersedes_requirement_id = r.id
    );

  if v_old_text_requirement_id is null then
    raise exception 'WNPH Dewy text diagnostic: expected current open text requirement not found';
  end if;

  select r.id
    into v_illustration_requirement_id
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id = v_decision_id
    and r.canonical_key = 'illustration-source-basis-diagnostic'
    and r.requirement_authority = 'evidence'
    and r.requirement_status = 'open'
    and not exists (
      select 1
      from wnph.recovery_decision_requirements newer
      where newer.supersedes_requirement_id = r.id
    );

  if v_illustration_requirement_id is null then
    raise exception 'WNPH Dewy text diagnostic: illustration requirement must still be open';
  end if;

  select r.id
    into v_judgment_requirement_id
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id = v_decision_id
    and r.canonical_key = 'intervention-scope-judgment'
    and r.requirement_authority = 'publishing_judgment'
    and r.requirement_status = 'open'
    and not exists (
      select 1
      from wnph.recovery_decision_requirements newer
      where newer.supersedes_requirement_id = r.id
    );

  if v_judgment_requirement_id is null then
    raise exception 'WNPH Dewy text diagnostic: publishing judgment must still be open';
  end if;

  select es.id
    into v_old_commons_source_id
  from wnph.evidence_sources es
  where es.canonical_key = 'wikimedia-commons:ia:wishfairydewydea00colv:index';

  if v_old_commons_source_id is null then
    raise exception 'WNPH Dewy text diagnostic: prior Commons metadata-only access source not found';
  end if;

  select es.id
    into v_commons_page_source_id
  from wnph.evidence_sources es
  where es.canonical_key = 'wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders';

  if v_commons_page_source_id is null then
    insert into wnph.evidence_sources (
      canonical_key,
      source_type,
      title,
      repository_name,
      url,
      external_identifier,
      retrieved_at,
      provenance_note,
      metadata,
      supersedes_source_id
    ) values (
      'wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders',
      'modern_aggregator',
      'The Wish fairy and Dewy Dear (IA wishfairydewydea00colv).pdf — file and page renders',
      'Wikimedia Commons',
      'https://commons.wikimedia.org/wiki/File:The_Wish_fairy_and_Dewy_Dear_(IA_wishfairydewydea00colv).pdf',
      'IA wishfairydewydea00colv',
      now(),
      'Exact Commons PDF file page and rendered per-page previews for the same Internet Archive / Library of Congress digitized witness. This supersedes the earlier metadata-only Commons index access record. It is an access mirror and derivative rendering surface, not a second independent historical witness.',
      jsonb_build_object(
        'mirror_role', 'access_mirror_not_independent_witness',
        'diagnostic_status', 'representative_page_sample_inspected',
        'listed_page_count', 72,
        'listed_dimensions_px', jsonb_build_array(931, 1320),
        'listed_file_size_mb', 13.32,
        'internet_archive_identifier', 'wishfairydewydea00colv',
        'representative_page_inspection_completed', true,
        'sampled_pdf_pages', jsonb_build_array(1, 2, 7, 8, 9, 11, 12, 13, 14),
        'historical_witness_count_delta', 0
      ),
      v_old_commons_source_id
    )
    returning id into v_commons_page_source_id;
  end if;

  select es.id
    into v_ia_ocr_source_id
  from wnph.evidence_sources es
  where es.canonical_key = 'internet-archive:ia:wishfairydewydea00colv:djvu-text';

  if v_ia_ocr_source_id is null then
    insert into wnph.evidence_sources (
      canonical_key,
      source_type,
      title,
      repository_name,
      url,
      external_identifier,
      retrieved_at,
      provenance_note,
      metadata
    ) values (
      'internet-archive:ia:wishfairydewydea00colv:djvu-text',
      'modern_aggregator',
      'Full text of The Wish fairy and Dewy Dear — IA OCR derivative',
      'Internet Archive',
      'https://archive.org/stream/wishfairydewydea00colv/wishfairydewydea00colv_djvu.txt',
      'IA wishfairydewydea00colv',
      now(),
      'Machine-readable OCR derivative exposed under the exact Internet Archive identifier corresponding to the LOC digitized witness. This is an OCR access layer of that same surrogate, not a second historical witness and not a governed reading text.',
      jsonb_build_object(
        'derivative_role', 'ocr_text_of_same_loc_ia_surrogate',
        'internet_archive_identifier', 'wishfairydewydea00colv',
        'historical_witness_count_delta', 0,
        'publication_ready', false
      )
    )
    returning id into v_ia_ocr_source_id;
  end if;

  insert into wnph.recovery_decision_requirements (
    recovery_decision_id,
    canonical_key,
    requirement_authority,
    requirement_scope,
    recovery_case_mode_id,
    question_text,
    completion_criterion,
    requirement_status,
    supersedes_requirement_id
  )
  select
    r.recovery_decision_id,
    r.canonical_key,
    r.requirement_authority,
    r.requirement_scope,
    r.recovery_case_mode_id,
    r.question_text,
    r.completion_criterion,
    'satisfied',
    r.id
  from wnph.recovery_decision_requirements r
  where r.id = v_old_text_requirement_id
  returning id into v_new_text_requirement_id;

  insert into wnph.recovery_decision_requirement_bases (
    requirement_id,
    basis_role,
    evidence_source_id,
    basis_note
  ) values
  (
    v_new_text_requirement_id,
    'satisfies',
    v_commons_page_source_id,
    'Bounded page-image diagnostic completed against representative pages of the exact LOC-derived witness. Front matter is legible: the title page clearly reads ALICE ROSS COLVER and the contents page is readable. Consecutive body pages are also legible. At the printed page 7 -> 8 transition, the sentence continues visually from “King Lion” / “said. We’re nearly dead of thirst,” while OCR inserts printed page number 7 into the sentence stream. At the printed page 8 -> 10 transition, printed page 9 is a full-page color illustration; the page images preserve the sequence and text resumes clearly on printed page 10. These samples establish the identified witness itself as sufficient for governed transcription; a second witness is not required merely to obtain a readable transcription basis. This finding does not assess the full illustration program.'
  ),
  (
    v_new_text_requirement_id,
    'satisfies',
    v_ia_ocr_source_id,
    'Comparison of the IA OCR derivative with the inspected page images identifies material but bounded machine-text defects: the title-page author name ALICE ROSS COLVER is misread as ALICE ROSSTOLVER; line-break hyphenation is retained inside words; printed page numbers can be injected into sentence flow; and the intervening full-page illustration at printed page 9 produces stray numeric OCR debris before the body sentence resumes. The OCR therefore may serve only as an acceleration/reference layer. A governed verified reading text must be normalized and checked against page images; the raw OCR is not publication-ready.'
  );

  -- Verify the bounded state transition and its limits.
  if not exists (
    select 1
    from wnph.recovery_decision_requirements r
    where r.id = v_new_text_requirement_id
      and r.requirement_status = 'satisfied'
      and r.requirement_authority = 'evidence'
      and r.supersedes_requirement_id = v_old_text_requirement_id
      and not exists (
        select 1
        from wnph.recovery_decision_requirements newer
        where newer.supersedes_requirement_id = r.id
      )
  ) then
    raise exception 'WNPH Dewy text diagnostic: text requirement did not become the current satisfied requirement';
  end if;

  if not exists (
    select 1
    from wnph.recovery_decision_requirements r
    where r.id = v_illustration_requirement_id
      and r.requirement_status = 'open'
      and not exists (
        select 1
        from wnph.recovery_decision_requirements newer
        where newer.supersedes_requirement_id = r.id
      )
  ) then
    raise exception 'WNPH Dewy text diagnostic: illustration requirement changed unexpectedly';
  end if;

  if not exists (
    select 1
    from wnph.recovery_decision_requirements r
    where r.id = v_judgment_requirement_id
      and r.requirement_status = 'open'
      and r.requirement_authority = 'publishing_judgment'
      and not exists (
        select 1
        from wnph.recovery_decision_requirements newer
        where newer.supersedes_requirement_id = r.id
      )
  ) then
    raise exception 'WNPH Dewy text diagnostic: publishing judgment changed unexpectedly';
  end if;

  if exists (
    select 1
    from wnph.recovery_decision_requirement_bases b
    join wnph.recovery_decision_requirements r on r.id = b.requirement_id
    where r.recovery_decision_id = v_decision_id
      and r.requirement_authority = 'publishing_judgment'
      and b.basis_role = 'satisfies'
  ) then
    raise exception 'WNPH Dewy text diagnostic: evidence must not satisfy publishing judgment';
  end if;

  select e.to_state
    into v_case_state
  from wnph.recovery_case_events e
  where e.recovery_case_id = v_case_id
    and not exists (
      select 1
      from wnph.recovery_case_events newer
      where newer.prior_event_id = e.id
    )
  order by e.created_at desc
  limit 1;

  if v_case_state is distinct from 'MORE_EVIDENCE_NEEDED' then
    raise exception 'WNPH Dewy text diagnostic: case must remain MORE_EVIDENCE_NEEDED after text diagnostic';
  end if;
end
$$;
