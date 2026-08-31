with package as (
  select id from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1'
), scans(scan_sequence,printed_page,image_height,inspection_derivative_sha256,inspection_derivative_byte_length,signals) as (
  values
    (26,22,1813,'224ab10574da16d6e8700cc569d402870406380c32332d352eac0e04fd3b4be3',309321,
      jsonb_build_array('TO CORN BEEF IN HOT WEATHER','thin brisket or plate','two large spoonsful of pounded salt-petre','gill of molasses','quart of salt')),
    (27,23,2013,'4e4d00a47b5c117014171538e99e46ec5d2f44a216d2b94ac23095e3017cfe61',329869,
      jsonb_build_array('bloody brine must run off','four days','tied up in a cloth','take the skin off','ice-house or refrigerator','fillet or breast of veal','leg or rack of mutton','GENERAL OBSERVATIONS'))
)
insert into wnph.publication_source_observations (
  source_asset_id,observation_key,observation_kind,ordinal,coordinate_unit,x,y,width,height,
  confidence,derivation_method,source_format,processor,external_locator,metadata
)
select a.id,
  format('virginia-house-wife:1824:corn-beef-hot-weather:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0')),
  'layout_region',1,'pixel',0,0,1200,s.image_height,0.98,
  'bounded_machine_pixel_corroboration_v1','image/jpeg',
  jsonb_build_object('provider','WNPH bounded source inspection','engine','ocrad.js 0.0.1','mode','whole_page_machine_corroboration'),
  jsonb_build_object('asset_key',a.asset_key,'scan_sequence',s.scan_sequence,'printed_page',s.printed_page,
    'iiif_uri',format('https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:%s/full/1200,/0/default.jpg',lpad(s.scan_sequence::text,4,'0'))),
  jsonb_build_object('verification_role','machine_pixel_corroboration','unit_key','virginia-house-wife:1824:semantic:corn-beef-hot-weather',
    'human_visual_inspection',false,'source_image_verification_claim',false,'inspection_derivative_sha256',s.inspection_derivative_sha256,
    'inspection_derivative_byte_length',s.inspection_derivative_byte_length,'comparison_source_key','textgrid:virginia-house-wife:1824',
    'comparison_agreement',true,'agreement_scope','lexical_and_semantic_claim_support','typographic_exactness_human_adjudicated',false,'stable_signals',s.signals)
from scans s join package p on true
join wnph.publication_source_assets a on a.source_package_id=p.id
 and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(s.scan_sequence::text,4,'0'))
where not exists (
  select 1 from wnph.publication_source_observations o where o.source_asset_id=a.id
   and o.observation_key=format('virginia-house-wife:1824:corn-beef-hot-weather:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0'))
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
  v_parent_block_id uuid;
  v_block_id uuid := gen_random_uuid();
  v_unit_id uuid := gen_random_uuid();
  v_act_id uuid := gen_random_uuid();
  v_locators jsonb;
begin
  if exists(select 1 from wnph.transmission_acts where canonical_key='virginia-house-wife:1824:transmission:corn-beef-hot-weather:source-text-verification:v1') then return; end if;
  select * into strict v_package from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';
  select * into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1';
  select * into strict v_work from wnph.historical_works where canonical_key='virginia-house-wife';
  select * into strict v_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';
  select * into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:73217897';
  select * into strict v_textgrid_source from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824';
  select id into strict v_parent_block_id from wnph.publication_source_blocks b
   where b.source_package_id=v_package.id and b.block_key='virginia-house-wife:1824:sequence:opening-preservation'
     and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

  v_locators := jsonb_build_array(
    jsonb_build_object('asset_key','virginia-house-wife:1824:source-surface:0026','scan_sequence',26,'printed_page',22,
      'inspection_derivative_sha256','224ab10574da16d6e8700cc569d402870406380c32332d352eac0e04fd3b4be3','inspection_derivative_byte_length',309321),
    jsonb_build_object('asset_key','virginia-house-wife:1824:source-surface:0027','scan_sequence',27,'printed_page',23,
      'inspection_derivative_sha256','4e4d00a47b5c117014171538e99e46ec5d2f44a216d2b94ac23095e3017cfe61','inspection_derivative_byte_length',329869)
  );

  insert into wnph.publication_source_blocks (
    id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance,reading_state
  ) values (
    v_block_id,v_package.id,'virginia-house-wife:1824:to-corn-beef-in-hot-weather',v_parent_block_id,6,'instruction',
    'hot_weather_short_cure_and_cooking_protocol',
    $corn$TO CORN BEEF IN HOT WEATHER.

Take a piece of thin brisket or plate, cut out the ribs nicely, rub it on both sides well with two large spoonsful of pounded salt-petre; pour on it a gill of molasses and a quart of salt; rub them both in; put it in a vessel just large enough to hold it, but not tight, for the bloody brine must run off as it makes, or the meat will spoil. Let it be well covered top, bottom, and sides, with the molasses and salt. In four days you may boil it, tied up with a cloth, with the salt, &c. about it: when done, take the skin off nicely, and serve it up. If you have an ice-house or refrigerator, it will be best to keep it there.—A fillet or breast of veal, and a leg or rack of mutton, are excellent done in the same way.$corn$,
    jsonb_build_object('printed_pages',jsonb_build_array(22,23),'historical_container','unsectioned opening instruction sequence',
      'historical_unit_type','hot_weather_short_cure_and_cooking_protocol','modern_safety_assessed',false,
      'modern_normalization_applied',false,'historical_preservation_instruction',true,'human_visual_inspection',false,
      'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery'),
    jsonb_build_object('text_authority','Library of Congress 1824 first-edition source surfaces are controlling; exact-1824 TextGrid comparison supports the transcription reading',
      'source_locators',v_locators,'verification_status','source_text_verified','source_verified',true,
      'controlling_witness','Library of Congress 1824 first edition','comparison_transcription_key','textgrid:virginia-house-wife:1824',
      'comparison_transcription_is_authority',false,'machine_pixel_corroboration',true,'human_visual_inspection',false,
      'source_image_verification_claim',false,'typographic_exactness_human_adjudicated',false,
      'derivation_method','exact_1824_comparison_transcription_corroborated_against_loc_pixels'),
    'verified'
  );

  insert into wnph.transmission_acts (
    id,canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values (
    v_act_id,'virginia-house-wife:1824:transmission:corn-beef-hot-weather:source-text-verification:v1',v_case.id,v_work.id,
    'source_text_verification','Verify To Corn Beef in Hot Weather against the selected 1824 Library of Congress witness for functional-semantic recovery.',
    'LOC scans 26 and 27 are the controlling first-edition surfaces. Machine reading independently recovers the heading, beef cut, salt-petre amount, molasses and salt quantities, drainage requirement, four-day interval, cloth-boiling instruction, cold-storage preference, and alternate meats represented by the exact-1824 comparison reading. Verification is lexical/semantic only and does not adjudicate modern safety, typography, or glyphs.',
    'system_recorded','high',
    jsonb_build_object('canonical_text_admission',true,'canonical_text_adjudication',false,'source_text_verified',true,'source_image_verified',false,
      'machine_pixel_corroboration',true,'human_visual_inspection',false,'page_image_is_controlling_witness',true,
      'comparison_transcription_key','textgrid:virginia-house-wife:1824','comparison_transcription_is_authority',false,
      'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery','typographic_exactness_human_adjudicated',false,
      'scan_locators',v_locators,'claim_promotion_target','verified_not_adjudicated','modern_safety_assessed',false)
  );

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,surrogate_id,locator)
   values (v_act_id,'input','preferred_historical_source',v_surrogate.id,jsonb_build_object('lccn','73217897','scan_sequences',jsonb_build_array(26,27)));
  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_package_id,locator)
   values (v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb);
  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,evidence_source_id,locator)
   values (v_act_id,'input','comparison_transcription',v_textgrid_source.id,jsonb_build_object('status','comparison_only','edition_year',1824));
  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_asset_id,locator)
  select v_act_id,'input','source_page_image',a.id,
    case a.asset_key when 'virginia-house-wife:1824:source-surface:0026' then
      jsonb_build_object('asset_key',a.asset_key,'scan_sequence',26,'printed_page',22,'inspection_derivative_sha256','224ab10574da16d6e8700cc569d402870406380c32332d352eac0e04fd3b4be3','inspection_derivative_byte_length',309321,'human_visual_inspection',false)
    else jsonb_build_object('asset_key',a.asset_key,'scan_sequence',27,'printed_page',23,'inspection_derivative_sha256','4e4d00a47b5c117014171538e99e46ec5d2f44a216d2b94ac23095e3017cfe61','inspection_derivative_byte_length',329869,'human_visual_inspection',false) end
  from wnph.publication_source_assets a where a.source_package_id=v_package.id
   and a.asset_key in ('virginia-house-wife:1824:source-surface:0026','virginia-house-wife:1824:source-surface:0027');
  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_block_id,locator)
   values (v_act_id,'output','verified_source_text',v_block_id,jsonb_build_object('block_key','virginia-house-wife:1824:to-corn-beef-in-hot-weather','reading_state','verified'));
  insert into wnph.transmission_act_evidence (transmission_act_id,source_id,support_role,confidence,note)
   values (v_act_id,v_loc_source.id,'supports','certain','Library of Congress LCCN 73217897 is the controlling 1824 first-edition witness; scans 26 and 27 were fetched from its IIIF image service.'),
          (v_act_id,v_textgrid_source.id,'supports','high','The independent TextGrid transcription is the same 1824 edition and agrees with the machine reading of LOC scans 26 and 27; it supplies comparison wording only.');

  insert into wnph.publication_semantic_units (
    id,expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,semantic_status,confidence,derivation_method,properties,source_provenance
  ) values (
    v_unit_id,v_package.expression_id,v_package.id,'virginia-house-wife:1824:semantic:corn-beef-hot-weather',null,6,
    'hot_weather_short_cure_and_cooking_protocol','TO CORN BEEF IN HOT WEATHER.','verified',0.99,'source_text_verified_semantic_extraction_v1',
    jsonb_build_object('printed_pages',jsonb_build_array(22,23),'primary_function','short cure and cook beef in hot weather',
      'historical_container','unsectioned opening instruction sequence','modern_safety_assessed',false,'modern_normalization_applied',false,
      'historical_preservation_instruction',true,'human_visual_inspection',false),
    jsonb_build_object('source_verified',true,'source_block_id',v_block_id,'verification_status','source_text_verified','controlling_witness','LOC 1824',
      'comparison_transcription_key','textgrid:virginia-house-wife:1824','machine_pixel_corroboration',true,'human_visual_inspection',false,
      'typographic_exactness_human_adjudicated',false)
  );

  insert into wnph.publication_semantic_claims (
    semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,
    temporal_text,condition_text,claim_status,confidence,derivation_method,properties,source_provenance
  )
  select v_unit_id,v_block_id,x.claim_key,x.ordinal,x.claim_kind,x.subject_key,x.predicate,x.object_text,x.quantity_value,x.quantity_unit,x.quantity_text,
    x.temporal_text,x.condition_text,'verified',x.confidence,'source_text_verified_semantic_extraction_v1',x.properties,
    jsonb_build_object('source_pages',jsonb_build_array(22,23),'source_verified',true,'verification_status','source_text_verified','verified_source_block_id',v_block_id,
      'controlling_witness','LOC 1824','comparison_transcription','TextGrid exact 1824','machine_pixel_corroboration',true,'human_visual_inspection',false,
      'typographic_exactness_human_adjudicated',false,'modern_use_requires_downstream_safety_review',true)
  from (values
    ('select-cut',1,'material_selection','beef','select','thin brisket or plate',null::numeric,null::text,null::text,null::text,null::text,0.99,jsonb_build_object()),
    ('remove-ribs',2,'butchery','beef_cut','remove','ribs nicely',null,null,null,'before cure',null,0.99,jsonb_build_object()),
    ('saltpetre-rub',3,'cure_application','beef_cut','rub_both_sides_with','pounded salt-petre',2,'large_spoonful','two large spoonsful',null,null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true)),
    ('molasses-amount',4,'cure_ingredient','beef_cut','add','molasses',1,'gill','a gill',null,null,0.99,jsonb_build_object()),
    ('salt-amount',5,'cure_ingredient','beef_cut','add','salt',1,'quart','a quart',null,null,0.99,jsonb_build_object()),
    ('rub-cure-in',6,'cure_application','beef_cut','rub_in','molasses and salt',null,null,null,'after adding',null,0.99,jsonb_build_object()),
    ('draining-vessel',7,'historical_preservation_rule','cure_vessel','allow_drainage','vessel just large enough to hold meat but not tight, so bloody brine runs off',null,null,null,'during cure','Randolph says meat will spoil if bloody brine cannot run off',0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true)),
    ('cover-all-surfaces',8,'cure_application','beef_cut','cover','top, bottom, and sides with molasses and salt',null,null,null,'during cure',null,0.99,jsonb_build_object()),
    ('cure-duration',9,'process_timing','beef_cut','cure_before_boiling','four days',4,'day','four days','before boiling',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true)),
    ('cloth-boil',10,'cooking_method','cured_beef','boil','tied up with a cloth, with the salt and cure about it',null,null,null,'after four days',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true)),
    ('remove-skin',11,'finishing','cooked_beef','remove','skin',null,null,null,'when done','before serving',0.99,jsonb_build_object()),
    ('cold-storage-preference',12,'historical_storage_preference','curing_beef','keep_in','ice-house or refrigerator if available',null,null,null,'during cure',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true)),
    ('alternate-meats',13,'cross_material_application','same_method','apply_to','fillet or breast of veal; leg or rack of mutton',null,null,null,null,null,0.98,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true))
  ) as x(claim_key,ordinal,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,confidence,properties);
end $$;