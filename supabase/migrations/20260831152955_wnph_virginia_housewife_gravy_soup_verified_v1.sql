with package as (
  select id from wnph.publication_source_packages
  where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1'
), scans(scan_sequence,printed_page,image_height,source_sha256,source_byte_length,signals) as (
  values
    (33,29,1938,'d1fddf526daf49327c4e2184933fb78b24bbc7c1d0764ad25f5d3ffa83ea6156',305894,jsonb_build_array('TO MAKE GRAVY SOUP','eight pounds','coarse lean beef','same ingredients','same quantity of water','Strain the soup','toasted bread','mushroom catsup')),
    (34,30,1886,'5c4a8add4e9e5fc2dcccdd1e2c52387b325d7467db72e7032786761d98b43bd2',299219,jsonb_build_array('mushroom catsup','fine flavour','SOUP WITH BOUILLI'))
)
insert into wnph.publication_source_observations(
  source_asset_id,observation_key,observation_kind,ordinal,coordinate_unit,x,y,width,height,confidence,
  derivation_method,source_format,processor,external_locator,metadata
)
select a.id,
  format('virginia-house-wife:1824:gravy-soup:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0')),
  'layout_region',1,'pixel',0,0,1200,s.image_height,0.98,'bounded_machine_pixel_corroboration_v1','image/jpeg',
  jsonb_build_object('provider','WNPH bounded source inspection','engine','ocrad.js 0.0.1','mode','whole_page_machine_corroboration'),
  jsonb_build_object('asset_key',a.asset_key,'scan_sequence',s.scan_sequence,'printed_page',s.printed_page,
    'iiif_uri',format('https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:%s/full/1200,/0/default.jpg',lpad(s.scan_sequence::text,4,'0'))),
  jsonb_build_object('verification_role','machine_pixel_corroboration','human_visual_inspection',false,'source_image_verification_claim',false,
    'source_sha256',s.source_sha256,'source_byte_length',s.source_byte_length,'comparison_source_key','textgrid:virginia-house-wife:1824',
    'comparison_agreement',true,'agreement_scope','lexical_and_semantic_claim_support','typographic_exactness_human_adjudicated',false,'stable_signals',s.signals)
from scans s join package p on true
join wnph.publication_source_assets a on a.source_package_id=p.id
 and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(s.scan_sequence::text,4,'0'))
where not exists(select 1 from wnph.publication_source_observations o where o.source_asset_id=a.id
 and o.observation_key=format('virginia-house-wife:1824:gravy-soup:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0'))
 and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id));

do $$
declare
 v_package wnph.publication_source_packages%rowtype;
 v_case wnph.recovery_cases%rowtype;
 v_work wnph.historical_works%rowtype;
 v_surrogate wnph.surrogates%rowtype;
 v_loc_source wnph.evidence_sources%rowtype;
 v_textgrid_source wnph.evidence_sources%rowtype;
 v_soup_container uuid;
 v_beef_unit uuid;
 v_block_id uuid;
 v_unit_id uuid;
 v_act_id uuid;
 v_locators jsonb;
 s record;
begin
 if exists(select 1 from wnph.transmission_acts where canonical_key='virginia-house-wife:1824:transmission:gravy-soup:source-text-verification:v1') then return; end if;
 select * into strict v_package from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';
 select * into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1';
 select * into strict v_work from wnph.historical_works where canonical_key='virginia-house-wife';
 select * into strict v_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';
 select * into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:73217897';
 select * into strict v_textgrid_source from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824';
 select id into strict v_soup_container from wnph.publication_source_blocks b where b.source_package_id=v_package.id
   and b.block_key='virginia-house-wife:1824:sequence:soups'
   and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);
 select id into strict v_beef_unit from wnph.publication_semantic_units u where u.source_package_id=v_package.id
   and u.unit_key='virginia-house-wife:1824:semantic:beef-soup'
   and not exists(select 1 from wnph.publication_semantic_units c where c.supersedes_unit_id=u.id);

 select jsonb_agg(jsonb_build_object('asset_key',a.asset_key,'scan_sequence',m.scan_sequence,'printed_page',m.printed_page,
   'source_sha256',m.sha256,'source_byte_length',m.byte_length) order by m.scan_sequence) into v_locators
 from (values
   (33,29,'d1fddf526daf49327c4e2184933fb78b24bbc7c1d0764ad25f5d3ffa83ea6156',305894),
   (34,30,'5c4a8add4e9e5fc2dcccdd1e2c52387b325d7467db72e7032786761d98b43bd2',299219)
 ) as m(scan_sequence,printed_page,sha256,byte_length)
 join wnph.publication_source_assets a on a.source_package_id=v_package.id
   and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'));

 v_block_id:=gen_random_uuid();
 insert into wnph.publication_source_blocks(id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance,reading_state)
 values(v_block_id,v_package.id,'virginia-house-wife:1824:to-make-gravy-soup',v_soup_container,2,'instruction','dependent_soup_variant_protocol',
$gravy$TO MAKE GRAVY SOUP.

Get eight pounds of coarse lean beef—wash it clean and lay it in your pot, put in the same ingredients as for the shin soup, with the same quantity of water, and follow the process directed for that. Strain the soup through a sieve and serve it up clear with nothing more than toasted bread in it, two table-spoonsful of mushroom catsup will add a fine flavour to the soup.$gravy$,
 jsonb_build_object('printed_pages',jsonb_build_array(29,30),'historical_unit_type','dependent_soup_variant_protocol','modern_safety_assessed',false,
   'modern_normalization_applied',false,'human_visual_inspection',false,'typographic_exactness_human_adjudicated',false,'next_heading','SOUP WITH BOUILLI.',
   'depends_on_unit_key','virginia-house-wife:1824:semantic:beef-soup'),
 jsonb_build_object('text_authority','Library of Congress 1824 first-edition source surfaces are controlling; exact-1824 TextGrid comparison supplies the lexical reading',
   'source_locators',v_locators,'verification_status','source_text_verified','source_verified',true,'controlling_witness','Library of Congress 1824 first edition',
   'comparison_transcription_key','textgrid:virginia-house-wife:1824','comparison_transcription_is_authority',false,'machine_pixel_corroboration',true,
   'human_visual_inspection',false,'source_image_verification_claim',false,'typographic_exactness_human_adjudicated',false,
   'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery','derivation_method','exact_1824_comparison_transcription_corroborated_against_loc_pixels'),'verified');

 v_act_id:=gen_random_uuid();
 insert into wnph.transmission_acts(id,canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata)
 values(v_act_id,'virginia-house-wife:1824:transmission:gravy-soup:source-text-verification:v1',v_case.id,v_work.id,'source_text_verification',
 'Verify TO MAKE GRAVY SOUP against the selected 1824 Library of Congress witness for functional-semantic recovery.',
 'LOC scans 33–34 bound the recipe from TO MAKE GRAVY SOUP through SOUP WITH BOUILLI. The source explicitly depends on the preceding shin-beef soup for ingredients, water quantity, and process; WNPH preserves that dependency rather than fabricating repeated text. Exact-1824 TextGrid supplies comparison wording. No human visual or glyph-level adjudication is claimed.',
 'system_recorded','high',jsonb_build_object('canonical_text_admission',true,'canonical_text_adjudication',false,'source_text_verified',true,'source_image_verified',false,
 'machine_pixel_corroboration',true,'human_visual_inspection',false,'page_image_is_controlling_witness',true,'comparison_transcription_key','textgrid:virginia-house-wife:1824',
 'comparison_transcription_is_authority',false,'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery','typographic_exactness_human_adjudicated',false,
 'scan_locators',v_locators,'claim_promotion_target','verified_not_adjudicated','depends_on_unit_key','virginia-house-wife:1824:semantic:beef-soup'));
 insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id,locator)
 values(v_act_id,'input','preferred_historical_source',v_surrogate.id,jsonb_build_object('lccn','73217897','scan_sequences',jsonb_build_array(33,34)));
 insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id,locator)
 values(v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb);
 insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id,locator)
 values(v_act_id,'input','comparison_transcription',v_textgrid_source.id,jsonb_build_object('status','comparison_only','edition_year',1824));
 for s in select a.id,a.asset_key,m.scan_sequence,m.printed_page,m.sha256,m.byte_length from (values
   (33,29,'d1fddf526daf49327c4e2184933fb78b24bbc7c1d0764ad25f5d3ffa83ea6156',305894),
   (34,30,'5c4a8add4e9e5fc2dcccdd1e2c52387b325d7467db72e7032786761d98b43bd2',299219)
 ) as m(scan_sequence,printed_page,sha256,byte_length)
 join wnph.publication_source_assets a on a.source_package_id=v_package.id
  and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0')) loop
   insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_asset_id,locator)
   values(v_act_id,'input','source_page_image',s.id,jsonb_build_object('asset_key',s.asset_key,'scan_sequence',s.scan_sequence,'printed_page',s.printed_page,'source_sha256',s.sha256,'source_byte_length',s.byte_length,'human_visual_inspection',false));
 end loop;
 insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator)
 values(v_act_id,'output','verified_source_text',v_block_id,jsonb_build_object('block_key','virginia-house-wife:1824:to-make-gravy-soup','reading_state','verified'));
 insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note) values
 (v_act_id,v_loc_source.id,'supports','certain','LOC LCCN 73217897 scans 33–34 are the controlling 1824 source surfaces.'),
 (v_act_id,v_textgrid_source.id,'supports','high','Exact-1824 TextGrid agrees with the LOC pixel reading and supplies comparison wording only.');

 v_unit_id:=gen_random_uuid();
 insert into wnph.publication_semantic_units(id,expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,semantic_status,confidence,derivation_method,properties,source_provenance)
 values(v_unit_id,v_package.expression_id,v_package.id,'virginia-house-wife:1824:semantic:gravy-soup',v_beef_unit,9,'dependent_soup_variant_protocol','TO MAKE GRAVY SOUP.','verified',0.99,
 'source_text_verified_semantic_extraction_v1',jsonb_build_object('printed_pages',jsonb_build_array(29,30),'primary_function','produce a clear beef soup variant by inheriting the shin-soup ingredients and process, changing beef quantity/cut and finish',
 'historical_container','unheaded soup instruction sequence','modern_safety_assessed',false,'modern_normalization_applied',false,'human_visual_inspection',false,'atlas_execution_requires_downstream_normalization',true,
 'depends_on_unit_key','virginia-house-wife:1824:semantic:beef-soup'),
 jsonb_build_object('source_verified',true,'source_block_id',v_block_id,'verification_status','source_text_verified','controlling_witness','LOC 1824','machine_pixel_corroboration',true,'human_visual_inspection',false,
 'typographic_exactness_human_adjudicated',false,'comparison_transcription_key','textgrid:virginia-house-wife:1824'));

 insert into wnph.publication_semantic_claims(semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,claim_status,confidence,derivation_method,properties,source_provenance)
 select v_unit_id,v_block_id,x.claim_key,x.ordinal,x.claim_kind,x.subject_key,x.predicate,x.object_text,x.quantity_value,x.quantity_unit,x.quantity_text,x.temporal_text,x.condition_text,'verified',x.confidence,
 'source_text_verified_semantic_extraction_v1',x.properties,
 jsonb_build_object('source_pages',x.source_pages,'source_verified',true,'verification_status','source_text_verified','verified_source_block_id',v_block_id,'controlling_witness','LOC 1824','comparison_transcription','TextGrid exact 1824',
 'machine_pixel_corroboration',true,'human_visual_inspection',false,'typographic_exactness_human_adjudicated',false,'modern_use_requires_downstream_safety_review',x.safety_review)
 from (values
  (1,'beef-quantity-cut','ingredient_quantity','beef','contains','coarse lean beef',8::numeric,'pound','eight pounds',null::text,null::text,0.99,jsonb_build_object(),jsonb_build_array(29),false),
  (2,'wash-beef','historical_raw_meat_handling','beef','wash','wash it clean',null,null,null,'before cooking',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(29),true),
  (3,'inherit-ingredients','recipe_dependency','gravy_soup','inherit_ingredients_from','virginia-house-wife:1824:semantic:beef-soup',null,null,null,null,'same ingredients as shin soup',0.99,jsonb_build_object('dependency_type','same_ingredients'),jsonb_build_array(29),false),
  (4,'inherit-water','recipe_dependency','gravy_soup','inherit_water_quantity_from','virginia-house-wife:1824:semantic:beef-soup',3::numeric,'quart','same quantity of water',null,null,0.99,jsonb_build_object('resolved_historical_quantity','three quarts'),jsonb_build_array(29),false),
  (5,'inherit-process','recipe_dependency','gravy_soup','follow_process_of','virginia-house-wife:1824:semantic:beef-soup',null,null,null,'cooking process',null,0.99,jsonb_build_object('dependency_type','same_process','modern_safety_assessed',false),jsonb_build_array(29),true),
  (6,'strain','finishing','gravy_soup','strain_through','sieve',null,null,null,'after cooking',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
  (7,'serve-clear','service','gravy_soup','serve','clear',null,null,null,'at service',null,0.99,jsonb_build_object(),jsonb_build_array(29),false),
  (8,'toasted-bread-only','service','gravy_soup','serve_with','nothing more than toasted bread',null,null,null,'at service',null,0.99,jsonb_build_object(),jsonb_build_array(29,30),false),
  (9,'mushroom-catsup-option','flavour_option','gravy_soup','optionally_add','mushroom catsup',2::numeric,'tablespoon','two table-spoonsful',null,'Randolph says it adds a fine flavour',0.99,jsonb_build_object('optional',true),jsonb_build_array(30),false)
 ) as x(ordinal,claim_key,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,confidence,properties,source_pages,safety_review);
end $$;