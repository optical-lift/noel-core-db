do $$
declare
  v_pkg uuid;
  v_expression uuid;
  v_opening uuid;
  v_textgrid uuid;
  v_obs uuid;
  v_proposal uuid;
  v_block uuid;
  v_unit uuid;
begin
  select p.id,p.expression_id into v_pkg,v_expression
  from wnph.publication_source_packages p
  where p.canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';

  if v_pkg is null then
    raise exception 'WNPH Virginia souse candidate: source package is missing';
  end if;

  if exists(
    select 1 from wnph.publication_semantic_units u
    where u.source_package_id=v_pkg
      and u.unit_key='virginia-house-wife:1824:semantic:make-souse'
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
  where a.source_package_id=v_pkg
    and a.asset_key='virginia-house-wife:1824:textgrid-transcription'
  order by a.created_at desc limit 1;

  if v_opening is null or v_textgrid is null then
    raise exception 'WNPH Virginia souse candidate: corrected opening/TextGrid prerequisites are missing';
  end if;

  insert into wnph.publication_source_observations(
    source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
    confidence,derivation_method,source_format,processor,external_locator,metadata
  ) values (
    v_textgrid,
    'virginia-house-wife:1824:p20-21:make-souse',
    'region',20,
    'TO MAKE SOUSE. Let all the pieces you intend to souse remain covered with cold water twelve hours; wash and wipe off blood, return them to fresh water, change it frequently in a cool place until the blood is drawn away; scrape and clean each piece; boil gently in meal-water with salt until a straw enters the skin easily. Avoid crowding the pot. Boil feet separately, ears and nose separately, and heads separately; debone heads, cool, season with pepper, salt and a little nutmeg, roll tightly, sew in cloth and press lightly. Make a pale meal-water-salt liquor with one-fourth vinegar, keep souse covered and closely stopped, renew every two or three weeks, and cool the souse fully before putting it into the liquor. Pale vinegar preserves the desired light colour; Randolph says singeing the hair darkens it.',
    'surface',0.97,
    'exact_1824_textgrid_transcription_bounded_semantic_observation',
    'text/html transcription',
    jsonb_build_object('provider','TextGrid Repository','engine','repository_transcription','edition','1824'),
    jsonb_build_object('printed_pages',jsonb_build_array(20,21),'resource_uri','https://sandbox.textgridrep.org/browse/textgrid%3A2s1gn.0?mode=gallery'),
    jsonb_build_object(
      'comparison_only',true,
      'semantic_abbreviation',true,
      'facsimile_page_span_cross_check','Hess facsimile as cited by Colonial Williamsburg: pp. 20-21',
      'controlling_witness_page_images_inspected',false
    )
  ) returning id into v_obs;

  insert into wnph.publication_source_reconstruction_proposals(
    source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
    proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
    source_observation_ids,confidence,disposition,review_reasons,proposed_properties,
    proposed_source_provenance,algorithm
  ) values (
    v_pkg,
    'virginia-house-wife:1824:make-souse:reconstruction:v1',
    v_opening,
    'virginia-house-wife:1824:to-make-souse',
    4,
    'instruction',
    'soak_clean_cook_form_acidified_storage_protocol',
    'TO MAKE SOUSE. Candidate reconstruction: soak the reserved pork parts in repeated cold water to remove blood; scrape and clean them; boil gently with meal-water and salt, separating anatomical groups and deboning heads; cool, season, roll, sew and press; then hold the finished souse under a meal-water-salt-vinegar liquor, renewing it periodically and preserving the pale appearance Randolph preferred.',
    'candidate',
    array[v_obs],
    0.96,
    'review',
    jsonb_build_array(
      'TextGrid exact-1824 transcription is comparison-only; LOC 1824 remains controlling witness',
      'LOC printed pages 20-21 have not passed direct page-image verification',
      'historical meat soaking, cooking, acidification and storage instructions require downstream modern safety review'
    ),
    jsonb_build_object(
      'historical_unit_type','soak_clean_cook_form_acidified_storage_protocol',
      'printed_pages',jsonb_build_array(20,21),
      'modern_safety_assessed',false,
      'incoming_dependency',jsonb_build_object('from_unit_key','virginia-house-wife:1824:semantic:cure-bacon','materials',jsonb_build_array('feet','ears','nose')),
      'historical_preservation_instruction',true
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first edition remains controlling; TextGrid exact-1824 transcription supplies comparison reading only',
      'source_locators',jsonb_build_array(
        jsonb_build_object('printed_page',20,'comparison_asset','virginia-house-wife:1824:textgrid-transcription'),
        jsonb_build_object('printed_page',21,'comparison_asset','virginia-house-wife:1824:textgrid-transcription')
      ),
      'derivation_method','exact-1824 comparison transcription with facsimile page-span cross-check; controlling-witness page-image verification pending',
      'verification_status','candidate_not_page_image_verified'
    ),
    jsonb_build_object('engine','wnph_exact_edition_semantic_reconstructor','version','1')
  ) returning id into v_proposal;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,
    properties,source_provenance,reading_state
  ) values (
    v_pkg,'virginia-house-wife:1824:to-make-souse',v_opening,4,'instruction',
    'soak_clean_cook_form_acidified_storage_protocol',
    (select proposed_text_content from wnph.publication_source_reconstruction_proposals where id=v_proposal),
    jsonb_build_object(
      'historical_unit_type','soak_clean_cook_form_acidified_storage_protocol',
      'printed_pages',jsonb_build_array(20,21),
      'modern_safety_assessed',false,
      'incoming_dependency',jsonb_build_object('from_unit_key','virginia-house-wife:1824:semantic:cure-bacon','materials',jsonb_build_array('feet','ears','nose')),
      'reconstruction_proposal_id',v_proposal::text
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first edition remains controlling; candidate block is a bounded semantic reconstruction, not a verified transcription',
      'source_locators',jsonb_build_array(
        jsonb_build_object('printed_page',20,'asset_key','virginia-house-wife:1824:textgrid-transcription'),
        jsonb_build_object('printed_page',21,'asset_key','virginia-house-wife:1824:textgrid-transcription')
      ),
      'derivation_method','bounded_semantic_reconstruction_from_exact_1824_comparison_transcription',
      'verification_status','candidate_not_page_image_verified',
      'source_verified',false
    ),
    'candidate'
  ) returning id into v_block;

  insert into wnph.publication_semantic_units(
    expression_id,source_package_id,unit_key,ordinal,unit_type,source_title,semantic_status,
    confidence,derivation_method,properties,source_provenance
  ) values (
    v_expression,v_pkg,'virginia-house-wife:1824:semantic:make-souse',4,
    'soak_clean_cook_form_acidified_storage_protocol','TO MAKE SOUSE.','candidate',0.96,
    'functional_semantic_parse_from_exact_1824_comparison_transcription',
    jsonb_build_object(
      'historical_container','unsectioned opening instruction sequence',
      'printed_pages',jsonb_build_array(20,21),
      'primary_function','prepare, cook, form and historically preserve souse',
      'modern_safety_assessed',false,
      'modern_normalization_applied',false,
      'incoming_dependency',jsonb_build_object('from_unit_key','virginia-house-wife:1824:semantic:cure-bacon','materials',jsonb_build_array('feet','ears','nose')),
      'historical_preservation_instruction',true
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
      'source_pages',jsonb_build_array(20,21),
      'comparison_transcription','TextGrid exact 1824',
      'controlling_witness','LOC 1824',
      'modern_use_requires_downstream_safety_review',x.safety_review
    )
  from (values
    ('incoming-bacon-parts',1,'cross_unit_handoff','souse_materials','receive_from','cure-bacon process: feet, ears, nose',null::numeric,null::text,null::text,null::text,null::text,0.99::numeric,jsonb_build_object('source_unit_key','virginia-house-wife:1824:semantic:cure-bacon'),false),
    ('initial-cold-soak',2,'process_timing','souse_pieces','soak_covered_in','cold water',12,'hour','twelve hours','before washing',null,0.99,'{}'::jsonb,true),
    ('wash-blood',3,'cleaning','souse_pieces','wash_and_wipe','blood',null,null,null,'after initial soak',null,0.99,'{}'::jsonb,true),
    ('repeat-fresh-water',4,'cleaning','souse_pieces','repeat_soak','fresh water changed frequently until blood is drawn away',null,null,null,'until blood is drawn away','keep in a cool place',0.99,'{}'::jsonb,true),
    ('scrape-clean',5,'cleaning','souse_pieces','scrape_and_clean','each piece',null,null,null,'before boiling',null,0.99,'{}'::jsonb,true),
    ('boiling-medium',6,'cooking_medium','souse','boil_in','meal mixed with water and salt',null,null,null,null,null,0.98,'{}'::jsonb,true),
    ('gentle-boil-endpoint',7,'cooking_endpoint','souse','boil_gently_until','a straw can run into the skin with ease',null,null,null,null,null,0.99,jsonb_build_object('historical_endpoint',true,'modern_safety_assessed',false),true),
    ('avoid-pot-crowding',8,'process_constraint','souse','avoid','too much in the pot because pieces may boil apart and spoil appearance',null,null,null,'during boiling',null,0.99,'{}'::jsonb,true),
    ('separate-boiling-groups',9,'process_partition','souse_parts','boil_separately','feet; ears and nose; heads',null,null,null,'during boiling',null,0.99,jsonb_build_object('groups',jsonb_build_array('feet','ears_and_nose','heads')),true),
    ('debone-heads',10,'preparation','heads','boil_until','all bones can be removed',null,null,null,null,null,0.99,jsonb_build_object('historical_endpoint',true),true),
    ('cool-before-seasoning',11,'process_sequence','cooked_parts','cool','before seasoning/forming',null,null,null,'after boiling',null,0.98,'{}'::jsonb,true),
    ('season-insides',12,'seasoning','cooked_parts','season_inside_with','pepper, salt, and a little nutmeg',null,null,null,'after cooling',null,0.99,'{}'::jsonb,false),
    ('roll-sew-press',13,'forming','seasoned_parts','form','tight roll; sew closely in cloth; press lightly',null,null,null,'after seasoning',null,0.99,'{}'::jsonb,false),
    ('holding-liquor',14,'historical_preservation_medium','souse','cover_with','meal and cold water just white, salt, and one-fourth vinegar',0.25,'proportion_vinegar','one-fourth vinegar',null,'after souse is quite cold',0.98,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),true),
    ('separate-storage-pots',15,'storage','souse','store','in different pots, well covered with liquor and closely stopped',null,null,null,null,null,0.99,jsonb_build_object('historical_storage_instruction',true),true),
    ('renew-liquor',16,'maintenance','holding_liquor','renew_every','two or three weeks',2,'week_minimum','two or three weeks','during storage',null,0.99,jsonb_build_object('maximum_value',3,'modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),true),
    ('cool-before-liquor',17,'process_sequence','souse','cool_completely','before placing in holding liquor',null,null,null,'after boiling','before liquor',0.99,jsonb_build_object('historical_preservation_instruction',true),true),
    ('pale-vinegar-colour',18,'appearance_rule','vinegar','prefer','pale coloured vinegar so souse will not be dark',null,null,null,null,null,0.99,jsonb_build_object('appearance_goal','white souse'),false),
    ('avoid-singeing-for-colour',19,'appearance_rule','feet','avoid','singeing hair because Randolph says it destroys the colour',null,null,null,null,null,0.98,jsonb_build_object('historical_appearance_judgment',true,'desired_colour','white'),false)
  ) as x(
    claim_key,ordinal,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,
    quantity_text,temporal_text,condition_text,confidence,properties,safety_review
  );
end $$;