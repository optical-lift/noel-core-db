-- WNPH Satapatha Brahmana / Eggeling 1882 vessel-cleansing recovery qualification v1.
-- Append-only correction and recovery advancement for the exact Eggeling witness passage.
-- The immutable intake's pp. 68-71 shorthand is corrected by new evidence/briefing to pp. 67-71.
-- No passage text or source-surface asset is admitted here.

insert into wnph.evidence_sources(
  canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,
  rights_note,provenance_note,metadata
) values
(
  'internetarchive:satapathabrhma01eggeuoft:verified-item-metadata',
  'repository_item_metadata',
  'The Satapatha-brâhmana, according to the text of the Mâdhyandina school — Internet Archive item metadata',
  'Internet Archive',
  'https://archive.org/details/satapathabrhma01eggeuoft',
  'satapathabrhma01eggeuoft',now(),
  'Internet Archive marks the item NOT_IN_COPYRIGHT for the United States. WNPH separately treats the 1882 Eggeling translation and historical publication as public domain in the United States; repository presentation remains separately attributable.',
  'Direct item record for volume 1 / Part I: contributor Robarts - University of Toronto; call number AAB-1369; LCCN 32034308; Open Library edition OL6283265M; Open Library work OL16867708W; repository reports 552 pages; ARK ark:/13960/t3mw2fw2x.',
  jsonb_build_object(
    'manifestation_year',1882,
    'contributor','Robarts - University of Toronto',
    'call_number','AAB-1369',
    'repository_reported_pages',552,
    'possible_copyright_status','NOT_IN_COPYRIGHT',
    'copyright_region','US',
    'open_library_edition','OL6283265M',
    'open_library_work','OL16867708W',
    'lccn','32034308',
    'identifier_ark','ark:/13960/t3mw2fw2x',
    'recovery_locator_focus','Satapatha Brahmana I.3.1.1-11; printed pp. 67-71'
  )
),
(
  'sacred-texts:sbe12:1-3-1',
  'public_domain_transcription_access_derivative',
  'Satapatha Brahmana Part 1 (SBE12): I.3.1, Third Adhyaya, First Brahmana',
  'Internet Sacred Text Archive',
  'https://www.sacred-texts.com/hin/sbr/sbe12/sbe1212.htm',
  null,now(),
  'The underlying Julius Eggeling translation was published in 1882 and is public domain in the United States. This WNPH record does not assert rights in the modern website presentation.',
  'Modern HTML access transcription of Eggeling''s 1882 English translation, retained only as a locating/comparison derivative. It does not substitute for the governed Internet Archive page-image witness.',
  jsonb_build_object(
    'translation_year',1882,
    'translator','Julius Eggeling',
    'section','I.3.1',
    'role','comparison_transcription',
    'printed_page_span','67-71'
  )
)
on conflict(canonical_key) do nothing;

do $$
declare
  v_case uuid;
  v_work uuid;
  v_expression uuid;
  v_manifestation uuid;
  v_item uuid;
  v_surrogate uuid;
  v_ia_source uuid;
  v_ia_meta_source uuid;
  v_ol_source uuid;
  v_compare_source uuid;
  v_usco_source uuid;
  v_ssa uuid;
  v_member uuid;
  v_rights uuid;
  v_component uuid;
  v_audit uuid;
  v_finding_ia uuid;
  v_finding_compare uuid;
  v_condition uuid;
  v_obs uuid;
  v_brief uuid;
  v_mode uuid;
  v_decision uuid;
  v_primary_target uuid;
  v_preferred_target uuid;
  v_package uuid;
  v_root uuid;
  v_section uuid;
  v_stream uuid;
  v_leaf uuid;
begin
  select c.id,c.work_id into strict v_case,v_work
  from wnph.recovery_cases c
  where c.canonical_key='satapatha-brahmana:eggeling-part1-vessel-cleansing-recovery-1';

  select id into strict v_expression
  from wnph.expressions where canonical_key='satapatha-brahmana:eggeling-1882-en-part1-e1';

  select id into strict v_manifestation
  from wnph.manifestations where canonical_key='satapatha-brahmana:oxford-clarendon-sbe12-1882';

  select id into strict v_item
  from wnph.items where canonical_key='satapatha-brahmana:ia-satapathabrhma01eggeuoft';

  select id into strict v_surrogate
  from wnph.surrogates where canonical_key='satapatha-brahmana:ia-1882-part1-surrogate';

  select id into strict v_ia_source
  from wnph.evidence_sources where canonical_key='internetarchive:satapathabrhma01eggeuoft';

  select id into strict v_ia_meta_source
  from wnph.evidence_sources where canonical_key='internetarchive:satapathabrhma01eggeuoft:verified-item-metadata';

  select id into strict v_ol_source
  from wnph.evidence_sources where canonical_key='openlibrary:OL6283265M';

  select id into strict v_compare_source
  from wnph.evidence_sources where canonical_key='sacred-texts:sbe12:1-3-1';

  select id into strict v_usco_source
  from wnph.evidence_sources where canonical_key='us-copyright-office:circular-15a:2026';

  -- Add direct item/surrogate evidence rather than mutating the immutable intake evidence.
  insert into wnph.evidence_links(source_id,item_id,confidence,note)
  values(v_ia_meta_source,v_item,'high',
    'Direct Internet Archive metadata establishes contributor Robarts - University of Toronto, call number AAB-1369, repository identifier and related catalog IDs for the represented copy.');

  insert into wnph.evidence_links(source_id,surrogate_id,confidence,note)
  values(v_ia_meta_source,v_surrogate,'high',
    'Direct Internet Archive metadata establishes the repository digitization, reported 552-page extent and NOT_IN_COPYRIGHT U.S. status. Exact scan-image mapping for printed pp. 67-71 remains separately unresolved.');

  -- SOURCE SUFFICIENCY.
  insert into wnph.source_sufficiency_assessments(
    recovery_case_id,result,confidence,rationale,recorded_by
  ) values(
    v_case,'sufficient','high',
    'The identified 1882 Part I Internet Archive witness exposes page images, PDF and OCR/full-text derivatives; Open Library independently supplies the edition identity. The source text itself identifies the cleaning-of-spoons unit as beginning on printed p. 67 and continuing through p. 71. This is sufficient for exact-witness recovery research, while exact scan-image-to-printed-page mapping remains mandatory before canonical reading admission.',
    'wnph:satapatha-vessel-cleansing-qualification-v1'
  ) returning id into v_ssa;

  insert into wnph.source_sufficiency_members(
    assessment_id,surrogate_id,source_role,completeness,quality,
    provenance_status,member_result,missing_or_damage_note,notes
  ) values(
    v_ssa,v_surrogate,'primary','substantially_complete','usable','sufficient','usable',
    'Exact Internet Archive scan-image identifiers for printed pp. 67-71 have not yet been fixed in WNPH source-surface custody.',
    'The repository witness is sufficient to continue recovery. Sufficiency does not waive page-image verification or authorize OCR/transcription promotion.'
  ) returning id into v_member;

  insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
  values(v_ia_meta_source,v_ssa,'high','Direct Internet Archive item metadata and access options support source sufficiency.');
  insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
  values(v_ol_source,v_ssa,'high','Open Library independently supports edition identity and Internet Archive linkage.');
  insert into wnph.evidence_links(source_id,source_sufficiency_member_id,confidence,note)
  values(v_ia_source,v_member,'high','The Internet Archive page-image surrogate is the governed primary recovery member.');
  insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
  values(v_compare_source,v_ssa,'medium','Sacred Texts corroborates paragraph and printed-page sequence but remains comparison material only.');

  -- U.S. RIGHTS.
  insert into wnph.rights_determinations(
    recovery_case_id,jurisdiction,overall_status,confidence,rationale,determined_by
  ) values(
    v_case,'US','cleared','high',
    'The ancient Śatapatha Brāhmaṇa is public-domain source material. Julius Eggeling''s English translation and the Clarendon Press Part I manifestation were published in 1882, and Eggeling died in 1918. They are public domain in the United States. Internet Archive additionally marks the governed digitized item NOT_IN_COPYRIGHT for the U.S. WNPH records these facts without claiming ownership of repository presentation or later third-party editorial matter.',
    'wnph:satapatha-vessel-cleansing-qualification-v1'
  ) returning id into v_rights;

  insert into wnph.rights_components(
    determination_id,component_type,component_status,work_id,use_scope,rationale
  ) values(
    v_rights,'underlying_work','public_domain',v_work,
    'U.S. source-faithful recovery and WNPH-derived scholarly/semantic editions',
    'The underlying Vedic Work is ancient and outside modern copyright.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_ol_source,v_component,'high',
    'Open Library attests the ancient Work/1882 edition lineage while WNPH keeps the Work distinct from the translation.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,expression_id,use_scope,rationale
  ) values(
    v_rights,'prior_translation','public_domain',v_expression,
    'U.S. recovery, transcription, publication and transformation of Eggeling''s 1882 English translation Expression',
    'Eggeling''s English translation was published in 1882. Current U.S. duration guidance places publications this old in the public domain; Eggeling died in 1918.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_usco_source,v_component,'high','Current U.S. Copyright Office duration guidance supports public-domain status by publication age.');
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_ol_source,v_component,'high','Open Library attests the 1882 English translation publication.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,manifestation_id,use_scope,rationale
  ) values(
    v_rights,'editorial_apparatus','public_domain',v_manifestation,
    'U.S. use of the 1882 title matter, footnotes and historical editorial presentation as source material',
    'The governed historical manifestation and its contemporary editorial matter were published in 1882.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_ol_source,v_component,'high','Open Library attests the 1882 Clarendon Press manifestation.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,surrogate_id,use_scope,rationale
  ) values(
    v_rights,'source_images','reuse_permitted',v_surrogate,
    'Use of governed Internet Archive page images as recovery/verification inputs',
    'Internet Archive marks the item NOT_IN_COPYRIGHT for the U.S. and exposes the digitized source for download. WNPH records source-image reuse evidence without claiming copyright ownership in the repository scan or interface.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_ia_meta_source,v_component,'high',
    'Direct Internet Archive item metadata supplies NOT_IN_COPYRIGHT and U.S. copyright-region evidence.');

  -- BOUNDED EXISTING-RECOVERY AUDIT.
  insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note)
  values(
    v_case,'complete',
    'Bounded audit completed for Eggeling 1882 Part I I.3.1.1-11. A full Internet Archive facsimile/OCR channel and a modern Sacred Texts HTML transcription already exist. The recovery condition is therefore not general availability; it is the absence inside WNPH of a page-image-verified, source-linked passage object whose historical wording and later functional-semantic interpretation remain separately governed.'
  ) returning id into v_audit;

  insert into wnph.existing_recovery_findings(
    audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes
  ) values(
    v_audit,'internet_archive','present','FACSIMILE','raw','satapathabrhma01eggeuoft',
    'Internet Archive exposes the 1882 Part I witness with page images, PDF and OCR/full text. The repository reports 552 pages. This is material access, not WNPH source-surface verification.'
  ) returning id into v_finding_ia;
  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
  values(v_ia_meta_source,v_finding_ia,'high','Direct repository record supports facsimile/OCR availability.');

  insert into wnph.existing_recovery_findings(
    audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes
  ) values(
    v_audit,'other','present','SEARCHABLE_TEXT','competent','Internet Sacred Text Archive SBE12 I.3.1',
    'A readable HTML transcription of Eggeling''s translation exists and preserves paragraph and printed-page cues. It is useful comparison/access material but is not substituted for the governed page-image witness.'
  ) returning id into v_finding_compare;
  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
  values(v_compare_source,v_finding_compare,'high','Sacred Texts directly supplies the accessible comparison transcription.');

  select e.id into strict v_leaf
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
  if (select to_state from wnph.recovery_case_events where id=v_leaf)<>'SOURCE_RESEARCH' then
    raise exception 'Satapatha qualification expected SOURCE_RESEARCH leaf';
  end if;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_leaf,'SOURCE_RESEARCH','RECOVERY_AUDIT','state_transition',
    'Source identity, U.S. rights, source sufficiency and bounded access channels are now recorded. Continue by evaluating the narrow source-linked recovery condition rather than claiming the text is unavailable.',
    'wnph:satapatha-vessel-cleansing-qualification-v1',false
  ) returning id into v_leaf;

  -- CONDITION ASSESSMENT.
  insert into wnph.recovery_condition_assessments(
    recovery_case_id,assessment_status,scope_note,confidence
  ) values(
    v_case,'bounded_complete',
    'Recovery condition for the exact Eggeling 1882 Part I I.3.1.1-11 witness, with corrected printed-page span 67-71, separated both from the ancient Sanskrit/Mādhyandina Work and from generic modern web access.',
    'high'
  ) returning id into v_condition;

  insert into wnph.recovery_condition_observations(
    assessment_id,condition_type_id,condition_state,epistemic_status,
    expression_id,manifestation_id,item_id,surrogate_id,observation_text,confidence
  )
  select
    v_condition,t.id,x.state,x.epistemic,
    case when x.target_kind='expression' then v_expression else null end,
    case when x.target_kind='manifestation' then v_manifestation else null end,
    case when x.target_kind='item' then v_item else null end,
    case when x.target_kind='surrogate' then v_surrogate else null end,
    x.observation_text,x.confidence
  from (values
    ('digital_facsimile_survival'::text,'adequate'::text,'evidence'::text,'surrogate'::text,
      'The governed 1882 Part I witness survives as an Internet Archive digitization with page-image, PDF and OCR access; the repository reports 552 pages.'::text,'high'::text),
    ('identified_surviving_witness','adequate','evidence','item',
      'The governed item is specifically identified as Internet Archive satapathabrhma01eggeuoft, contributed by Robarts - University of Toronto, call number AAB-1369.','high'),
    ('library_access','adequate','evidence','manifestation',
      'Open Library and Internet Archive provide stable public bibliographic and digital access to the 1882 witness.','high'),
    ('modern_reading_edition','adequate','evidence','expression',
      'A readable HTML transcription of Eggeling''s 1882 translation is publicly available through Sacred Texts, so ordinary reading access is not the recovery gap.','high'),
    ('reflowable_ebook_availability','adequate','evidence','expression',
      'The Eggeling text is already accessible as searchable/reflowable web text; WNPH is not qualifying this recovery on ebook absence.','high'),
    ('text_integrity','unverified','evidence','surrogate',
      'WNPH has not yet fixed the exact Internet Archive scan-image identifiers for printed pp. 67-71 or verified each passage reading against those images. OCR/web-transcription availability therefore does not satisfy WNPH canonical-text custody.','high'),
    ('edition_relationship_clarity','adequate','interpretation','expression',
      'The qualified object can be cleanly bounded as Eggeling''s 1882 English Part I translation Expression. It must remain distinct from the ancient Sanskrit/Mādhyandina Work and from later translations or editions.','high'),
    ('accessibility','adequate','interpretation','expression',
      'The passage is readily accessible to readers online. WNPH recovery value lies in source-linked custody and semantic addressability, not basic discoverability.','high'),
    ('modern_recovery_adequacy','limited','interpretation','expression',
      'Generic access is adequate, but no WNPH object yet binds this exact passage to verified source surfaces while preserving the domestic-vessel analogy, ritual actions, formulae, directionality and disposal sequence as separately queryable source-grounded structure.','high')
  ) as x(type_key,state,epistemic,target_kind,observation_text,confidence)
  join wnph.recovery_condition_types t on t.canonical_key=x.type_key and t.status='active';

  insert into wnph.evidence_links(source_id,recovery_condition_observation_id,confidence,note)
  select
    case
      when t.canonical_key in ('modern_reading_edition','reflowable_ebook_availability') then v_compare_source
      when t.canonical_key in ('digital_facsimile_survival','identified_surviving_witness','library_access','text_integrity') then v_ia_meta_source
      else v_ol_source
    end,
    o.id,o.confidence,
    'Evidence supporting the bounded Satapatha recovery-condition observation.'
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_types t on t.id=o.condition_type_id
  where o.assessment_id=v_condition and o.epistemic_status='evidence';

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_leaf,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition',
    'The bounded audit shows competent public access but a narrower WNPH source-custody gap: the exact pp. 67-71 witness has not yet been source-image verified or made semantically addressable without collapsing translation and ancient Work.',
    'wnph:satapatha-vessel-cleansing-qualification-v1',false
  ) returning id into v_leaf;

  -- Active brief corrects the immutable intake's pp. 68-71 shorthand.
  insert into wnph.recovery_case_briefs(
    recovery_case_id,scope_note,why_recover,proposed_expression_type,priority
  ) values(
    v_case,
    'Recover Eggeling 1882 Part I I.3.1.1-11, printed pp. 67-71, as a page-image-verified witness passage. Preserve paragraph order, historical terminology, footnote boundaries and the explicit household-vessel comparison. Any modern functional classification such as cleansing, food-service preparation, protective formula, directional action or disposal rule must live downstream as derived semantics rather than replacing the source wording.',
    'The passage is already publicly readable, but WNPH lacks a governed source-linked object that can support later discovery by function without forcing a modern genre label onto the ancient ritual sequence. Recovering this narrow witness adds provenance and semantic addressability rather than duplicating an ordinary ebook.',
    'verified_1882_translation_witness_passage','high'
  ) returning id into v_brief;

  -- Commit the already-proposed text/transcription/witness modes by supersession.
  for v_mode in
    select m.id
    from wnph.recovery_case_modes m
    where m.recovery_case_id=v_case
      and m.recovery_mode in ('text','transcription','witness')
      and m.intent_status='proposed'
      and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
  loop
    insert into wnph.recovery_case_modes(
      recovery_case_id,recovery_mode,intent_status,rationale,supersedes_mode_id
    )
    select
      recovery_case_id,recovery_mode,'committed',
      case recovery_mode
        when 'text' then 'Recover the complete I.3.1.1-11 cleaning-of-spoons unit before extracting functional claims.'
        when 'transcription' then 'Verify Eggeling''s English wording directly against the governed 1882 page images with exact printed-page/source-surface locators.'
        else 'Preserve the 1882 Part I translation witness as its own historical Expression; do not silently substitute Sanskrit or later English readings.'
      end,
      id
    from wnph.recovery_case_modes where id=v_mode;
  end loop;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_leaf,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition',
    'Review whether the narrow page-image-verified Eggeling witness passage adds WNPH value despite competent generic public access.',
    'wnph:satapatha-vessel-cleansing-qualification-v1',false
  ) returning id into v_leaf;

  -- QUALIFICATION DECISION.
  insert into wnph.recovery_decisions(
    recovery_case_id,decision_outcome,decision_scope,decision_summary
  ) values(
    v_case,'qualify',
    'Qualify only a source-linked verified recovery of Eggeling 1882 Part I I.3.1.1-11, printed pp. 67-71, and the later source-grounded semantic representation of that passage. Do not qualify a generic new ebook, do not claim the Work is unavailable, do not treat Eggeling''s English as the Sanskrit text, and do not admit OCR or modern web transcription as canonical without page-image verification.',
    'Public access is already competent: Internet Archive supplies the facsimile/OCR and Sacred Texts supplies readable HTML. WNPH nevertheless has a distinct narrow recovery condition because its corpus must support function-first discovery across historical categories while retaining exact source custody. The passage explicitly connects ordinary human vessel-rinsing and food service to a ritual cleaning sequence containing formulae, directionality and disposal rules. That connection is worth recovering as a verified witness object, but the modern functional reading must remain derived and reversible to the 1882 source surfaces.'
  ) returning id into v_decision;

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note
  ) values(v_decision,'supports',v_ssa,
    'The governed 1882 witness is sufficient for exact-passage recovery while keeping page-image verification mandatory.');

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,rights_determination_id,basis_note
  ) values(v_decision,'supports',v_rights,
    'U.S. rights are cleared for the ancient Work, Eggeling translation, historical manifestation and source-image recovery inputs.');

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note
  ) values(v_decision,'limits',v_audit,
    'Generic public access is already competent, so qualification is restricted to source-linked custody and functionally addressable recovery rather than ordinary republication.');

  select o.id into strict v_obs
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_types t on t.id=o.condition_type_id
  where o.assessment_id=v_condition and t.canonical_key='text_integrity'
    and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note
  ) values(v_decision,'supports',v_obs,
    'The unresolved exact source-surface verification is the concrete text-integrity condition this recovery must solve.');

  select o.id into strict v_obs
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_types t on t.id=o.condition_type_id
  where o.assessment_id=v_condition and t.canonical_key='edition_relationship_clarity'
    and not exists(select 1 from wnph.recovery_condition_observations n where n.supersedes_observation_id=o.id);
  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note
  ) values(v_decision,'limits',v_obs,
    'The recovered object must remain explicitly the Eggeling 1882 English Expression and may not be represented as the ancient Sanskrit Work itself.');

  insert into wnph.recovery_decision_plan_members(
    recovery_decision_id,member_role,recovery_case_brief_id
  ) values(v_decision,'scope',v_brief);

  insert into wnph.recovery_decision_plan_members(
    recovery_decision_id,member_role,recovery_case_mode_id
  )
  select v_decision,'mode',m.id
  from wnph.recovery_case_modes m
  where m.recovery_case_id=v_case
    and m.intent_status='committed'
    and m.recovery_mode in ('text','transcription','witness')
    and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id);

  select t.id into strict v_primary_target
  from wnph.recovery_case_targets t
  where t.recovery_case_id=v_case
    and t.target_role='primary_source'
    and t.surrogate_id=v_surrogate
    and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id);

  insert into wnph.recovery_decision_plan_members(
    recovery_decision_id,member_role,recovery_case_target_id
  ) values(v_decision,'source_target',v_primary_target);

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_leaf,'DECISION_REVIEW','QUALIFIED','decision',
    'Qualify the exact Eggeling 1882 pp. 67-71 witness passage for source-linked recovery. Ordinary public access already exists; the qualified value is verified source custody plus separately governed functional semantics.',
    'wnph:satapatha-vessel-cleansing-qualification-v1',false
  ) returning id into v_leaf;

  -- EXPLICIT SELECTION.
  insert into wnph.recovery_case_targets(
    recovery_case_id,target_role,surrogate_id,rationale
  ) values(
    v_case,'preferred_source',v_surrogate,
    'Preferred historical recovery source for the qualified Eggeling 1882 passage. Exact source-surface identifiers for printed pp. 67-71 remain a blocking verification task.'
  ) returning id into v_preferred_target;

  insert into wnph.publication_source_packages(
    canonical_key,recovery_case_id,expression_id,qualifying_decision_id,
    package_role,source_model,model_version,package_status,render_contract,notes
  ) values(
    'satapatha-brahmana:eggeling-1882-part1-i-3-1-canonical-source:v1',
    v_case,v_expression,v_decision,
    'canonical_master','semantic_single_source','1','planned',
    jsonb_build_object(
      'single_source_publishing',true,
      'manifestation_agnostic',true,
      'expression_identity','Eggeling 1882 English translation, Part I',
      'printed_page_span','67-71',
      'source_surface_assets_required_before_text_admission',true,
      'functional_semantics_separate_from_source_text',true,
      'ancient_work_may_not_be_collapsed_into_translation',true,
      'supported_by_design',jsonb_build_array(
        'responsive_web','reflowable_epub','print_pdf','paperback','future_output_families'
      ),
      'renderer_rule',
      'Renderers may change presentation but may not modernize, normalize, translate, or replace Eggeling''s governed source wording. Derived function-first labels remain separate semantic objects and must retain source-span provenance.'
    ),
    'Canonical source package for the selected I.3.1.1-11 witness recovery. It begins with structure only. No OCR, Sacred Texts wording, remembered quotation, or semantic paraphrase is canonical text until the exact Internet Archive source surfaces for printed pp. 67-71 are identified and verified.'
  ) returning id into v_package;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_leaf,'QUALIFIED','SELECTED_FOR_RECOVERY','selection',
    'Select the exact Eggeling 1882 I.3.1.1-11 witness recovery and its manifestation-agnostic canonical source package. Selection authorizes source-surface recovery work only; passage text remains blocked until printed pp. 67-71 are mapped to exact Internet Archive page images and verified.',
    'wnph:satapatha-vessel-cleansing-qualification-v1',true
  ) returning id into v_leaf;

  -- STRUCTURE-ONLY SOURCE PACKET.
  insert into wnph.publication_source_blocks(
    source_package_id,block_key,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'satapatha-eggeling1882:i-3-1:document',0,'document','book_root',
    jsonb_build_object('translation_year',1882,'part','I','books','I-II'),
    jsonb_build_object(
      'structure_authority','governed_1882_witness',
      'source_surrogate_key','satapatha-brahmana:ia-1882-part1-surrogate'
    )
  ) returning id into v_root;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'satapatha-eggeling1882:i-3-1:section',v_root,1,'section','cleaning_of_spoons',
    jsonb_build_object(
      'canonical_section_locator','I.3.1',
      'printed_page_start',67,
      'printed_page_end',71,
      'paragraph_start',1,
      'paragraph_end',11,
      'source_surface_mapping_complete',false
    ),
    jsonb_build_object(
      'structure_authority','1882_contents_and_printed_page_headers',
      'comparison_transcription_key','sacred-texts:sbe12:1-3-1'
    )
  ) returning id into v_section;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'satapatha-eggeling1882:i-3-1:reading-stream',v_section,1,'reading_stream','witness_passage',
    jsonb_build_object(
      'printed_page_span','67-71',
      'paragraph_span','1-11',
      'completion',false,
      'blocked_on','exact Internet Archive scan-image mapping and page-image verification'
    ),
    jsonb_build_object(
      'text_authority','none_yet',
      'ocr_role','locating_aid_only',
      'modern_transcription_role','comparison_only',
      'canonical_text_admitted',false
    )
  ) returning id into v_stream;
end $$;
