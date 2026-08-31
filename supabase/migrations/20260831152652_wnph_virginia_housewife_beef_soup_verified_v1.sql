with package as (
  select id from wnph.publication_source_packages
  where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1'
), scans(scan_sequence,printed_page,image_height,source_sha256,source_byte_length,signals) as (
  values
    (32,28,1886,'73a96ffa650edfb2cecbe6996bd96cf1d46debc543a280a44e0fb9653b07a40f',305225,jsonb_build_array('TO MAKE BEEF SOUP','hind shin of beef','leg-bone','one small table-spoonful','three onions','six small carrots','two small turnips','three quarts of water','five hours')),
    (33,29,1938,'d1fddf526daf49327c4e2184933fb78b24bbc7c1d0764ad25f5d3ffa83ea6156',305894,jsonb_build_array('bundle of thyme and parsley','pint of celery','tea-spoonful of celery seed','brown sugar','iron skillet','toasted bread','TO MAKE GRAVY SOUP'))
)
insert into wnph.publication_source_observations (
  source_asset_id,observation_key,observation_kind,ordinal,
  coordinate_unit,x,y,width,height,confidence,
  derivation_method,source_format,processor,external_locator,metadata
)
select
  a.id,
  format('virginia-house-wife:1824:beef-soup:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0')),
  'layout_region',1,'pixel',0,0,1200,s.image_height,0.98,
  'bounded_machine_pixel_corroboration_v1','image/jpeg',
  jsonb_build_object('provider','WNPH bounded source inspection','engine','ocrad.js 0.0.1','mode','whole_page_machine_corroboration'),
  jsonb_build_object(
    'asset_key',a.asset_key,'scan_sequence',s.scan_sequence,'printed_page',s.printed_page,
    'iiif_uri',format('https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:%s/full/1200,/0/default.jpg',lpad(s.scan_sequence::text,4,'0'))
  ),
  jsonb_build_object(
    'verification_role','machine_pixel_corroboration','human_visual_inspection',false,
    'source_image_verification_claim',false,'source_sha256',s.source_sha256,
    'source_byte_length',s.source_byte_length,'comparison_source_key','textgrid:virginia-house-wife:1824',
    'comparison_agreement',true,'agreement_scope','lexical_and_semantic_claim_support',
    'typographic_exactness_human_adjudicated',false,'stable_signals',s.signals
  )
from scans s
join package p on true
join wnph.publication_source_assets a
  on a.source_package_id=p.id
 and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(s.scan_sequence::text,4,'0'))
where not exists(
  select 1 from wnph.publication_source_observations o
  where o.source_asset_id=a.id
    and o.observation_key=format('virginia-house-wife:1824:beef-soup:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0'))
    and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id)
);

do $$
declare
  v_package wnph.publication_source_packages%rowtype;
  v_case wnph.recovery_cases%rowtype;
  v_work wnph.historical_works%rowtype;
  v_surrogate wnph.surrogates%rowtype;
  v_loc_source wnph.evidence_sources%rowtype;
  v_textgrid_source wnph.evidence_sources%rowtype;
  v_root_block uuid;
  v_soup_container uuid;
  v_block_id uuid;
  v_unit_id uuid;
  v_act_id uuid;
  v_locators jsonb;
  s record;
begin
  if exists(select 1 from wnph.transmission_acts where canonical_key='virginia-house-wife:1824:transmission:beef-soup:source-text-verification:v1') then
    return;
  end if;

  select * into strict v_package from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';
  select * into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1';
  select * into strict v_work from wnph.historical_works where canonical_key='virginia-house-wife';
  select * into strict v_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';
  select * into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:73217897';
  select * into strict v_textgrid_source from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824';
  select id into strict v_root_block from wnph.publication_source_blocks b
   where b.source_package_id=v_package.id and b.block_key='virginia-house-wife:1824:root'
     and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

  select id into v_soup_container from wnph.publication_source_blocks b
   where b.source_package_id=v_package.id and b.block_key='virginia-house-wife:1824:sequence:soups'
     and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);
  if v_soup_container is null then
    v_soup_container := gen_random_uuid();
    insert into wnph.publication_source_blocks(
      id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
      properties,source_provenance
    ) values(
      v_soup_container,v_package.id,'virginia-house-wife:1824:sequence:soups',v_root_block,2,
      'editorial_container','unheaded_soup_instruction_sequence',
      jsonb_build_object(
        'editorial_container',true,'printed_heading_absent',true,'first_printed_page',28,
        'historical_structure_status','adjudicated_from_exact_1824_sequence',
        'later_edition_SOUPS_heading_excluded',true
      ),
      jsonb_build_object(
        'structure_authority','LOC 1824 first edition corroborated by exact-1824 TextGrid transcription',
        'printed_heading_absent',true,'source_verified',true,
        'note','Editorial grouping only; no SOUPS heading is admitted at this boundary.'
      )
    );
  end if;

  select jsonb_agg(jsonb_build_object(
    'asset_key',a.asset_key,'scan_sequence',m.scan_sequence,'printed_page',m.printed_page,
    'source_sha256',m.sha256,'source_byte_length',m.byte_length
  ) order by m.scan_sequence) into v_locators
  from (values
    (32,28,'73a96ffa650edfb2cecbe6996bd96cf1d46debc543a280a44e0fb9653b07a40f',305225),
    (33,29,'d1fddf526daf49327c4e2184933fb78b24bbc7c1d0764ad25f5d3ffa83ea6156',305894)
  ) as m(scan_sequence,printed_page,sha256,byte_length)
  join wnph.publication_source_assets a
    on a.source_package_id=v_package.id
   and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'));

  v_block_id := gen_random_uuid();
  insert into wnph.publication_source_blocks(
    id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
    text_content,properties,source_provenance,reading_state
  ) values(
    v_block_id,v_package.id,'virginia-house-wife:1824:to-make-beef-soup',v_soup_container,1,
    'instruction','soup_recipe_and_service_protocol',
$beef$TO MAKE BEEF SOUP.

Take the hind shin of beef, cut off all the flesh of the leg-bone which must be taken away entirely, or the soup will be greasy.—Wash the meat clean and lay it in a pot, sprinkle over it one small table-spoonful of pounded black pepper, and two of salt; three onions the size of a hen's egg, cut small, six small carrots scraped and cut up, two small turnips pared and cut into dice; pour on three quarts of water, cover the pot close, and keep it gently and steadily boiling five hours, which will leave about three pints of clear soup; do not let the pot boil over, but take the scum carefully, as it rises.—When it has boiled four hours, put in a small bundle of thyme and parsley, and a pint of celery cut small, or a tea-spoonful of celery seed pounded. These latter ingredients, would lose their delicate flavour if boiled too much. Just before you take it up brown it in the following manner:—Put a small table-spoonful of nice brown sugar into an iron skillet, set it on the fire and stir it till it melts and looks very dark, pour into it a ladle full of the soup, a little at a time stirring it all the while. Strain the browning and mix it well with the soup; take out the bundle of thyme and parsley, put the nicest pieces of meat in your tureen, and pour on the soup and vegetables, put in some toasted bread cut in dice, and serve it up.$beef$,
    jsonb_build_object(
      'printed_pages',jsonb_build_array(28,29),'historical_unit_type','soup_recipe_and_service_protocol',
      'modern_safety_assessed',false,'modern_normalization_applied',false,'human_visual_inspection',false,
      'typographic_exactness_human_adjudicated',false,'next_heading','TO MAKE GRAVY SOUP.'
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first-edition source surfaces are controlling; exact-1824 TextGrid comparison supplies the lexical reading',
      'source_locators',v_locators,'verification_status','source_text_verified','source_verified',true,
      'controlling_witness','Library of Congress 1824 first edition','comparison_transcription_key','textgrid:virginia-house-wife:1824',
      'comparison_transcription_is_authority',false,'machine_pixel_corroboration',true,'human_visual_inspection',false,
      'source_image_verification_claim',false,'typographic_exactness_human_adjudicated',false,
      'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery',
      'derivation_method','exact_1824_comparison_transcription_corroborated_against_loc_pixels'
    ),'verified'
  );

  v_act_id := gen_random_uuid();
  insert into wnph.transmission_acts(
    id,canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values(
    v_act_id,'virginia-house-wife:1824:transmission:beef-soup:source-text-verification:v1',
    v_case.id,v_work.id,'source_text_verification',
    'Verify TO MAKE BEEF SOUP against the selected 1824 Library of Congress witness for functional-semantic recovery.',
    'LOC scans 32–33 are the controlling first-edition witness and bound the complete recipe from TO MAKE BEEF SOUP through the next heading TO MAKE GRAVY SOUP. Exact-1824 TextGrid supplies comparison wording. Machine pixel corroboration independently recovers the heading, ingredient quantities, five-hour simmer, delayed herbs/celery, brown-sugar colouring step, and service instructions. This does not claim human visual inspection or glyph-level adjudication.',
    'system_recorded','high',
    jsonb_build_object(
      'canonical_text_admission',true,'canonical_text_adjudication',false,'source_text_verified',true,
      'source_image_verified',false,'machine_pixel_corroboration',true,'human_visual_inspection',false,
      'page_image_is_controlling_witness',true,'comparison_transcription_key','textgrid:virginia-house-wife:1824',
      'comparison_transcription_is_authority',false,'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery',
      'typographic_exactness_human_adjudicated',false,'scan_locators',v_locators,'claim_promotion_target','verified_not_adjudicated'
    )
  );

  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id,locator)
  values(v_act_id,'input','preferred_historical_source',v_surrogate.id,jsonb_build_object('lccn','73217897','scan_sequences',jsonb_build_array(32,33)));
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id,locator)
  values(v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id,locator)
  values(v_act_id,'input','comparison_transcription',v_textgrid_source.id,jsonb_build_object('status','comparison_only','edition_year',1824));

  for s in
    select a.id,a.asset_key,m.scan_sequence,m.printed_page,m.sha256,m.byte_length
    from (values
      (32,28,'73a96ffa650edfb2cecbe6996bd96cf1d46debc543a280a44e0fb9653b07a40f',305225),
      (33,29,'d1fddf526daf49327c4e2184933fb78b24bbc7c1d0764ad25f5d3ffa83ea6156',305894)
    ) as m(scan_sequence,printed_page,sha256,byte_length)
    join wnph.publication_source_assets a
      on a.source_package_id=v_package.id
     and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'))
  loop
    insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_asset_id,locator)
    values(v_act_id,'input','source_page_image',s.id,jsonb_build_object(
      'asset_key',s.asset_key,'scan_sequence',s.scan_sequence,'printed_page',s.printed_page,
      'source_sha256',s.sha256,'source_byte_length',s.byte_length,'human_visual_inspection',false));
  end loop;

  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator)
  values(v_act_id,'output','verified_source_text',v_block_id,jsonb_build_object('block_key','virginia-house-wife:1824:to-make-beef-soup','reading_state','verified'));
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values
    (v_act_id,v_loc_source.id,'supports','certain','LOC LCCN 73217897 first-edition scans 32–33 are the controlling witness and provide the exact source surfaces.'),
    (v_act_id,v_textgrid_source.id,'supports','high','Exact-1824 TextGrid agrees with the LOC pixel reading and supplies comparison wording only.');

  v_unit_id := gen_random_uuid();
  insert into wnph.publication_semantic_units(
    id,expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,
    semantic_status,confidence,derivation_method,properties,source_provenance
  ) values(
    v_unit_id,v_package.expression_id,v_package.id,'virginia-house-wife:1824:semantic:beef-soup',null,8,
    'soup_recipe_and_service_protocol','TO MAKE BEEF SOUP.','verified',0.99,'source_text_verified_semantic_extraction_v1',
    jsonb_build_object(
      'printed_pages',jsonb_build_array(28,29),'primary_function','produce a clear beef-and-vegetable soup with late aromatics and browned-sugar colouring',
      'historical_container','unheaded soup instruction sequence','modern_safety_assessed',false,'modern_normalization_applied',false,
      'human_visual_inspection',false,'atlas_execution_requires_downstream_normalization',true
    ),
    jsonb_build_object(
      'source_verified',true,'source_block_id',v_block_id,'verification_status','source_text_verified','controlling_witness','LOC 1824',
      'machine_pixel_corroboration',true,'human_visual_inspection',false,'typographic_exactness_human_adjudicated',false,
      'comparison_transcription_key','textgrid:virginia-house-wife:1824'
    )
  );

  insert into wnph.publication_semantic_claims(
    semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,
    object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,
    claim_status,confidence,derivation_method,properties,source_provenance
  )
  select v_unit_id,v_block_id,x.claim_key,x.ordinal,x.claim_kind,x.subject_key,x.predicate,
         x.object_text,x.quantity_value,x.quantity_unit,x.quantity_text,x.temporal_text,x.condition_text,
         'verified',x.confidence,'source_text_verified_semantic_extraction_v1',x.properties,
         jsonb_build_object(
           'source_pages',x.source_pages,'source_verified',true,'verification_status','source_text_verified',
           'verified_source_block_id',v_block_id,'controlling_witness','LOC 1824','comparison_transcription','TextGrid exact 1824',
           'machine_pixel_corroboration',true,'human_visual_inspection',false,'typographic_exactness_human_adjudicated',false,
           'modern_use_requires_downstream_safety_review',x.safety_review
         )
  from (values
    (1,'primary-cut','ingredient_selection','beef','use_cut','hind shin',null::numeric,null::text,null::text,null::text,null::text,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (2,'remove-leg-bone','preparation','beef_shin','remove','leg-bone and flesh from it to avoid greasy soup',null,null,null,'before cooking',null,0.99,jsonb_build_object('historical_causal_claim',true),jsonb_build_array(28),true),
    (3,'wash-meat','historical_raw_meat_handling','beef','wash','wash meat clean',null,null,null,'before pot',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(28),true),
    (4,'black-pepper','ingredient_quantity','soup','contains','pounded black pepper',1::numeric,'small_tablespoon','one small table-spoonful',null,null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (5,'salt','ingredient_quantity','soup','contains','salt',2::numeric,'tablespoon','two table-spoonfuls',null,null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (6,'onions','ingredient_quantity','soup','contains','onions about the size of a hen''s egg, cut small',3::numeric,'count','three onions',null,null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (7,'carrots','ingredient_quantity','soup','contains','small carrots, scraped and cut up',6::numeric,'count','six small carrots',null,null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (8,'turnips','ingredient_quantity','soup','contains','small turnips, pared and diced',2::numeric,'count','two small turnips',null,null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (9,'water','ingredient_quantity','soup','contains','water',3::numeric,'quart','three quarts',null,null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (10,'covered-pot','cooking_condition','soup','cook_covered','cover pot close',null,null,null,'during main boil',null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (11,'main-boil','historical_cooking_duration','soup','boil','gently and steadily',5::numeric,'hour','five hours','main cooking stage',null,0.99,jsonb_build_object('modern_safety_assessed',false),jsonb_build_array(28),true),
    (12,'yield','yield','soup','yields','clear soup',3::numeric,'pint_approximate','about three pints','after five hours',null,0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (13,'skim','cooking_maintenance','soup','skim','remove scum carefully as it rises',null,null,null,'during boiling','do not let pot boil over',0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (14,'late-herbs','ingredient_timing','soup','add','small bundle thyme and parsley',null,null,null,'after four hours of boiling',null,0.99,jsonb_build_object('delayed_aromatic',true),jsonb_build_array(29),false),
    (15,'celery-option','ingredient_option','soup','add','one pint celery cut small OR one tea-spoonful pounded celery seed',1::numeric,'pint_or_teaspoon','one pint celery or one tea-spoonful celery seed','after four hours of boiling',null,0.99,jsonb_build_object('alternatives',jsonb_build_array('celery','celery_seed')),jsonb_build_array(29),false),
    (16,'late-aromatic-rationale','historical_flavour_rule','late_aromatics','delay_to_preserve','delicate flavour',null,null,null,'late in cooking','Randolph says prolonged boiling would diminish flavour',0.98,jsonb_build_object('author_judgment',true),jsonb_build_array(29),false),
    (17,'brown-sugar','colouring_ingredient','soup_browning','contains','nice brown sugar',1::numeric,'small_tablespoon','one small table-spoonful','just before serving',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
    (18,'browning-method','colouring_process','soup_browning','prepare','melt sugar in iron skillet until very dark; add a ladle of soup gradually while stirring',null,null,null,'just before serving',null,0.99,jsonb_build_object('equipment','iron skillet'),jsonb_build_array(29),false),
    (19,'strain-browning','finishing','soup_browning','strain_and_mix','strain browning and mix into soup',null,null,null,'after browning preparation',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
    (20,'remove-herb-bundle','finishing','soup','remove','bundle of thyme and parsley',null,null,null,'before service',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
    (21,'select-meat-for-tureen','plating','beef','select_and_place','nicest pieces in tureen',null,null,null,'before pouring soup',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
    (22,'serve-vegetables','plating','soup','serve_with','soup and vegetables poured over meat',null,null,null,'at service',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
    (23,'toasted-bread','service','soup','finish_with','toasted bread cut in dice',null,null,null,'at service',null,0.99,jsonb_build_object(),jsonb_build_array(29),false)
  ) as x(ordinal,claim_key,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,confidence,properties,source_pages,safety_review);
end $$;