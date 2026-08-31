do $$
declare
  v_pkg uuid;
  v_expression uuid;
  v_opening uuid;
  v_textgrid uuid;
  v_loc_pdf uuid;
  v_obs17 uuid;
  v_obs18 uuid;
  v_obs19_cmp uuid;
  v_obs19_loc uuid;
  v_proposal uuid;
  v_block uuid;
  v_unit uuid;
begin
  select p.id,p.expression_id into v_pkg,v_expression
  from wnph.publication_source_packages p
  where p.canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';

  if v_pkg is null then
    raise exception 'WNPH Virginia cure-bacon candidate: source package is missing';
  end if;

  if exists(
    select 1 from wnph.publication_semantic_units u
    where u.source_package_id=v_pkg
      and u.unit_key='virginia-house-wife:1824:semantic:cure-bacon'
      and not exists(select 1 from wnph.publication_semantic_units n where n.supersedes_unit_id=u.id)
  ) then
    return;
  end if;

  select b.id into v_opening
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_key='virginia-house-wife:1824:sequence:opening-preservation'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;

  select a.id into v_textgrid
  from wnph.publication_source_assets a
  where a.source_package_id=v_pkg and a.asset_key='virginia-house-wife:1824:textgrid-transcription'
  order by a.created_at desc limit 1;

  select a.id into v_loc_pdf
  from wnph.publication_source_assets a
  where a.source_package_id=v_pkg and a.asset_key='virginia-house-wife:1824:loc-pdf'
  order by a.created_at desc limit 1;

  if v_opening is null or v_textgrid is null or v_loc_pdf is null then
    raise exception 'WNPH Virginia cure-bacon candidate: corrected opening/TextGrid/LOC source prerequisites are missing';
  end if;

  insert into wnph.publication_source_observations(
    source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
    confidence,derivation_method,source_format,processor,external_locator,metadata
  ) values (
    v_textgrid,'virginia-house-wife:1824:p17:cure-bacon','page_text',17,
    'TO CURE BACON. Hogs are in the highest perfection, from two and a half to four years old, and make',
    'surface',0.98,'exact_1824_textgrid_transcription_comparison','text/html transcription',
    jsonb_build_object('provider','TextGrid Repository','engine','repository_transcription','edition','1824'),
    jsonb_build_object('printed_page',17,'resource_uri','https://sandbox.textgridrep.org/browse/textgrid%3A2s1gn.0?mode=gallery'),
    jsonb_build_object('comparison_only',true,'controlling_witness_page_image_inspected',false)
  ) returning id into v_obs17;

  insert into wnph.publication_source_observations(
    source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
    confidence,derivation_method,source_format,processor,external_locator,metadata
  ) values (
    v_textgrid,'virginia-house-wife:1824:p18:cure-bacon','page_text',18,
    'the best bacon, when they do not weigh more than one hundred and fifty or sixty at farthest. They should be fed with corn six weeks at least before they are killed. Salt before the meat gets cold; separate hams, shoulders and middlings; salt the cuts, and prepare feet, ears and nose for souse. The jowls remain in salt two weeks before smoking.',
    'surface',0.96,'exact_1824_textgrid_transcription_comparison_with_bounded_semantic_abbreviation','text/html transcription',
    jsonb_build_object('provider','TextGrid Repository','engine','repository_transcription','edition','1824'),
    jsonb_build_object('printed_page',18,'resource_uri','https://sandbox.textgridrep.org/browse/textgrid%3A2s1gn.0?mode=gallery'),
    jsonb_build_object('comparison_only',true,'semantic_abbreviation',true,'controlling_witness_page_image_inspected',false)
  ) returning id into v_obs18;

  insert into wnph.publication_source_observations(
    source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
    confidence,derivation_method,source_format,processor,external_locator,metadata
  ) values (
    v_textgrid,'virginia-house-wife:1824:p19:cure-bacon:textgrid','page_text',19,
    'Smoke shoulders and middlings after three weeks and hams after four; longer salting hardens them. Hang hocks down. Make smoke every morning without a blaze; keep the smoke-house separate from added heat. Beginning April first, inspect during hot weather, rub with hickory ashes, and rehang. Randolph then discusses salt-petre, brining, boiling bacon, and the longer boiling required by new bacon.',
    'surface',0.97,'exact_1824_textgrid_transcription_comparison_with_bounded_semantic_abbreviation','text/html transcription',
    jsonb_build_object('provider','TextGrid Repository','engine','repository_transcription','edition','1824'),
    jsonb_build_object('printed_page',19,'resource_uri','https://sandbox.textgridrep.org/browse/textgrid%3A2s1gn.0?mode=gallery'),
    jsonb_build_object('comparison_only',true,'semantic_abbreviation',true,'controlling_witness_page_image_inspected',false)
  ) returning id into v_obs19_cmp;

  insert into wnph.publication_source_observations(
    source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
    confidence,derivation_method,source_format,processor,external_locator,metadata
  ) values (
    v_loc_pdf,'virginia-house-wife:1824:p19:cure-bacon:loc-indexed','page_text',19,
    'The Library of Congress indexed PDF resolves printed page 19 as the close of the cure-bacon instruction, including three/four-week smoke timing, hocks-down hanging, daily smoke without blaze, April hot-weather hickory-ash maintenance, salt-petre/brine commentary, and bacon/ham boiling endpoints.',
    'surface',0.99,'direct_loc_pdf_indexed_text_semantic_observation','application/pdf indexed text',
    jsonb_build_object('provider','Library of Congress','engine','indexed_pdf_text','edition','1824'),
    jsonb_build_object('printed_page',19,'pdf_uri','https://tile.loc.gov/storage-services/service/rbc/rbc0001/2015/2015pennell17897/2015pennell17897.pdf'),
    jsonb_build_object('controlling_witness',true,'page_image_inspected',false,'indexed_text_only',true)
  ) returning id into v_obs19_loc;

  insert into wnph.publication_source_reconstruction_proposals(
    source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
    proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
    source_observation_ids,confidence,disposition,review_reasons,proposed_properties,
    proposed_source_provenance,algorithm
  ) values (
    v_pkg,
    'virginia-house-wife:1824:cure-bacon:reconstruction:v1',
    v_opening,
    'virginia-house-wife:1824:to-cure-bacon',
    3,
    'instruction',
    'animal_selection_butchery_cure_smoke_storage_protocol',
    'TO CURE BACON. Candidate reconstruction: select hogs by age, size, feed and travel condition; butcher into hams, shoulders, middlings and jowls; salt with cut-specific salt-petre treatment; reserve feet, ears and nose for souse; smoke cuts after different cure intervals; hang hocks down; operate a cool smoke-house without blaze; inspect and ash-rub during hot weather; then apply the stated historical boiling guidance.',
    'candidate',
    array[v_obs17,v_obs18,v_obs19_cmp,v_obs19_loc],
    0.96,
    'review',
    jsonb_build_array(
      'TextGrid supplies exact-1824 comparison reading but is not the controlling witness',
      'LOC printed page 19 is resolved through indexed PDF text, not direct page-image inspection',
      'LOC printed pages 17-18 have not passed direct page-image verification',
      'historical preservation and salt-petre claims require downstream modern safety separation'
    ),
    jsonb_build_object(
      'historical_unit_type','animal_selection_butchery_cure_smoke_storage_protocol',
      'printed_pages',jsonb_build_array(17,18,19),
      'modern_safety_assessed',false,
      'cross_unit_dependency',jsonb_build_object('reserved_parts_for','souse'),
      'historical_health_or_preservation_beliefs_present',true
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first edition remains controlling; TextGrid exact-1824 transcription is comparison-only',
      'source_locators',jsonb_build_array(
        jsonb_build_object('printed_page',17,'comparison_asset','virginia-house-wife:1824:textgrid-transcription'),
        jsonb_build_object('printed_page',18,'comparison_asset','virginia-house-wife:1824:textgrid-transcription'),
        jsonb_build_object('printed_page',19,'asset_key','virginia-house-wife:1824:loc-pdf','comparison_asset','virginia-house-wife:1824:textgrid-transcription')
      ),
      'derivation_method','exact-1824 comparison transcription plus controlling-witness indexed-PDF cross-check; page-image verification pending',
      'verification_status','candidate_not_page_image_verified'
    ),
    jsonb_build_object('engine','wnph_exact_edition_semantic_reconstructor','version','1')
  ) returning id into v_proposal;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,
    properties,source_provenance,reading_state
  ) values (
    v_pkg,'virginia-house-wife:1824:to-cure-bacon',v_opening,3,'instruction',
    'animal_selection_butchery_cure_smoke_storage_protocol',
    (select proposed_text_content from wnph.publication_source_reconstruction_proposals where id=v_proposal),
    jsonb_build_object(
      'historical_unit_type','animal_selection_butchery_cure_smoke_storage_protocol',
      'printed_pages',jsonb_build_array(17,18,19),
      'modern_safety_assessed',false,
      'cross_unit_dependency',jsonb_build_object('reserved_parts_for','souse'),
      'reconstruction_proposal_id',v_proposal::text
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first edition remains controlling; candidate block is a bounded semantic reconstruction, not a verified transcription',
      'source_locators',jsonb_build_array(
        jsonb_build_object('printed_page',17,'asset_key','virginia-house-wife:1824:textgrid-transcription'),
        jsonb_build_object('printed_page',18,'asset_key','virginia-house-wife:1824:textgrid-transcription'),
        jsonb_build_object('printed_page',19,'asset_key','virginia-house-wife:1824:loc-pdf')
      ),
      'derivation_method','bounded_semantic_reconstruction_from_exact_1824_comparison_and_loc_indexed_text',
      'verification_status','candidate_not_page_image_verified',
      'source_verified',false
    ),
    'candidate'
  ) returning id into v_block;

  insert into wnph.publication_semantic_units(
    expression_id,source_package_id,unit_key,ordinal,unit_type,source_title,semantic_status,
    confidence,derivation_method,properties,source_provenance
  ) values (
    v_expression,v_pkg,'virginia-house-wife:1824:semantic:cure-bacon',3,
    'animal_selection_butchery_cure_smoke_storage_protocol','TO CURE BACON.','candidate',0.96,
    'functional_semantic_parse_from_exact_1824_comparison_and_loc_indexed_text',
    jsonb_build_object(
      'historical_container','unsectioned opening instruction sequence',
      'printed_pages',jsonb_build_array(17,18,19),
      'primary_function','select, butcher, cure, smoke, store and cook bacon',
      'modern_safety_assessed',false,
      'modern_normalization_applied',false,
      'cross_unit_dependency',jsonb_build_object('reserved_parts_for','souse'),
      'historical_preservation_beliefs_present',true
    ),
    jsonb_build_object(
      'source_block_id',v_block::text,
      'source_verified',false,
      'source_state','candidate',
      'controlling_witness','1824 LOC first edition',
      'comparison_transcription','TextGrid exact 1824'
    )
  ) returning id into v_unit;

  insert into wnph.publication_semantic_claims(
    semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,object_text,
    quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,claim_status,confidence,
    derivation_method,properties,source_provenance
  )
  select
    v_unit,v_block,x.claim_key,x.ordinal,x.claim_kind,x.subject_key,x.predicate,x.object_text,
    x.quantity_value,x.quantity_unit,x.quantity_text,x.temporal_text,x.condition_text,
    'candidate',x.confidence,'historical_function_parse_without_modern_normalization',x.properties,
    jsonb_build_object(
      'source_verified',false,
      'source_pages',x.source_pages,
      'comparison_transcription','TextGrid exact 1824',
      'controlling_witness','LOC 1824',
      'modern_use_requires_downstream_safety_review',x.safety_review
    )
  from (values
    ('hog-age',1,'material_selection','hog','preferred_age','two and a half to four years',2.5::numeric,'year_minimum','two and a half to four years',null::text,null::text,0.98::numeric,jsonb_build_object('maximum_value',4,'maximum_unit','year'),jsonb_build_array(17,18),false),
    ('hog-weight',2,'material_selection','hog','preferred_max_weight','one hundred and fifty or sixty at farthest',150,'pound_target','150 to 160 pounds',null,null,0.96,jsonb_build_object('historical_range_max',160),jsonb_build_array(18),false),
    ('corn-feed-duration',3,'material_selection','hog','feed_before_killing','corn',6,'week_minimum','six weeks at least','before killing',null,0.99,'{}'::jsonb,jsonb_build_array(18),false),
    ('market-drive-distance',4,'historical_quality_judgment','hog','prefer','shorter distance driven to market',null,null,null,'before killing',null,0.97,jsonb_build_object('author_judgment',true),jsonb_build_array(18),false),
    ('salt-before-cold',5,'preservation_timing','fresh_pork','salt','before meat gets cold',null,null,null,'immediately after butchery','to secure against spoiling',0.99,jsonb_build_object('historical_preservation_instruction',true),jsonb_build_array(18),true),
    ('remove-chine',6,'butchery','carcass','remove','chine/back-bone from neck to tail',null,null,null,null,null,0.98,'{}'::jsonb,jsonb_build_array(18),false),
    ('separate-primary-cuts',7,'butchery','carcass','separate_into','hams, shoulders, middlings; ribs from shoulders; leaf fat from hams',null,null,null,null,null,0.98,'{}'::jsonb,jsonb_build_array(18),false),
    ('ham-saltpetre',8,'cure_application','ham','rub_inside_with','large table-spoonful of salt-petre for some minutes',1,'large_tablespoon','one large table-spoonful',null,'inside each ham',0.98,jsonb_build_object('historical_preservation_instruction',true),jsonb_build_array(18),true),
    ('ham-salt-layering',9,'cure_application','ham','salt_and_layer','rub both sides with salt; lay skin downward with salt between layers',null,null,null,null,null,0.99,'{}'::jsonb,jsonb_build_array(18),true),
    ('shoulder-middling-cure',10,'cure_application','shoulders_and_middlings','salt_like_hams','same general method with less salt-petre',null,null,null,null,null,0.98,jsonb_build_object('relative_quantity','less salt-petre'),jsonb_build_array(18),true),
    ('jowl-cure',11,'cure_application','jowl','rub_with','salt and salt-petre',null,null,null,null,null,0.98,'{}'::jsonb,jsonb_build_array(18),true),
    ('reserve-souse-parts',12,'cross_unit_handoff','feet_ears_nose','reserve_for','souse in large tub of cold water',null,null,null,null,null,0.99,jsonb_build_object('target_unit_key','virginia-house-wife:1824:semantic:make-souse'),jsonb_build_array(18),true),
    ('jowl-cure-duration',13,'process_timing','jowl','smoke_after',null,2,'week','two weeks','after salting',null,0.99,'{}'::jsonb,jsonb_build_array(18,19),true),
    ('shoulder-middling-duration',14,'process_timing','shoulders_and_middlings','smoke_after',null,3,'week','three weeks','after salting',null,0.99,'{}'::jsonb,jsonb_build_array(19),true),
    ('ham-cure-duration',15,'process_timing','ham','smoke_after',null,4,'week','four weeks','after salting',null,0.99,'{}'::jsonb,jsonb_build_array(19),true),
    ('overlong-salt-hardens',16,'historical_causal_claim','cured_pork','avoid_overlong_salting','remaining longer in salt hardens meat',null,null,null,null,'beyond stated intervals',0.97,jsonb_build_object('modern_validity_assessed',false),jsonb_build_array(19),true),
    ('hocks-down',17,'storage_orientation','hams_and_shoulders','hang','hocks down to preserve juices',null,null,null,'during smoking/storage',null,0.99,'{}'::jsonb,jsonb_build_array(19),false),
    ('daily-smoke',18,'smokehouse_operation','smokehouse','make_smoke','good smoke every morning',null,null,null,'every morning','no blaze',0.99,jsonb_build_object('open_flame_warning_historical',true),jsonb_build_array(19),true),
    ('standalone-smokehouse',19,'smokehouse_operation','smokehouse','keep_separate','stand alone; additional heat will spoil meat',null,null,null,null,null,0.98,jsonb_build_object('historical_preservation_instruction',true),jsonb_build_array(19),true),
    ('april-maintenance',20,'seasonal_maintenance','smoked_meat','inspect_and_rehang','take down, examine, rub with hickory ashes, and hang again',null,null,null,'hot weather beginning first of April','occasionally',0.99,'{}'::jsonb,jsonb_build_array(19),true),
    ('saltpetre-preservation-belief',21,'historical_preservation_claim','salt_petre','attributed_effect','prevent putrefaction without hardening meat',null,null,null,null,null,0.98,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(19),true),
    ('cold-brine-hardening-belief',22,'historical_preservation_claim','cold_weather_brining','not_attributed_effect','five or six weeks in brine does not harden meat',5,'week_minimum','five or six weeks','cold weather',null,0.96,jsonb_build_object('maximum_value',6,'modern_validity_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(19),true),
    ('bacon-boil-water',23,'cooking_condition','bacon','boil_in','large quantity of water',null,null,null,null,null,0.99,'{}'::jsonb,jsonb_build_array(19),true),
    ('ham-boil-endpoint',24,'cooking_endpoint','ham','boil_until','bone on under part comes off with ease',null,null,null,null,null,0.99,jsonb_build_object('historical_endpoint',true,'modern_safety_assessed',false),jsonb_build_array(19),true),
    ('new-bacon-longer-boil',25,'relative_cooking_time','new_bacon','requires','much longer boiling than old bacon',null,null,null,null,null,0.99,'{}'::jsonb,jsonb_build_array(19),true)
  ) as x(
    claim_key,ordinal,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,
    quantity_text,temporal_text,condition_text,confidence,properties,source_pages,safety_review
  );
end $$;