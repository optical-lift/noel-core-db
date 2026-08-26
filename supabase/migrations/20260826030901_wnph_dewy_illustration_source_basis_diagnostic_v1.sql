-- WNPH Dewy Dear illustration source-basis diagnostic v1
--
-- Bounded empirical step:
--   * inventories the interior color-plate program preserved in the already identified
--     LOC / Internet Archive witness through its exact Wikimedia Commons page renders;
--   * records capture completeness, cropping, visible damage/obscuration, color limits,
--     and source-resolution availability;
--   * satisfies ONLY the evidence-authority illustration-source-basis diagnostic;
--   * leaves the text diagnostic satisfied, publishing judgment open, the current
--     Recovery Decision at more_evidence_needed, and the Recovery Case at
--     MORE_EVIDENCE_NEEDED.
--
-- This does not restore, redraw, recolor, select, qualify, or authorize publication.

do $$
declare
  v_case_id uuid;
  v_decision_id uuid;
  v_decision_outcome text;
  v_case_state text;
  v_old_illustration_requirement_id uuid;
  v_new_illustration_requirement_id uuid;
  v_text_requirement_id uuid;
  v_judgment_requirement_id uuid;
  v_old_commons_page_source_id uuid;
  v_commons_diagnostic_source_id uuid;
  v_ia_image_source_id uuid;
begin
  select rc.id
    into v_case_id
  from wnph.recovery_cases rc
  where rc.canonical_key = 'wish-fairy-and-dewy-dear:recovery-evaluation-1';

  if v_case_id is null then
    raise exception 'WNPH Dewy illustration diagnostic: recovery case not found';
  end if;

  select rd.id, rd.decision_outcome
    into v_decision_id, v_decision_outcome
  from wnph.recovery_decisions rd
  where rd.recovery_case_id = v_case_id
    and not exists (
      select 1 from wnph.recovery_decisions newer
      where newer.supersedes_decision_id = rd.id
    )
  order by rd.created_at desc
  limit 1;

  if v_decision_id is null or v_decision_outcome <> 'more_evidence_needed' then
    raise exception 'WNPH Dewy illustration diagnostic: current decision must remain more_evidence_needed';
  end if;

  select e.to_state
    into v_case_state
  from wnph.recovery_case_events e
  where e.recovery_case_id = v_case_id
    and not exists (
      select 1 from wnph.recovery_case_events newer
      where newer.prior_event_id = e.id
    )
  order by e.created_at desc
  limit 1;

  if v_case_state is distinct from 'MORE_EVIDENCE_NEEDED' then
    raise exception 'WNPH Dewy illustration diagnostic: case must remain MORE_EVIDENCE_NEEDED';
  end if;

  select r.id
    into v_old_illustration_requirement_id
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id = v_decision_id
    and r.canonical_key = 'illustration-source-basis-diagnostic'
    and r.requirement_authority = 'evidence'
    and r.requirement_scope = 'mode'
    and r.requirement_status = 'open'
    and not exists (
      select 1 from wnph.recovery_decision_requirements newer
      where newer.supersedes_requirement_id = r.id
    );

  if v_old_illustration_requirement_id is null then
    raise exception 'WNPH Dewy illustration diagnostic: expected current open illustration requirement not found';
  end if;

  select r.id
    into v_text_requirement_id
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id = v_decision_id
    and r.canonical_key = 'text-source-basis-diagnostic'
    and r.requirement_authority = 'evidence'
    and r.requirement_status = 'satisfied'
    and not exists (
      select 1 from wnph.recovery_decision_requirements newer
      where newer.supersedes_requirement_id = r.id
    );

  if v_text_requirement_id is null then
    raise exception 'WNPH Dewy illustration diagnostic: text requirement must remain satisfied';
  end if;

  select r.id
    into v_judgment_requirement_id
  from wnph.recovery_decision_requirements r
  where r.recovery_decision_id = v_decision_id
    and r.canonical_key = 'intervention-scope-judgment'
    and r.requirement_authority = 'publishing_judgment'
    and r.requirement_status = 'open'
    and not exists (
      select 1 from wnph.recovery_decision_requirements newer
      where newer.supersedes_requirement_id = r.id
    );

  if v_judgment_requirement_id is null then
    raise exception 'WNPH Dewy illustration diagnostic: publishing judgment must still be open';
  end if;

  select es.id
    into v_old_commons_page_source_id
  from wnph.evidence_sources es
  where es.canonical_key = 'wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders';

  if v_old_commons_page_source_id is null then
    raise exception 'WNPH Dewy illustration diagnostic: prior Commons page-render source not found';
  end if;

  select es.id
    into v_commons_diagnostic_source_id
  from wnph.evidence_sources es
  where es.canonical_key = 'wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic';

  if v_commons_diagnostic_source_id is null then
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
      'wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic',
      'modern_aggregator',
      'The Wish fairy and Dewy Dear — bounded interior color-plate diagnostic',
      'Wikimedia Commons',
      'https://commons.wikimedia.org/wiki/File:The_Wish_fairy_and_Dewy_Dear_(IA_wishfairydewydea00colv).pdf',
      'IA wishfairydewydea00colv',
      now(),
      'Expanded page-render evidence for the same LOC-derived Internet Archive witness already under custody. This record captures the bounded interior color-plate diagnostic and supersedes the representative-sample access record only as an evidence description; it does not create a second historical witness.',
      jsonb_build_object(
        'mirror_role', 'access_mirror_not_independent_witness',
        'diagnostic_status', 'interior_color_plate_source_basis_completed',
        'internet_archive_identifier', 'wishfairydewydea00colv',
        'historical_witness_count_delta', 0,
        'commons_pdf_page_count', 72,
        'commons_pdf_dimensions_px', jsonb_build_array(931, 1320),
        'interior_color_plate_count', 7,
        'interior_color_plate_pdf_pages', jsonb_build_array(6, 13, 23, 33, 41, 51, 59),
        'interior_color_plate_printed_positions', jsonb_build_array('frontispiece', '9', '19', '29', '37', '47', '55'),
        'full_artwork_boundary_observed_on_all_plate_pages', true,
        'surrounding_margin_observed_on_all_plate_pages', true,
        'material_crop_or_missing_image_area_observed', false,
        'material_damage_or_obscuration_observed', false,
        'ordinary_age_or_scan_cast_observed', true,
        'distinct_color_relationships_preserved', true,
        'color_calibration_target_observed', false,
        'absolute_historical_colorimetry_verified', false,
        'manifestation_cover_endpaper_program_in_scope', false,
        'second_historical_witness_required_for_recovery_basis', false,
        'second_witness_conditionally_useful_for_color_critical_facsimile', true
      ),
      v_old_commons_page_source_id
    )
    returning id into v_commons_diagnostic_source_id;
  end if;

  select es.id
    into v_ia_image_source_id
  from wnph.evidence_sources es
  where es.canonical_key = 'internet-archive:ia:wishfairydewydea00colv:image-derivative-access';

  if v_ia_image_source_id is null then
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
      'internet-archive:ia:wishfairydewydea00colv:image-derivative-access',
      'modern_aggregator',
      'The Wish fairy and Dewy Dear — IA image derivative access surface',
      'Internet Archive',
      'https://archive.org/details/wishfairydewydea00colv',
      'IA wishfairydewydea00colv',
      now(),
      'Internet Archive item metadata and download surface for the same LOC-derived digitized witness. It records a 300 PPI scan and exposes original and processed single-page JP2 derivatives. This is source-resolution/access evidence, not an additional historical witness and not a claim that the processed Commons PDF itself is the final production master.',
      jsonb_build_object(
        'derivative_role', 'image_access_of_same_loc_surrogate',
        'internet_archive_identifier', 'wishfairydewydea00colv',
        'historical_witness_count_delta', 0,
        'scan_ppi_reported', 300,
        'single_page_original_jp2_tar_available', true,
        'single_page_processed_jp2_zip_available', true,
        'original_jp2_tar_listed_size_mb', 82.5,
        'processed_jp2_zip_listed_size_mb', 15.6,
        'production_asset_selection_completed', false
      )
    )
    returning id into v_ia_image_source_id;
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
  where r.id = v_old_illustration_requirement_id
  returning id into v_new_illustration_requirement_id;

  insert into wnph.recovery_decision_requirement_bases (
    requirement_id,
    basis_role,
    evidence_source_id,
    basis_note
  ) values
  (
    v_new_illustration_requirement_id,
    'satisfies',
    v_commons_diagnostic_source_id,
    'Bounded visual diagnostic of the interior illustration program completed on the exact Commons page renders of IA/LOC witness wishfairydewydea00colv. The recoverable interior color-plate sequence is frontispiece plus printed pages 9, 19, 29, 37, 47, and 55 (Commons PDF pages 6, 13, 23, 33, 41, 51, and 59). Across the plate sequence, the complete rectangular artwork boundary and surrounding page margins are present; no material crop, missing illustrated area, tear, or obscuration was observed. Ordinary age/scan cast is present. Distinct colors and tonal relationships survive, but no calibration target was observed, so exact historical colorimetry is not claimed. The identified witness is sufficient as the illustration recovery basis; another witness is not required unless a later publishing judgment demands color-critical facsimile calibration beyond what this uncalibrated scan can establish. Cover/endpaper design is manifestation-bound and is not adjudicated here as part of the recovered Expression interior plate program.'
  ),
  (
    v_new_illustration_requirement_id,
    'satisfies',
    v_ia_image_source_id,
    'Source-resolution access is adequate to proceed beyond diagnostic work if illustration recovery is later authorized: Internet Archive reports the same witness was scanned at 300 PPI and exposes both original single-page JP2 and processed single-page JP2 derivative bundles. The 931 x 1320 Commons PDF render therefore need not be treated as the only available image asset. Final production-master selection, tonal cleanup, color policy, and print-size suitability remain downstream production/publishing decisions; this evidence only establishes that the source basis is not blocked by absence of higher-resolution derivative access.'
  );

  if not exists (
    select 1
    from wnph.recovery_decision_requirements r
    where r.id = v_new_illustration_requirement_id
      and r.requirement_status = 'satisfied'
      and r.requirement_authority = 'evidence'
      and r.supersedes_requirement_id = v_old_illustration_requirement_id
      and not exists (
        select 1 from wnph.recovery_decision_requirements newer
        where newer.supersedes_requirement_id = r.id
      )
  ) then
    raise exception 'WNPH Dewy illustration diagnostic: illustration requirement did not become current satisfied requirement';
  end if;

  if not exists (
    select 1
    from wnph.recovery_decision_requirements r
    where r.id = v_text_requirement_id
      and r.requirement_status = 'satisfied'
      and not exists (
        select 1 from wnph.recovery_decision_requirements newer
        where newer.supersedes_requirement_id = r.id
      )
  ) then
    raise exception 'WNPH Dewy illustration diagnostic: text requirement changed unexpectedly';
  end if;

  if not exists (
    select 1
    from wnph.recovery_decision_requirements r
    where r.id = v_judgment_requirement_id
      and r.requirement_status = 'open'
      and r.requirement_authority = 'publishing_judgment'
      and not exists (
        select 1 from wnph.recovery_decision_requirements newer
        where newer.supersedes_requirement_id = r.id
      )
  ) then
    raise exception 'WNPH Dewy illustration diagnostic: publishing judgment changed unexpectedly';
  end if;

  if exists (
    select 1
    from wnph.recovery_decision_requirement_bases b
    join wnph.recovery_decision_requirements r on r.id = b.requirement_id
    where r.recovery_decision_id = v_decision_id
      and r.requirement_authority = 'publishing_judgment'
      and b.basis_role = 'satisfies'
  ) then
    raise exception 'WNPH Dewy illustration diagnostic: evidence must not satisfy publishing judgment';
  end if;

  select e.to_state
    into v_case_state
  from wnph.recovery_case_events e
  where e.recovery_case_id = v_case_id
    and not exists (
      select 1 from wnph.recovery_case_events newer
      where newer.prior_event_id = e.id
    )
  order by e.created_at desc
  limit 1;

  if v_case_state is distinct from 'MORE_EVIDENCE_NEEDED' then
    raise exception 'WNPH Dewy illustration diagnostic: case must remain MORE_EVIDENCE_NEEDED after illustration diagnostic';
  end if;
end
$$;
