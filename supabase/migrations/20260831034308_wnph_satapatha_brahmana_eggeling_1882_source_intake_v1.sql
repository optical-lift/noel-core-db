-- WNPH Satapatha Brahmana / Eggeling 1882 Part I source intake v1.
-- Establishes the ancient Work, the distinct Eggeling English translation Expression,
-- the 1882 Clarendon Press SBE XII manifestation, a repository surrogate, and a
-- bounded recovery case for I.3.1.1-11. No passage text is admitted here.

insert into wnph.evidence_sources (
  canonical_key, source_type, title, repository_name, url, external_identifier,
  retrieved_at, rights_note, provenance_note, metadata
) values
(
  'openlibrary:OL6283265M',
  'library_catalog_and_digital_surrogate',
  'The Satapatha-brahmana, according to the text of the Madhyandina school',
  'Open Library / Internet Archive',
  'https://openlibrary.org/books/OL6283265M/The_satapatha-bra%CC%82hmana',
  'OL6283265M', now(),
  'The governed manifestation is an 1882 publication and is public domain in the United States by publication date. Repository access/derivative terms remain separately attributable to the repository.',
  'Open Library catalog record identifies the 1882 Oxford Clarendon Press English edition/translation by Julius Eggeling, Sacred Books of the East series, and links Internet Archive item satapathabrhma01eggeuoft, LCCN 32034308 and OCLC 3880106.',
  jsonb_build_object(
    'manifestation_year',1882,
    'publisher','The Clarendon Press',
    'publication_place','Oxford',
    'series','The Sacred Books of the East',
    'series_volume',12,
    'part','Part I',
    'coverage','Books I and II',
    'internet_archive_identifier','satapathabrhma01eggeuoft',
    'lccn','32034308',
    'oclc','3880106'
  )
),
(
  'internetarchive:satapathabrhma01eggeuoft',
  'digital_surrogate_record',
  'The Satapatha-brahmana, Part I, Books I and II (Eggeling translation)',
  'Internet Archive',
  'https://archive.org/details/satapathabrhma01eggeuoft',
  'satapathabrhma01eggeuoft', now(),
  'The underlying 1882 Clarendon Press manifestation is public domain in the United States by publication date. Repository access/derivative terms are not converted into a claim about the historical Work.',
  'Internet Archive digital surrogate identified by the Open Library edition record for OL6283265M; retained as the page-image recovery source. Page sequence, printed-page locators and image fidelity remain subject to WNPH source-surface verification.',
  jsonb_build_object(
    'manifestation_year',1882,
    'open_library_edition','OL6283265M',
    'recovery_locator_focus','Satapatha Brahmana I.3.1.1-11; printed pp. 68-71',
    'derivative_role','page_image_recovery_surrogate'
  )
)
on conflict (canonical_key) do nothing;

do $$
declare
  v_catalog_source uuid;
  v_scan_source uuid;
  v_work uuid;
  v_expression uuid;
  v_manifestation uuid;
  v_item uuid;
  v_surrogate uuid;
  v_case uuid;
  v_event_identity uuid;
  v_event_research uuid;
  v_app uuid;
  v_att uuid;
begin
  select id into strict v_catalog_source from wnph.evidence_sources where canonical_key='openlibrary:OL6283265M';
  select id into strict v_scan_source from wnph.evidence_sources where canonical_key='internetarchive:satapathabrhma01eggeuoft';

  insert into wnph.historical_works(
    canonical_key, canonical_label, work_type, language_code, status, identity_confidence, notes
  ) values (
    'satapatha-brahmana', 'Śatapatha Brāhmaṇa', 'brahmana_ritual_text', 'sa', 'established', 'high',
    'Ancient Vedic Brāhmaṇa Work associated with the Mādhyandina textual tradition. This Work record does not assert a single author or a single composition date and does not collapse Julius Eggeling''s nineteenth-century English translation into the ancient Work.'
  ) on conflict (canonical_key) do nothing;
  select id into strict v_work from wnph.historical_works where canonical_key='satapatha-brahmana';

  if not exists (
    select 1 from wnph.appellation_attestations aa
    join wnph.appellations a on a.id=aa.appellation_id
    where aa.source_id=v_catalog_source and a.normalized_value='the satapatha brahmana according to the text of the madhyandina school'
  ) then
    insert into wnph.appellations(value,kind,language_code,normalized_value)
    values('The Satapatha-brahmana, according to the text of the Madhyandina school','title','en','the satapatha brahmana according to the text of the madhyandina school')
    returning id into v_app;

    insert into wnph.appellation_attestations(appellation_id,source_id,observed_value,observed_context,source_locator,notes)
    values(
      v_app,v_catalog_source,
      'The Satapatha-brahmana, according to the text of the Madhyandina school',
      'Open Library 1882 edition title','edition record OL6283265M',
      'The English edition title attests the identity of the ancient Śatapatha Brāhmaṇa while also identifying the Mādhyandina-school basis of Eggeling''s translation.'
    ) returning id into v_att;

    insert into wnph.work_identity_adjudications(left_attestation_id,result_work_id,result,rationale,confidence,recorded_by)
    values(
      v_att,v_work,'ESTABLISHES_WORK',
      'The 1882 edition title and catalog lineage establish the bibliographic identity of the ancient Work for WNPH intake; the translation Expression and printed manifestation remain distinct entities.',
      'high','wnph:satapatha-eggeling-1882-intake-v1'
    );
  end if;

  insert into wnph.expressions(
    canonical_key,work_id,expression_type,language_code,status,identity_confidence,summary
  ) values (
    'satapatha-brahmana:eggeling-1882-en-part1-e1',v_work,'translation','en','established','high',
    'Julius Eggeling''s English translation Expression represented here by Part I (Books I and II), published in Sacred Books of the East XII in 1882. Bibliographic establishment does not admit any recovered passage text; readings must be verified against the governed page-image surrogate.'
  ) on conflict (canonical_key) do nothing;
  select id into strict v_expression from wnph.expressions where canonical_key='satapatha-brahmana:eggeling-1882-en-part1-e1';

  insert into wnph.manifestations(
    canonical_key,publisher_name,publication_place,publication_statement,extent_statement,format_statement,status,notes
  ) values (
    'satapatha-brahmana:oxford-clarendon-sbe12-1882',
    'The Clarendon Press','Oxford',
    'Oxford : The Clarendon Press, 1882; The Sacred Books of the East, Vol. XII; Part I, Books I and II',
    'Part I; Books I and II','printed book','established',
    '1882 printed manifestation of Julius Eggeling''s English translation. Extent is intentionally stated by part/coverage rather than an unverified page total. Open Library edition OL6283265M identifies the five-volume series and Internet Archive item satapathabrhma01eggeuoft for this source line.'
  ) on conflict (canonical_key) do nothing;
  select id into strict v_manifestation from wnph.manifestations where canonical_key='satapatha-brahmana:oxford-clarendon-sbe12-1882';

  if not exists(select 1 from wnph.work_manifestations where work_id=v_work and manifestation_id=v_manifestation and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes)
    values(v_work,v_manifestation,'manifestation_of','established','high',
      '1882 English translation manifestation of the ancient Work; this relationship does not attribute authorship of the ancient Work to Eggeling.');
  end if;

  if not exists(select 1 from wnph.expression_manifestations where expression_id=v_expression and manifestation_id=v_manifestation and supersedes_relationship_id is null) then
    insert into wnph.expression_manifestations(expression_id,manifestation_id,relationship_type,status,confidence,notes)
    values(v_expression,v_manifestation,'embodied_in','established','high',
      'The Clarendon Press SBE XII Part I manifestation embodies Eggeling''s governed English translation Expression for Books I and II.');
  end if;

  insert into wnph.items(
    canonical_key,manifestation_id,holding_institution,call_number,external_identifier,status,copy_note,provenance_note
  ) values (
    'satapatha-brahmana:ia-satapathabrhma01eggeuoft',v_manifestation,null,null,'satapathabrhma01eggeuoft','digitized_item_confirmed',
    'Copy represented by Internet Archive item satapathabrhma01eggeuoft; physical holding institution/call number are not asserted by this intake.',
    'Item identity is bounded to the copy represented by the governed Internet Archive surrogate. Physical-copy provenance may be enriched only from a source that explicitly attests it.'
  ) on conflict (canonical_key) do nothing;
  select id into strict v_item from wnph.items where canonical_key='satapatha-brahmana:ia-satapathabrhma01eggeuoft';

  insert into wnph.surrogates(
    canonical_key,item_id,source_id,surrogate_type,image_count,formats,checksum,status,quality_note
  ) values (
    'satapatha-brahmana:ia-1882-part1-surrogate',v_item,v_scan_source,
    'repository_page_image_surrogate',null,array['page_images','pdf','plain_text']::text[],null,'available',
    'Public repository surrogate for the 1882 Part I manifestation. Page-image sequence, exact scan-image numbers corresponding to printed pp. 68-71, and text fidelity remain unverified in WNPH and therefore block canonical passage admission.'
  ) on conflict (canonical_key) do nothing;
  select id into strict v_surrogate from wnph.surrogates where canonical_key='satapatha-brahmana:ia-1882-part1-surrogate';

  insert into wnph.recovery_cases(canonical_key,work_id,initial_scope,created_by)
  values(
    'satapatha-brahmana:eggeling-part1-vessel-cleansing-recovery-1',v_work,
    'Recover and source-verify Eggeling 1882 Part I, Śatapatha Brāhmaṇa I.3.1.1-11 (printed pp. 68-71), preserving the full vessel-cleansing operation: human food-vessel analogy, water-plus-spoken-formula distinction, cleaning formulae, directional wiping/cleaning actions, and disposal of used cleaning material. Do not classify the passage by a modern genre label before source recovery.',
    'wnph:satapatha-eggeling-1882-intake-v1'
  ) on conflict (canonical_key) do nothing;
  select id into strict v_case from wnph.recovery_cases where canonical_key='satapatha-brahmana:eggeling-part1-vessel-cleansing-recovery-1';

  if not exists(select 1 from wnph.recovery_case_targets where recovery_case_id=v_case and target_role='publication_model' and manifestation_id=v_manifestation and supersedes_target_id is null) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,manifestation_id,rationale)
    values(v_case,'publication_model',v_manifestation,'1882 Clarendon Press SBE XII Part I is the bounded English publication model for this recovery.');
  end if;
  if not exists(select 1 from wnph.recovery_case_targets where recovery_case_id=v_case and target_role='primary_source' and surrogate_id=v_surrogate and supersedes_target_id is null) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
    values(v_case,'primary_source',v_surrogate,'Internet Archive page-image surrogate is the governed recovery source; exact printed-page/image mapping remains to be verified before text admission.');
  end if;
  if not exists(select 1 from wnph.recovery_case_targets where recovery_case_id=v_case and target_role='candidate' and expression_id=v_expression and supersedes_target_id is null) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,expression_id,rationale)
    values(v_case,'candidate',v_expression,'Recover the bounded Eggeling English translation passage as an Expression-level witness reading, not as the ancient Sanskrit text itself.');
  end if;

  if not exists(select 1 from wnph.recovery_case_modes where recovery_case_id=v_case and recovery_mode='witness' and supersedes_mode_id is null) then
    insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
    values(v_case,'witness','proposed','Preserve the exact 1882 Part I witness and its printed structure.');
  end if;
  if not exists(select 1 from wnph.recovery_case_modes where recovery_case_id=v_case and recovery_mode='transcription' and supersedes_mode_id is null) then
    insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
    values(v_case,'transcription','proposed','Verify Eggeling''s English wording directly against the governed page images; modern web transcriptions are locating/comparison aids only.');
  end if;
  if not exists(select 1 from wnph.recovery_case_modes where recovery_case_id=v_case and recovery_mode='text' and supersedes_mode_id is null) then
    insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
    values(v_case,'text','proposed','Recover the complete vessel-cleansing unit before extracting functional semantic claims.');
  end if;

  if not exists(select 1 from wnph.recovery_case_events where recovery_case_id=v_case) then
    insert into wnph.recovery_case_events(
      recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
    ) values (
      v_case,null,null,'IDENTITY_ESTABLISHED','state_transition',
      'Ancient Work identity, Eggeling English Expression, 1882 Clarendon Press manifestation, repository item and page-image surrogate are now separately governed in WNPH.',
      'wnph:satapatha-eggeling-1882-intake-v1',false
    ) returning id into v_event_identity;

    insert into wnph.recovery_case_events(
      recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
    ) values (
      v_case,v_event_identity,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition',
      'Begin exact page-image verification for I.3.1.1-11, printed pp. 68-71. No modern transcription, paraphrase, functional label, or remembered quotation may become canonical reading text before source-surface verification.',
      'wnph:satapatha-eggeling-1882-intake-v1',false
    ) returning id into v_event_research;
  end if;
end $$;