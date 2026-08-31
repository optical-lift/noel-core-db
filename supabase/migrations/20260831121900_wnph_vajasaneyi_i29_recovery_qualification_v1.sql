begin;

-- WNPH Vājasaneyi Saṁhitā I.29 recovery qualification v1.
--
-- Qualifies the bounded recovery of the Mādhyandina I.29 formula from Albrecht
-- Weber's 1852 Sanskrit editorial witness. The ancient Work, Weber's edited
-- Sanskrit Expression, the Kāṇva recension, Mahīdhara's commentary, Śatapatha
-- Brāhmaṇa, and later electronic transcriptions remain distinct objects.
--
-- No Sanskrit reading text and no source-surface image asset is admitted here.
-- Exact DLI/Commons scan-image mapping and visual verification remain mandatory
-- before any Sanskrit text can be promoted to verified/adjudicated state.

do $$
declare
  v_case uuid;
  v_work uuid;
  v_expression uuid;
  v_manifestation uuid;
  v_item uuid;
  v_surrogate uuid;
  v_primary_source uuid;
  v_compare_source uuid;
  v_usco_source uuid;
  v_ssa uuid;
  v_ssm uuid;
  v_rights uuid;
  v_component uuid;
  v_audit_open uuid;
  v_audit uuid;
  v_finding uuid;
  v_condition uuid;
  v_brief uuid;
  v_mode record;
  v_decision uuid;
  v_primary_target uuid;
  v_expression_target uuid;
  v_package uuid;
  v_root uuid;
  v_section uuid;
  v_formula uuid;
  v_leaf uuid;
begin
  select c.id,c.work_id into strict v_case,v_work
  from wnph.recovery_cases c
  where c.canonical_key='vajasaneyi-samhita:weber1852-i-29-cleansing-formula-recovery-1';

  select id into strict v_expression
  from wnph.expressions
  where canonical_key='vajasaneyi-samhita:weber-1852-madhyandina-edited-e1';

  select id into strict v_manifestation
  from wnph.manifestations
  where canonical_key='white-yajurveda:weber-part1-1852';

  select id into strict v_item
  from wnph.items
  where canonical_key='vajasaneyi-samhita:weber1852:dli-486971';

  select id into strict v_surrogate
  from wnph.surrogates
  where canonical_key='vajasaneyi-samhita:weber1852:dli-486971-surrogate';

  select id into strict v_primary_source
  from wnph.evidence_sources
  where canonical_key='commons:vajasaneyi-weber-1852-dli-486971';

  select id into strict v_compare_source
  from wnph.evidence_sources
  where canonical_key='titus:vajasaneyi-samhita-madhyandina-weber';

  select id into strict v_usco_source
  from wnph.evidence_sources
  where canonical_key='us-copyright-office:circular-15a:2026';

  -- SOURCE SUFFICIENCY. The historical scan is materially available and the
  -- electronic comparison witness fixes the requested textual locator, but exact
  -- scan-image mapping remains a later verification task.
  insert into wnph.source_sufficiency_assessments(
    recovery_case_id,result,confidence,rationale,recorded_by
  ) values(
    v_case,'sufficient','high',
    'Weber''s 1852 Vājasaneyi-Saṁhitā survives as a public page-image/PDF scan represented by DLI/Commons, and the Weber-based TITUS Mādhyandina electronic text independently fixes the target as I.29. This is sufficient for bounded witness recovery research. Exact scan leaf/page mapping and direct visual verification remain mandatory before any Sanskrit reading is admitted.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_ssa;

  insert into wnph.source_sufficiency_members(
    assessment_id,surrogate_id,source_role,completeness,quality,
    provenance_status,member_result,missing_or_damage_note,notes
  ) values(
    v_ssa,v_surrogate,'primary','substantially_complete','usable','sufficient','usable',
    'Exact source-image locator for Mādhyandina Vājasaneyi Saṁhitā I.29 has not yet been fixed in WNPH source-surface custody.',
    'The historical scan is sufficient to continue recovery but not sufficient to authorize a Sanskrit reading without page-image verification.'
  ) returning id into v_ssm;

  insert into wnph.evidence_links(
    source_id,source_sufficiency_assessment_id,support_role,confidence,note
  ) values(
    v_primary_source,v_ssa,'supports','high',
    'DLI/Commons identifies and exposes Weber''s 1852 historical Sanskrit publication and digitized scan.'
  );

  insert into wnph.evidence_links(
    source_id,source_sufficiency_assessment_id,support_role,confidence,note
  ) values(
    v_compare_source,v_ssa,'supports','high',
    'TITUS identifies the Mādhyandina Vājasaneyi Saṁhitā and fixes the target at I.29 on a Weber-edition basis; it remains comparison text only.'
  );

  insert into wnph.evidence_links(
    source_id,source_sufficiency_member_id,support_role,confidence,note
  ) values(
    v_primary_source,v_ssm,'supports','high',
    'The DLI/Commons page-image surrogate is the governed primary recovery member.'
  );

  -- U.S. RIGHTS. Keep rights to the ancient Work, Weber editorial witness, and
  -- repository source images explicit and component-specific.
  insert into wnph.rights_determinations(
    recovery_case_id,jurisdiction,overall_status,confidence,rationale,determined_by
  ) values(
    v_case,'US','cleared','high',
    'The underlying Vājasaneyi Saṁhitā is ancient. Weber''s Sanskrit editorial publication dates to 1852 and is public domain in the United States by publication age. The DLI/Commons record presents the historical scan as public-domain source material. WNPH claims no copyright ownership in modern repository interfaces or later electronic transcription layers.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_rights;

  insert into wnph.rights_components(
    determination_id,component_type,component_status,work_id,use_scope,rationale
  ) values(
    v_rights,'underlying_work','public_domain',v_work,
    'U.S. source-faithful recovery and WNPH-derived scholarly/semantic editions',
    'The underlying Vedic Work is ancient.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,support_role,confidence,note)
  values(v_usco_source,v_component,'supports','high','Current U.S. duration guidance is context for the public-domain recovery boundary.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,expression_id,use_scope,rationale
  ) values(
    v_rights,'other','public_domain',v_expression,
    'U.S. recovery, transcription, publication and analysis of Weber''s 1852 Mādhyandina edited Sanskrit Expression',
    'The governed historical editorial witness was published in 1852.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,support_role,confidence,note)
  values(v_usco_source,v_component,'supports','high','Official U.S. duration guidance supports public-domain status by publication age.');
  insert into wnph.evidence_links(source_id,rights_component_id,support_role,confidence,note)
  values(v_primary_source,v_component,'supports','high','The scan record identifies the 1852 Weber publication used for this Expression recovery.');

  insert into wnph.rights_components(
    determination_id,component_type,component_status,surrogate_id,use_scope,rationale
  ) values(
    v_rights,'source_images','reuse_permitted',v_surrogate,
    'Use of the DLI/Commons page-image/PDF surrogate as recovery and verification input',
    'The historical publication is public domain and the repository exposes the scan as public-domain source material. WNPH records reuse evidence without asserting ownership of repository presentation.'
  ) returning id into v_component;
  insert into wnph.evidence_links(source_id,rights_component_id,support_role,confidence,note)
  values(v_primary_source,v_component,'supports','high','DLI/Commons source record supports source-image reuse for recovery.');

  -- Open the bounded access audit before entering RECOVERY_AUDIT.
  insert into wnph.existing_recovery_audits(
    recovery_case_id,audit_status,scope_note
  ) values(
    v_case,'in_progress',
    'Bounded audit of existing Weber 1852 Mādhyandina I.29 facsimile and electronic-text access; no claim of textual verification or meaningful recovery gap yet.'
  ) returning id into v_audit_open;

  -- Exact recovery state membrane.
  select e.id into strict v_leaf
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id);

  if (select to_state from wnph.recovery_case_events where id=v_leaf) <> 'SOURCE_RESEARCH' then
    raise exception 'Vājasaneyi I.29 qualification expected SOURCE_RESEARCH leaf';
  end if;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'SOURCE_RESEARCH','SOURCE_SUFFICIENT','state_transition',
    'The governed Weber 1852 Sanskrit source is materially sufficient for continued recovery; exact scan-image mapping remains mandatory.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,support_role,confidence,note)
  values(v_primary_source,v_leaf,'supports','high','The historical scan supports the SOURCE_SUFFICIENT gate.');

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'SOURCE_SUFFICIENT','RIGHTS_RESEARCH','state_transition',
    'Evaluate component-specific U.S. rights for the ancient Work, Weber 1852 Sanskrit editorial witness and source-image recovery input.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'RIGHTS_RESEARCH','RIGHTS_CLEARED','state_transition',
    'U.S. rights are cleared for the bounded historical recovery inputs while modern electronic presentation remains separately attributable.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;
  insert into wnph.evidence_links(source_id,recovery_case_event_id,support_role,confidence,note)
  values(v_usco_source,v_leaf,'supports','high','Official U.S. duration guidance supports RIGHTS_CLEARED.');
  insert into wnph.evidence_links(source_id,recovery_case_event_id,support_role,confidence,note)
  values(v_primary_source,v_leaf,'supports','high','Historical publication and repository rights evidence support RIGHTS_CLEARED.');

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'RIGHTS_CLEARED','RECOVERY_AUDIT','state_transition',
    'Begin governed comparison of the surviving historical scan and the Weber-based electronic reading witness. Ordinary online readability does not settle WNPH recovery value.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;

  -- Complete the bounded audit. The recovery gap is source custody and reversible
  -- structure, not generic access to a Sanskrit string.
  insert into wnph.existing_recovery_audits(
    recovery_case_id,audit_status,scope_note,supersedes_audit_id
  ) values(
    v_case,'complete',
    'A historical Weber 1852 scan exists, and TITUS supplies a competent Weber-based Mādhyandina electronic text. WNPH therefore does not claim that I.29 is unavailable. The remaining recovery gap is an exact source-image-verified, accent-preserving witness object that preserves the paired masculine/feminine formula structure and its direct documentary relationship to Śatapatha Brāhmaṇa I.3.1 without collapsing Works or recensions.',
    v_audit_open
  ) returning id into v_audit;

  insert into wnph.existing_recovery_findings(
    audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes
  ) values(
    v_audit,'other','present','FACSIMILE','raw','DLI/Commons in.ernet.dli.2015.486971',
    'A full historical page-image/PDF scan of Weber 1852 exists. Exact scan leaf for Mādhyandina I.29 has not yet been fixed in WNPH.'
  ) returning id into v_finding;
  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,support_role,confidence,note)
  values(v_primary_source,v_finding,'supports','high','Direct historical scan record supports facsimile availability.');

  insert into wnph.existing_recovery_findings(
    audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes
  ) values(
    v_audit,'other','present','SEARCHABLE_TEXT','competent','TITUS Mādhyandina Vājasaneyi Saṁhitā I.29',
    'A Weber-based scholarly electronic reading exists and preserves Vedic accentuation and the paired masculine/feminine forms. It is comparison evidence only until the governed 1852 scan is visually checked.'
  ) returning id into v_finding;
  insert into wnph.evidence_links(source_id,existing_recovery_finding_id,support_role,confidence,note)
  values(v_compare_source,v_finding,'supports','high','TITUS directly supplies the competent electronic comparison reading.');

  -- Recovery condition.
  insert into wnph.recovery_condition_assessments(
    recovery_case_id,assessment_status,scope_note,confidence
  ) values(
    v_case,'bounded_complete',
    'Condition of the exact Mādhyandina Vājasaneyi Saṁhitā I.29 formula in Weber''s 1852 Sanskrit editorial witness, kept distinct from the ancient Work, Kāṇva recension, Mahīdhara commentary and later electronic transcriptions.',
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
      'A specific DLI/Commons digitized copy of Weber''s 1852 Vājasaneyi-Saṁhitā is identified as in.ernet.dli.2015.486971.'::text,'high'::text),
    ('digital_facsimile_survival','adequate','evidence','surrogate',
      'The governed Weber 1852 witness survives as a public page-image/PDF surrogate.','high'),
    ('modern_reading_edition','adequate','evidence','expression',
      'A competent Weber-based Mādhyandina electronic reading of I.29 exists; ordinary reading access is not the gap.','high'),
    ('text_integrity','unverified','evidence','surrogate',
      'The exact 1852 scan leaf for I.29 has not been fixed and the Vedic accents/marks have not been visually checked against the governed source image.','high'),
    ('edition_relationship_clarity','adequate','interpretation','expression',
      'The recovery target is Weber''s Mādhyandina edited Sanskrit Expression, kept separate from the ancient Work, Kāṇva recension and commentary streams.','high'),
    ('modern_recovery_adequacy','limited','interpretation','expression',
      'Generic electronic readability is adequate; a source-image-verified, provenance-linked I.29 formula object with preserved paired-form structure does not yet exist in WNPH.','high')
  ) as x(type_key,state,epistemic,target_kind,text,confidence)
  join wnph.recovery_condition_types t
    on t.canonical_key=x.type_key and t.status='active';

  insert into wnph.evidence_links(
    source_id,recovery_condition_observation_id,support_role,confidence,note
  )
  select case when t.canonical_key='modern_reading_edition' then v_compare_source else v_primary_source end,
         o.id,'supports',o.confidence,'Evidence for the bounded Vājasaneyi I.29 recovery condition.'
  from wnph.recovery_condition_observations o
  join wnph.recovery_condition_types t on t.id=o.condition_type_id
  where o.assessment_id=v_condition and o.epistemic_status='evidence';

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition',
    'Public reading access is competent, but exact 1852 source-image text integrity is unverified and the source-linked formula object does not yet exist.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;

  insert into wnph.recovery_case_briefs(
    recovery_case_id,scope_note,why_recover,proposed_expression_type,priority
  ) values(
    v_case,
    'Recover Mādhyandina Vājasaneyi Saṁhitā I.29 from Weber''s 1852 Sanskrit editorial witness as a source-image-verified formula unit. Preserve Vedic accent marks, line/order boundaries, repeated protection/removal clauses, the paired masculine/feminine forms, and the exact I.29 locator. Do not let Eggeling''s English gloss or modern functional labels overwrite the Sanskrit witness.',
    'I.29 is the direct formula parent invoked by Śatapatha Brāhmaṇa I.3.1 in the sacrificial-spoon cleansing operation. WNPH recovery adds exact source custody and reversible functional addressability rather than merely another electronic transcription.',
    'verified_1852_sanskrit_madhyandina_formula_witness','high'
  ) returning id into v_brief;

  -- Commit the already-proposed recovery modes through append-only supersession.
  for v_mode in
    select m.* from wnph.recovery_case_modes m
    where m.recovery_case_id=v_case
      and m.recovery_mode in ('text','transcription','witness')
      and m.intent_status='proposed'
      and not exists(select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
  loop
    insert into wnph.recovery_case_modes(
      recovery_case_id,recovery_mode,intent_status,rationale,supersedes_mode_id
    ) values(
      v_case,v_mode.recovery_mode,'committed',
      case v_mode.recovery_mode
        when 'text' then 'Recover the complete I.29 formula unit before functional extraction or translation.'
        when 'transcription' then 'Transcribe and verify Vedic marks/accents directly against the governed Weber 1852 source image.'
        else 'Preserve Weber''s 1852 Mādhyandina Sanskrit editorial witness distinctly from the ancient Work, Kāṇva stream, commentary and later electronic readings.'
      end,
      v_mode.id
    );
  end loop;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'CONDITION_ASSESSED','DECISION_REVIEW','state_transition',
    'Review the narrow source-linked recovery of I.29, not generic availability of the Sanskrit formula online.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;

  insert into wnph.recovery_decisions(
    recovery_case_id,decision_outcome,decision_scope,decision_summary
  ) values(
    v_case,'qualify',
    'Qualify only the source-linked recovery of Mādhyandina Vājasaneyi Saṁhitā I.29 in Weber''s 1852 edited Sanskrit witness, including preserved accentuation and paired masculine/feminine formula structure. Do not qualify a generic modern electronic republication, do not collapse Kāṇva or commentary streams into the Mādhyandina Expression, and do not admit TITUS or remembered Sanskrit canonically before source-image verification.',
    'The formula is already readable in scholarly electronic form. WNPH''s distinct recovery value is a governed historical Sanskrit witness whose exact marks can be traced back to source images and whose relationship to Śatapatha I.3.1 is explicit without making the two Works identical.'
  ) returning id into v_decision;

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note
  ) values(v_decision,'supports',v_ssa,'The Weber 1852 scan is sufficient for bounded exact-witness recovery.');

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,rights_determination_id,basis_note
  ) values(v_decision,'supports',v_rights,'U.S. rights are cleared for the historical recovery inputs.');

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,existing_recovery_audit_id,basis_note
  ) values(v_decision,'context',v_audit,'Competent modern access exists; qualification is for source custody and exact reversible recovery, not availability.');

  insert into wnph.recovery_decision_bases(
    recovery_decision_id,basis_role,evidence_source_id,basis_note
  ) values(v_decision,'limits',v_compare_source,'The electronic comparison reading may locate/collate I.29 but may not authorize canonical Sanskrit text without source verification.');

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

  select t.id into strict v_expression_target
  from wnph.recovery_case_targets t
  where t.recovery_case_id=v_case
    and t.target_role='candidate'
    and t.expression_id=v_expression
    and not exists(select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id);

  insert into wnph.recovery_decision_plan_members(
    recovery_decision_id,member_role,recovery_case_target_id
  ) values(v_decision,'source_target',v_expression_target);

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by
  ) values(
    v_case,v_leaf,'DECISION_REVIEW','QUALIFIED','decision',
    'Qualify the exact Weber 1852 Mādhyandina I.29 formula witness for source-linked recovery.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1'
  ) returning id into v_leaf;

  insert into wnph.recovery_case_targets(
    recovery_case_id,target_role,surrogate_id,rationale
  ) values(
    v_case,'preferred_source',v_surrogate,
    'Preferred historical source for the qualified I.29 recovery. Exact DLI/Commons source-surface image locator remains a blocking verification task.'
  );

  insert into wnph.publication_source_packages(
    canonical_key,recovery_case_id,expression_id,qualifying_decision_id,
    package_role,source_model,model_version,package_status,render_contract,notes
  ) values(
    'vajasaneyi-samhita:weber-1852-i-29-canonical-source:v1',
    v_case,v_expression,v_decision,
    'canonical_master','semantic_single_source','1','planned',
    jsonb_build_object(
      'single_source_publishing',true,
      'manifestation_agnostic',true,
      'expression_identity','Weber 1852 Mādhyandina edited Sanskrit witness',
      'canonical_locator','Vājasaneyi Saṁhitā I.29',
      'source_surface_assets_required_before_text_admission',true,
      'accentuation_preserved',true,
      'recension_identity_preserved',true,
      'paired_formula_distinction_preserved',true,
      'masculine_feminine_forms_may_not_be_collapsed',true,
      'functional_semantics_separate_from_source_text',true,
      'ancient_work_may_not_be_collapsed_into_weber_expression',true,
      'supported_by_design',jsonb_build_array('responsive_web','reflowable_epub','print_pdf','paperback','future_output_families')
    ),
    'Structure-only canonical source package for Weber''s Mādhyandina I.29 witness. No electronic transcription, remembered Sanskrit, translation or functional gloss is canonical text until an exact 1852 source image is fixed and verified.'
  ) returning id into v_package;

  insert into wnph.recovery_case_events(
    recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized
  ) values(
    v_case,v_leaf,'QUALIFIED','SELECTED_FOR_RECOVERY','selection',
    'Select the exact Weber 1852 Mādhyandina I.29 witness and its source package. Sanskrit text remains blocked on source-image verification.',
    'wnph:vajasaneyi-i29-recovery-qualification-v1',true
  ) returning id into v_leaf;

  -- Structure only. No Sanskrit reading text is admitted here.
  insert into wnph.publication_source_blocks(
    source_package_id,block_key,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'vajasaneyi-weber1852:i-29:document',0,'document','book_root',
    jsonb_build_object('publication_year',1852,'editor','Albrecht Weber','recension_target','Mādhyandina'),
    jsonb_build_object('structure_authority','governed_1852_weber_witness','source_surrogate_key','vajasaneyi-samhita:weber1852:dli-486971-surrogate')
  ) returning id into v_root;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'vajasaneyi-weber1852:adhyaya-1',v_root,1,'section','adhyaya',
    jsonb_build_object('canonical_locator','I','recension','Mādhyandina'),
    jsonb_build_object('structure_authority','Weber 1852 editorial organization','source_image_mapping_complete',false)
  ) returning id into v_section;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'vajasaneyi-weber1852:i-29:formula',v_section,29,'section','ritual_formula_unit',
    jsonb_build_object(
      'canonical_locator','I.29',
      'formula_pair',true,
      'masculine_form_present',true,
      'feminine_form_present',true,
      'accentuation_required',true,
      'source_surface_mapping_complete',false
    ),
    jsonb_build_object(
      'structure_authority','Weber-based scholarly comparison plus historical manifestation identity',
      'comparison_text_key','titus:vajasaneyi-samhita-madhyandina-weber',
      'source_image_authority','none_yet'
    )
  ) returning id into v_formula;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_package,'vajasaneyi-weber1852:i-29:reading-stream',v_formula,1,'reading_stream','sanskrit_formula_witness',
    jsonb_build_object(
      'canonical_locator','I.29',
      'expected_structure','paired repeated clauses with masculine and feminine formula forms',
      'completion',false,
      'blocked_on','exact Weber 1852 DLI/Commons scan-image mapping and direct visual verification'
    ),
    jsonb_build_object(
      'text_authority','none_yet',
      'electronic_text_role','comparison_only',
      'canonical_text_admitted',false,
      'source_image_verification_required',true
    )
  );
end $$;

commit;
