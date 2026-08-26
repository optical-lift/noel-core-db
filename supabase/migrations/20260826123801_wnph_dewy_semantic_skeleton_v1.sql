-- WNPH Dewy canonical semantic skeleton v1
--
-- This step instantiates only directly evidenced structural hierarchy and illustration placements.
-- It does NOT promote OCR prose or machine-guessed paragraph boundaries into canonical content.
-- Each chapter receives an ordered paragraph-stream container whose children must be created later
-- by governed page-image-verified transcription acts.

do $$
declare
  v_case uuid;
  v_work uuid;
  v_package uuid;
  v_surrogate uuid;
  v_ocr_source uuid;
  v_plate_source uuid;
  v_wnph_agent uuid;
  v_act uuid;
  v_root uuid;
  v_front uuid;
  v_body uuid;
  v_ch uuid;
  v_block uuid;
  v_count integer;
begin
  select c.id,c.work_id into v_case,v_work
  from wnph.recovery_cases c
  where c.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';

  select p.id into v_package
  from wnph.publication_source_packages p
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);

  select s.id into v_surrogate from wnph.surrogates s where s.canonical_key='wish-fairy-dewy-dear:loc-digital';
  select es.id into v_ocr_source from wnph.evidence_sources es where es.canonical_key='internet-archive:ia:wishfairydewydea00colv:djvu-text';
  select es.id into v_plate_source from wnph.evidence_sources es where es.canonical_key='wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic';
  select a.id into v_wnph_agent from wnph.transmission_agents a where a.canonical_key='wnph:recovery-process' and not exists(select 1 from wnph.transmission_agents n where n.supersedes_agent_id=a.id);

  if v_case is null or v_work is null or v_package is null or v_surrogate is null or v_ocr_source is null or v_plate_source is null or v_wnph_agent is null then
    raise exception 'WNPH Dewy semantic skeleton: required governed inputs are incomplete';
  end if;

  select count(*) into v_count from wnph.publication_source_blocks where source_package_id=v_package;
  if v_count <> 0 then raise exception 'WNPH Dewy semantic skeleton: canonical package must have zero existing source blocks, found %',v_count; end if;

  -- Root document.
  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance
  ) values(
    v_package,'dewy:document',null,0,'document','canonical_document',null,
    jsonb_build_object(
      'skeleton_version',1,
      'canonical_text_populated',false,
      'paragraph_segmentation_status','not_yet_verified',
      'illustration_placement_count',7,
      'chapter_count',6
    ),
    jsonb_build_object(
      'preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital',
      'ocr_structure_aid_key','internet-archive:ia:wishfairydewydea00colv:djvu-text',
      'illustration_diagnostic_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'
    )
  ) returning id into v_root;

  -- Front matter container.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:front-matter',v_root,0,'section_group','front_matter',
    jsonb_build_object('source_region','before_printed_page_7'),
    jsonb_build_object('source_basis','LOC/IA witness front matter sequence'))
  returning id into v_front;

  -- Frontispiece placement: directly evidenced by illustration diagnostic.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:frontispiece',v_front,0,'illustration_placement','frontispiece',
    jsonb_build_object('printed_position','frontispiece','source_pdf_page',6,'asset_population_status','pending_extraction'),
    jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:title-page',v_front,1,'front_matter_component','title_page',
    jsonb_build_object('text_population_status','pending_verification'),
    jsonb_build_object('structure_observed_in_ocr',true,'canonical_text_asserted',false));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:copyright-page',v_front,2,'front_matter_component','copyright_page',
    jsonb_build_object('text_population_status','pending_verification'),
    jsonb_build_object('structure_observed_in_ocr',true,'canonical_text_asserted',false));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:contents',v_front,3,'front_matter_component','table_of_contents',
    jsonb_build_object(
      'entry_population_status','represented_by_chapter_structure',
      'chapter_start_pages',jsonb_build_array(7,17,27,35,45,53)
    ),
    jsonb_build_object('source_basis','observed contents structure; labels retained as structural observations, not canonical prose'));

  -- Body container and repeated body title observation.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:body',v_root,1,'section_group','body',
    jsonb_build_object('printed_page_start',7,'printed_page_end',63),
    jsonb_build_object('source_basis','printed pagination and chapter transitions in governed witness'))
  returning id into v_body;

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:body-title',v_body,0,'heading','body_title',
    jsonb_build_object('text_population_status','pending_verification','observed_label','The Wish Fairy and Dewy Dear','label_role','structural_observation_not_canonical_prose'),
    jsonb_build_object('structure_observed_in_ocr',true,'canonical_text_asserted',false));

  -- Chapter I.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:1',v_body,1,'chapter','chapter',
    jsonb_build_object('chapter_number',1,'observed_title','Dewy Dear','label_role','structural_observation_not_canonical_prose','printed_page_start',7,'printed_page_end',16),
    jsonb_build_object('source_basis','contents plus chapter transition in governed OCR derivative')) returning id into v_ch;
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph-stream',v_ch,0,'content_stream','paragraph_stream',
    jsonb_build_object('population_status','pending_page_image_verified_transcription','canonical_paragraph_count',null),
    jsonb_build_object('machine_segmentation_may_assist',true,'machine_segmentation_is_canonical',false));
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:page-9',v_ch,1,'illustration_placement','interior_color_plate',
    jsonb_build_object('printed_position',9,'source_pdf_page',13,'asset_population_status','pending_extraction'),
    jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  -- Chapter II.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:2',v_body,2,'chapter','chapter',
    jsonb_build_object('chapter_number',2,'observed_title','Roarabout and Wisselit','label_role','structural_observation_not_canonical_prose','printed_page_start',17,'printed_page_end',26),
    jsonb_build_object('source_basis','contents plus chapter transition in governed OCR derivative')) returning id into v_ch;
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:2:paragraph-stream',v_ch,0,'content_stream','paragraph_stream',jsonb_build_object('population_status','pending_page_image_verified_transcription','canonical_paragraph_count',null),jsonb_build_object('machine_segmentation_may_assist',true,'machine_segmentation_is_canonical',false));
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:page-19',v_ch,1,'illustration_placement','interior_color_plate',jsonb_build_object('printed_position',19,'source_pdf_page',23,'asset_population_status','pending_extraction'),jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  -- Chapter III.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:3',v_body,3,'chapter','chapter',jsonb_build_object('chapter_number',3,'observed_title','Twinkletoes','label_role','structural_observation_not_canonical_prose','printed_page_start',27,'printed_page_end',34),jsonb_build_object('source_basis','contents plus chapter transition in governed OCR derivative')) returning id into v_ch;
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:3:paragraph-stream',v_ch,0,'content_stream','paragraph_stream',jsonb_build_object('population_status','pending_page_image_verified_transcription','canonical_paragraph_count',null),jsonb_build_object('machine_segmentation_may_assist',true,'machine_segmentation_is_canonical',false));
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:page-29',v_ch,1,'illustration_placement','interior_color_plate',jsonb_build_object('printed_position',29,'source_pdf_page',33,'asset_population_status','pending_extraction'),jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  -- Chapter IV.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:4',v_body,4,'chapter','chapter',jsonb_build_object('chapter_number',4,'observed_title','Silver Nose and Star','label_role','structural_observation_not_canonical_prose','printed_page_start',35,'printed_page_end',44),jsonb_build_object('source_basis','contents plus chapter transition in governed OCR derivative')) returning id into v_ch;
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:4:paragraph-stream',v_ch,0,'content_stream','paragraph_stream',jsonb_build_object('population_status','pending_page_image_verified_transcription','canonical_paragraph_count',null),jsonb_build_object('machine_segmentation_may_assist',true,'machine_segmentation_is_canonical',false));
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:page-37',v_ch,1,'illustration_placement','interior_color_plate',jsonb_build_object('printed_position',37,'source_pdf_page',41,'asset_population_status','pending_extraction'),jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  -- Chapter V.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:5',v_body,5,'chapter','chapter',jsonb_build_object('chapter_number',5,'observed_title','Bumps','label_role','structural_observation_not_canonical_prose','printed_page_start',45,'printed_page_end',52),jsonb_build_object('source_basis','contents plus chapter transition in governed OCR derivative')) returning id into v_ch;
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:5:paragraph-stream',v_ch,0,'content_stream','paragraph_stream',jsonb_build_object('population_status','pending_page_image_verified_transcription','canonical_paragraph_count',null),jsonb_build_object('machine_segmentation_may_assist',true,'machine_segmentation_is_canonical',false));
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:page-47',v_ch,1,'illustration_placement','interior_color_plate',jsonb_build_object('printed_position',47,'source_pdf_page',51,'asset_population_status','pending_extraction'),jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  -- Chapter VI.
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:6',v_body,6,'chapter','chapter',jsonb_build_object('chapter_number',6,'observed_title','Black Face and White Face','label_role','structural_observation_not_canonical_prose','printed_page_start',53,'printed_page_end',63),jsonb_build_object('source_basis','contents plus chapter transition in governed OCR derivative')) returning id into v_ch;
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:chapter:6:paragraph-stream',v_ch,0,'content_stream','paragraph_stream',jsonb_build_object('population_status','pending_page_image_verified_transcription','canonical_paragraph_count',null),jsonb_build_object('machine_segmentation_may_assist',true,'machine_segmentation_is_canonical',false));
  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_package,'dewy:plate:page-55',v_ch,1,'illustration_placement','interior_color_plate',jsonb_build_object('printed_position',55,'source_pdf_page',59,'asset_population_status','pending_extraction'),jsonb_build_object('evidence_source_key','wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic'));

  -- Record the act that produced the skeleton.
  insert into wnph.transmission_acts(
    canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values(
    'wish-fairy-dewy-dear:transmission:semantic-skeleton-instantiation:v1',v_case,v_work,'semantic_skeleton_instantiation',
    'Instantiate the format-neutral structural skeleton of the canonical WNPH publication source before transcription.',
    'Directly evidenced front matter, six chapter spans, body range and seven color-plate placements are represented. OCR is used only as a structural aid. Canonical prose and machine-guessed paragraph boundaries are not populated.',
    'system_recorded','certain',
    jsonb_build_object('canonical_text_populated',false,'paragraph_slots_populated',false,'paragraph_stream_containers',6,'illustration_placements',7,'source_blocks_created',26)
  ) returning id into v_act;

  insert into wnph.transmission_act_agents(transmission_act_id,agent_id,agent_role)
  values(v_act,v_wnph_agent,'recovery_structure_process');

  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id)
  values(v_act,'input','preferred_historical_source',v_surrogate);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id)
  values(v_act,'input','ocr_structural_aid',v_ocr_source);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id)
  values(v_act,'input','illustration_placement_diagnostic',v_plate_source);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id)
  values(v_act,'context','canonical_publication_source',v_package);

  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id)
  select v_act,'output','semantic_skeleton_block',b.id
  from wnph.publication_source_blocks b
  where b.source_package_id=v_package;

  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  select v_act,es.id,'supports','high','OCR derivative supports the observed chapter/front-matter structural sequence but is not canonical reading text.'
  from wnph.evidence_sources es where es.id=v_ocr_source;
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  select v_act,es.id,'supports','high','Illustration diagnostic establishes all seven color-plate placements used by the skeleton.'
  from wnph.evidence_sources es where es.id=v_plate_source;

  -- Assertions: exactly the intended skeleton, no prose and no fabricated interventions.
  select count(*) into v_count from wnph.publication_source_blocks where source_package_id=v_package;
  if v_count <> 26 then raise exception 'WNPH Dewy semantic skeleton: expected 26 source blocks, found %',v_count; end if;
  if exists(select 1 from wnph.publication_source_blocks where source_package_id=v_package and text_content is not null) then
    raise exception 'WNPH Dewy semantic skeleton: no canonical prose may be populated in skeleton step';
  end if;
  if (select count(*) from wnph.publication_source_blocks where source_package_id=v_package and semantic_role='chapter') <> 6 then
    raise exception 'WNPH Dewy semantic skeleton: expected six chapters';
  end if;
  if (select count(*) from wnph.publication_source_blocks where source_package_id=v_package and semantic_role='paragraph_stream') <> 6 then
    raise exception 'WNPH Dewy semantic skeleton: expected six paragraph-stream containers';
  end if;
  if (select count(*) from wnph.publication_source_blocks where source_package_id=v_package and semantic_role in ('frontispiece','interior_color_plate')) <> 7 then
    raise exception 'WNPH Dewy semantic skeleton: expected seven illustration placements';
  end if;
  if exists(select 1 from wnph.transmission_interventions ti where ti.transmission_act_id=v_act) then
    raise exception 'WNPH Dewy semantic skeleton: no editorial interventions belong in skeleton instantiation';
  end if;
end $$;