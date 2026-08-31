-- Queue scan page 3 for reconstruction without admitting canonical text.
-- Wikisource is comparison evidence only; direct page-image verification remains required.
do $$
declare
  v_pkg uuid;
  v_root uuid;
  v_body uuid;
  v_stream uuid;
  v_asset uuid;
  v_obs uuid;
begin
  select p.id into strict v_pkg
  from wnph.publication_source_packages p
  where p.canonical_key='proper-new-booke-of-cookery:1575-canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);

  select b.id into strict v_root
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_key='proper-new-booke:document'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_pkg,'proper-new-booke:historical-body',v_root,2,'section','historical_body',
    jsonb_build_object('witness_year',1575,'canonical_text_completion',false),
    jsonb_build_object('structure_authority','source_page_sequence')
  ) returning id into v_body;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values(
    v_pkg,'proper-new-booke:page3:reading-stream',v_body,3,'reading_stream','historical_page_reading',
    jsonb_build_object('scan_page',3,'completion',false,'canonical_text_admitted',false),
    jsonb_build_object('structure_authority','governed_1575_source_surface')
  ) returning id into v_stream;

  select a.id into strict v_asset
  from wnph.publication_source_assets a
  where a.source_package_id=v_pkg
    and a.asset_key='proper-new-booke:1575:source-surface:0003'
    and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id);

  insert into wnph.publication_source_observations(
    source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
    confidence,derivation_method,source_format,processor,external_locator,metadata
  ) values(
    v_asset,
    'proper-new-booke:1575:page3:wikisource:first-region-candidate',
    'region',1,
    E'The Booke of\ncookery.\n\nBrawne is beſt from a fo ꝛ te-night befo ꝛ e Mighelmas till Lent. Beife and Bakon is good all times the yere. Mutton is good at all times, but from Eaſter to midſommer it is woo ꝛ ſt. A fat Pigge is ever in ſeaſon. A goſe is woo ꝛ ſt in midſommer moone, and beſt in ſtubble time, but whē they be yonge Greene Geeſe, than they be beſt. Veale is beſt in January and Feb ꝛ uarye and all other times good.',
    'surface',0.90,
    'external_transcription_alignment_pending_direct_visual_verification',
    'wikisource_proofreadpage',
    jsonb_build_object('provider','Wikisource','engine','ProofreadPage'),
    jsonb_build_object('scan_page',3,'url','https://en.wikisource.org/wiki/Page:A_Proper_New_Booke_of_Cookery_(1575).djvu/3'),
    jsonb_build_object(
      'canonical_authority',false,
      'verification_status','comparison_only',
      'direct_source_image_visual_inspection','pending',
      'promotion_allowed',false
    )
  ) returning id into v_obs;

  insert into wnph.publication_source_reconstruction_proposals(
    source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
    proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
    source_observation_ids,confidence,disposition,review_reasons,proposed_properties,
    proposed_source_provenance,algorithm
  ) values(
    v_pkg,
    'proper-new-booke:1575:reconstruction:page3-heading:v1',
    v_stream,
    'proper-new-booke:page3:heading',
    1,
    'heading',
    'historical_heading',
    'The Booke of cookery.',
    'usable',
    array[v_obs],
    0.90,
    'review',
    jsonb_build_array(
      'candidate currently supported only by comparison transcription',
      'direct visual verification against governed scan page 3 required before canonical admission'
    ),
    jsonb_build_object('scan_page',3,'modernization_performed',false),
    jsonb_build_object(
      'text_authority','comparison_transcription_only_pending_source_image_verification',
      'derivation_method','wikisource_candidate_reconstruction',
      'source_locators',jsonb_build_array(jsonb_build_object('scan_page',3,'asset_key','proper-new-booke:1575:source-surface:0003'))
    ),
    jsonb_build_object('engine','wnph_reconstruction_queue','version','1')
  );

  insert into wnph.publication_source_reconstruction_proposals(
    source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
    proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
    source_observation_ids,confidence,disposition,review_reasons,proposed_properties,
    proposed_source_provenance,algorithm
  ) values(
    v_pkg,
    'proper-new-booke:1575:reconstruction:page3-seasonal-paragraph-1:v1',
    v_stream,
    'proper-new-booke:page3:seasonal-paragraph-1',
    2,
    'paragraph',
    'historical_prose',
    'Brawne is best from a forte-night before Mighelmas till Lent. Beife and Bakon is good all times the yere. Mutton is good at all times, but from Easter to midsommer it is worst. A fat Pigge is ever in season. A gose is worst in midsommer moone, and best in stubble time, but when they be yonge Greene Geese, than they be best. Veale is best in January and Februarye and all other times good.',
    'usable',
    array[v_obs],
    0.88,
    'review',
    jsonb_build_array(
      'candidate currently supported only by comparison transcription',
      'ordinary reading characters have been proposed for long-s and r-shaped glyph forms but cannot be admitted until checked directly against scan page 3',
      'direct visual verification against governed scan page 3 required before canonical admission'
    ),
    jsonb_build_object('scan_page',3,'content_kind_candidate','seasonal_food_guidance','canonical_semantic_classification',false),
    jsonb_build_object(
      'text_authority','comparison_transcription_only_pending_source_image_verification',
      'derivation_method','wikisource_candidate_reading_character_normalization',
      'source_locators',jsonb_build_array(jsonb_build_object('scan_page',3,'asset_key','proper-new-booke:1575:source-surface:0003'))
    ),
    jsonb_build_object('engine','wnph_reconstruction_queue','version','1')
  );

  if exists(
    select 1 from wnph.publication_source_blocks b
    where b.source_package_id=v_pkg
      and b.parent_block_id=v_stream
      and b.text_content is not null
      and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  ) then
    raise exception 'WNPH Proper New Booke page 3 queue: candidate-only pass must not admit canonical text';
  end if;
end $$;