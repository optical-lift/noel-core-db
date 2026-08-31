do $block$
declare r record;
begin
  perform public.wnph_record_publication_expression_block_v2(
    'wish-fairy-dewy-dear:wnph-publication-e1','dewy:publication-expression:chapter5:v1','wnph:dewy:chapter:5',null,5,
    'chapter','chapter','CHAPTER V','admitted','structural_adjudication',0.99,
    'wnph_publication_expression_structural_adjudication_v2',array['dewy:chapter:5'],'[]'::jsonb,
    jsonb_build_object('publication_admission',true,'observed_title','Bumps','printed_page_start',45,'printed_page_end',52,'publication_expression_only',true,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_skeleton_unchanged',true),null
  );
  for r in select * from (values
    (1,'Of course Roarabout and Wisselit could not keep quiet long, but with Star and Silver Nose in the Sunshine and Shadow Forest they did not dare play any tricks. They went about their business of blowing up snowstorms, and came home at nightfall out of breath and very tired. But if they so much as tried any funny stunts Silver Nose and Star got after them and nipped their noses and toes.',jsonb_build_array('Normalized split name and line-end hyphenation.')),
    (2,'So the winter passed peacefully for all the inhabitants of the great Sunshine and Shadow Forest. But with the coming of warm days Silver Nose and Star lost their energy, and their nips did not bother Roarabout and Wisselit so much.',jsonb_build_array('Normalized line-end hyphenation.')),
    (3,'“Ha! Ha!” they whispered. “Pretty soon Silver Nose and Star will have to go back to their home, and we will be free to have some fun again!”',jsonb_build_array('Normalized OCR opening quotation marks.')),
    (4,'So they plotted and planned, while Silver Nose and Star went about saying goodbye to everyone in the forest. All were sorry to see the faithful little fairies depart and Mr. and Mrs. Robin wept big tears.','[]'::jsonb),
    (5,'“There will be no one to save our home and egg-babies,” they said. “What shall we do? Last year we tried to have a family three times, and each time Roarabout and Wisselit upset our plans and our nests.”',jsonb_build_array('Normalized split name.')),
    (6,'But Silver Nose and Star told them not to worry. Miss Wish Fairy would manage it, and they went last of all to her to say goodbye, and told her a secret. Miss Wish Fairy listened soberly, and at last nodded with a smile.',jsonb_build_array('Rejoined paragraph across printed page break.','Corrected OCR “manag-e” and line-end hyphenation.')),
    (7,'“Your cousins will come? Can they manage Roarabout and Wisselit? Oh, all right then. And they’ll stay until—” she finished in a whisper.',jsonb_build_array('Normalized split name and OCR quotation marks.')),
    (8,'Silver Nose and Star said “yes” and then waved their last goodbyes and slipped away along the icy stream that was beginning to tinkle and gurgle under its frail covering of ice. Once Silver Nose broke through the thin ice and Star had to pull him out. But at last they reached the cool mouth of the cave where they had their home and disappeared.',jsonb_build_array('Normalized OCR quote marks, “good-byes,” and stray comma in “where they had”.')),
    (9,'Then Roarabout and Wisselit looked about in glee.','[]'::jsonb),
    (10,'“Whoopla!” they shouted. “We’ll have some fun!”',jsonb_build_array('Normalized OCR quote marks.')),
    (11,'And they blew little bits of sticks and dirt into Little Baby Reindeer’s brown eyes; and they blew down a whole branch of a tree where Mr. and Mrs. Robin had begun to build their nest; and they blew up big waves in the still pool that washed down the Beaver Boy’s carefully built house of sticks; and everybody grew cross and tearful.',jsonb_build_array('Rejoined paragraph across printed page break.')),
    (12,'At last Miss Wish Fairy came to the rescue.','[]'::jsonb),
    (13,'“Boys!” she cried sternly. “It’s time to quit this nonsense. Up you go now and blow up a few clouds. We want a nice Spring rain to start the flowers and grass to growing.”','[]'::jsonb),
    (14,'Grinning and giggling the wind twins whisked up in the air very much pleased with themselves, and the Wish Fairy watched them anxiously. Suppose Silver Nose’s cousins shouldn’t come?','[]'::jsonb),
    (15,'But they did.','[]'::jsonb),
    (16,'And who do you think they were?',jsonb_build_array('Normalized spacing before question mark and removed running page furniture.')),
    (17,'Well, when the twins had blown up clouds and Dewy Dear had called down the rain, lo and behold! The rain froze on its way down into sleet and hail, and banged and bumped on Wisselit’s and Roarabout’s heads until they hollered for help and ran whimpering to shelter.',jsonb_build_array('Normalized “lo and behold,” line-end hyphenation, and removed stray comma after “froze”.')),
    (18,'No sooner had they crawled under the overhanging roof on the Wish Fairy’s doorstep than there stood before them a funny-looking figure.',jsonb_build_array('Normalized line-end hyphenation.')),
    (19,'His head was a round bump. His shoulders were bumpy. His feet ended in bumps, and his hands were doubled up into balls of bumps, and he was gray and hard and cold.','[]'::jsonb),
    (20,'“Now then, youngsters,” he said, and his gray whiskers shook as he talked, “you’ll have to behave yourselves a while longer. I’ve got something that will make you.”',jsonb_build_array('Rejoined paragraph across printed page break and page furniture.','Corrected OCR “IVe” to “I’ve” and line-end hyphenation.','Normalized malformed closing quote.')),
    (21,'And Bumps, the Hail Fairy, suddenly threw a handful of hard stones down on the frightened wind twins that made them duck and run while Miss Wish Fairy giggled from her window.','[]'::jsonb)
  ) as v(ordinal,text_content,repairs)
  loop
    perform public.wnph_record_publication_expression_block_v2(
      'wish-fairy-dewy-dear:wnph-publication-e1',format('dewy:publication-expression:chapter5:paragraph:%s:v1',lpad(r.ordinal::text,3,'0')),format('wnph:dewy:chapter:5:paragraph:%s',lpad(r.ordinal::text,3,'0')),
      'wnph:dewy:chapter:5',r.ordinal,'paragraph','body_paragraph',r.text_content,'admitted','editorial_reconstruction_high_confidence',0.99,
      'wnph_publication_expression_same_surrogate_ocr_collation_v2',array['dewy:chapter:5:paragraph-stream'],
      jsonb_build_array(jsonb_build_object('source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','evidence_role','same_surrogate_derivative','notes','Internet Archive DjVu OCR derivative of the same governed LOC/IA surrogate; zero additional historical-witness count and not source-image verification.')),
      jsonb_build_object('publication_admission',true,'publication_expression_only',true,'raw_ocr_sha256','7e9006f7f96af55c5ef4acb7f8572d6247c4573ce0bbc5cc8da6c2870be648fc','same_surrogate_derivative',true,'historical_witness_count_delta',0,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_forensic_stream_unchanged',true,'printed_page_range',jsonb_build_array(45,52),'page_furniture_removed',true,'line_end_hyphenation_normalized',true,'paragraph_boundary_reconstruction',true,'editorial_repairs',r.repairs),null
    );
  end loop;
  perform public.wnph_refresh_expression_manifestation_derivations_v1('wish-fairy-dewy-dear:wnph-publication-e1');
end;
$block$;