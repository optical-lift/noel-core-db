with package as (
  select id from wnph.publication_source_packages
  where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1'
), scans(scan_sequence,printed_page,image_height,inspection_derivative_sha256,inspection_derivative_byte_length,signals) as (
  values
    (25,21,1995,'5590d9dbf25b7d4dd422a444b3382a7d62a3fd312e15ff0385fde332d377e5db',330058,
      jsonb_build_array('TO CURE HERRINGS','winter stock for beef','largest herrings having roes','alive into the brine','twenty-four hours','sloping planks','coarse allum salt','salt-petre')),
    (26,22,1813,'224ab10574da16d6e8700cc569d402870406380c32332d352eac0e04fd3b4be3',309321,
      jsonb_build_array('rusty if not kept under brine','long enough to fatten','scales','soak them an hour or two','pull off the gills','white paper','butter','preserving their juices','one or two years old','equal to anchovies','TO CORN BEEF IN HOT WEATHER'))
)
insert into wnph.publication_source_observations (
  source_asset_id,observation_key,observation_kind,ordinal,coordinate_unit,x,y,width,height,
  confidence,derivation_method,source_format,processor,external_locator,metadata
)
select
  a.id,
  format('virginia-house-wife:1824:cure-herrings:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0')),
  'layout_region',1,'pixel',0,0,1200,s.image_height,0.98,
  'bounded_machine_pixel_corroboration_v1','image/jpeg',
  jsonb_build_object('provider','WNPH bounded source inspection','engine','ocrad.js 0.0.1','mode','whole_page_machine_corroboration'),
  jsonb_build_object(
    'asset_key',a.asset_key,
    'scan_sequence',s.scan_sequence,
    'printed_page',s.printed_page,
    'iiif_uri',format('https://tile.loc.gov/image-services/iiif/service:rbc:rbc0001:2015:2015pennell17897:%s/full/1200,/0/default.jpg',lpad(s.scan_sequence::text,4,'0'))
  ),
  jsonb_build_object(
    'verification_role','machine_pixel_corroboration',
    'unit_key','virginia-house-wife:1824:semantic:cure-herrings',
    'human_visual_inspection',false,
    'source_image_verification_claim',false,
    'inspection_derivative_sha256',s.inspection_derivative_sha256,
    'inspection_derivative_byte_length',s.inspection_derivative_byte_length,
    'comparison_source_key','textgrid:virginia-house-wife:1824',
    'comparison_agreement',true,
    'agreement_scope','lexical_and_semantic_claim_support',
    'typographic_exactness_human_adjudicated',false,
    'stable_signals',s.signals
  )
from scans s
join package p on true
join wnph.publication_source_assets a
  on a.source_package_id=p.id
 and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(s.scan_sequence::text,4,'0'))
where not exists (
  select 1 from wnph.publication_source_observations o
  where o.source_asset_id=a.id
    and o.observation_key=format('virginia-house-wife:1824:cure-herrings:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0'))
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
  if exists(select 1 from wnph.transmission_acts where canonical_key='virginia-house-wife:1824:transmission:cure-herrings:source-text-verification:v1') then
    return;
  end if;

  select * into strict v_package from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';
  select * into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1';
  select * into strict v_work from wnph.historical_works where canonical_key='virginia-house-wife';
  select * into strict v_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';
  select * into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:73217897';
  select * into strict v_textgrid_source from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824';
  select id into strict v_parent_block_id from wnph.publication_source_blocks b
    where b.source_package_id=v_package.id
      and b.block_key='virginia-house-wife:1824:sequence:opening-preservation'
      and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

  v_locators := jsonb_build_array(
    jsonb_build_object(
      'asset_key','virginia-house-wife:1824:source-surface:0025','scan_sequence',25,'printed_page',21,
      'inspection_derivative_sha256','5590d9dbf25b7d4dd422a444b3382a7d62a3fd312e15ff0385fde332d377e5db','inspection_derivative_byte_length',330058
    ),
    jsonb_build_object(
      'asset_key','virginia-house-wife:1824:source-surface:0026','scan_sequence',26,'printed_page',22,
      'inspection_derivative_sha256','224ab10574da16d6e8700cc569d402870406380c32332d352eac0e04fd3b4be3','inspection_derivative_byte_length',309321
    )
  );

  insert into wnph.publication_source_blocks (
    id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,
    properties,source_provenance,reading_state
  ) values (
    v_block_id,v_package.id,'virginia-house-wife:1824:to-cure-herrings',v_parent_block_id,5,'instruction',
    'fish_selection_brine_cure_storage_and_cooking_protocol',
    $herring$TO CURE HERRINGS.

The best method for preserving herrings, and which may be followed with ease, for a small family, is to take the brine left of your winter stock for beef, to the fishing place, and when the seine is hauled, to pick out the largest herrings, having roes, and throw them alive into the brine; let them remain twenty-four hours, take them out and lay them on sloping planks, that the brine may drain off; have a tight barrel, put some coarse allum salt in the bottom, then put in a layer of herrings—take care not to bruise them; sprinkle over it allum salt and some salt-petre, then fish salt and salt-petre, till the barrel is full; keep a board over it. Should they not make brine enough to cover them in a few weeks, you must add some, for they will be rusty if not kept under brine. The proper time to salt them is when they have been up the rivers long enough to fatten: the scales will adhere closely to a lean herring, but will be loose on a fat one—the former is not fit to be eaten. Do not be sparing of salt when you put them up. When they are to be used, take a few out of brine, soak them an hour or two, scale them nicely, pull off the gills, and the only entrail they have will come with them; wash them clean and hang them up to dry. When to be broiled, take half a sheet of white paper, rub it over with butter, put the herring in, double the edges securely, and broil, without burning, it. The brine the herrings drink in before they die, has a wonderful effect in preserving their juices:—When one or two years old, they are equal to anchovies.$herring$,
    jsonb_build_object(
      'printed_pages',jsonb_build_array(21,22),
      'historical_container','unsectioned opening instruction sequence',
      'historical_unit_type','fish_selection_brine_cure_storage_and_cooking_protocol',
      'modern_safety_assessed',false,
      'modern_normalization_applied',false,
      'historical_preservation_beliefs_present',true,
      'human_visual_inspection',false,
      'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery'
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first-edition source surfaces are controlling; exact-1824 TextGrid comparison supports the transcription reading',
      'source_locators',v_locators,
      'verification_status','source_text_verified',
      'source_verified',true,
      'controlling_witness','Library of Congress 1824 first edition',
      'comparison_transcription_key','textgrid:virginia-house-wife:1824',
      'comparison_transcription_is_authority',false,
      'machine_pixel_corroboration',true,
      'human_visual_inspection',false,
      'source_image_verification_claim',false,
      'typographic_exactness_human_adjudicated',false,
      'derivation_method','exact_1824_comparison_transcription_corroborated_against_loc_pixels'
    ),
    'verified'
  );

  insert into wnph.transmission_acts (
    id,canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values (
    v_act_id,'virginia-house-wife:1824:transmission:cure-herrings:source-text-verification:v1',v_case.id,v_work.id,
    'source_text_verification','Verify To Cure Herrings against the selected 1824 Library of Congress witness for functional-semantic recovery.',
    'LOC scans 25 and 26 are the controlling first-edition surfaces. Machine reading of those deterministic IIIF derivatives independently recovers the heading, preservation sequence, twenty-four-hour brine interval, barrel layering, submersion rule, fatness test, one-to-two-hour soak, buttered-paper broiling, historical juice-preservation claim, and one-to-two-year quality claim found in the exact-1824 TextGrid comparison. Verification is lexical/semantic only; there is no human visual or typographic/glyph-level adjudication.',
    'system_recorded','high',
    jsonb_build_object(
      'canonical_text_admission',true,
      'canonical_text_adjudication',false,
      'source_text_verified',true,
      'source_image_verified',false,
      'machine_pixel_corroboration',true,
      'human_visual_inspection',false,
      'page_image_is_controlling_witness',true,
      'comparison_transcription_key','textgrid:virginia-house-wife:1824',
      'comparison_transcription_is_authority',false,
      'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery',
      'typographic_exactness_human_adjudicated',false,
      'scan_locators',v_locators,
      'claim_promotion_target','verified_not_adjudicated'
    )
  );

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,surrogate_id,locator)
  values (v_act_id,'input','preferred_historical_source',v_surrogate.id,jsonb_build_object('lccn','73217897','scan_sequences',jsonb_build_array(25,26)));

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_package_id,locator)
  values (v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb);

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,evidence_source_id,locator)
  values (v_act_id,'input','comparison_transcription',v_textgrid_source.id,jsonb_build_object('status','comparison_only','edition_year',1824));

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_asset_id,locator)
  select v_act_id,'input','source_page_image',a.id,
         case a.asset_key
           when 'virginia-house-wife:1824:source-surface:0025' then jsonb_build_object('asset_key',a.asset_key,'scan_sequence',25,'printed_page',21,'inspection_derivative_sha256','5590d9dbf25b7d4dd422a444b3382a7d62a3fd312e15ff0385fde332d377e5db','inspection_derivative_byte_length',330058,'human_visual_inspection',false)
           else jsonb_build_object('asset_key',a.asset_key,'scan_sequence',26,'printed_page',22,'inspection_derivative_sha256','224ab10574da16d6e8700cc569d402870406380c32332d352eac0e04fd3b4be3','inspection_derivative_byte_length',309321,'human_visual_inspection',false)
         end
  from wnph.publication_source_assets a
  where a.source_package_id=v_package.id
    and a.asset_key in ('virginia-house-wife:1824:source-surface:0025','virginia-house-wife:1824:source-surface:0026');

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_block_id,locator)
  values (v_act_id,'output','verified_source_text',v_block_id,jsonb_build_object('block_key','virginia-house-wife:1824:to-cure-herrings','reading_state','verified'));

  insert into wnph.transmission_act_evidence (transmission_act_id,source_id,support_role,confidence,note)
  values
    (v_act_id,v_loc_source.id,'supports','certain','Library of Congress LCCN 73217897 is the controlling 1824 first-edition witness; scans 25 and 26 were fetched from its IIIF image service.'),
    (v_act_id,v_textgrid_source.id,'supports','high','The independent TextGrid transcription is the same 1824 edition and agrees with the machine reading of LOC scans 25 and 26; it supplies comparison wording only.');

  insert into wnph.publication_semantic_units (
    id,expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,
    semantic_status,confidence,derivation_method,properties,source_provenance
  ) values (
    v_unit_id,v_package.expression_id,v_package.id,'virginia-house-wife:1824:semantic:cure-herrings',null,5,
    'fish_selection_brine_cure_storage_and_cooking_protocol','TO CURE HERRINGS.','verified',0.99,
    'source_text_verified_semantic_extraction_v1',
    jsonb_build_object(
      'printed_pages',jsonb_build_array(21,22),
      'primary_function','select, brine-cure, store, prepare and broil herrings',
      'historical_container','unsectioned opening instruction sequence',
      'modern_safety_assessed',false,
      'modern_normalization_applied',false,
      'historical_preservation_beliefs_present',true,
      'human_visual_inspection',false
    ),
    jsonb_build_object(
      'source_verified',true,
      'source_block_id',v_block_id,
      'verification_status','source_text_verified',
      'controlling_witness','LOC 1824',
      'comparison_transcription_key','textgrid:virginia-house-wife:1824',
      'machine_pixel_corroboration',true,
      'human_visual_inspection',false,
      'typographic_exactness_human_adjudicated',false
    )
  );

  insert into wnph.publication_semantic_claims (
    semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,
    object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,
    claim_status,confidence,derivation_method,properties,source_provenance
  )
  select v_unit_id,v_block_id,x.claim_key,x.ordinal,x.claim_kind,x.subject_key,x.predicate,
         x.object_text,x.quantity_value,x.quantity_unit,x.quantity_text,x.temporal_text,x.condition_text,
         'verified',x.confidence,'source_text_verified_semantic_extraction_v1',x.properties,
         jsonb_build_object(
           'source_pages',jsonb_build_array(21,22),
           'source_verified',true,
           'verification_status','source_text_verified',
           'verified_source_block_id',v_block_id,
           'controlling_witness','LOC 1824',
           'comparison_transcription','TextGrid exact 1824',
           'machine_pixel_corroboration',true,
           'human_visual_inspection',false,
           'typographic_exactness_human_adjudicated',false,
           'modern_use_requires_downstream_safety_review',x.safety_review
         )
  from (values
    ('purpose',1,'purpose','herrings','preserve_for','small-family household preservation',null::numeric,null::text,null::text,null::text,null::text,0.99,jsonb_build_object(),true),
    ('reuse-beef-brine',2,'cross_unit_reuse','winter_beef_brine','reuse_for','herring cure',null,null,null,'at fishing place',null,0.99,jsonb_build_object('source_unit_key','virginia-house-wife:1824:semantic:curing-beef'),true),
    ('select-herrings',3,'material_selection','herrings','select','largest herrings having roes',null,null,null,'when the seine is hauled',null,0.99,jsonb_build_object(),false),
    ('live-brine-entry',4,'historical_process_stage','herrings','place_in','brine while alive',null,null,null,'immediately after selection',null,0.99,jsonb_build_object('historical_animal_handling',true),true),
    ('initial-brine-duration',5,'process_timing','herrings','remain_in','brine',24,'hour','twenty-four hours',null,null,0.99,jsonb_build_object(),true),
    ('drain-on-planks',6,'process_stage','herrings','drain_on','sloping planks',null,null,null,'after initial brine',null,0.99,jsonb_build_object(),true),
    ('barrel-bottom-salt',7,'preservation_medium','barrel','line_with','coarse allum salt',null,null,null,null,'tight barrel',0.99,jsonb_build_object('historical_term','allum salt'),true),
    ('barrel-layering',8,'preservation_process','herrings','layer_with','allum salt and salt-petre; repeat fish, salt and salt-petre until barrel is full',null,null,null,null,'take care not to bruise fish',0.99,jsonb_build_object(),true),
    ('board-cover',9,'storage_condition','barrel','cover_with','board',null,null,null,'after packing',null,0.98,jsonb_build_object(),true),
    ('maintain-brine-cover',10,'historical_preservation_rule','herrings','keep_under','brine',null,null,null,'during storage','if fish do not make enough brine in a few weeks, add some; Randolph says uncovered fish become rusty',0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),true),
    ('seasonal-fatness',11,'seasonal_timing','herrings','salt_when','fish have been up the rivers long enough to fatten',null,null,null,null,null,0.98,jsonb_build_object(),false),
    ('scale-fatness-test',12,'historical_quality_test','herrings','judge_fatness_by','scales adhere closely to lean fish and are loose on fat fish; lean fish judged unfit to eat',null,null,null,null,null,0.98,jsonb_build_object('author_judgment',true),false),
    ('salt-generously',13,'historical_preservation_instruction','herrings','salt','do not be sparing of salt',null,null,null,'when packing',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),true),
    ('preuse-soak',14,'preparation','herrings','soak','out of brine',1,'hour_minimum','one or two hours','before use',null,0.99,jsonb_build_object('maximum_value',2),true),
    ('prebroil-cleaning',15,'preparation','herrings','clean','scale; remove gills and entrail; wash clean; hang to dry',null,null,null,'after soaking and before broiling',null,0.99,jsonb_build_object(),true),
    ('paper-broil',16,'cooking_method','herring','broil_in','half sheet of white paper rubbed with butter, edges doubled securely',null,null,null,null,'broil without burning',0.99,jsonb_build_object(),true),
    ('brine-juice-belief',17,'historical_causal_claim','initial_brine_ingestion','attributed_effect','wonderful effect in preserving their juices',null,null,null,'before fish die',null,0.98,jsonb_build_object('modern_validity_assessed',false,'do_not_use_as_modern_safety_rule',true),true),
    ('aged-quality-claim',18,'historical_quality_claim','cured_herrings','compared_as','equal to anchovies',1,'year_minimum','one or two years old','after storage',null,0.98,jsonb_build_object('maximum_value',2,'modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),true)
  ) as x(claim_key,ordinal,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,confidence,properties,safety_review);
end $$;