-- WNPH foundational cookbook source sufficiency, U.S. rights, and recovery-audit pass v1.
-- Advances only to RECOVERY_AUDIT. It does not establish a recovery gap, qualify a Work,
-- select a preferred source, normalize recipes, or expose an Atlas cookbook API.

insert into wnph.evidence_sources(
  canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,rights_note,provenance_note,metadata
) values
(
  'us-copyright-office:circular-15a:2026','government_guidance','Circular 15A: Duration of Copyright','U.S. Copyright Office',
  'https://www.copyright.gov/circs/circ15a.pdf',null,now(),
  'Official U.S. Copyright Office guidance revised April 2026 states that all works published in the United States before January 1, 1931 are in the public domain.',
  'Official U.S. duration guidance used only for the U.S. rights determination; it does not establish worldwide rights.',
  jsonb_build_object('revision','2026-04','jurisdiction','US')
),
(
  'internet-archive:newsystemofdomes01rund','digital_surrogate_record','A new system of domestic cookery, formed upon principles of economy, and adapted to the use of private families','Internet Archive',
  'https://archive.org/details/newsystemofdomes01rund','newsystemofdomes01rund',now(),
  'Internet Archive metadata states: Possible copyright status: The Library of Congress is unaware of any copyright restrictions for this item.',
  'Direct Internet Archive item page for the 1807 Boston W. Andrews exemplar; contributor is The Library of Congress. Download options include PDF, full text, OCR, EPUB, JP2-derived image packages, and related source files.',
  jsonb_build_object('publication_year',1807,'contributor','The Library of Congress','pages_reported',338,'collection',jsonb_build_array('library_of_congress','americana'))
),
(
  'wikisource:proper-new-booke-of-cookery-1575','public_domain_transcription_project','A Proper New Booke of Cookery','Wikisource',
  'https://en.wikisource.org/wiki/A_Proper_New_Booke_of_Cookery',null,now(),
  'The transcription project derives from the public-domain 1575 scan; individual pages may have proofread-but-not-validated status.',
  'Comparison transcription project tied to the 1575 DjVu witness. It is not promoted as a source-authoritative reconstruction.',
  jsonb_build_object('witness_year',1575,'role','comparison_transcription')
)
on conflict(canonical_key) do nothing;

do $$
declare
  v_usco uuid;
  v_case uuid;
  v_work uuid;
  v_manifestation uuid;
  v_surrogate uuid;
  v_primary_source uuid;
  v_compare_source uuid;
  v_assessment uuid;
  v_member uuid;
  v_rights uuid;
  v_component uuid;
  v_audit uuid;
  v_finding uuid;
  v_event uuid;
  v_next uuid;
  r record;
begin
  select id into strict v_usco from wnph.evidence_sources where canonical_key='us-copyright-office:circular-15a:2026';

  for r in
    select * from (values
      ('forme-of-cury:foundational-cookbook-recovery-1'::text,'forme-of-cury'::text,'forme-of-cury:pegge-london-1780'::text,'forme-of-cury:loc-digital-44031282'::text,'loc:item:44031282'::text,'project-gutenberg:8102'::text,'medium'::text,'complete'::text,'usable'::text,'reuse_permitted'::text),
      ('proper-new-booke-of-cookery:foundational-cookbook-recovery-1','proper-new-booke-of-cookery','proper-new-booke-of-cookery:london-how-veale-1575','proper-new-booke-of-cookery:commons-ia-1575','wikimedia-commons:proper-new-booke-cookery-1575','wikisource:proper-new-booke-of-cookery-1575','medium','substantially_complete','usable','public_domain'),
      ('new-system-of-domestic-cookery:foundational-cookbook-recovery-1','new-system-of-domestic-cookery','new-system-of-domestic-cookery:boston-andrews-1807','new-system-of-domestic-cookery:ia-newsystemofdomes01rund','internet-archive:newsystemofdomes01rund','project-gutenberg:69519','high','complete','good','reuse_permitted'),
      ('virginia-house-wife:foundational-cookbook-recovery-1','virginia-house-wife','virginia-house-wife:washington-davis-force-1824','virginia-house-wife:loc-digital-73217897','loc:item:73217897','project-gutenberg:12519','high','complete','usable','reuse_permitted')
    ) as x(case_key,work_key,manifestation_key,surrogate_key,primary_source_key,compare_source_key,confidence,completeness,quality,source_image_rights)
  loop
    select id into strict v_case from wnph.recovery_cases where canonical_key=r.case_key;
    select id into strict v_work from wnph.historical_works where canonical_key=r.work_key;
    select id into strict v_manifestation from wnph.manifestations where canonical_key=r.manifestation_key;
    select id into strict v_surrogate from wnph.surrogates where canonical_key=r.surrogate_key;
    select id into strict v_primary_source from wnph.evidence_sources where canonical_key=r.primary_source_key;
    select id into strict v_compare_source from wnph.evidence_sources where canonical_key=r.compare_source_key;

    insert into wnph.source_sufficiency_assessments(recovery_case_id,result,confidence,rationale,recorded_by)
    values(
      v_case,'sufficient',r.confidence,
      case r.work_key
        when 'forme-of-cury' then 'The specifically identified LOC 1780 Pegge exemplar exposes 244 page images plus PDF access and is sufficient for governed recovery of that editorial witness. This does not authorize claims about readings of the medieval manuscript beyond what this witness transmits; manuscript-level claims remain a separate source problem.'
        when 'proper-new-booke-of-cookery' then 'The 1575 scan has 33 digital pages, while the cataloged edition is [32] printed pages, and the scan is usable for recovery research. Wikisource demonstrates readable page-level transcription but pages may still require validation. Source sufficiency is therefore sufficient for continued WNPH recovery work, with page-sequence and transcription QC still capable of reopening the gate.'
        when 'new-system-of-domestic-cookery' then 'The identified 1807 Internet Archive exemplar contributed by the Library of Congress provides original/processed page images, PDF, OCR, full text, and ebook derivatives, with the edition independently identified by Open Library and Project Gutenberg. This is sufficient for source-governed recovery research while derivative-to-image collation remains downstream.'
        else 'The LOC 1824 first-edition exemplar exposes 244 page images and PDF access and is sufficient for source-governed recovery research. Project Gutenberg 12519 is a later-edition comparison and is not allowed to substitute for the 1824 witness.'
      end,
      'wnph:foundational-cookbooks-source-rights-audit-v1'
    ) returning id into v_assessment;

    insert into wnph.source_sufficiency_members(
      assessment_id,surrogate_id,source_role,completeness,quality,provenance_status,member_result,missing_or_damage_note,notes
    ) values(
      v_assessment,v_surrogate,'primary',r.completeness,r.quality,'sufficient','usable',
      case r.work_key
        when 'forme-of-cury' then 'Selected source is a 1780 editorial witness, not a medieval manuscript surrogate.'
        when 'proper-new-booke-of-cookery' then 'Page-image sequence and all transcription pages have not yet passed WNPH validation.'
        when 'new-system-of-domestic-cookery' then 'Tight gutters are noted by Internet Archive; source-image/transcription collation remains required.'
        else null
      end,
      'Usable source member for Recovery Work. Sufficiency does not mean every page or semantic unit has passed reconstruction verification.'
    ) returning id into v_member;

    insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
    values(v_primary_source,v_assessment,r.confidence,'Primary repository evidence supports the current source-sufficiency assessment.');
    insert into wnph.evidence_links(source_id,source_sufficiency_member_id,confidence,note)
    values(v_primary_source,v_member,r.confidence,'Primary repository evidence supports the assessed source member.');
    insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
    values(v_compare_source,v_assessment,'medium','Comparison/transcription source corroborates recoverability but is not treated as an independent historical witness.');

    insert into wnph.rights_determinations(recovery_case_id,jurisdiction,overall_status,confidence,rationale,determined_by)
    values(
      v_case,'US','cleared','high',
      'The governed historical publication predates January 1, 1931 and is in the U.S. public domain under current U.S. Copyright Office duration guidance. The selected source-image surrogate is separately resolved as public-domain mechanical scan or repository reuse-permitted/no-known-restrictions evidence. This determination is limited to the current U.S. recovery scope; later-added third-party material and non-U.S. distribution require separate review.',
      'wnph:foundational-cookbooks-source-rights-audit-v1'
    ) returning id into v_rights;

    insert into wnph.rights_components(determination_id,component_type,component_status,work_id,use_scope,rationale)
    values(
      v_rights,'underlying_work','public_domain',v_work,'U.S. source-faithful recovery and downstream WNPH-derived editions',
      'The governed publication evidence predates January 1, 1931; U.S. Copyright Office Circular 15A states all works published in the United States before January 1, 1931 are in the public domain. For the much older English works, this date rule is conservative as to the selected historical publication itself and does not imply worldwide rights.'
    ) returning id into v_component;
    insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
    values(v_usco,v_component,'high','Official U.S. copyright-duration guidance supports the underlying-work determination.');
    insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
    values(v_primary_source,v_component,'high','Primary repository record establishes the historical publication date used by this determination.');

    if r.work_key='forme-of-cury' then
      insert into wnph.rights_components(determination_id,component_type,component_status,manifestation_id,use_scope,rationale)
      values(v_rights,'editorial_apparatus','public_domain',v_manifestation,'Use of Samuel Pegge''s 1780 notes, glossary, and editorial presentation as historical-source material','Pegge''s editorial apparatus was published in 1780 and is public domain in the United States.') returning id into v_component;
      insert into wnph.evidence_links(source_id,rights_component_id,confidence,note) values(v_primary_source,v_component,'high','LOC identifies the 1780 publication and its editorial apparatus.');
    end if;

    insert into wnph.rights_components(determination_id,component_type,component_status,surrogate_id,use_scope,rationale)
    values(
      v_rights,'source_images',r.source_image_rights,v_surrogate,'Use of governed page images as source-recovery inputs',
      case r.work_key
        when 'proper-new-booke-of-cookery' then 'Wikimedia Commons identifies the file as a mere mechanical scan of a public-domain original and says it is free of known copyright restrictions, including related and neighboring rights.'
        when 'new-system-of-domestic-cookery' then 'Internet Archive metadata for this Library of Congress-contributed item records that the Library of Congress is unaware of copyright restrictions. WNPH therefore records source-image reuse permission/no-known-restrictions rather than claiming new copyright ownership in the scan.'
        else 'The Library of Congress Rights & Access statement says it is not aware of U.S. copyright or other restrictions in the documents in this collection. WNPH records this as reuse-permitted/no-known-restrictions evidence rather than a stronger worldwide ownership claim.'
      end
    ) returning id into v_component;
    insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
    values(v_primary_source,v_component,'high','Repository rights/access statement supports the selected source-image component.');

    insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note)
    values(
      v_case,'in_progress',
      'Bounded audit records the currently evidenced facsimile/transcription/ebook channels and their relation to the selected historical witness. It is not complete enough to establish a recovery gap or reject the Work as already competently recovered.'
    ) returning id into v_audit;

    if r.work_key='forme-of-cury' then
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'library_of_congress','present','FACSIMILE','raw','LCCN 44031282','LOC exposes a complete-looking 244-image/PDF digitization of Pegge''s 1780 edition. This is material access, not a WNPH-verified reconstruction.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_primary_source,v_finding,'high','LOC item page supports this finding.');
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'project_gutenberg','present','REFLOWABLE_EBOOK','partial','Project Gutenberg 8102','Public-domain reflowable text exists, but it represents Pegge''s editorial text/transcription lineage and is not treated as a source-image-verified medieval witness.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_compare_source,v_finding,'high','Project Gutenberg 8102 supports this finding.');
    elsif r.work_key='proper-new-booke-of-cookery' then
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'internet_archive','present','FACSIMILE','raw','bim_early-english-books-1475-1640_a-proper-new-booke-of-co_1575','The 1575 mechanical scan exists via Internet Archive/Commons. Source-image page order and WNPH production-level verification remain open.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_primary_source,v_finding,'high','Commons/IA record supports this finding.');
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'other','present','SEARCHABLE_TEXT','partial','Wikisource: A Proper New Booke of Cookery','A source-linked Wikisource transcription exists. Checked pages are marked proofread but needing validation, so it is comparison material rather than a finished governed text.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_compare_source,v_finding,'high','Wikisource transcription project supports this finding.');
    elsif r.work_key='new-system-of-domestic-cookery' then
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'internet_archive','present','FACSIMILE','raw','newsystemofdomes01rund','Internet Archive provides PDF, OCR/full text, and page-image derivatives for the Library of Congress-contributed 1807 exemplar. Tight gutters are noted; WNPH reconstruction verification remains open.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_primary_source,v_finding,'high','Direct Internet Archive record supports this finding.');
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'project_gutenberg','present','REFLOWABLE_EBOOK','partial','Project Gutenberg 69519','Project Gutenberg provides a public-domain reflowable transcription explicitly produced from Internet Archive images. Its transcriber notes include silent corrections, so it is a useful derivative/comparison layer, not automatically the WNPH canonical source text.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_compare_source,v_finding,'high','Project Gutenberg 69519 supports this finding and declares its Internet Archive image source.');
    else
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'library_of_congress','present','FACSIMILE','raw','LCCN 73217897','LOC exposes 244 page images/PDF for the 1824 Washington first edition. This is material access, not yet a WNPH-verified reconstruction.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_primary_source,v_finding,'high','LOC item page supports this finding.');
      insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
      values(v_audit,'project_gutenberg','present','REFLOWABLE_EBOOK','partial','Project Gutenberg 12519','A public-domain e-text exists, but the rendered title page identifies the transcribed edition as 1860. It is therefore comparison/access evidence and cannot substitute for the governed 1824 first-edition witness.') returning id into v_finding;
      insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values(v_compare_source,v_finding,'high','Project Gutenberg 12519 directly shows the 1860 edition title page and supports this finding.');
    end if;

    select e.id into strict v_event
    from wnph.recovery_case_events e
    where e.recovery_case_id=v_case
      and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
    if (select to_state from wnph.recovery_case_events where id=v_event) <> 'SOURCE_RESEARCH' then
      raise exception 'WNPH cookbook audit expected SOURCE_RESEARCH leaf for %, found %',r.case_key,(select to_state from wnph.recovery_case_events where id=v_event);
    end if;

    insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
    values(v_case,v_event,'SOURCE_RESEARCH','SOURCE_SUFFICIENT','state_transition','The selected source member is now sufficient for continued recovery research within its explicitly bounded witness claims. Page-level verification may still reopen source sufficiency.','wnph:foundational-cookbooks-source-rights-audit-v1') returning id into v_next;
    v_event:=v_next;
    insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note) values(v_primary_source,v_event,r.confidence,'Primary repository source supports the SOURCE_SUFFICIENT gate.');

    insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
    values(v_case,v_event,'SOURCE_SUFFICIENT','RIGHTS_RESEARCH','state_transition','Evaluate component-specific U.S. rights for the historical work and the selected recovery-source images.','wnph:foundational-cookbooks-source-rights-audit-v1') returning id into v_next;
    v_event:=v_next;

    insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
    values(v_case,v_event,'RIGHTS_RESEARCH','RIGHTS_CLEARED','state_transition','Current U.S. rights determination clears the bounded recovery inputs while reserving non-U.S. and future third-party-material questions.','wnph:foundational-cookbooks-source-rights-audit-v1') returning id into v_next;
    v_event:=v_next;
    insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note) values(v_usco,v_event,'high','Official U.S. duration guidance supports the RIGHTS_CLEARED gate.');
    insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note) values(v_primary_source,v_event,'high','Repository date and rights/access evidence supports the RIGHTS_CLEARED gate.');

    insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
    values(v_case,v_event,'RIGHTS_CLEARED','RECOVERY_AUDIT','state_transition','Begin governed comparison of existing facsimile, transcription, ebook, print, library, audio, and scholarly recovery states. Audit remains in progress; no meaningful-gap claim is authorized yet.','wnph:foundational-cookbooks-source-rights-audit-v1');
  end loop;
end $$;