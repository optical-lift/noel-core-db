-- WNPH Satapatha Brahmana / Eggeling 1882 vessel-cleansing recovery qualification v1.
-- Append-only correction: the immutable intake shorthand pp. 68-71 is superseded
-- by governed evidence/briefing establishing I.3.1.1-11 on printed pp. 67-71.
-- This migration qualifies and selects the exact Eggeling witness passage.
-- It admits no passage text and no source-surface image asset.

insert into wnph.evidence_sources(
  canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,
  rights_note,provenance_note,metadata
) values
(
  'internetarchive:satapathabrhma01eggeuoft:verified-item-metadata',
  'repository_item_metadata',
  'The Satapatha-brâhmana — Internet Archive item metadata',
  'Internet Archive',
  'https://archive.org/details/satapathabrhma01eggeuoft',
  'satapathabrhma01eggeuoft',now(),
  'Internet Archive marks this item NOT_IN_COPYRIGHT for the United States.',
  'Volume 1 / Part I item record: contributor Robarts - University of Toronto; call number AAB-1369; LCCN 32034308; Open Library edition OL6283265M; Open Library work OL16867708W; repository reports 552 pages; ARK ark:/13960/t3mw2fw2x.',
  jsonb_build_object(
    'manifestation_year',1882,'contributor','Robarts - University of Toronto',
    'call_number','AAB-1369','repository_reported_pages',552,
    'possible_copyright_status','NOT_IN_COPYRIGHT','copyright_region','US',
    'open_library_edition','OL6283265M','open_library_work','OL16867708W',
    'lccn','32034308','identifier_ark','ark:/13960/t3mw2fw2x',
    'recovery_locator_focus','I.3.1.1-11; printed pp. 67-71'
  )
),
(
  'sacred-texts:sbe12:1-3-1',
  'public_domain_transcription_access_derivative',
  'Satapatha Brahmana Part 1 (SBE12): I.3.1',
  'Internet Sacred Text Archive',
  'https://www.sacred-texts.com/hin/sbr/sbe12/sbe1212.htm',
  null,now(),
  'The underlying Eggeling 1882 translation is public domain in the United States. No rights claim is made here about the modern website presentation.',
  'Modern HTML access transcription used only as a locating/comparison derivative, never as a substitute for the governed Internet Archive page-image witness.',
  jsonb_build_object('translation_year',1882,'translator','Julius Eggeling',
                     'section','I.3.1','role','comparison_transcription',
                     'printed_page_span','67-71')
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
  v_ia uuid;
  v_meta uuid;
  v_ol uuid;
  v_compare uuid;
  v_usco uuid;
  v_ssa uuid;
  v_ssm uuid;
  v_rights uuid;
  v_component uuid;
  v_audit_open uuid;
  v_audit uuid;
  v_finding uuid;
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
  v_leaf uuid;
begin
  select c.id,c.work_id into strict v_case,v_work
  from wnph.recovery_cases c
  where c.canonical_key='satapatha-brahmana:eggeling-part1-vessel-cleansing-recovery-1';

  select id into strict v_expression from wnph.expressions
  where canonical_key='satapatha-brahmana:eggeling-1882-en-part1-e1';
  select id into strict v_manifestation from wnph.manifestations
  where canonical_key='satapatha-brahmana:oxford-clarendon-sbe12-1882';
  select id into strict v_item from wnph.items
  where canonical_key='satapatha-brahmana:ia-satapathabrhma01eggeuoft';
  select id into strict v_surrogate from wnph.surrogates
  where canonical_key='satapatha-brahmana:ia-1882-part1-surrogate';

  select id into strict v_ia from wnph.evidence_sources
  where canonical_key='internetarchive:satapathabrhma01eggeuoft';
  select id into strict v_meta from wnph.evidence_sources
  where canonical_key='internetarchive:satapathabrhma01eggeuoft:verified-item-metadata';
  select id into strict v_ol from wnph.evidence_sources
  where canonical_key='openlibrary:OL6283265M';
  select id into strict v_compare from wnph.evidence_sources
  where canonical_key='sacred-texts:sbe12:1-3-1';
  select id into strict v_usco from wnph.evidence_sources
  where canonical_key='us-copyright-office:circular-15a:2026';

  insert into wnph.evidence_links(source_id,item_id,confidence,note)
  values(v_meta,v_item,'high','Direct IA metadata identifies the represented Robarts copy and call number AAB-1369.');
  insert into wnph.evidence_links(source_id,surrogate_id,confidence,note)
  values(v_meta,v_surrogate,'high','Direct IA metadata identifies the governed digitization and reports 552 pages; exact scan-image mapping for printed pp. 67-71 remains unresolved.');

  -- Source sufficiency.
  insert into wnph.source_sufficiency_assessments(
    recovery_case_id,result,confidence,rationale,recorded_by
  ) values(
    v_case,'sufficient','high',
    'The 1882 Part I Internet Archive witness provides page-image/PDF/OCR access and Open Library independently establishes edition identity. Printed-page evidence fixes I.3.1.1-11 at pp. 67-71. Exact scan-image IDs still must be verified before canonical text admission.',
    'wnph:satapatha-vessel-cleansing-qualification-v1'
  ) returning id into v_ssa;

  insert into wnph.source_sufficiency_members(
    assessment_id,surrogate_id,source_role,completeness,quality,provenance_status,
    member_result,missing_or_damage_note,notes
  ) values(
    v_ssa,v_surrogate,'primary','substantially_complete','usable','sufficient',
    'usable','Exact scan-image IDs for printed pp. 67-71 are not yet fixed.',
    'Sufficient to continue governed recovery; not sufficient to bypass page-image verification.'
  ) returning id into v_ssm;

  insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
  values(v_meta,v_ssa,'high','Direct repository metadata/access support source sufficiency.');
  insert into wnph.evidence_links(source_id,source_sufficiency_assessment_id,confidence,note)
  values(v_ol,v_ssa,'high','Open Library independently supports edition identity.');
  insert into wnph.evidence_links(source_id,source_sufficiency_member_id,confidence,note)
  values(v_ia,v_ssm,'high','The governed IA surrogate is the primary source member.');

  -- U.S. rights.
  insert into wnph.rights_determinations(
    recovery_case_id,jurisdiction,overall_status,confidence,rationale,determined_by
  ) values(
    v_case,'US','cleared','high',
    'The underlying Śatapatha Brāhmaṇa is ancient. Eggeling''s English translation and this Clarendon Press Part I publication date to 1882; Eggeling died in 1918. The historical Work/translation/publication are public domain in the United States. Internet Archive also marks the governed item NOT_IN_COPYRIGHT for the U.S.',
    'wnph:satapatha-vessel-cleansing-qualification-v1'
  ) returning id into v_rights;

  insert into wnph.rights_components(
    determination_id,component_type,component_status,work_id,use_scope,rationale
  ) values(v_rights,'underlying_work','public_domain',v_work,
    'U.S. source-faithful recovery and derived scholarly/semantic editions',
    'Ancient underlying Work.') returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_ol,v_component,'high','Bibliographic evidence keeps the ancient Work distinct from the 1882 translation.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,expression_id,use_scope,rationale
  ) values(v_rights,'prior_translation','public_domain',v_expression,
    'U.S. recovery and publication of Eggeling''s 1882 English translation Expression',
    'Published 1882; Eggeling died 1918.') returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_usco,v_component,'high','Official U.S. duration guidance supports public-domain status.');
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_ol,v_component,'high','Open Library attests the 1882 English manifestation.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,surrogate_id,use_scope,rationale
  ) values(v_rights,'source_images','reuse_permitted',v_surrogate,
    'Use of IA page images as recovery/verification inputs',
    'Internet Archive marks the item NOT_IN_COPYRIGHT for the U.S.; WNPH claims no ownership in repository presentation.') returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,confidence,note)
  values(v_meta,v_component,'high','Direct IA rights metadata.');

  -- Open the bounded audit before entering RECOVERY_AUDIT.
  insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note)
  values(v_case,'in_progress',
    'Bounded audit of existing Eggeling 1882 Part I facsimile and transcription access; no meaningful-gap claim yet.')
  returning id into v_audit_open;

  -- Exact state membrane.
  select e.id into strict v_leaf from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);
  if (select to_state from wnph.recovery_case_events where id=v_leaf)<>'SOURCE_RESEARCH' then
    raise exception 'Satapatha expected SOURCE_RESEARCH leaf';
  end if;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'SOURCE_RESEARCH','SOURCE_SUFFICIENT','state_transition',
    'The governed 1882 source is sufficient for continued recovery research; exact page-image verification remains mandatory.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note)
  values(v_meta,v_leaf,'high','Direct repository evidence supports the SOURCE_SUFFICIENT gate.');

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'SOURCE_SUFFICIENT','RIGHTS_RESEARCH','state_transition',
    'Evaluate component-specific U.S. rights for the ancient Work, Eggeling translation and source-image recovery input.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'RIGHTS_RESEARCH','RIGHTS_CLEARED','state_transition',
    'U.S. rights are cleared for the bounded recovery inputs.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note)
  values(v_usco,v_leaf,'high','Official U.S. duration guidance supports RIGHTS_CLEARED.');
  insert into wnph.evidence_links(source_id,recovery_case_event_id,confidence,note)
  values(v_meta,v_leaf,'high','IA item rights metadata supports RIGHTS_CLEARED.');

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'RIGHTS_CLEARED','RECOVERY_AUDIT','state_transition',
    'Begin governed comparison of the surviving facsimile and public transcription. Existing access does not itself settle WNPH recovery value.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;

  -- Complete bounded audit and record the actual recovery gap.
  insert into wnph.existing_recovery_audits(
    recovery_case_id,audit_status,scope_note,supersedes_audit_id
  ) values(
    v_case,'complete',
    'Internet Archive already supplies the 1882 facsimile/OCR, and Sacred Texts supplies readable HTML. The remaining WNPH gap is not access: it is an exact page-image-verified, source-linked passage object whose later functional semantics remain distinct from the historical wording.',
    v_audit_open
  ) returning id into v_audit;

  insert into wnph.existing_recovery_findings(
    audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes
  ) values(
    v_audit,'internet_archive','present','FACSIMILE','raw','satapathabrhma01eggeuoft',
    'Facsimile, PDF and OCR/full-text channels exist; WNPH source-surface verification remains open.'
  ) returning id into v_finding;
  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
  values(v_meta,v_finding,'high','Direct IA item evidence.');

  insert into wnph.existing_recovery_findings(
    audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes
  ) values(
    v_audit,'other','present','SEARCHABLE_TEXT','competent','Internet Sacred Text Archive SBE12 I.3.1',
    'Readable HTML of Eggeling''s translation exists and preserves paragraph/page cues; comparison only.'
  ) returning id into v_finding;
  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
  values(v_compare,v_finding,'high','Public comparison transcription.');

  insert into wnph.recovery_condition_assessments(
    recovery_case_id,assessment_status,scope_note,confidence
  ) values(
    v_case,'bounded_complete',
    'Condition of the exact Eggeling 1882 I.3.1.1-11 witness, corrected to printed pp. 67-71 and kept distinct from the ancient Sanskrit/Mādhyandina Work.',
    'high'
  ) returning id into v_condition;

  insert into wnph.recovery_condition_observations(
    assessment_id,condition_type_id,condition_state,epistemic_status,
    expression_id,item_id,surrogate_id,observation_text,confidence
  )
  select v_condition,t.id,x.state,x.epistemic,
         case when x.target_kind='expression' then v_expression else null end,
         case when x.target_kind='item' then v_item else null end,
         case when x.target_kind='surrogate' then v_surrogate else null end,
         x.text,x.confidence
  from (values
    ('identified_surviving_witness'::text,'adequate'::text,'evidence'::text,'item'::text,
      'Specific Robarts/University of Toronto copy identified as IA satapathabrhma01eggeuoft, call number AAB-1369.'::text,'high'::text),
    ('digital_facsimile_survival','adequate','evidence','surrogate',
      'The 1882 Part I witness survives digitally with page-image/PDF/OCR access.','high'),
    ('modern_reading_edition','adequate','evidence','expression',
      'A readable public HTML transcription exists; ordinary reading access is not the gap.','high'),
    ('text_integrity','unverified','evidence','surrogate',
      'Exact IA scan-image identifiers for printed pp. 67-71 are not yet fixed and the passage has not yet been verified image-by-image in WNPH.','high'),
    ('edition_relationship_clarity','adequate','interpretation','expression',
      'The recoverable object is Eggeling''s 1882 English Expression, not the Sanskrit Work itself.','high'),
    ('modern_recovery_adequacy','limited','interpretation','expression',
      'Generic access is adequate, but WNPH lacks source-linked page verification plus separately governed function-first semantics for this passage.','high')
  ) as x(type_key,state,epistemic,target_kind,text,confidence)
  join wnph.recovery_condition_types t on t.canonical_key=x.type_key and t.status='active';

  insert into wnph.evidence_links(source_id,recovery_condition_observation_id,confidence,note)
  select case
           when t.canonical_key='modern_reading_edition' then v_compare
           else v_meta
         end,
         o.id,o.confidence,'Evidence for bounded Satapatha recovery condition.'
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_types t on t.id=o.condition_type_id
  where o.assessment_id=v_condition and o.epistemic_status='evidence';

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition',
    'Public access is competent, but exact source-image text integrity is unverified and the function-first source-linked object does not yet exist.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;

  -- Current brief supersedes the immutable intake shorthand by governing the recovery scope.
  insert into wnph.recovery_case_briefs(
    recovery_case_id,scope_note,why_recover,proposed_expression_type,priority
  ) values(
    v_case,
    'Recover Eggeling 1882 Part I I.3.1.1-11, printed pp. 67-71, as a page-image-verified witness passage. Preserve paragraph order, historical terminology, footnote boundaries, the explicit household-vessel comparison, formulae, directionality and disposal sequence. Modern labels such as cleansing, food-service preparation, protective formula or disposal rule must remain downstream derived semantics.',
    'The passage is already readable online. WNPH recovery adds provenance and function-first semantic addressability without forcing a modern genre label onto the historical source.',
    'verified_1882_translation_witness_passage','high'
  ) returning id into v_brief;

  for v_mode in
    select m.id from wnph.recovery_case_modes m
    where m.recovery_case_id=v_case
      and m.recovery_mode in ('text','transcription','witness')
      and m.intent_status='proposed'
      and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
  loop
    insert into wnph.recovery_case_modes(
      recovery_case_id,recovery_mode,intent_status,rationale,supersedes_mode_id
    )
    select recovery_case_id,recovery_mode,'committed',
      case recovery_mode
        when 'text' then 'Recover the whole I.3.1.1-11 unit before functional extraction.'
        when 'transcription' then 'Verify Eggeling wording directly against governed 1882 page images.'
        else 'Preserve the 1882 translation witness distinctly from Sanskrit and later English witnesses.'
      end,
      id
    from wnph.recovery_case_modes where id=v_mode;
  end loop;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition',
    'Review the narrow source-linked recovery value, not generic ebook availability.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;

  insert into wnph.recovery_decisions(
    recovery_case_id,decision_outcome,decision_scope,decision_summary
  ) values(
    v_case,'qualify',
    'Qualify only the source-linked recovery of Eggeling 1882 Part I I.3.1.1-11, printed pp. 67-71, plus later derived semantics with source-span provenance. Do not qualify generic republication, do not treat Eggeling as Sanskrit, and do not admit OCR/web text canonically before page-image verification.',
    'Facsimile and readable HTML already exist. The distinct WNPH value is a verified witness object that preserves the text''s explicit analogy between ordinary human vessel-rinsing/food service and a ritual cleaning sequence with formulae, directionality and disposal rules, while keeping any modern functional interpretation reversible to the historical source.'
  ) returning id into v_decision;

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note
  ) values(v_decision,'supports',v_ssa,'Source is sufficient for exact-witness recovery.');
  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,rights_determination_id,basis_note
  ) values(v_decision,'supports',v_rights,'U.S. rights are cleared.');
  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note
  ) values(v_decision,'limits',v_audit,'Generic access already exists; recovery is therefore narrowly scoped.');

  select o.id into strict v_obs
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_types t on t.id=o.condition_type_id
  where o.assessment_id=v_condition and t.canonical_key='text_integrity';
  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note
  ) values(v_decision,'supports',v_obs,'Exact source-surface verification is the concrete unresolved condition.');

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
  where t.recovery_case_id=v_case and t.target_role='primary_source'
    and t.surrogate_id=v_surrogate
    and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id);
  insert into wnph.recovery_decision_plan_members(
    recovery_decision_id,member_role,recovery_case_target_id
  ) values(v_decision,'source_target',v_primary_target);

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(v_case,v_leaf,'DECISION_REVIEW','QUALIFIED','decision',
    'Qualify the exact Eggeling 1882 pp. 67-71 witness passage for source-linked recovery.',
    'wnph:satapatha-vessel-cleansing-qualification-v1') returning id into v_leaf;

  insert into wnph.recovery_case_targets(
    recovery_case_id,target_role,surrogate_id,rationale
  ) values(v_case,'preferred_source',v_surrogate,
    'Preferred historical source for this qualified passage. Exact IA source-surface IDs for printed pp. 67-71 remain a blocking verification task.')
  returning id into v_preferred_target;

  insert into wnph.publication_source_packages(
    canonical_key,recovery_case_id,expression_id,qualifying_decision_id,
    package_role,source_model,model_version,package_status,render_contract,notes
  ) values(
    'satapatha-brahmana:eggeling-1882-part1-i-3-1-canonical-source:v1',
    v_case,v_expression,v_decision,'canonical_master','semantic_single_source','1','planned',
    jsonb_build_object(
      'single_source_publishing',true,'manifestation_agnostic',true,
      'expression_identity','Eggeling 1882 English translation, Part I',
      'printed_page_span','67-71',
      'source_surface_assets_required_before_text_admission',true,
      'functional_semantics_separate_from_source_text',true,
      'ancient_work_may_not_be_collapsed_into_translation',true,
      'supported_by_design',jsonb_build_array('responsive_web','reflowable_epub','print_pdf','paperback','future_output_families')
    ),
    'Structure-only canonical source package. No OCR, modern web transcription or remembered quotation is canonical text until exact IA source surfaces for printed pp. 67-71 are fixed and verified.'
  ) returning id into v_package;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(v_case,v_leaf,'QUALIFIED','SELECTED_FOR_RECOVERY','selection',
    'Select the exact Eggeling 1882 I.3.1.1-11 witness and its source package. Text remains blocked on source-image verification.',
    'wnph:satapatha-vessel-cleansing-qualification-v1',true) returning id into v_leaf;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'satapatha-eggeling1882:i-3-1:document',0,'document','book_root',
    jsonb_build_object('translation_year',1882,'part','I','books','I-II'),
    jsonb_build_object('structure_authority','governed_1882_witness',
                       'source_surrogate_key','satapatha-brahmana:ia-1882-part1-surrogate')
  ) returning id into v_root;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'satapatha-eggeling1882:i-3-1:section',v_root,1,'section','cleaning_of_spoons',
    jsonb_build_object('canonical_section_locator','I.3.1','printed_page_start',67,
                       'printed_page_end',71,'paragraph_start',1,'paragraph_end',11,
                       'source_surface_mapping_complete',false),
    jsonb_build_object('structure_authority','1882_contents_and_printed_page_headers',
                       'comparison_transcription_key','sacred-texts:sbe12:1-3-1')
  ) returning id into v_section;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'satapatha-eggeling1882:i-3-1:reading-stream',v_section,1,
    'reading_stream','witness_passage',
    jsonb_build_object('printed_page_span','67-71','paragraph_span','1-11',
                       'completion',false,
                       'blocked_on','exact Internet Archive scan-image mapping and page-image verification'),
    jsonb_build_object('text_authority','none_yet','ocr_role','locating_aid_only',
                       'modern_transcription_role','comparison_only','canonical_text_admitted',false)
  );
end $$;
