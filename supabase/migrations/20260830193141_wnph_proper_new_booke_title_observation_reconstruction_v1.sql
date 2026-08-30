do $$
declare
  v_pkg uuid;
  v_parent uuid;
  v_asset uuid;
  v_ws uuid;
  v_visual uuid;
begin
  select p.id into strict v_pkg from wnph.publication_source_packages p where p.canonical_key='proper-new-booke-of-cookery:1575-canonical-publication-source:v1' and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);
  select b.id into strict v_parent from wnph.publication_source_blocks b where b.source_package_id=v_pkg and b.block_key='proper-new-booke:title-page:reading-stream' and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);
  select a.id into strict v_asset from wnph.publication_source_assets a where a.source_package_id=v_pkg and a.asset_key='proper-new-booke:1575:source-surface:0001' and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id);

  insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
  values(v_asset,'proper-new-booke:1575:page1:wikisource:title-candidate','line',1,E'A proper new\nBooke of Cookery.','surface',0.95,'external_transcription_alignment','wikisource_proofreadpage',jsonb_build_object('provider','Wikisource','engine','ProofreadPage'),jsonb_build_object('scan_page',1,'url','https://en.wikisource.org/wiki/Page:A_Proper_New_Booke_of_Cookery_(1575).djvu/1'),jsonb_build_object('status','proofread_not_validated','canonical_authority',false)) returning id into v_ws;

  insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
  values(v_asset,'proper-new-booke:1575:page1:visual:title-reading','line',2,E'A proper new\nBooke of Cookery.','surface',0.99,'direct_visual_inspection_of_source_page_image','commons_page_image_render',jsonb_build_object('provider','OpenAI','engine','GPT-5.6 Sol visual inspection'),jsonb_build_object('scan_page',1,'asset_key','proper-new-booke:1575:source-surface:0001'),jsonb_build_object('canonical_authority',false,'lineation_preserved',true)) returning id into v_visual;

  insert into wnph.publication_source_reconstruction_proposals(source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,source_observation_ids,confidence,disposition,review_reasons,proposed_properties,proposed_source_provenance,algorithm)
  values(v_pkg,'proper-new-booke:1575:reconstruction:title:v1',v_parent,'proper-new-booke:title-page:title',1,'title','work_title_as_printed','A proper new Booke of Cookery.','usable',array[v_ws,v_visual],0.99,'review',jsonb_build_array('canonical source-image verification required before admission'),jsonb_build_object('scan_page',1,'source_lineation',jsonb_build_array('A proper new','Booke of Cookery.')),jsonb_build_object('text_authority','source_image_observation_with_comparison_transcription','derivation_method','comparison_alignment_plus_direct_visual_reading','source_locators',jsonb_build_array(jsonb_build_object('scan_page',1,'asset_key','proper-new-booke:1575:source-surface:0001'))),jsonb_build_object('engine','wnph_visual_reconstruction_review','version','1'));
end $$;