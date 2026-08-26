do $guard$
declare
  v_pkg constant uuid := '7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid;
  v_existing integer;
  v_later integer;
begin
  select count(*) into v_existing
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_type='paragraph'
    and b.block_key like 'dewy:chapter:1:paragraph:%';

  if v_existing <> 14 then
    raise exception 'WNPH Dewy Chapter I usable completion expected 14 existing paragraphs, found %',v_existing;
  end if;

  select count(*) into v_later
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.text_content is not null
    and b.block_key like 'dewy:chapter:%:paragraph:%'
    and b.block_key not like 'dewy:chapter:1:paragraph:%';

  if v_later <> 0 then
    raise exception 'WNPH Dewy Chapter I usable completion stop boundary violated: later chapter text already exists';
  end if;
end;
$guard$;

with parent as (
  select id
  from wnph.publication_source_blocks
  where source_package_id='7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid
    and block_key='dewy:chapter:1:paragraph-stream'
  order by created_at desc
  limit 1
), rows(block_key,ordinal,text_content,source_locators,extra_properties,extra_provenance) as (
values
('dewy:chapter:1:paragraph:015',15,$t$So the eagle turned and flew straight toward the red, red ball that was almost ready to drop behind the mountains. It was out of sight before he reached it, and, sure enough, just as it disappeared, a great big white puffy cloud popped its head up over the edge of the world. It was colored in wonderful colors; mostly shades of pink and orange and purple and red, but by the time the weary eagle had reached it, the color had faded and it was just a thick gray and white heap.$t$, '[{"printed_page":10,"source_pdf_page":14,"loc_image":14},{"printed_page":11,"source_pdf_page":15,"loc_image":15}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:016',16,$t$The eagle tumbled down in it and rested on its edge. Miss Wish Fairy hopped off his back and made her way straight to the centre of the cloud. Here she saw dimly through the mist, seated on his throne, the King of the Clouds, and about him were his gray-clad Rain Fairies. They all stopped their dancing and prancing to the soft musical sound of raindrops, as the Wish Fairy came near, and stood in silence while she bowed before the King.$t$, '[{"printed_page":11,"source_pdf_page":15,"loc_image":15},{"printed_page":12,"source_pdf_page":16,"loc_image":16}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:017',17,$t$“Greetings! Oh, King!” she cried sweetly. “Greetings to the Cloud Kingdom from the Sunshine and Shadow Forest. I come to ask a favor. My land and my people are nigh dead with thirst, for not a drop of rain has come to them for weeks. We fear fire and death. Will it not be possible for one of your subjects to come back with me to the Sunshine and Shadow Forest and have power to call down the rain that is so sorely needed?”$t$, '[{"printed_page":12,"source_pdf_page":16,"loc_image":16}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:018',18,$t$She waited in silence for his answer, and at last it came.$t$, '[{"printed_page":12,"source_pdf_page":16,"loc_image":16}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:019',19,$t$“Greetings! Lady Wish Fairy! Greetings to the Sunshine and Shadow Forest from the great Cloud Kingdom. We have been aware of your distress, but the world is a big place and we are out of clouds. I shall be glad to let you take back with you Dewy Dear, who shall have power to call down the rain that is needed. She shall take a corner of this cloud with her, which will relieve you for the present, but I would suggest that you visit King Wind. He has been lazy lately and has blown so few clouds that there is thirst all over the earth. He is a kind-hearted king and will help you, I feel sure, when he knows how greatly his help is needed.”$t$, '[{"printed_page":12,"source_pdf_page":16,"loc_image":16},{"printed_page":13,"source_pdf_page":17,"loc_image":17}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:020',20,$t$“My thanks, oh, King,” the Wish Fairy said. “My thanks. And now we will be on our way, for we must hasten back ere it is too late.”$t$, '[{"printed_page":13,"source_pdf_page":17,"loc_image":17}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:021',21,$t$“Dewy Dear!” the King called. And from the midst of the fairies came a dainty little figure. She was dressed in gray, and her soft gown dropped shining drops of water with a soft musical patter as she ran. At the edge of the cloud she stooped and tore a big armful of the soft stuff loose. Then she jumped up on the eagle’s back behind the Wish Fairy and sat very still.$t$, '[{"printed_page":13,"source_pdf_page":17,"loc_image":17},{"printed_page":14,"source_pdf_page":18,"loc_image":18}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:022',22,$t$It was night when they saw the Sunshine and Shadow Forest below them. By the clear light of the white moon it lay black and silent and breathless. Suddenly Dewy Dear stood up.$t$, '[{"printed_page":14,"source_pdf_page":18,"loc_image":18}]'::jsonb, '{}'::jsonb, '{}'::jsonb),
('dewy:chapter:1:paragraph:023',23,$t$“I shall jump off here,” she said. “You hasten home. I shall come later.”$t$, '[{"printed_page":14,"source_pdf_page":18,"loc_image":18}]'::jsonb, '{"machine_normalization_review_needed":true}'::jsonb, '{"machine_normalizations":[{"normalized_to":"I","loc_alto_candidate":"YT","ia_djvu_candidate":"T","basis":"known capital-I OCR confusion; context normalization; not source-image verified"}]}'::jsonb),
('dewy:chapter:1:paragraph:024',24,$t$So she jumped off, with the cloud in her arms, and hovered there in the air until she saw the eagle sink out of sight in the tree tops. Then she began shaking her armful of cloud. And she shook and shook, and a gentle rain pattered down, and she kept on shaking until the cloud had quite disappeared in a veil of rain. As the last shred of cloud left her fingers little Dewy Dear hopped on the gray curtain that was streaming to earth, and slid down until she landed at the door of the toadstool cottage where little Miss Wish Fairy was waiting for her.$t$, '[{"printed_page":14,"source_pdf_page":18,"loc_image":18},{"printed_page":16,"source_pdf_page":20,"loc_image":20}]'::jsonb, '{"historical_page_interruption":"nontext_surface_printed_page_15","intervening_source_pdf_page":19,"intervening_loc_image":19}'::jsonb, '{}'::jsonb)
)
insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance,reading_state)
select '7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid,
       r.block_key,
       p.id,
       r.ordinal,
       'paragraph',
       'body_paragraph',
       r.text_content,
       jsonb_build_object('chapter_number',1,'paragraph_number',r.ordinal,'reading_status','usable','canonical_status','not_yet_verified') || r.extra_properties,
       jsonb_build_object(
         'text_authority','derived_same_witness_dual_ocr_consensus',
         'source_locators',r.source_locators,
         'derivation_method','loc_alto_plus_internet_archive_djvu_consensus_with_mechanical_line_unwrap_and_dehyphenation',
         'verification_status','machine_derived_not_source_verified',
         'preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital',
         'ocr_source_keys',jsonb_build_array('library-of-congress:alto:per-page','internet-archive:ia:wishfairydewydea00colv:djvu-text')
       ) || r.extra_provenance,
       'usable'
from rows r cross join parent p;

set constraints all immediate;

do $verify$
declare
  v_pkg constant uuid := '7ff672f8-ee89-4327-b7d6-3d802b85e481'::uuid;
  v_total integer;
  v_verified integer;
  v_usable integer;
  v_later integer;
  v_ch1_end integer;
  v_ch2_start integer;
begin
  select count(*),
         count(*) filter (where wnph.resolve_publication_source_block_reading_state_v1(reading_state,text_content,source_provenance)='verified'),
         count(*) filter (where wnph.resolve_publication_source_block_reading_state_v1(reading_state,text_content,source_provenance)='usable')
    into v_total,v_verified,v_usable
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_type='paragraph'
    and b.block_key like 'dewy:chapter:1:paragraph:%';

  select (properties->>'printed_page_end')::integer into v_ch1_end
  from wnph.publication_source_blocks
  where source_package_id=v_pkg and block_key='dewy:chapter:1'
  order by created_at desc limit 1;

  select (properties->>'printed_page_start')::integer into v_ch2_start
  from wnph.publication_source_blocks
  where source_package_id=v_pkg and block_key='dewy:chapter:2'
  order by created_at desc limit 1;

  select count(*) into v_later
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.text_content is not null
    and b.block_key like 'dewy:chapter:%:paragraph:%'
    and b.block_key not like 'dewy:chapter:1:paragraph:%';

  if v_total<>24 or v_verified<>14 or v_usable<>10 then
    raise exception 'WNPH Dewy Chapter I usable completion parity failed: total %, verified %, usable %',v_total,v_verified,v_usable;
  end if;
  if v_ch1_end<>16 or v_ch2_start<>17 then
    raise exception 'WNPH Dewy Chapter boundary parity failed: chapter I end %, chapter II start %',v_ch1_end,v_ch2_start;
  end if;
  if v_later<>0 then
    raise exception 'WNPH Dewy Chapter I stop boundary failed: later chapter text count %',v_later;
  end if;
end;
$verify$;