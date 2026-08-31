insert into wnph.evidence_sources (
  canonical_key, source_type, title, repository_name, url, external_identifier,
  rights_note, provenance_note, metadata
)
select
  'textgrid:virginia-house-wife:1824',
  'repository_transcription',
  'The Virginia House-wife — exact 1824 comparison transcription',
  'TextGrid Repository',
  'https://sandbox.textgridrep.org/browse/textgrid%3A2s1gn.0?mode=gallery',
  'textgrid:2s1gn.0',
  'Comparison transcription of a public-domain 1824 work; Library of Congress witness remains controlling.',
  'Used only as an independent exact-edition comparison reading against the Library of Congress first-edition source surfaces.',
  jsonb_build_object(
    'edition_year',1824,
    'comparison_only',true,
    'controlling_witness',false,
    'work_key','virginia-house-wife'
  )
where not exists (
  select 1 from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824'
);

with scans(scan_sequence,printed_page,image_height,inspection_derivative_sha256,inspection_derivative_byte_length,signals) as (
  values
    (17,13,1984,'ce51644c7a6abcd60f26620c38169557a4573e2276c5d124d3e6be57d3403e93',302393,jsonb_build_array('DIRECTIONS FOR CURING BEEF','thirty gallon cask','one pound salt-petre','fifteen quarts salt','fifteen gallons cold water','bear up an egg')),
    (18,14,1852,'41ed02c798d663308eac0077b74c179dfa25d0ba36cd3a9fbd6b5e926bb2ca42',308441,jsonb_build_array('course of the winter','cool dry place','newly killed','Liverpool salt','fleshy side downward')),
    (19,15,2040,'e9c581cb678dd97a1b4b3408893dedc9149ff7d30468192010c2a05cc08c0dac',337635,jsonb_build_array('salt ten days','bit of board and weight','about ten days','latter end of October','Tongues are cured in the same manner','TO DRY BEEF FOR SUMMER USE','middle of February')),
    (20,16,1851,'1c0d55256df909fda1467775a92ddde1a60582855e7be28da02fad54c2416f67',305194,jsonb_build_array('one hundred and fifty per quarter','one fortnight','three weeks','rub with bran','cool dry dark place','look over occasionally','long wet season','large quantity of water','bones are ready to fall out')),
    (21,17,2040,'4871a49dfbb10979e96fcbd722f6f9c28a99ae546674d8e1686f29a59764d8dc',315916,jsonb_build_array('decrease of the moon','old age','diseased state','three to five years','colour of the fat','TO CURE BACON','two and a half to four years old')),
    (22,18,1813,'4365a66ee588326c970961f6d5b013f7fbd848dd29d8946dbeda7e6fe1233577',292739,jsonb_build_array('one hundred and fifty or sixty','fed with corn six weeks','salt them before they get cold','take out the chine','hams shoulders and middlings','large table-spoonful of salt petre','feet','ears and noses','cold water for souse')),
    (23,19,1995,'0382c08a0fcf3bfbd99b8bfaf4d536b2671f0fe5fe25dd25f92c595f4beefd57',309446,jsonb_build_array('jowls two weeks','shoulders and middlings three weeks','hams four weeks','hocks down','good smoke every morning','not to have a blaze','first of April','hickory ashes','large quantity of water','bone on the under part comes off with ease','New bacon requires much longer boiling')),
    (24,20,1813,'208d0ef8b9dd1b836d83a0ed85c54dac097798b5f19dcccad3f632f284f5ff1a',301349,jsonb_build_array('TO MAKE SOUSE','cold water twelve hours','changing the water frequently','scrape and clean each piece','meal with water','boil gently','run a straw into the skin','feet in one pot','ears and noses in another','heads in a third','pepper salt and a little nutmeg','tight roll','one fourth of vinegar','renew this liquor every two or three weeks')),
    (25,21,1995,'5590d9dbf25b7d4dd422a444b3382a7d62a3fd312e15ff0385fde332d377e5db',330058,jsonb_build_array('souse get quite cold after boiling','pale coloured vinegar','souse will be dark','singe the hair','good souse will always be white','TO CURE HERRINGS'))
), package as (
  select id from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1'
)
insert into wnph.publication_source_observations (
  source_asset_id, observation_key, observation_kind, ordinal,
  coordinate_unit, x, y, width, height, confidence,
  derivation_method, source_format, processor, external_locator, metadata
)
select
  a.id,
  format('virginia-house-wife:1824:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0')),
  'layout_region', 1,
  'pixel',0,0,1200,s.image_height,0.98,
  'bounded_machine_pixel_corroboration_v1',
  'image/jpeg',
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
    and o.observation_key=format('virginia-house-wife:1824:scan:%s:machine-pixel-corroboration:v1',lpad(s.scan_sequence::text,4,'0'))
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
  v_old_block wnph.publication_source_blocks%rowtype;
  v_old_unit wnph.publication_semantic_units%rowtype;
  v_new_block_id uuid;
  v_new_unit_id uuid;
  v_act_id uuid;
  v_text text;
  v_locators jsonb;
  r record;
  s record;
begin
  select * into strict v_package from wnph.publication_source_packages where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';
  select * into strict v_case from wnph.recovery_cases where canonical_key='virginia-house-wife:functional-semantic-cookbook-recovery-1';
  select * into strict v_work from wnph.historical_works where canonical_key='virginia-house-wife';
  select * into strict v_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';
  select * into strict v_loc_source from wnph.evidence_sources where canonical_key='loc:item:73217897';
  select * into strict v_textgrid_source from wnph.evidence_sources where canonical_key='textgrid:virginia-house-wife:1824';

  for r in
    select * from (values
      (
        'virginia-house-wife:1824:beef:directions-for-curing-beef'::text,
        'virginia-house-wife:1824:semantic:curing-beef'::text,
        'virginia-house-wife:1824:transmission:curing-beef:source-text-verification:v1'::text,
        array[17,18,19]::int[],
        null::text
      ),
      (
        'virginia-house-wife:1824:to-dry-beef-for-summer-use'::text,
        'virginia-house-wife:1824:semantic:dry-beef-for-summer-use'::text,
        'virginia-house-wife:1824:transmission:dry-beef-for-summer-use:source-text-verification:v1'::text,
        array[19,20,21]::int[],
        null::text
      ),
      (
        'virginia-house-wife:1824:to-cure-bacon'::text,
        'virginia-house-wife:1824:semantic:cure-bacon'::text,
        'virginia-house-wife:1824:transmission:cure-bacon:source-text-verification:v1'::text,
        array[21,22,23]::int[],
        $bacon$TO CURE BACON.

Hogs are in the highest perfection, from two and a half to four years old, and make the best bacon, when they do not weigh more than one hundred and fifty or sixty at farthest: They should be fed with corn, six weeks, at least, before they are killed, and the shorter distance they are driven to market, the better their flesh will be. To secure them against the possibility of spoiling, salt them before they get cold: take out the chine or back-bone from the neck to the tail, cut the hams, shoulders and middlings; take the ribs from the shoulders, and the leaf fat from the hams: have such tubs as are directed for beef, rub a large table-spoonful of salt petre on the inside of each ham, for some minutes, then rub both sides well with salt, lay the hams with the skin downward, and put a good deal of salt between each layer; salt the shoulders and middlings in the same manner, but with less salt-petre if necessary: cut the jowl or chop from the head, and rub it with salt and salt-petre. You should cut off the feet just above the knee-joint; take off the ears and noses, and lay them in a large tub of cold water for souse. When the jowls have been in salt two weeks, hang them up to smoke—do so with the shoulders and middlings at the end of three weeks, and the hams at the end of four. If they remain longer in salt they will be hard. Remember to hang the hams and shoulders with the hocks down to preserve the juices. Make a good smoke every morning, and be careful not to have a blaze; the smoke-house should stand alone, for any additional heat will spoil the meat. During the hot weather, beginning the first of April, it should be occasionally taken down, examined, rubbed with hickory ashes, and hung up again.

The generally received opinion that salt-petre hardens meat, is entirely erroneous:—it tends greatly to prevent putrefaction, but it will not make it hard; neither will laying in brine for five or six weeks in cold weather, have that effect, but remaining in salt too long, will certainly draw off the juices, and harden it. Bacon should be boiled in a large quantity of water, and a ham is not done sufficiently, till the bone on the under part comes off with ease. New bacon requires much longer boiling than that which is old.$bacon$::text
      ),
      (
        'virginia-house-wife:1824:to-make-souse'::text,
        'virginia-house-wife:1824:semantic:make-souse'::text,
        'virginia-house-wife:1824:transmission:make-souse:source-text-verification:v1'::text,
        array[24,25]::int[],
        $souse$TO MAKE SOUSE.

Let all the pieces you intend to souse, remain covered with cold water twelve hours; then wash them out, wipe off the blood, and put them again in fresh water; soak them in this manner, changing the water frequently, and keeping it in a cool place, till the blood is drawn away; scrape and clean each piece perfectly nice, mix some meal with water, add salt to it, and boil your souse gently, until you can run a straw into the skin with ease. Do not put too much in the pot for it will boil to pieces and spoil the appearance. The best way is, to boil the feet in one pot, the ears and noses in another, and the heads in a third; these should be boiled till you can take all the bones out; let them get cold, season the insides with pepper, salt, and a little nutmeg; make a tight roll, sew it up close in a cloth, and press it lightly. Mix some more meal and cold water, just enough to look white; add salt, and one fourth of vinegar; put your souse in different pots, and keep it well covered with this mixture, and closely stopped. It will be necessary to renew this liquor, every two or three weeks. Let your souse get quite cold after boiling, before you put it in the liquor, and be sure to use pale coloured vinegar, or the souse will be dark. Some cooks singe the hair from the feet, etcetera, but this destroys the colour:—good souse will always be white.$souse$::text
      )
    ) as x(block_key,unit_key,act_key,scans,exact_text)
  loop
    if exists(select 1 from wnph.transmission_acts where canonical_key=r.act_key) then
      continue;
    end if;

    select * into strict v_old_block
    from wnph.publication_source_blocks b
    where b.source_package_id=v_package.id
      and b.block_key=r.block_key
      and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

    select * into strict v_old_unit
    from wnph.publication_semantic_units u
    where u.source_package_id=v_package.id
      and u.unit_key=r.unit_key
      and not exists(select 1 from wnph.publication_semantic_units child where child.supersedes_unit_id=u.id);

    v_text := coalesce(r.exact_text,v_old_block.text_content);

    select jsonb_agg(
      jsonb_build_object(
        'asset_key',a.asset_key,
        'scan_sequence',m.scan_sequence,
        'printed_page',m.printed_page,
        'inspection_derivative_sha256',m.sha256,
        'inspection_derivative_byte_length',m.byte_length
      ) order by m.scan_sequence
    ) into v_locators
    from (values
      (17,13,'ce51644c7a6abcd60f26620c38169557a4573e2276c5d124d3e6be57d3403e93',302393),
      (18,14,'41ed02c798d663308eac0077b74c179dfa25d0ba36cd3a9fbd6b5e926bb2ca42',308441),
      (19,15,'e9c581cb678dd97a1b4b3408893dedc9149ff7d30468192010c2a05cc08c0dac',337635),
      (20,16,'1c0d55256df909fda1467775a92ddde1a60582855e7be28da02fad54c2416f67',305194),
      (21,17,'4871a49dfbb10979e96fcbd722f6f9c28a99ae546674d8e1686f29a59764d8dc',315916),
      (22,18,'4365a66ee588326c970961f6d5b013f7fbd848dd29d8946dbeda7e6fe1233577',292739),
      (23,19,'0382c08a0fcf3bfbd99b8bfaf4d536b2671f0fe5fe25dd25f92c595f4beefd57',309446),
      (24,20,'208d0ef8b9dd1b836d83a0ed85c54dac097798b5f19dcccad3f632f284f5ff1a',301349),
      (25,21,'5590d9dbf25b7d4dd422a444b3382a7d62a3fd312e15ff0385fde332d377e5db',330058)
    ) as m(scan_sequence,printed_page,sha256,byte_length)
    join wnph.publication_source_assets a
      on a.source_package_id=v_package.id
     and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'))
    where m.scan_sequence=any(r.scans);

    v_new_block_id := gen_random_uuid();
    insert into wnph.publication_source_blocks (
      id,source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
      text_content,properties,source_provenance,supersedes_block_id,reading_state
    ) values (
      v_new_block_id,
      v_old_block.source_package_id,
      v_old_block.block_key,
      v_old_block.parent_block_id,
      v_old_block.ordinal,
      v_old_block.block_type,
      v_old_block.semantic_role,
      v_text,
      v_old_block.properties || jsonb_build_object(
        'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery',
        'typographic_exactness_human_adjudicated',false,
        'human_visual_inspection',false
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
        'verification_scope','lexical_and_semantic_content_for_functional_semantic_recovery',
        'derivation_method','exact_1824_comparison_transcription_corroborated_against_loc_pixels'
      ),
      v_old_block.id,
      'verified'
    );

    v_act_id := gen_random_uuid();
    insert into wnph.transmission_acts (
      id,canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,
      epistemic_status,confidence,metadata
    ) values (
      v_act_id,
      r.act_key,
      v_case.id,
      v_work.id,
      'source_text_verification',
      format('Verify %s against the selected 1824 Library of Congress witness for functional-semantic recovery.',r.block_key),
      'The Library of Congress first-edition scan sequence is the controlling witness. A bounded OCRAD pass over deterministic 1200-pixel LOC IIIF derivatives independently recovered the headings, quantities, timings, process order, and historical causal statements represented by the semantic claims. The exact-1824 TextGrid transcription supplies comparison wording only. This act verifies lexical and semantic source text for the functional-semantic layer; it does not claim human visual inspection or typographic/glyph-level adjudication.',
      'system_recorded',
      'high',
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

    insert into wnph.transmission_act_objects (
      transmission_act_id,direction,object_role,surrogate_id,locator
    ) values (
      v_act_id,'input','preferred_historical_source',v_surrogate.id,
      jsonb_build_object('lccn','73217897','scan_sequences',to_jsonb(r.scans))
    );

    insert into wnph.transmission_act_objects (
      transmission_act_id,direction,object_role,publication_source_package_id,locator
    ) values (
      v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb
    );

    insert into wnph.transmission_act_objects (
      transmission_act_id,direction,object_role,publication_source_block_id,locator
    ) values (
      v_act_id,'context','candidate_reading_superseded',v_old_block.id,'{}'::jsonb
    );

    insert into wnph.transmission_act_objects (
      transmission_act_id,direction,object_role,evidence_source_id,locator
    ) values (
      v_act_id,'input','comparison_transcription',v_textgrid_source.id,
      jsonb_build_object('status','comparison_only','edition_year',1824)
    );

    for s in
      select a.id,a.asset_key,m.scan_sequence,m.printed_page,m.sha256,m.byte_length
      from (values
        (17,13,'ce51644c7a6abcd60f26620c38169557a4573e2276c5d124d3e6be57d3403e93',302393),
        (18,14,'41ed02c798d663308eac0077b74c179dfa25d0ba36cd3a9fbd6b5e926bb2ca42',308441),
        (19,15,'e9c581cb678dd97a1b4b3408893dedc9149ff7d30468192010c2a05cc08c0dac',337635),
        (20,16,'1c0d55256df909fda1467775a92ddde1a60582855e7be28da02fad54c2416f67',305194),
        (21,17,'4871a49dfbb10979e96fcbd722f6f9c28a99ae546674d8e1686f29a59764d8dc',315916),
        (22,18,'4365a66ee588326c970961f6d5b013f7fbd848dd29d8946dbeda7e6fe1233577',292739),
        (23,19,'0382c08a0fcf3bfbd99b8bfaf4d536b2671f0fe5fe25dd25f92c595f4beefd57',309446),
        (24,20,'208d0ef8b9dd1b836d83a0ed85c54dac097798b5f19dcccad3f632f284f5ff1a',301349),
        (25,21,'5590d9dbf25b7d4dd422a444b3382a7d62a3fd312e15ff0385fde332d377e5db',330058)
      ) as m(scan_sequence,printed_page,sha256,byte_length)
      join wnph.publication_source_assets a
        on a.source_package_id=v_package.id
       and a.asset_key=format('virginia-house-wife:1824:source-surface:%s',lpad(m.scan_sequence::text,4,'0'))
      where m.scan_sequence=any(r.scans)
      order by m.scan_sequence
    loop
      insert into wnph.transmission_act_objects (
        transmission_act_id,direction,object_role,publication_source_asset_id,locator
      ) values (
        v_act_id,'input','source_page_image',s.id,
        jsonb_build_object(
          'asset_key',s.asset_key,
          'scan_sequence',s.scan_sequence,
          'printed_page',s.printed_page,
          'inspection_derivative_sha256',s.sha256,
          'inspection_derivative_byte_length',s.byte_length,
          'human_visual_inspection',false
        )
      );
    end loop;

    insert into wnph.transmission_act_objects (
      transmission_act_id,direction,object_role,publication_source_block_id,locator
    ) values (
      v_act_id,'output','verified_source_text',v_new_block_id,
      jsonb_build_object('block_key',r.block_key,'reading_state','verified')
    );

    insert into wnph.transmission_act_evidence (
      transmission_act_id,source_id,support_role,confidence,note
    ) values
      (v_act_id,v_loc_source.id,'supports','certain','The Library of Congress LCCN 73217897 first-edition digital surrogate is the controlling witness; mapped scan leaves were fetched from its IIIF image service.'),
      (v_act_id,v_textgrid_source.id,'supports','high','The independent TextGrid transcription is the same 1824 edition and agrees with the machine reading of the mapped LOC source surfaces; it supplies comparison wording only, not authority.');

    v_new_unit_id := gen_random_uuid();
    insert into wnph.publication_semantic_units (
      id,expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,
      semantic_status,confidence,derivation_method,properties,source_provenance,supersedes_unit_id
    ) values (
      v_new_unit_id,
      v_old_unit.expression_id,
      v_old_unit.source_package_id,
      v_old_unit.unit_key,
      v_old_unit.parent_unit_id,
      v_old_unit.ordinal,
      v_old_unit.unit_type,
      v_old_unit.source_title,
      'verified',
      v_old_unit.confidence,
      'source_text_verified_semantic_carryforward_v1',
      v_old_unit.properties || jsonb_build_object(
        'verification_scope','historical_source_semantics',
        'modern_safety_assessed',false,
        'human_visual_inspection',false
      ),
      v_old_unit.source_provenance || jsonb_build_object(
        'source_verified',true,
        'source_block_id',v_new_block_id,
        'verification_status','source_text_verified',
        'machine_pixel_corroboration',true,
        'human_visual_inspection',false,
        'typographic_exactness_human_adjudicated',false,
        'comparison_transcription_key','textgrid:virginia-house-wife:1824'
      ),
      v_old_unit.id
    );

    insert into wnph.publication_semantic_claims (
      id,semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,
      object_text,quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,
      claim_status,confidence,derivation_method,properties,source_provenance,supersedes_claim_id
    )
    select
      gen_random_uuid(),
      v_new_unit_id,
      v_new_block_id,
      c.claim_key,
      c.ordinal,
      c.claim_kind,
      c.subject_key,
      c.predicate,
      c.object_text,
      c.quantity_value,
      c.quantity_unit,
      c.quantity_text,
      c.temporal_text,
      c.condition_text,
      'verified',
      c.confidence,
      'source_text_verified_claim_carryforward_v1',
      c.properties,
      c.source_provenance || jsonb_build_object(
        'source_verified',true,
        'verification_status','source_text_verified',
        'verified_source_block_id',v_new_block_id,
        'machine_pixel_corroboration',true,
        'human_visual_inspection',false,
        'typographic_exactness_human_adjudicated',false,
        'comparison_transcription_key','textgrid:virginia-house-wife:1824'
      ),
      c.id
    from wnph.publication_semantic_claims c
    where c.semantic_unit_id=v_old_unit.id
      and not exists(select 1 from wnph.publication_semantic_claims child where child.supersedes_claim_id=c.id)
    order by c.ordinal;
  end loop;
end $$;