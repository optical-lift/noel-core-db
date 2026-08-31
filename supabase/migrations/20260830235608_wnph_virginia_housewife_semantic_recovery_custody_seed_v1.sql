do $$
declare
  v_work uuid;
  v_item uuid;
  v_manifestation uuid;
  v_surrogate uuid;
  v_case uuid;
  v_brief uuid;
  v_mode_other uuid;
  v_mode_witness uuid;
  v_mode_text uuid;
  v_source_assessment uuid;
  v_rights uuid;
  v_condition_assessment uuid;
  v_condition_observation uuid;
  v_condition_type uuid;
  v_expression uuid;
  v_target_expression uuid;
  v_target_primary uuid;
  v_target_preferred uuid;
  v_decision uuid;
  v_package uuid;
  v_event uuid;
  v_prev uuid;
  v_root uuid;
  v_opening uuid;
begin
  if exists(select 1 from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1') then
    return;
  end if;

  select id into v_work from wnph.historical_works where canonical_key='virginia-house-wife';
  select s.id,s.item_id,i.manifestation_id into v_surrogate,v_item,v_manifestation
  from wnph.surrogates s join wnph.items i on i.id=s.item_id
  where s.canonical_key='loc:item:73217897';

  if v_work is null or v_surrogate is null or v_item is null or v_manifestation is null then
    raise exception 'WNPH Virginia semantic custody seed: governed 1824 Work/Item/Surrogate prerequisites are missing';
  end if;

  insert into wnph.recovery_cases(canonical_key,work_id,initial_scope,created_by)
  values(
    'virginia-house-wife:functional-semantic-cookbook-recovery-1',v_work,
    'Recover a provenance-preserving functional-semantic culinary and household-knowledge layer from the governed 1824 Library of Congress first-edition witness. This is not another generic reading edition. Historical structure, ingredients, quantities as expressed, operations, preservation, seasonality, service relationships, and uncertainty remain traceable to exact 1824 source surfaces. Later editions are comparison witnesses only and may not be silently blended.',
    'wnph:virginia-housewife-semantic-recovery-custody-seed-v1'
  ) returning id into v_case;

  insert into wnph.recovery_case_briefs(recovery_case_id,scope_note,why_recover,proposed_expression_type,priority)
  values(
    v_case,
    'Build a machine-usable historical cookery expression for WNPH/Atlas with single-witness page provenance; keep modern normalization downstream.',
    'Existing editions already recover the book for human reading. The distinct value here is governed source-addressable culinary and household semantics that can be computed over without pretending a modern collated or later edition is the 1824 witness.',
    'functional_semantic_cookbook_expression','high'
  ) returning id into v_brief;

  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
  values(v_case,'other','committed','Functional-semantic recovery with claim-level source provenance and bounded uncertainty') returning id into v_mode_other;
  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
  values(v_case,'witness','committed','Keep the 1824 first-edition state controlling and separate from later editions') returning id into v_mode_witness;
  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale)
  values(v_case,'text','withdrawn','Generic reading-text recovery is excluded by the prior governed decline') returning id into v_mode_text;

  insert into wnph.source_sufficiency_assessments(recovery_case_id,result,confidence,rationale,recorded_by)
  values(v_case,'sufficient','high','The complete ordered 244-image LOC surrogate is sufficient for source-located semantic reconstruction; page-level claims still require verification.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1')
  returning id into v_source_assessment;

  insert into wnph.source_sufficiency_members(assessment_id,surrogate_id,source_role,completeness,quality,provenance_status,member_result,notes)
  values(v_source_assessment,v_surrogate,'primary','complete','usable','sufficient','usable','Usable source member for semantic reconstruction; sufficiency does not itself verify any recipe claim');

  insert into wnph.rights_determinations(recovery_case_id,jurisdiction,overall_status,confidence,rationale,determined_by)
  values(v_case,'US','cleared','high','Same 1824 historical work and LOC mechanical-scan source already cleared in the foundational audit; bounded to U.S. historical-source recovery with third-party/non-U.S. reservations preserved.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1')
  returning id into v_rights;

  insert into wnph.rights_components(determination_id,component_type,component_status,work_id,use_scope,rationale)
  values(v_rights,'underlying_work','public_domain',v_work,'U.S. functional-semantic historical-source recovery','The 1824 underlying work is in the U.S. public domain under the already governed rights basis');
  insert into wnph.rights_components(determination_id,component_type,component_status,surrogate_id,use_scope,rationale)
  values(v_rights,'source_images','reuse_permitted',v_surrogate,'Use as source-recovery inputs','LOC reports no known U.S. copyright or other restrictions for this collection; retain bounded reuse-permitted characterization');

  insert into wnph.recovery_condition_assessments(recovery_case_id,assessment_status,scope_note,confidence)
  values(v_case,'bounded_complete','Assess only whether a differentiated source-addressable semantic project is supportable while general modern reading recovery remains adequate.','high')
  returning id into v_condition_assessment;

  select id into v_condition_type from wnph.recovery_condition_types where canonical_key='modern_recovery_adequacy';
  insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
  values(v_condition_assessment,v_condition_type,'adequate','interpretation',v_work,'General modern reading recovery is already adequate; qualification here must remain differentiated functional semantics and must not be used to justify redundant republication.','high')
  returning id into v_condition_observation;

  insert into wnph.expressions(canonical_key,work_id,expression_type,language_code,status,identity_confidence,summary)
  values(
    'virginia-house-wife:wnph-1824-functional-semantic-e1',v_work,'functional_semantic_cookbook_expression','en','established','high',
    'WNPH functional-semantic representation derived only from the governed 1824 LOC first-edition witness. It encodes historical culinary/household functions with exact provenance and bounded uncertainty. Modern normalization and later-edition readings are separate downstream/comparison layers.'
  ) returning id into v_expression;

  insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
  values(v_case,'primary_source',v_surrogate,'The 244-image LOC 1824 surrogate controls extraction') returning id into v_target_primary;
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,item_id,rationale)
  values(v_case,'reference',v_item,'Copy-level provenance remains anchored to LCCN 73217897 / TX715 .R215 1824');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,manifestation_id,rationale)
  values(v_case,'publication_model',v_manifestation,'The 1824 Washington Davis and Force manifestation defines the historical edition state');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,expression_id,rationale)
  values(v_case,'candidate',v_expression,'Empty qualified semantic Expression; population requires source-governed reconstruction/verification') returning id into v_target_expression;
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
  values(v_case,'preferred_source',v_surrogate,'Explicitly selected controlling historical source for the qualified semantic Expression') returning id into v_target_preferred;

  insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,null,'IDENTITY_ESTABLISHED','state_transition','Historical Work identity and the exact 1824 LOC source are already governed in WNPH.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','Evaluate the exact 1824 source for source-addressable semantic recovery rather than generic republication.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'SOURCE_RESEARCH','SOURCE_SUFFICIENT','The ordered 244-image LOC witness is sufficient for bounded semantic reconstruction, subject to page-level verification.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'SOURCE_SUFFICIENT','RIGHTS_RESEARCH','Carry forward a component-specific U.S. rights determination for the differentiated semantic recovery.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'RIGHTS_RESEARCH','RIGHTS_CLEARED','Underlying 1824 work and LOC source-image use are cleared for this bounded U.S. recovery scope.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'RIGHTS_CLEARED','RECOVERY_AUDIT','Apply the existing recovery audit as a scope limiter: ordinary human-reading recovery is already adequate.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'RECOVERY_AUDIT','CONDITION_ASSESSED','The differentiated semantic condition is bounded: source-addressable computation is useful, redundant republication is not.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'CONDITION_ASSESSED','DECISION_REVIEW','Review only the single-witness functional-semantic recovery scope.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;

  insert into wnph.recovery_decisions(recovery_case_id,decision_outcome,decision_scope,decision_summary)
  values(
    v_case,'qualify',
    'Qualify a single-witness 1824 functional-semantic cookbook expression. Exclude generic reading republication, modernized recipe claims, and cross-edition conflation. Normalization, substitution, safety guidance, modern measures, and Atlas recommendations are downstream layers and must be distinguished from historical claims.',
    'The prior decline remains valid for generic republication. This separate project is qualified because it creates source-addressable culinary and household semantics for computation and comparison from the governed 1824 witness without competing with existing scholarly reading editions.'
  ) returning id into v_decision;

  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,source_sufficiency_assessment_id,basis_note)
  values(v_decision,'supports',v_source_assessment,'The explicit 1824 source member is sufficient for page-located semantic reconstruction');
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,rights_determination_id,basis_note)
  values(v_decision,'supports',v_rights,'Rights are cleared for the bounded U.S. historical-source semantic recovery');
  insert into wnph.recovery_decision_bases(recovery_decision_id,basis_role,recovery_condition_observation_id,basis_note)
  values(v_decision,'limits',v_condition_observation,'Adequate modern reading recovery prohibits recharacterizing this qualification as a reading-edition need');

  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_brief_id)
  values(v_decision,'scope',v_brief);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_mode_id)
  values(v_decision,'mode',v_mode_other);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_mode_id)
  values(v_decision,'mode',v_mode_witness);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_target_id)
  values(v_decision,'source_target',v_target_expression);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_target_id)
  values(v_decision,'source_target',v_target_primary);
  insert into wnph.recovery_decision_plan_members(recovery_decision_id,member_role,recovery_case_target_id)
  values(v_decision,'source_target',v_target_preferred);

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case,v_prev,'DECISION_REVIEW','QUALIFIED','Qualify only the differentiated 1824 functional-semantic recovery; no generic reading-edition need is asserted.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1') returning id into v_prev;

  insert into wnph.publication_source_packages(
    canonical_key,recovery_case_id,expression_id,qualifying_decision_id,package_role,package_status,source_model,model_version,render_contract,notes
  ) values(
    'virginia-house-wife:1824-functional-semantic-source:v1',v_case,v_expression,v_decision,'canonical_master','building','semantic_single_source','1',
    jsonb_build_object(
      'canonical_layers',jsonb_build_array('source_surface','historical_structure','functional_semantics','provenance'),
      'intended_consumers',jsonb_build_array('wnph_cookbook_container','atlas_meal_planning'),
      'controlling_witness','virginia-house-wife:loc-digital-73217897',
      'allow_cross_edition_blend',false,
      'downstream_normalization_separate',true,
      'allow_unprovenanced_semantic_claims',false,
      'allow_modern_normalization_in_historical_layer',false
    ),
    'Canonical package opened against the preferred 1824 LOC surrogate. Individual claims remain governed by source-locator reconstruction/verification custody.'
  ) returning id into v_package;

  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by,selection_authorized)
  values(v_case,v_prev,'QUALIFIED','SELECTED_FOR_RECOVERY','Select the governed 1824 LOC witness and semantic canonical package. Selection admits no semantic claim; every claim still passes source-locator reconstruction/verification custody.','wnph:virginia-housewife-semantic-recovery-custody-seed-v1',true);

  insert into wnph.publication_source_assets(source_package_id,asset_key,asset_role,source_surrogate_id,source_locator,media_type,metadata)
  select v_package,
         'virginia-house-wife:1824:source-surface:'||lpad(gs::text,4,'0'),
         'source_surface',v_surrogate,
         jsonb_build_object(
           'item_uri','https://www.loc.gov/item/73217897/',
           'image_uri','https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:'||lpad(gs::text,4,'0')||'/full/max/0/default.jpg',
           'loc_image',gs,
           'repository','Library of Congress',
           'iiif_info_uri','https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:'||lpad(gs::text,4,'0')||'/info.json',
           'sequence_index',gs,
           'source_pdf_page',gs,
           'resource_page_uri','https://www.loc.gov/resource/rbc0001.2015pennell17897/?sp='||gs::text||'&st=image',
           'iiif_image_service_uri','https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:'||lpad(gs::text,4,'0')
         ),
         'image/jpeg',
         jsonb_build_object(
           'surface_kind','repository_page_image',
           'locator_basis','LOC resource rbc0001.2015pennell17897 plus verified IIIF naming pattern',
           'master_page_count',244,
           'controlling_witness','virginia-house-wife:loc-digital-73217897',
           'source_access_state','locator_registered_pending_page_qc',
           'page_sequence_status','repository_ordered'
         )
  from generate_series(1,244) gs;

  insert into wnph.publication_source_assets(source_package_id,asset_key,asset_role,source_surrogate_id,source_locator,storage_uri,media_type,metadata)
  values(
    v_package,'virginia-house-wife:1824:loc-pdf','source_surface',v_surrogate,
    jsonb_build_object('repository','Library of Congress','item_uri','https://www.loc.gov/item/73217897/','pdf_uri','https://tile.loc.gov/storage-services/service/rbc/rbc0001/2015/2015pennell17897/2015pennell17897.pdf'),
    'https://tile.loc.gov/storage-services/service/rbc/rbc0001/2015/2015pennell17897/2015pennell17897.pdf','application/pdf',
    jsonb_build_object('surface_kind','bound_source_pdf','image_count',244,'text_layer_use','candidate_reconstruction_only','page_image_verification_completed',false)
  );

  insert into wnph.publication_source_blocks(source_package_id,block_key,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'virginia-house-wife:1824:root',0,'work','historical_source_structure',jsonb_build_object('edition','1824 first edition','cross_edition_blend_allowed',false),jsonb_build_object('text_authority','Library of Congress 1824 first-edition witness'))
  returning id into v_root;

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'virginia-house-wife:1824:sequence:opening-preservation',v_root,1,'editorial_container','unsectioned_opening_instruction_sequence',jsonb_build_object('printed_heading_absent',true,'editorial_container',true,'first_printed_page',13,'historical_structure_status','adjudicated_from_exact_1824_sequence'),jsonb_build_object('controlling_witness','Library of Congress 1824 first edition','structure_basis','exact 1824 opening sequence; later stereotype section headings are excluded','cross_edition_blend_allowed',false))
  returning id into v_opening;
end $$;