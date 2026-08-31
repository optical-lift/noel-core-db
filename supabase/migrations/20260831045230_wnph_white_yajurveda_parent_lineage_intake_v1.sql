begin;

-- WNPH White Yajurveda parent lineage intake v1.
--
-- Establishes the upstream Vājasaneyi Saṁhitā Work and two public-domain Sanskrit
-- editorial witnesses used to investigate the vessel-cleansing operation:
--   * Albrecht Weber, Vājasaneyi Saṁhitā, Part I of The White Yajurveda, 1852;
--   * Albrecht Weber, Śatapatha Brāhmaṇa (Mādhyandina), Part II, 1855.
--
-- It also records the direct documentary relationship by which Śatapatha Brāhmaṇa
-- I.3.1 invokes Vājasaneyi Saṁhitā I.29 while explaining the sacrificial-spoon
-- cleansing operation.  The two ancient Works remain distinct.  Weber's printed
-- Sanskrit editorial texts remain distinct Expressions and are not represented as
-- untouched ancient manuscripts.  No Sanskrit reading text is admitted here.

insert into wnph.evidence_sources(
  canonical_key,source_type,title,repository_name,url,external_identifier,
  retrieved_at,rights_note,provenance_note,metadata
) values
(
  'commons:vajasaneyi-weber-1852-dli-486971',
  'digital_surrogate_record',
  'The Vajasaneyi-sanhita',
  'Wikimedia Commons / Digital Library of India',
  'https://commons.wikimedia.org/wiki/File:The_Vajasaneyi-sanhita_(IA_in.ernet.dli.2015.486971).pdf',
  'in.ernet.dli.2015.486971',now(),
  'Wikimedia Commons metadata records the digitized historical publication as public domain. The 1852 Weber edition is itself public domain in the United States by publication date. WNPH makes no ownership claim over repository presentation or modern metadata.',
  'DLI/Commons record for Weber''s 1852 Vājasaneyi-Saṁhitā. Metadata identifies Sanskrit language, Williams and Norgate as publisher, Ramakrishna Mission Institute of Culture, Golpark as source library, 1094 scanned pages, and Internet Archive identifier in.ernet.dli.2015.486971.',
  jsonb_build_object(
    'publication_year',1852,
    'editor','Albrecht Weber',
    'publisher','Williams and Norgate',
    'source_library','Ramakrishna Mission Institute of Culture, Golpark',
    'internet_archive_identifier','in.ernet.dli.2015.486971',
    'scanned_pages',1094,
    'language','Sanskrit',
    'rights_status','public_domain',
    'edition_scope','Madhyandina and Kanva recensions with Mahidhara commentary'
  )
),
(
  'prajnaquest:satapatha-weber-1855',
  'segmented_scan_index',
  'Śatapatha-brāhmaṇa, Mādhyandina-śākhā, ed. Albrecht Weber, 1855',
  'PrajnaQuest',
  'https://prajnaquest.fr/blog/sanskrit-texts-3/sanskrit-hindu-texts/',
  null,now(),
  'Weber''s 1855 historical edition is public domain in the United States by publication date. WNPH uses the repository scan only as historical-source material and makes no ownership claim over repository presentation.',
  'Repository index exposes Weber''s 1855 Mādhyandina Śatapatha-Brāhmaṇa as four PDF segments covering printed pp. 1-340, 341-636, 637-956, and 957-1194. The title page identifies Part II of The White Yajurveda, Berlin: Ferd. Dümmler and London: Williams and Norgate, 1855.',
  jsonb_build_object(
    'publication_year',1855,
    'editor','Albrecht Weber',
    'publisher_berlin','Ferd. Dümmler',
    'publisher_london','Williams and Norgate',
    'recension','Madhyandina',
    'printed_pages_end',1194,
    'segment_ranges',jsonb_build_array('1-340','341-636','637-956','957-1194'),
    'role','sanskrit_editorial_witness'
  )
),
(
  'titus:vajasaneyi-samhita-madhyandina-weber',
  'scholarly_electronic_text',
  'White Yajur-Veda: Vājasaneyi-Saṃhitā, Mādhyandina Recension',
  'TITUS / Goethe University Frankfurt',
  'https://titus.uni-frankfurt.de/texte/etcd/ind/aind/ved/yvw/vs/vst.htm',
  null,now(),
  'Electronic scholarly transcription is retained as research/comparison evidence. WNPH does not assert that the modern electronic presentation is public domain merely because the underlying Weber edition is.',
  'TITUS states that its Mādhyandina Vājasaneyi-Saṃhitā text is based on Albrecht Weber''s edition and exposes verse I.29 with both masculine and feminine cleansing formula forms. It is comparison evidence, not a substitute for the governed 1852 scan.',
  jsonb_build_object(
    'recension','Madhyandina',
    'edition_basis','Albrecht Weber',
    'target_locator','1.29',
    'role','comparison_text',
    'source_image_authority',false
  )
),
(
  'sacred-texts:sbe12:introduction-madhyandina-lineage',
  'historical_translation_introduction',
  'Śatapatha Brāhmaṇa Part I (SBE 12): Introduction',
  'Internet Sacred Text Archive',
  'https://sacred-texts.com/hin/sbr/sbe12/sbe1202.htm',
  null,now(),
  'Eggeling''s 1882 introduction is public domain in the United States. Modern website presentation is separately attributable.',
  'Eggeling states that both the Vājasaneyi-Saṁhitā and Śatapatha-Brāhmaṇa survive in Mādhyandina and Kāṇva recensions and that Weber edited the Mādhyandina text of both. This supports the documented textual-tradition relationship without collapsing the Works.',
  jsonb_build_object(
    'publication_year',1882,
    'author','Julius Eggeling',
    'role','tradition_relationship_evidence'
  )
)
on conflict(canonical_key) do nothing;

do $$
declare
  v_vs_source uuid;
  v_sb_weber_source uuid;
  v_titus_source uuid;
  v_intro_source uuid;
  v_eggeling_passage_source uuid;
  v_vs_work uuid;
  v_sb_work uuid;
  v_vs_expression uuid;
  v_sb_weber_expression uuid;
  v_vs_manifestation uuid;
  v_sb_weber_manifestation uuid;
  v_vs_item uuid;
  v_sb_weber_item uuid;
  v_vs_surrogate uuid;
  v_sb_weber_surrogate uuid;
  v_app uuid;
  v_att uuid;
  v_circle uuid;
  v_membership_vs uuid;
  v_membership_sb uuid;
  v_claim_sb uuid;
  v_claim_vs uuid;
  v_cont uuid;
  v_case_vs uuid;
  v_event uuid;
  v_existing_satapatha_case uuid;
begin
  select id into strict v_vs_source from wnph.evidence_sources where canonical_key='commons:vajasaneyi-weber-1852-dli-486971';
  select id into strict v_sb_weber_source from wnph.evidence_sources where canonical_key='prajnaquest:satapatha-weber-1855';
  select id into strict v_titus_source from wnph.evidence_sources where canonical_key='titus:vajasaneyi-samhita-madhyandina-weber';
  select id into strict v_intro_source from wnph.evidence_sources where canonical_key='sacred-texts:sbe12:introduction-madhyandina-lineage';
  select id into strict v_eggeling_passage_source from wnph.evidence_sources where canonical_key='sacred-texts:sbe12:1-3-1';

  -- Ancient Vājasaneyi Saṁhitā Work: distinct from every modern edition.
  insert into wnph.historical_works(
    canonical_key,canonical_label,work_type,language_code,status,identity_confidence,notes
  ) values(
    'vajasaneyi-samhita','Vājasaneyi Saṁhitā','samhita_ritual_formula_text','sa','established','high',
    'Ancient White Yajurveda Saṁhitā Work with Mādhyandina and Kāṇva recension traditions. This Work identity does not collapse its recensions, Weber''s nineteenth-century editions, Mahīdhara''s commentary, or later electronic transcriptions.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_vs_work from wnph.historical_works where canonical_key='vajasaneyi-samhita';

  select id into strict v_sb_work from wnph.historical_works where canonical_key='satapatha-brahmana';

  if not exists(
    select 1 from wnph.appellation_attestations aa
    join wnph.appellations a on a.id=aa.appellation_id
    where aa.source_id=v_vs_source and a.normalized_value='the vajasaneyi sanhita'
  ) then
    insert into wnph.appellations(value,kind,language_code,normalized_value)
    values('The Vajasaneyi-sanhita','title','en','the vajasaneyi sanhita')
    returning id into v_app;

    insert into wnph.appellation_attestations(
      appellation_id,source_id,observed_value,observed_context,source_locator,notes
    ) values(
      v_app,v_vs_source,'The Vajasaneyi-sanhita','1852 Weber scan title/catalog record',
      'Wikimedia Commons / DLI item in.ernet.dli.2015.486971',
      'Historical edition title supplies bibliographic evidence for the Work appellation while Weber''s edited Expression remains separate.'
    ) returning id into v_att;

    insert into wnph.appellation_bindings(
      appellation_id,relationship_type,work_id,status,confidence,notes
    ) values(v_app,'title_of',v_vs_work,'established','high','Bound to the ancient Work identity, not to Weber as author.');

    insert into wnph.work_identity_adjudications(
      left_attestation_id,result_work_id,result,rationale,confidence,recorded_by
    ) values(
      v_att,v_vs_work,'ESTABLISHES_WORK',
      'The governed 1852 edition title and independent scholarly tradition metadata establish the Vājasaneyi Saṁhitā Work identity for WNPH intake while preserving recension and editorial distinctions.',
      'high','wnph:white-yajurveda-parent-lineage-intake-v1'
    );
  end if;

  -- Weber 1852 Mādhyandina edited textual stream as an Expression of the ancient Saṁhitā.
  insert into wnph.expressions(
    canonical_key,work_id,expression_type,language_code,status,identity_confidence,summary
  ) values(
    'vajasaneyi-samhita:weber-1852-madhyandina-edited-e1',v_vs_work,
    'edited_sanskrit_recension','sa','established','high',
    'The Mādhyandina textual stream as edited by Albrecht Weber within his 1852 Vājasaneyi-Saṁhitā publication. The printed volume also contains the Kāṇva recension and Mahīdhara commentary; those are not silently merged into this Expression. Establishment does not admit any Sanskrit reading text.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_vs_expression from wnph.expressions where canonical_key='vajasaneyi-samhita:weber-1852-madhyandina-edited-e1';

  insert into wnph.manifestations(
    canonical_key,publisher_name,publication_place,publication_statement,extent_statement,format_statement,status,notes
  ) values(
    'white-yajurveda:weber-part1-1852',
    'Ferd. Dümmler / Williams and Norgate','Berlin / London',
    'The White Yajurveda, Part I: The Vājasaneyi-Saṁhitā in the Mādhyandina and Kāṇva Śākhā with the commentary of Mahīdhara; Berlin: Ferd. Dümmler; London: Williams and Norgate, 1852',
    'Part I; historical catalogs report approximately xcv + 989 pages','printed book','established',
    'Manifestation embodies a multi-recension scholarly edition. WNPH does not infer that every textual stream in the volume is the same Expression.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_vs_manifestation from wnph.manifestations where canonical_key='white-yajurveda:weber-part1-1852';

  if not exists(select 1 from wnph.work_manifestations where work_id=v_vs_work and manifestation_id=v_vs_manifestation and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes)
    values(v_vs_work,v_vs_manifestation,'editorial_manifestation_of','established','high','1852 Weber editorial manifestation of Vājasaneyi Saṁhitā textual traditions.');
  end if;
  if not exists(select 1 from wnph.expression_manifestations where expression_id=v_vs_expression and manifestation_id=v_vs_manifestation and supersedes_relationship_id is null) then
    insert into wnph.expression_manifestations(expression_id,manifestation_id,relationship_type,status,confidence,notes)
    values(v_vs_expression,v_vs_manifestation,'embodied_in','established','high','Weber''s Mādhyandina edited textual stream is embodied within the larger 1852 Part I manifestation.');
  end if;

  insert into wnph.items(
    canonical_key,manifestation_id,holding_institution,call_number,external_identifier,status,copy_note,provenance_note
  ) values(
    'vajasaneyi-samhita:weber1852:dli-486971',v_vs_manifestation,
    'Ramakrishna Mission Institute of Culture, Golpark',null,'in.ernet.dli.2015.486971','surviving_item_confirmed',
    'Physical copy represented by the Digital Library of India / Wikimedia Commons scan; repository metadata reports 1094 scanned pages.',
    'Source-library identity is taken from the DLI/Commons metadata. WNPH does not infer a call number not supplied by that record.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_vs_item from wnph.items where canonical_key='vajasaneyi-samhita:weber1852:dli-486971';

  insert into wnph.surrogates(
    canonical_key,item_id,source_id,surrogate_type,image_count,formats,status,quality_note
  ) values(
    'vajasaneyi-samhita:weber1852:dli-486971-surrogate',v_vs_item,v_vs_source,
    'repository_page_image_surrogate',1094,array['pdf','page_images']::text[],'available',
    'Public-domain DLI/Commons scan. Exact scan-image mapping for Vājasaneyi Saṁhitā I.29 remains to be established before any Sanskrit reading admission.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_vs_surrogate from wnph.surrogates where canonical_key='vajasaneyi-samhita:weber1852:dli-486971-surrogate';

  -- Weber 1855 Sanskrit editorial Expression of the already-established Śatapatha Work.
  insert into wnph.expressions(
    canonical_key,work_id,expression_type,language_code,status,identity_confidence,summary
  ) values(
    'satapatha-brahmana:weber-1855-madhyandina-edited-e1',v_sb_work,
    'edited_sanskrit_recension','sa','established','high',
    'Albrecht Weber''s 1855 edited Sanskrit Mādhyandina Śatapatha-Brāhmaṇa textual stream, with extracts from historical commentaries. It is a nineteenth-century editorial witness to the ancient Work, not an untouched ancient manuscript and not Eggeling''s later English translation.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_sb_weber_expression from wnph.expressions where canonical_key='satapatha-brahmana:weber-1855-madhyandina-edited-e1';

  insert into wnph.manifestations(
    canonical_key,publisher_name,publication_place,publication_statement,extent_statement,format_statement,status,notes
  ) values(
    'white-yajurveda:weber-part2-1855',
    'Ferd. Dümmler / Williams and Norgate','Berlin / London',
    'The White Yajurveda, Part II: The Śatapatha-Brāhmaṇa in the Mādhyandina Śākhā with extracts from the commentaries of Sāyaṇa, Harisvāmin and Dvivedaganga; Berlin: Ferd. Dümmler; London: Williams and Norgate, 1855',
    'xiii + 1194 printed pages','printed book','established',
    'Historical Sanskrit editorial manifestation. PrajnaQuest exposes the text as four scan segments covering printed pp. 1-1194.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_sb_weber_manifestation from wnph.manifestations where canonical_key='white-yajurveda:weber-part2-1855';

  if not exists(select 1 from wnph.work_manifestations where work_id=v_sb_work and manifestation_id=v_sb_weber_manifestation and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes)
    values(v_sb_work,v_sb_weber_manifestation,'editorial_manifestation_of','established','high','1855 Weber Sanskrit editorial manifestation of the Mādhyandina Śatapatha-Brāhmaṇa tradition.');
  end if;
  if not exists(select 1 from wnph.expression_manifestations where expression_id=v_sb_weber_expression and manifestation_id=v_sb_weber_manifestation and supersedes_relationship_id is null) then
    insert into wnph.expression_manifestations(expression_id,manifestation_id,relationship_type,status,confidence,notes)
    values(v_sb_weber_expression,v_sb_weber_manifestation,'embodied_in','established','high','The Weber 1855 Mādhyandina Sanskrit edited Expression is embodied in Part II of The White Yajurveda.');
  end if;

  insert into wnph.items(
    canonical_key,manifestation_id,holding_institution,call_number,external_identifier,status,copy_note,provenance_note
  ) values(
    'satapatha-brahmana:weber1855:prajnaquest-segmented-scan',v_sb_weber_manifestation,
    null,null,'PrajnaQuest Weber 1855 segmented scan','digitized_item_confirmed',
    'Digital exemplar represented by four repository PDF segments covering printed pp. 1-1194.',
    'Physical-copy holding provenance is unresolved in the current source packet and therefore is not inferred.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_sb_weber_item from wnph.items where canonical_key='satapatha-brahmana:weber1855:prajnaquest-segmented-scan';

  insert into wnph.surrogates(
    canonical_key,item_id,source_id,surrogate_type,image_count,formats,status,quality_note
  ) values(
    'satapatha-brahmana:weber1855:prajnaquest-segmented-surrogate',v_sb_weber_item,v_sb_weber_source,
    'repository_segmented_pdf_surrogate',null,array['pdf']::text[],'available',
    'Four public repository PDF segments span printed pp. 1-1194. Exact page location of I.3.1 remains to be source-mapped before this witness can verify Sanskrit readings.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_sb_weber_surrogate from wnph.surrogates where canonical_key='satapatha-brahmana:weber1855:prajnaquest-segmented-surrogate';

  -- Add Weber 1855 as an independent Sanskrit comparison target for the existing vessel-cleansing case.
  select id into strict v_existing_satapatha_case
  from wnph.recovery_cases where canonical_key='satapatha-brahmana:eggeling-part1-vessel-cleansing-recovery-1';

  if not exists(
    select 1 from wnph.recovery_case_targets t
    where t.recovery_case_id=v_existing_satapatha_case and t.target_role='comparison'
      and t.surrogate_id=v_sb_weber_surrogate and t.supersedes_target_id is null
  ) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
    values(v_existing_satapatha_case,'comparison',v_sb_weber_surrogate,
      'Independent Sanskrit Mādhyandina editorial witness upstream of Eggeling''s English translation. It may corroborate the ancient-language basis of I.3.1 after exact source mapping; it cannot silently overwrite or verify Eggeling''s Expression.');
  end if;

  -- New bounded recovery case for the upstream formula itself.
  insert into wnph.recovery_cases(canonical_key,work_id,initial_scope,created_by)
  values(
    'vajasaneyi-samhita:weber1852-i-29-cleansing-formula-recovery-1',v_vs_work,
    'Recover and source-verify the Mādhyandina Vājasaneyi Saṁhitā I.29 formula as transmitted in Weber''s governed 1852 Sanskrit editorial witness, preserving accent marks, masculine/feminine formula forms, and exact source locators. Do not infer meaning from Eggeling before the Sanskrit marks are secured.',
    'wnph:white-yajurveda-parent-lineage-intake-v1'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_case_vs from wnph.recovery_cases where canonical_key='vajasaneyi-samhita:weber1852-i-29-cleansing-formula-recovery-1';

  if not exists(select 1 from wnph.recovery_case_targets where recovery_case_id=v_case_vs and target_role='candidate' and expression_id=v_vs_expression and supersedes_target_id is null) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,expression_id,rationale)
    values(v_case_vs,'candidate',v_vs_expression,'Recover the Mādhyandina formula from Weber''s 1852 edited Sanskrit Expression without conflating the Kāṇva stream or Mahīdhara commentary.');
  end if;
  if not exists(select 1 from wnph.recovery_case_targets where recovery_case_id=v_case_vs and target_role='publication_model' and manifestation_id=v_vs_manifestation and supersedes_target_id is null) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,manifestation_id,rationale)
    values(v_case_vs,'publication_model',v_vs_manifestation,'Weber 1852 Part I is the bounded historical publication model for this source recovery.');
  end if;
  if not exists(select 1 from wnph.recovery_case_targets where recovery_case_id=v_case_vs and target_role='primary_source' and surrogate_id=v_vs_surrogate and supersedes_target_id is null) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
    values(v_case_vs,'primary_source',v_vs_surrogate,'DLI/Commons page-image scan is the governed source; TITUS remains comparison text until source images are mapped.');
  end if;
  if not exists(select 1 from wnph.recovery_case_modes where recovery_case_id=v_case_vs and recovery_mode='witness' and supersedes_mode_id is null) then
    insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
    values(v_case_vs,'witness','proposed','Preserve Weber''s exact 1852 Sanskrit editorial witness and its accentuation/recension boundaries.');
  end if;
  if not exists(select 1 from wnph.recovery_case_modes where recovery_case_id=v_case_vs and recovery_mode='transcription' and supersedes_mode_id is null) then
    insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
    values(v_case_vs,'transcription','proposed','Transcribe I.29 from governed page images with explicit source locators before promotion.');
  end if;
  if not exists(select 1 from wnph.recovery_case_modes where recovery_case_id=v_case_vs and recovery_mode='text' and supersedes_mode_id is null) then
    insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
    values(v_case_vs,'text','proposed','Recover the complete I.29 formula unit, not only a remembered English gloss.');
  end if;
  if not exists(select 1 from wnph.recovery_case_events where recovery_case_id=v_case_vs) then
    insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
    values(v_case_vs,null,'IDENTITY_ESTABLISHED','state_transition','Ancient Saṁhitā Work, Weber Mādhyandina Expression, 1852 manifestation, identified DLI item and page-image surrogate are separately established.','wnph:white-yajurveda-parent-lineage-intake-v1') returning id into v_event;
    insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
    values(v_case_vs,v_event,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition','Begin exact page-image location and source verification for Vājasaneyi Saṁhitā I.29; electronic text is comparison only.','wnph:white-yajurveda-parent-lineage-intake-v1');
  end if;

  -- Documented Mādhyandina ritual/textual lineage. This circle is relational metadata,
  -- not a claim that the Saṁhitā and Brāhmaṇa are one Work.
  insert into wnph.source_circles(canonical_key,canonical_label,circle_type,status,notes)
  values(
    'wnph:circle:madhyandina-white-yajurveda-ritual-lineage',
    'Mādhyandina White Yajurveda Ritual-Textual Lineage',
    'ritual_tradition','documented',
    'Narrow source circle for direct textual/ritual relationships between the Mādhyandina Vājasaneyi Saṁhitā and Śatapatha Brāhmaṇa. Membership does not merge Work identities and does not imply a single date, author, manuscript, or textual state.'
  ) on conflict(canonical_key) do nothing;
  select id into strict v_circle from wnph.source_circles where canonical_key='wnph:circle:madhyandina-white-yajurveda-ritual-lineage';

  if not exists(select 1 from wnph.source_circle_memberships m where m.source_circle_id=v_circle and m.work_id=v_vs_work and m.supersedes_membership_id is null) then
    insert into wnph.source_circle_memberships(
      source_circle_id,work_id,relationship_type,evidence_status,mechanism_status,confidence,notes
    ) values(
      v_circle,v_vs_work,'inherited_tradition','documented','known','high',
      'The Mādhyandina Vājasaneyi Saṁhitā supplies formula text used within the same named White Yajurveda textual/ritual tradition.'
    ) returning id into v_membership_vs;
  else
    select id into strict v_membership_vs from wnph.source_circle_memberships m where m.source_circle_id=v_circle and m.work_id=v_vs_work and m.supersedes_membership_id is null order by created_at desc limit 1;
  end if;

  if not exists(select 1 from wnph.source_circle_memberships m where m.source_circle_id=v_circle and m.work_id=v_sb_work and m.supersedes_membership_id is null) then
    insert into wnph.source_circle_memberships(
      source_circle_id,work_id,relationship_type,evidence_status,mechanism_status,confidence,notes
    ) values(
      v_circle,v_sb_work,'inherited_tradition','documented','known','high',
      'The Mādhyandina Śatapatha Brāhmaṇa explicitly invokes Saṁhitā formula locators while explaining ritual operations.'
    ) returning id into v_membership_sb;
  else
    select id into strict v_membership_sb from wnph.source_circle_memberships m where m.source_circle_id=v_circle and m.work_id=v_sb_work and m.supersedes_membership_id is null order by created_at desc limit 1;
  end if;

  insert into wnph.evidence_links(source_id,source_circle_id,support_role,confidence,note)
  select v_intro_source,v_circle,'supports','high','Eggeling''s historical introduction explicitly describes both Works as surviving in Mādhyandina and Kāṇva recensions and identifies Weber''s Mādhyandina editions.'
  where not exists(select 1 from wnph.evidence_links where source_id=v_intro_source and source_circle_id=v_circle and supersedes_evidence_link_id is null);
  insert into wnph.evidence_links(source_id,source_circle_membership_id,support_role,confidence,note)
  select v_titus_source,v_membership_vs,'supports','high','TITUS identifies the Mādhyandina Vājasaneyi Saṁhitā and its Weber edition basis.'
  where not exists(select 1 from wnph.evidence_links where source_id=v_titus_source and source_circle_membership_id=v_membership_vs and supersedes_evidence_link_id is null);
  insert into wnph.evidence_links(source_id,source_circle_membership_id,support_role,confidence,note)
  select v_eggeling_passage_source,v_membership_sb,'supports','high','Eggeling I.3.1 explicitly cites Vāg. S. I.29 while describing the spoon-cleaning operation.'
  where not exists(select 1 from wnph.evidence_links where source_id=v_eggeling_passage_source and source_circle_membership_id=v_membership_sb and supersedes_evidence_link_id is null);

  -- Direct documentary transmission claims.
  insert into wnph.transmission_claims(
    source_circle_id,work_id,claim_text,epistemic_status,confidence,notes
  ) values(
    v_circle,v_sb_work,
    'Śatapatha Brāhmaṇa I.3.1 explicitly invokes Vājasaneyi Saṁhitā I.29 for formulae used while heating and cleaning sacrificial spoons. This is a direct documentary relationship between distinct Works, not an inference of identical Work identity.',
    'evidence','high','The citation is visible in Eggeling''s I.3.1 witness as “Vâg. S. I, 29”; Sanskrit source verification remains a separate recovery task.'
  ) returning id into v_claim_sb;
  insert into wnph.evidence_links(source_id,transmission_claim_id,support_role,confidence,note)
  values(v_eggeling_passage_source,v_claim_sb,'supports','high','Eggeling I.3.1 supplies the explicit Saṁhitā locator in the governed historical translation witness.');

  insert into wnph.transmission_claim_continuities(
    transmission_claim_id,continuity_kind,observation_text,notes
  ) values(
    v_claim_sb,'direct_documentary_link',
    'The Brāhmaṇa names Vājasaneyi Saṁhitā I.29 at the point where it prescribes the relevant spoken formulae.',
    'Direct locator relationship; no chronological inference is required.'
  ) returning id into v_cont;
  insert into wnph.evidence_links(source_id,transmission_claim_continuity_id,support_role,confidence,note)
  values(v_eggeling_passage_source,v_cont,'supports','high','Historical translation witness supports the direct locator continuity.');

  insert into wnph.transmission_claim_continuities(
    transmission_claim_id,continuity_kind,observation_text,notes
  ) values(
    v_claim_sb,'ritual_operation',
    'The cited Saṁhitā formula is embedded by the Brāhmaṇa within the physical operation of heating/brushing sacrificial spoons and distinguishing the masculine dipping-spoon and feminine offering-spoon formula forms.',
    'Functional relationship is recorded independently of later genre labels such as spell, prayer, hymn, or liturgy.'
  ) returning id into v_cont;
  insert into wnph.evidence_links(source_id,transmission_claim_continuity_id,support_role,confidence,note)
  values(v_eggeling_passage_source,v_cont,'supports','high','I.3.1 provides the operational context in which the Saṁhitā locator is invoked.');

  insert into wnph.transmission_claims(
    source_circle_id,work_id,claim_text,epistemic_status,confidence,notes
  ) values(
    v_circle,v_vs_work,
    'Vājasaneyi Saṁhitā I.29 preserves paired masculine and feminine formula forms containing the cleansing verb-form conventionally represented in Weber-derived electronic text as saṃ mārjmi; this is the formula unit invoked by Śatapatha Brāhmaṇa I.3.1.',
    'evidence','high','TITUS provides a Weber-based Mādhyandina electronic witness at verse I.29; WNPH has not yet promoted that electronic text to canonical Sanskrit reading.'
  ) returning id into v_claim_vs;
  insert into wnph.evidence_links(source_id,transmission_claim_id,support_role,confidence,note)
  values(v_titus_source,v_claim_vs,'supports','high','TITUS exposes the Mādhyandina I.29 paired formula forms on a Weber-edition basis.');

  insert into wnph.transmission_claim_continuities(
    transmission_claim_id,continuity_kind,observation_text,notes
  ) values(
    v_claim_vs,'ritual_operation',
    'I.29 contains two closely parallel utterance forms differentiated by the grammatical/ritual object form; the Brāhmaṇa explains their deployment across dipping and offering spoons.',
    'Raw Sanskrit source-image verification is pending and will govern any future textual admission.'
  ) returning id into v_cont;
  insert into wnph.evidence_links(source_id,transmission_claim_continuity_id,support_role,confidence,note)
  values(v_titus_source,v_cont,'supports','high','Weber-based Mādhyandina electronic text supports the paired-form observation as comparison evidence.');
end $$;

commit;
