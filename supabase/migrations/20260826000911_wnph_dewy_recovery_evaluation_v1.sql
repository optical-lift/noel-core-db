-- WNPH empirical Recovery Work reconciliation: The Wish Fairy and Dewy Dear
-- Source sufficiency and U.S. rights are established for evaluation; recovery audit remains in progress.
-- This migration deliberately does not establish a recovery gap, qualification, or production selection.

insert into wnph.evidence_sources (
  canonical_key, source_type, title, repository_name, url, retrieved_at, rights_note, provenance_note
) values (
  'us-copyright-office:circular-15a:2026',
  'government_guidance',
  'Circular 15A: Duration of Copyright',
  'U.S. Copyright Office',
  'https://www.copyright.gov/circs/circ15a.pdf',
  now(),
  'Official U.S. Copyright Office guidance states that all works published in the United States before January 1, 1931 are in the public domain.',
  'Official copyright-duration guidance used only for the U.S. rights determination; it does not establish worldwide rights.'
);

do $$
declare
  v_work uuid;
  v_expression uuid;
  v_manifestation uuid;
  v_item uuid;
  v_surrogate uuid;
  v_loc_source uuid;
  v_usco_source uuid;
  v_case uuid;
  v_assessment uuid;
  v_member uuid;
  v_rights uuid;
  v_underlying uuid;
  v_illustrations uuid;
  v_source_images uuid;
  v_audit uuid;
  v_find_facsimile uuid;
  v_find_text uuid;
  v_gap uuid;
  v_gap_material uuid;
  v_gap_witness uuid;
  v_event uuid;
  v_next_event uuid;
begin
  select id into strict v_work from wnph.historical_works where canonical_key='wish-fairy-and-dewy-dear';
  select id into strict v_expression from wnph.expressions where canonical_key='wish-fairy-dewy-dear:e1';
  select id into strict v_manifestation from wnph.manifestations where canonical_key='wish-fairy-dewy-dear:altemus-c1922';
  select id into strict v_item from wnph.items where canonical_key='wish-fairy-dewy-dear:loc-item';
  select id into strict v_surrogate from wnph.surrogates where canonical_key='wish-fairy-dewy-dear:loc-digital';
  select id into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:22008427';
  select id into strict v_usco_source from wnph.evidence_sources where canonical_key='us-copyright-office:circular-15a:2026';

  insert into wnph.recovery_cases(canonical_key,work_id,initial_scope,created_by)
  values (
    'wish-fairy-and-dewy-dear:recovery-evaluation-1',
    v_work,
    'Evaluate recovery of the established c1922 textual/illustrated realization from the Library of Congress exemplar and digital surrogate without presuming qualification or selection.',
    'wnph:dewy-recovery-empirical-pass-v1'
  ) returning id into v_case;

  insert into wnph.recovery_case_briefs(recovery_case_id,scope_note,why_recover,proposed_expression_type,priority)
  values (
    v_case,
    'Provisional first-pilot evaluation scope: text, original illustration program, accessibility and reflowable ebook/web outputs. Recovery value remains unadjudicated until the existing-recovery audit is complete.',
    null,
    'restored_textual_and_illustrated_realization',
    'normal'
  );

  insert into wnph.recovery_case_targets(recovery_case_id,target_role,expression_id,rationale)
  values (v_case,'candidate',v_expression,'Established c1922 textual/illustrated Expression is the provisional content basis.');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,manifestation_id,rationale)
  values (v_case,'publication_model',v_manifestation,'LOC-attested c1922 Altemus publication embodiment is the provisional historical publication model.');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,item_id,rationale)
  values (v_case,'reference',v_item,'Specific Library of Congress exemplar anchors copy-level provenance.');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
  values (v_case,'primary_source',v_surrogate,'LOC digital surrogate is the current primary recovery-evaluation source; it is not yet designated preferred production source.');

  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale) values
    (v_case,'text','proposed','Evaluate verified text recovery.'),
    (v_case,'illustration','proposed','Evaluate preservation/restoration of the historical illustration program.'),
    (v_case,'accessibility','proposed','Evaluate an accessible reading realization.'),
    (v_case,'ebook','proposed','Evaluate reflowable ebook recovery.');

  insert into wnph.recovery_case_outputs(recovery_case_id,manifestation_type,plan_role,notes) values
    (v_case,'web','planned','Provisional output only; no production selection has occurred.'),
    (v_case,'epub','planned','Provisional output only; no production selection has occurred.');

  insert into wnph.source_sufficiency_assessments(recovery_case_id,result,confidence,rationale,recorded_by)
  values (
    v_case,'sufficient','medium',
    'The LOC record exposes a Complete PDF, Complete Text, 72 page images, and high-resolution JPEG access for a specifically identified surviving Item. This is sufficient to proceed with rights and recovery-gap research. Page-by-page reconstruction QC remains downstream and may reopen source sufficiency if defects emerge.',
    'wnph:dewy-recovery-empirical-pass-v1'
  ) returning id into v_assessment;

  insert into wnph.source_sufficiency_members(
    assessment_id,surrogate_id,source_role,completeness,quality,provenance_status,member_result,missing_or_damage_note,notes
  ) values (
    v_assessment,v_surrogate,'primary','complete','usable','sufficient','usable',null,
    'Usable for Recovery Work qualification research based on LOC-provided complete PDF/text plus 72 images; this is not a claim that every page has passed production-image QC.'
  ) returning id into v_member;

  insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
  values (v_loc_source,v_assessment,'high','LOC item page directly supports availability/completeness claims.');
  insert into wnph.evidence_links(source_id,source_sufficiency_member_id,confidence,note)
  values (v_loc_source,v_member,'high','LOC item page supports the assessed digital source member.');

  insert into wnph.rights_determinations(
    recovery_case_id,jurisdiction,overall_status,confidence,rationale,determined_by
  ) values (
    v_case,'US','cleared','high',
    'For the provisional U.S. web/EPUB recovery scope, the c1922 published work and its published historical illustration program are in the U.S. public domain under current U.S. Copyright Office duration guidance, and the LOC states the digitized collection item is public domain and free to use/reuse. Any later-added third-party material or non-U.S. distribution requires a separate determination.',
    'wnph:dewy-recovery-empirical-pass-v1'
  ) returning id into v_rights;

  insert into wnph.rights_components(determination_id,component_type,component_status,work_id,use_scope,rationale)
  values (
    v_rights,'underlying_work','public_domain',v_work,'Provisional U.S. web and EPUB recovery',
    'Published in the United States in 1922; current U.S. Copyright Office guidance states works published in the United States before January 1, 1931 are public domain.'
  ) returning id into v_underlying;

  insert into wnph.rights_components(determination_id,component_type,component_status,expression_id,use_scope,rationale)
  values (
    v_rights,'historical_illustrations','public_domain',v_expression,'Reuse of the illustration program embodied in the c1922 publication for provisional U.S. web and EPUB recovery',
    'The historical illustrations were published as part of the c1922 book; the publication-date rule places that published material in the U.S. public domain.'
  ) returning id into v_illustrations;

  insert into wnph.rights_components(determination_id,component_type,component_status,surrogate_id,use_scope,rationale)
  values (
    v_rights,'source_images','reuse_permitted',v_surrogate,'Use of LOC source images as recovery inputs',
    'The LOC Rights & Access statement for this digitized collection says the books are in the public domain and free to use and reuse.'
  ) returning id into v_source_images;

  insert into wnph.rights_components(determination_id,component_type,component_status,use_scope,rationale)
  values (
    v_rights,'prior_translation','not_applicable','Current provisional English recovery scope',
    'No prior translation is selected or required for the present recovery evaluation.'
  );

  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note) values
    (v_usco_source,v_underlying,'high','Official U.S. duration guidance supports the underlying-work determination.'),
    (v_loc_source,v_underlying,'high','LOC publication date and Rights & Access statement corroborate the determination.'),
    (v_usco_source,v_illustrations,'high','Official U.S. duration guidance supports the published-illustration determination.'),
    (v_loc_source,v_illustrations,'high','LOC record establishes that the c1922 book includes color illustrations and is public domain.'),
    (v_loc_source,v_source_images,'high','LOC directly states the collection books are free to use and reuse.');

  insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note)
  values (
    v_case,'in_progress',
    'Initial bounded audit records only currently evidenced recovery manifestations. The LOC digitization is established; Project Gutenberg, Standard Ebooks, LibriVox, modern commercial ebook/audio, library ebook/audio, modern print, and scholarly/critical edition channels are not yet fully evidenced in canonical custody.'
  ) returning id into v_audit;

  insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
  values (
    v_audit,'library_of_congress','present','FACSIMILE','raw','LCCN 22008427',
    'Complete digitized page-image/PDF access exists. This establishes digitization, not a governed restored edition.'
  ) returning id into v_find_facsimile;

  insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
  values (
    v_audit,'library_of_congress','present','SEARCHABLE_TEXT','raw','LCCN 22008427',
    'LOC exposes complete online text, but no evidence has yet established this as a verified/reconstructed modern edition.'
  ) returning id into v_find_text;

  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note) values
    (v_loc_source,v_find_facsimile,'high','LOC item page explicitly exposes Complete PDF and 72 images.'),
    (v_loc_source,v_find_text,'high','LOC item page explicitly exposes Complete Text.');

  insert into wnph.recovery_gap_assessments(recovery_case_id,assessment_status,confidence,rationale)
  values (
    v_case,'preliminary','medium',
    'Digitization/material access is demonstrably present, but the existing-recovery audit is intentionally incomplete. No claim of a meaningful ebook, accessibility, audio, library, text-integrity, or illustration-recovery gap is yet authorized.'
  ) returning id into v_gap;

  insert into wnph.recovery_gap_dimensions(assessment_id,dimension,gap_state,score,critical,rationale)
  values (v_gap,'material_recovery','closed',0,false,'A complete LOC digital surrogate is available.') returning id into v_gap_material;
  insert into wnph.recovery_gap_dimensions(assessment_id,dimension,gap_state,score,critical,rationale)
  values (v_gap,'witness_recovery','closed',0,false,'A specifically identified surviving LOC Item and digital Surrogate are already in custody.') returning id into v_gap_witness;
  insert into wnph.recovery_gap_dimensions(assessment_id,dimension,gap_state,critical,rationale) values
    (v_gap,'text_recovery','unknown',false,'Complete online text exists, but verification/restoration quality has not yet been audited.'),
    (v_gap,'illustration_recovery','unknown',false,'Historical illustrations are digitized, but competent modern restoration/reuse has not yet been audited.'),
    (v_gap,'ebook_recovery','unknown',false,'Modern reflowable ebook availability has not yet been fully evidenced.'),
    (v_gap,'accessibility','unknown',false,'Accessibility recovery has not yet been fully audited.'),
    (v_gap,'audiobook','unknown',false,'Audiobook availability has not yet been fully audited.'),
    (v_gap,'library_access','unknown',false,'Modern library-distribution availability has not yet been fully audited.'),
    (v_gap,'translation','not_applicable',false,'Current evaluation is for the established English realization.'),
    (v_gap,'functional_translation','not_applicable',false,'Functional translation is outside the current children''s-book recovery scope.');

  insert into wnph.evidence_links(source_id,recovery_gap_dimension_id,confidence,note) values
    (v_loc_source,v_gap_material,'high','LOC complete digitization closes the basic material-access gap.'),
    (v_loc_source,v_gap_witness,'high','LOC Item and Surrogate establish surviving witness access.');

  insert into wnph.evidence_links(source_id,recovery_case_id,confidence,note)
  values (v_loc_source,v_case,'high','Primary source supporting the bounded Recovery Case intake.');

  insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (
    v_case,null,'IDENTITY_ESTABLISHED','state_transition',
    'Recovery Work inherits an established Historical Work and prior append-only Work-identity adjudication; discovery/identity research is not replayed inside the Recovery layer.',
    'wnph:dewy-recovery-empirical-pass-v1'
  ) returning id into v_event;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note)
  values (v_loc_source,v_event,'high','LOC evidence participates in the inherited Work identity basis.');

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (v_case,v_event,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition','Evaluate identified Item/Surrogate for the bounded recovery scope.','wnph:dewy-recovery-empirical-pass-v1')
  returning id into v_next_event;
  v_event := v_next_event;

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (v_case,v_event,'SOURCE_RESEARCH','SOURCE_SUFFICIENT','state_transition','Current LOC surrogate meets the Recovery Work sufficiency gate for continued qualification research; downstream page-level QC may still reopen this claim.','wnph:dewy-recovery-empirical-pass-v1')
  returning id into v_next_event;
  v_event := v_next_event;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note)
  values (v_loc_source,v_event,'high','LOC complete PDF/text/images support the SOURCE_SUFFICIENT transition.');

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (v_case,v_event,'SOURCE_SUFFICIENT','RIGHTS_RESEARCH','state_transition','Evaluate rights for the actual c1922 source components and provisional U.S. web/EPUB use.','wnph:dewy-recovery-empirical-pass-v1')
  returning id into v_next_event;
  v_event := v_next_event;

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (v_case,v_event,'RIGHTS_RESEARCH','RIGHTS_CLEARED','state_transition','Current component-specific U.S. determination clears the proposed evaluation scope while reserving non-U.S. and future third-party questions.','wnph:dewy-recovery-empirical-pass-v1')
  returning id into v_next_event;
  v_event := v_next_event;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note) values
    (v_usco_source,v_event,'high','Official U.S. copyright-duration guidance supports the RIGHTS_CLEARED gate.'),
    (v_loc_source,v_event,'high','LOC Rights & Access statement supports source-image reuse and public-domain status.');

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values (v_case,v_event,'RIGHTS_CLEARED','RECOVERY_AUDIT','state_transition','Begin governed audit of whether competent modern recoveries already close the proposed gaps.','wnph:dewy-recovery-empirical-pass-v1');
end $$;
