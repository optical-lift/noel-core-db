with package as (
  select id from wnph.publication_source_packages
  where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1'
), scans(scan_sequence,printed_page,image_height,source_sha256,source_byte_length,signals) as (
  values
    (27,23,2013,'4e4d00a47b5c117014171538e99e46ec5d2f44a216d2b94ac23095e3017cfe61',329869,jsonb_build_array('GENERAL OBSERVATIONS','roasting butcher''s meat','lie in water one hour','clear steady fire','baste with salt and water','nice lard')),
    (28,24,1825,'ee3d361b47dd702bfc40f39c6c80baa5398d06411f12190bce8fcf826b43c0f9',323635,jsonb_build_array('cover it with paper','dredge it with flour','raise a froth','mutton','dry flour','joint every thing')),
    (29,25,1993,'83ac440056f16fd7f7a8957c225cd9211d5491bb94355645c19cdfa75f74cfe2',328762,jsonb_build_array('No meat can be well roasted','cold water with a little salt','nice lard','fat is not yellow','fine close grain','white fat','breast bone','liveliness of their eyes','bright red of their gills')),
    (30,26,1886,'79e54478e97a5b1043764ee0a80b37cbb842239dd48f9f02a95878378dd8523c',313764,jsonb_build_array('close and damp','wash each piece','dry bran','coolest place','every morning','poultry','dredge every thing','Fish','frying','For broiling')),
    (31,27,1897,'91d6f67e86592f3961bc1881a269bc0baf0673bbdd0d4a1f82c1ac35487b95d3',314202,jsonb_build_array('viands served in perfection','dishes should be made hot','pewter dish cover','Profusion is not elegance','brown flour')),
    (32,28,1886,'73a96ffa650edfb2cecbe6996bd96cf1d46debc543a280a44e0fb9653b07a40f',305225,jsonb_build_array('pint of flour','Dutch oven','dark brown','none of it burnt','saw for trimming meat','larding needles','TO MAKE BEEF SOUP'))
)
insert into wnph.publication_source_observations (
  source_asset_id, observation_key, observation_kind, ordinal,
  coordinate_unit, x, y, width, height, confidence,
  derivation_method, source_format, processor, external_locator, metadata
)
select
  a.id,
  format('virginia-house-wife:1824:general-observations:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0')),
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
    'human_visual_inspection',false,
    'source_image_verification_claim',false,
    'source_sha256',s.source_sha256,
    'source_byte_length',s.source_byte_length,
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
    and o.observation_key=format('virginia-house-wife:1824:general-observations:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0'))
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
  v_parent_block uuid;
  v_block_id uuid;
  v_unit_id uuid;
  v_act_id uuid;
  v_locators jsonb;
  s record;
begin
  if exists(select 1 from wnph.transmission_acts where canonical_key='virginia-house-wife:1824:transmission:general-observations:source-text-verification:v1') then
    return;
  end if;

  select * into strict v_package from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';
  select * into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1';
  select * into strict v_work from wnph.historical_works where canonical_key='virginia-house-wife';
  select * into strict v_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';
  select * into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:73217897';
  select * into strict v_textgrid_source from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824';
  select id into strict v_parent_block from wnph.publication_source_blocks b
    where b.source_package_id=v_package.id
      and b.block_key='virginia-house-wife:1824:sequence:opening-preservation'
      and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

  select jsonb_agg(jsonb_build_object(
      'asset_key',a.asset_key,
      'scan_sequence',m.scan_sequence,
      'printed_page',m.printed_page,
      'source_sha256',m.sha256,
      'source_byte_length',m.byte_length
    ) order by m.scan_sequence)
  into v_locators
  from (values
    (27,23,'4e4d00a47b5c117014171538e99e46ec5d2f44a216d2b94ac23095e3017cfe61',329869),
    (28,24,'ee3d361b47dd702bfc40f39c6c80baa5398d06411f12190bce8fcf826b43c0f9',323635),
    (29,25,'83ac440056f16fd7f7a8957c225cd9211d5491bb94355645c19cdfa75f74cfe2',328762),
    (30,26,'79e54478e97a5b1043764ee0a80b37cbb842239dd48f9f02a95878378dd8523c',313764),
    (31,27,'91d6f67e86592f3961bc1881a269bc0baf0673bbdd0d4a1f82c1ac35487b95d3',314202),
    (32,28,'73a96ffa650edfb2cecbe6996bd96cf1d46debc543a280a44e0fb9653b07a40f',305225)
  ) as m(scan_sequence,printed_page,sha256,byte_length)
  join wnph.publication_source_assets a
    on a.source_package_id=v_package.id
   and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'));

  v_block_id := gen_random_uuid();
  insert into wnph.publication_source_blocks (
    id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
    text_content,properties,source_provenance,reading_state
  ) values (
    v_block_id,v_package.id,'virginia-house-wife:1824:general-observations',v_parent_block,7,
    'instruction','general_kitchen_operations_and_service_rules',
$general$GENERAL OBSERVATIONS.

In roasting butcher's meat, be careful not to run the spit through the nice parts: let the piece lie in water one hour, then wash it out, wipe it perfectly dry, and put it on the spit. Set it before a clear, steady, fire; sprinkle some salt on it, and when it becomes hot, baste it for a time with salt and water; then put a good spoonful of nice lard into the dripping-pan, and when melted, continue to baste with it. When your meat, of whatever kind, has been down some time, but before it begins to look brown, cover it with paper, and baste on it; when it is nearly done, take off the paper, dredge it with flour, turn the spit for some minutes very quickly, and baste all the time to raise a froth—after which, serve it up. When mutton is roasted, after you take off the paper, loosen the skin and peel it off carefully, then dredge and froth it up. Beef and mutton must not be roasted as much as veal, lamb, or pork; the last two must be skinned in the manner directed for mutton.—You may pour a little melted butter in the dish with veal, but all the others must be served without sauce, and garnished with horse-radish, nicely scraped. Be careful not to let a particle of dry flour be seen on the meat—it has a very ill appearance. Beef may look brown, but the whiter the other meats are, the more genteel are they, and if properly roasted, they may be perfectly done, and quite white. A loin of veal, and hind quarter of lamb, should be dished with the kidneys uppermost; and be sure to joint every thing that is to be separated at table, or it will be impossible to carve neatly. For those who must have gravy with these meats, let it be made in any way they like, and served in a boat. No meat can be well roasted, except on a spit turned by a jack, and before a steady clear fire—other methods are no better than baking. Many cooks are in the habit of half-boiling the meats to plump them as they turn it, before they are spitted, but it destroys their fine flavour. Whatever is to be boiled, must be put into cold water with a little salt, which will cook them regularly. When they are put in boiling water, the outer side is done too much before the inside gets heated. Nice lard is much better than butter for basting roasted meats, or for frying. To choose butcher's meat, you must see that the fat is not yellow, and that the lean parts are of a fine close grain, a lively colour, and will feel tender when pinched. Poultry should be well covered with white fat; if the bottom of the breast bone be gristly, it is young, but if it be a hard bone it is an old one. Fish are judged by the liveliness of their eyes, and bright red of their gills.

If the weather should become close and damp, while there is a large supply of provisions in the house, the best way to preserve them is to wash each piece in a quantity of cold water, wipe it perfectly dry with a cloth, and rub some dry bran over it, then hang it in the coolest place. This must be done every morning till the weather changes. Beef and mutton will keep much longer than veal, lamb, or pork. Poultry may be preserved in the same manner, by having a little mop to scour the inside, and another to wipe it dry; but as they are more difficult to keep than butcher's meat it would be best to dress them when there is much danger of their spoiling, and either eat them cold, or recook them some other way. Dredge every thing with flour before it is put on to boil, and be sure to add salt to the water.

Fish, and all other articles for frying, after being nicely prepared, should be laid on a board and dredged with flour or meal mixed with salt: when it becomes dry on one side, turn it, and dredge the other. For broiling, have very clear coals, sprinkle a little salt and pepper over the pieces, and when done, dish them, and pour over some melted butter and chopped parsley—this is for broiled veal, wild fowl, birds, or poultry: Beef-steaks and mutton chops require only a table-spoonfull of hot water to be poured over. Slice an onion in the dish before you put in the steaks or chops, and garnish both with rasped horse-raddish. To have viands served in perfection, the dishes should be made hot, either by setting them over hot water, or by putting some in them, and the instant the meats are laid in and garnished, put on a pewter dish cover. A dinner looks very enticing, when the steam rises from each dish on removing the covers, and if it be judiciously ordered, will have a double relish. Profusion is not elegance—a dinner justly calculated for the company, and consisting for the greater part of small articles, correctly prepared, and neatly served up, will make a much more pleasing appearance to the sight, and give far greater gratification to the appetite, than a table loaded with food, and from the multiplicity of dishes, unavoidably neglected in the preparation, and served up cold.

There should always be a supply of brown flour kept in readiness to thicken brown gravies, which must be prepared in the following manner:—Put a pint of flour in a Dutch oven, with some coals under it; keep constantly stirring it until it is uniformly of a dark brown, but none of it burnt, which would look like dirt in the gravy. All kitchens should be provided with a saw for trimming meat, and also with larding needles.$general$,
    jsonb_build_object(
      'printed_pages',jsonb_build_array(23,24,25,26,27,28),
      'historical_unit_type','general_kitchen_operations_and_service_rules',
      'modern_safety_assessed',false,
      'modern_normalization_applied',false,
      'human_visual_inspection',false,
      'typographic_exactness_human_adjudicated',false,
      'next_heading','TO MAKE BEEF SOUP.'
    ),
    jsonb_build_object(
      'text_authority','Library of Congress 1824 first-edition source surfaces are controlling; exact-1824 TextGrid comparison supplies the lexical reading',
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
      'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery',
      'derivation_method','exact_1824_comparison_transcription_corroborated_against_loc_pixels'
    ),
    'verified'
  );

  v_act_id := gen_random_uuid();
  insert into wnph.transmission_acts (
    id,canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,
    epistemic_status,confidence,metadata
  ) values (
    v_act_id,
    'virginia-house-wife:1824:transmission:general-observations:source-text-verification:v1',
    v_case.id,v_work.id,'source_text_verification',
    'Verify Mary Randolph''s GENERAL OBSERVATIONS against the selected 1824 Library of Congress witness for functional-semantic recovery.',
    'The Library of Congress first-edition scans 27 through 32 are the controlling witness. Deterministic 1200-pixel LOC IIIF derivatives independently recover the section heading, roasting/boiling/frying/broiling rules, meat-selection criteria, damp-weather handling, service-temperature guidance, meal-sizing principle, brown-flour preparation, and kitchen-equipment list represented by the semantic claims. The exact-1824 TextGrid transcription supplies comparison wording only. This verifies lexical and semantic source text; it does not claim human visual inspection or typographic/glyph-level adjudication.',
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
  values (v_act_id,'input','preferred_historical_source',v_surrogate.id,jsonb_build_object('lccn','73217897','scan_sequences',jsonb_build_array(27,28,29,30,31,32)));
  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_package_id,locator)
  values (v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb);
  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,evidence_source_id,locator)
  values (v_act_id,'input','comparison_transcription',v_textgrid_source.id,jsonb_build_object('status','comparison_only','edition_year',1824));

  for s in
    select a.id,a.asset_key,m.scan_sequence,m.printed_page,m.sha256,m.byte_length
    from (values
      (27,23,'4e4d00a47b5c117014171538e99e46ec5d2f44a216d2b94ac23095e3017cfe61',329869),
      (28,24,'ee3d361b47dd702bfc40f39c6c80baa5398d06411f12190bce8fcf826b43c0f9',323635),
      (29,25,'83ac440056f16fd7f7a8957c225cd9211d5491bb94355645c19cdfa75f74cfe2',328762),
      (30,26,'79e54478e97a5b1043764ee0a80b37cbb842239dd48f9f02a95878378dd8523c',313764),
      (31,27,'91d6f67e86592f3961bc1881a269bc0baf0673bbdd0d4a1f82c1ac35487b95d3',314202),
      (32,28,'73a96ffa650edfb2cecbe6996bd96cf1d46debc543a280a44e0fb9653b07a40f',305225)
    ) as m(scan_sequence,printed_page,sha256,byte_length)
    join wnph.publication_source_assets a
      on a.source_package_id=v_package.id
     and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'))
    order by m.scan_sequence
  loop
    insert into wnph.transmission_act_objects (
      transmission_act_id,direction,object_role,publication_source_asset_id,locator
    ) values (
      v_act_id,'input','source_page_image',s.id,
      jsonb_build_object('asset_key',s.asset_key,'scan_sequence',s.scan_sequence,'printed_page',s.printed_page,'source_sha256',s.sha256,'source_byte_length',s.byte_length,'human_visual_inspection',false)
    );
  end loop;

  insert into wnph.transmission_act_objects (transmission_act_id,direction,object_role,publication_source_block_id,locator)
  values (v_act_id,'output','verified_source_text',v_block_id,jsonb_build_object('block_key','virginia-house-wife:1824:general-observations','reading_state','verified'));

  insert into wnph.transmission_act_evidence (transmission_act_id,source_id,support_role,confidence,note)
  values
    (v_act_id,v_loc_source.id,'supports','certain','The Library of Congress LCCN 73217897 first-edition digital surrogate is the controlling witness; scans 27–32 bound GENERAL OBSERVATIONS and the next heading.'),
    (v_act_id,v_textgrid_source.id,'supports','high','The independent TextGrid transcription is the same 1824 edition and agrees with the machine reading of the mapped LOC source surfaces; it supplies comparison wording only, not authority.');

  v_unit_id := gen_random_uuid();
  insert into wnph.publication_semantic_units (
    id,expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,
    semantic_status,confidence,derivation_method,properties,source_provenance
  ) values (
    v_unit_id,v_package.expression_id,v_package.id,
    'virginia-house-wife:1824:semantic:general-observations',null,7,
    'general_kitchen_operations_and_service_rules','GENERAL OBSERVATIONS.',
    'verified',0.99,'source_text_verified_semantic_extraction_v1',
    jsonb_build_object(
      'printed_pages',jsonb_build_array(23,24,25,26,27,28),
      'primary_function','general cooking, food handling, service, meal planning, mise-en-place, and kitchen-equipment rules',
      'historical_container','unsectioned opening instruction sequence',
      'modern_safety_assessed',false,
      'modern_normalization_applied',false,
      'human_visual_inspection',false,
      'contains_reusable_non_recipe_principles',true
    ),
    jsonb_build_object(
      'source_verified',true,
      'source_block_id',v_block_id,
      'verification_status','source_text_verified',
      'controlling_witness','LOC 1824',
      'machine_pixel_corroboration',true,
      'human_visual_inspection',false,
      'typographic_exactness_human_adjudicated',false,
      'comparison_transcription_key','textgrid:virginia-house-wife:1824'
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
           'source_pages',x.source_pages,
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
    (1,'roast-spit-placement','roasting_setup','butchers_meat','avoid_piercing','nice parts',null::numeric,null::text,null::text,null::text,null::text,0.99,jsonb_build_object(),jsonb_build_array(23),false),
    (2,'pre-roast-soak','preparation','butchers_meat','soak','water',1::numeric,'hour','one hour','before roasting',null,0.99,jsonb_build_object(),jsonb_build_array(23),true),
    (3,'pre-roast-wash-dry','preparation','butchers_meat','wash_and_dry','wash; wipe perfectly dry',null,null,null,'after soak','before spit',0.99,jsonb_build_object(),jsonb_build_array(23),true),
    (4,'roast-fire','heat_source','roasting','use_fire','clear, steady fire',null,null,null,null,null,0.99,jsonb_build_object(),jsonb_build_array(23),false),
    (5,'initial-roast-salt','seasoning','butchers_meat','sprinkle','salt',null,null,null,'before basting',null,0.99,jsonb_build_object(),jsonb_build_array(23),false),
    (6,'roast-basting-sequence','process_stage','butchers_meat','baste','salt and water, then melted lard',null,null,null,'during roasting',null,0.99,jsonb_build_object('sequence',jsonb_build_array('salt_and_water','lard')),jsonb_build_array(23),false),
    (7,'paper-before-browning','process_stage','roasting_meat','cover_with','paper',null,null,null,'before browning','after meat has been down some time',0.99,jsonb_build_object(),jsonb_build_array(24),false),
    (8,'finish-froth','finishing','roasting_meat','dredge_and_froth','remove paper; dredge with flour; turn spit quickly; baste to raise froth',null,null,null,'near end of roasting',null,0.99,jsonb_build_object(),jsonb_build_array(24),false),
    (9,'mutton-skin-finish','finishing','mutton','remove_skin_and_froth','loosen and peel skin; dredge and froth',null,null,null,'near end of roasting',null,0.99,jsonb_build_object(),jsonb_build_array(24),false),
    (10,'relative-roast-doneness','historical_cooking_endpoint','beef_and_mutton','roast_less_than','veal, lamb, or pork',null,null,null,null,null,0.98,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(24),true),
    (11,'veal-service','service','veal','serve_with','a little melted butter',null,null,null,'at serving',null,0.98,jsonb_build_object(),jsonb_build_array(24),false),
    (12,'other-roast-service','service','other_roasts','serve_with','no sauce; scraped horse-radish garnish',null,null,null,'at serving',null,0.98,jsonb_build_object(),jsonb_build_array(24),false),
    (13,'no-visible-dry-flour','appearance_rule','roasted_meat','avoid','visible dry flour',null,null,null,'at serving',null,0.99,jsonb_build_object(),jsonb_build_array(24),false),
    (14,'historical-colour-preference','historical_appearance_judgment','roasted_meat','prefer_colour','beef may be brown; other meats preferred white',null,null,null,'at serving',null,0.98,jsonb_build_object('author_judgment',true),jsonb_build_array(24),false),
    (15,'dish-kidneys-up','plating','veal_and_lamb','orient','kidneys uppermost',null,null,null,'at serving',null,0.98,jsonb_build_object(),jsonb_build_array(24),false),
    (16,'pre-joint-for-carving','service_preparation','table_meat','joint_before_service','everything to be separated at table',null,null,null,'before serving','for neat carving',0.99,jsonb_build_object(),jsonb_build_array(24),false),
    (17,'gravy-in-boat','service','gravy','serve_in','boat',null,null,null,'at serving','if gravy is wanted',0.97,jsonb_build_object(),jsonb_build_array(25),false),
    (18,'preferred-roasting-apparatus','historical_equipment_judgment','meat_roasting','prefer','spit turned by a jack before a steady clear fire',null,null,null,null,null,0.99,jsonb_build_object('author_judgment',true),jsonb_build_array(25),false),
    (19,'reject-half-boil-before-roast','historical_quality_rule','roasting_meat','avoid','half-boiling before spitting because Randolph says it destroys flavour',null,null,null,'before roasting',null,0.98,jsonb_build_object('author_judgment',true),jsonb_build_array(25),false),
    (20,'historical-boil-start','historical_cooking_rule','boiled_food','start_in','cold water with a little salt',null,null,null,'start of boiling',null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(25),true),
    (21,'cold-water-causal-claim','historical_causal_claim','boiling','attributed_effect','more regular cooking than beginning in boiling water',null,null,null,null,null,0.97,jsonb_build_object('modern_validity_assessed',false),jsonb_build_array(25),true),
    (22,'lard-over-butter','historical_quality_rule','basting_and_frying','prefer_fat','nice lard over butter',null,null,null,null,null,0.98,jsonb_build_object('author_judgment',true),jsonb_build_array(25),false),
    (23,'meat-fat-colour-selection','historical_health_rule','butchers_meat','reject_if','fat is yellow',null,null,null,null,null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(25),true),
    (24,'meat-lean-selection','historical_quality_rule','butchers_meat','prefer','fine close grain; lively colour; tender when pinched',null,null,null,null,null,0.98,jsonb_build_object('modern_validity_assessed',false),jsonb_build_array(25),true),
    (25,'poultry-fat-selection','historical_quality_rule','poultry','prefer','well covered with white fat',null,null,null,null,null,0.98,jsonb_build_object('modern_validity_assessed',false),jsonb_build_array(25),true),
    (26,'poultry-age-breastbone','historical_age_test','poultry','judge_age_by','gristly breast bone = young; hard bone = old',null,null,null,null,null,0.99,jsonb_build_object('modern_validity_assessed',false),jsonb_build_array(25),true),
    (27,'fish-freshness-test','historical_freshness_test','fish','judge_by','lively eyes and bright red gills',null,null,null,null,null,0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(25),true),
    (28,'damp-weather-preservation','historical_preservation_protocol','household_provisions','preserve_by','wash in cold water; wipe dry; rub with dry bran; hang in coolest place',null,null,null,'close and damp weather','repeat every morning until weather changes',0.99,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(26),true),
    (29,'relative-keeping-time','historical_preservation_claim','meats','keep_longer','beef and mutton longer than veal, lamb, or pork',null,null,null,null,null,0.98,jsonb_build_object('modern_validity_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(26),true),
    (30,'poultry-damp-preservation','historical_preservation_protocol','poultry','preserve_by','scour inside; wipe dry; Randolph advises cooking when spoilage danger is high',null,null,null,'close and damp weather',null,0.98,jsonb_build_object('modern_safety_assessed',false,'do_not_use_as_modern_safety_rule',true),jsonb_build_array(26),true),
    (31,'boil-dredge-and-salt','historical_cooking_rule','boiled_articles','prepare_by','dredge with flour before boiling; add salt to water',null,null,null,'before boiling',null,0.98,jsonb_build_object('modern_safety_assessed',false),jsonb_build_array(26),true),
    (32,'frying-dredge','frying_preparation','frying_articles','dredge','flour or meal mixed with salt on both sides',null,null,null,'before frying','allow first side to become dry before turning',0.99,jsonb_build_object(),jsonb_build_array(26),false),
    (33,'broiling-fire-seasoning','broiling','broiled_articles','broil_over','very clear coals with a little salt and pepper',null,null,null,'during broiling',null,0.99,jsonb_build_object(),jsonb_build_array(27),false),
    (34,'broiled-light-meat-finish','service','broiled_veal_wildfowl_birds_poultry','finish_with','melted butter and chopped parsley',null,null,null,'at serving',null,0.98,jsonb_build_object(),jsonb_build_array(27),false),
    (35,'steak-chop-service','service','beef_steaks_and_mutton_chops','finish_with','one table-spoonful hot water; sliced onion; rasped horse-radish',1::numeric,'tablespoon','one table-spoonful hot water','at serving',null,0.99,jsonb_build_object(),jsonb_build_array(27),false),
    (36,'heat-serving-dishes','service_temperature','serving_dishes','preheat','over hot water or with hot water in them',null,null,null,'before plating',null,0.99,jsonb_build_object(),jsonb_build_array(27),false),
    (37,'cover-hot-dishes','service_temperature','plated_meat','cover_immediately','pewter dish cover',null,null,null,'immediately after plating and garnish',null,0.99,jsonb_build_object(),jsonb_build_array(27),false),
    (38,'serve-steaming','historical_service_judgment','dinner_service','prefer','steam rising when covers are removed',null,null,null,'at table',null,0.98,jsonb_build_object('author_judgment',true),jsonb_build_array(27),false),
    (39,'profusion-not-elegance','meal_planning_principle','dinner','prefer','a meal sized to the company, largely small articles correctly prepared and served hot, over excessive multiplicity',null,null,null,'meal planning and service',null,0.99,jsonb_build_object('reusable_planning_principle',true,'historical_author_value_judgment',true),jsonb_build_array(27),false),
    (40,'brown-flour-mise-en-place','mise_en_place','brown_flour','keep_ready','supply for thickening brown gravies',null,null,null,'ongoing kitchen readiness',null,0.99,jsonb_build_object('reusable_planning_principle',true),jsonb_build_array(27,28),false),
    (41,'brown-flour-preparation','ingredient_preparation','brown_flour','prepare','one pint flour in Dutch oven over coals; stir constantly until uniformly dark brown; do not burn',1::numeric,'pint','one pint flour',null,'keep constantly stirring',0.99,jsonb_build_object(),jsonb_build_array(28),false),
    (42,'kitchen-saw','equipment','kitchen','keep_equipment','saw for trimming meat',null,null,null,'ongoing kitchen readiness',null,0.99,jsonb_build_object('reusable_equipment_rule',true),jsonb_build_array(28),false),
    (43,'larding-needles','equipment','kitchen','keep_equipment','larding needles',null,null,null,'ongoing kitchen readiness',null,0.99,jsonb_build_object('reusable_equipment_rule',true),jsonb_build_array(28),false)
  ) as x(ordinal,claim_key,claim_kind,subject_key,predicate,object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,confidence,properties,source_pages,safety_review);
end $$;