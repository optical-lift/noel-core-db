do $$
declare
  v_case uuid;
  v_work uuid;
  v_pkg uuid;
  v_parent uuid;
  v_surrogate uuid;
  v_asset uuid;
  v_commons uuid;
  v_wikisource uuid;
  v_agent uuid;
  v_proposal uuid;
  v_act uuid;
  v_block uuid;
begin
  select c.id,c.work_id into strict v_case,v_work from wnph.recovery_cases c where c.canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1';
  select p.id into strict v_pkg from wnph.publication_source_packages p where p.canonical_key='proper-new-booke-of-cookery:1575-canonical-publication-source:v1' and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);
  select b.id into strict v_parent from wnph.publication_source_blocks b where b.source_package_id=v_pkg and b.block_key='proper-new-booke:title-page:reading-stream' and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);
  select s.id into strict v_surrogate from wnph.surrogates s where s.canonical_key='proper-new-booke-of-cookery:commons-ia-1575';
  select a.id into strict v_asset from wnph.publication_source_assets a where a.source_package_id=v_pkg and a.asset_key='proper-new-booke:1575:source-surface:0001' and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id);
  select es.id into strict v_commons from wnph.evidence_sources es where es.canonical_key='wikimedia-commons:proper-new-booke-cookery-1575';
  select es.id into strict v_wikisource from wnph.evidence_sources es where es.canonical_key='wikisource:proper-new-booke-of-cookery-1575';
  select a.id into strict v_agent from wnph.transmission_agents a where a.canonical_key='wnph:recovery-process' and not exists(select 1 from wnph.transmission_agents n where n.supersedes_agent_id=a.id);
  select rp.id into strict v_proposal from wnph.publication_source_reconstruction_proposals rp where rp.source_package_id=v_pkg and rp.proposal_key='proper-new-booke:1575:reconstruction:title:v1' and not exists(select 1 from wnph.publication_source_reconstruction_proposals n where n.supersedes_proposal_id=rp.id);

  insert into wnph.transmission_acts(canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata)
  values('proper-new-booke:1575:transmission:first-canonical-title:v1',v_case,v_work,'verified_transcription','Admit the first source-image-verified text into the selected 1575 recovery Expression.','Direct visual inspection of scan page 1 is the reading authority. Wikisource supplies comparison text only. The printed two-line title is stored as one semantic title without modernizing spelling.','system_recorded','certain',jsonb_build_object('canonical_text_admission',true,'source_image_verified',true,'scan_page_scope',jsonb_build_array(1),'canonical_blocks_admitted',1,'reconstruction_proposal_id',v_proposal,'page_image_is_authority',true,'wikisource_is_authority',false,'normalization_performed',false)) returning id into v_act;

  insert into wnph.transmission_act_agents(transmission_act_id,agent_id,agent_role) values(v_act,v_agent,'source_image_transcription_and_verification');
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id,locator) values(v_act,'input','preferred_historical_source',v_surrogate,jsonb_build_object('scan_page',1));
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_asset_id,locator) values(v_act,'input','source_page_image',v_asset,jsonb_build_object('scan_page',1,'asset_key','proper-new-booke:1575:source-surface:0001'));
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id,locator) values(v_act,'input','comparison_transcription',v_wikisource,jsonb_build_object('scan_page',1,'status','proofread_not_validated'));
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id) values(v_act,'context','canonical_publication_source',v_pkg);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id) values(v_act,'context','title_page_reading_stream',v_parent);

  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note) values(v_act,v_commons,'supports','certain','The governed page-image surface is the canonical reading authority for this title.');
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note) values(v_act,v_wikisource,'context','high','Wikisource agrees on the title but is proofread-not-validated comparison material only.');

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance,reading_state)
  values(v_pkg,'proper-new-booke:title-page:title',v_parent,1,'title','work_title_as_printed','A proper new Booke of Cookery.',jsonb_build_object('witness_year',1575,'scan_page',1,'canonical_status','admitted','source_lineation',jsonb_build_array('A proper new','Booke of Cookery.'),'modernization_performed',false),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','proper-new-booke-of-cookery:commons-ia-1575','source_surface_asset_key','proper-new-booke:1575:source-surface:0001','comparison_transcription_key','wikisource:proper-new-booke-of-cookery-1575','reconstruction_proposal_id',v_proposal,'source_locators',jsonb_build_array(jsonb_build_object('scan_page',1,'sequence_index',1,'asset_key','proper-new-booke:1575:source-surface:0001'))),'verified') returning id into v_block;

  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_title',v_block,jsonb_build_object('scan_page',1,'ordinal',1));
end $$;