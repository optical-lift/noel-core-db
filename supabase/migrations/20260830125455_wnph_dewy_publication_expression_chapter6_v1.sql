do $block$
declare r record;
begin
  perform public.wnph_record_publication_expression_block_v2(
    'wish-fairy-dewy-dear:wnph-publication-e1','dewy:publication-expression:chapter6:v1','wnph:dewy:chapter:6',null,6,
    'chapter','chapter','CHAPTER VI','admitted','structural_adjudication',0.99,
    'wnph_publication_expression_structural_adjudication_v2',array['dewy:chapter:6'],'[]'::jsonb,
    jsonb_build_object('publication_admission',true,'observed_title','Black Face and White Face','printed_page_start',53,'printed_page_end',63,'publication_expression_only',true,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_skeleton_unchanged',true),null
  );
  for r in select * from (values
    (1,'“But whatever we will do when summer comes, and it is too warm for Bumps to stay with us, I don’t know,” Miss Wish Fairy sighed to Dewy Dear and Twinkletoes. “Those wind twins know Bumps will leave us soon and already they are planning all sorts of naughty mischief.”',jsonb_build_array('Recovered mangled decorative opening from OCR and normalized split words/names.')),
    (2,'And sure enough it was as the Wish Fairy said. Bumps left the Sunshine and Shadow Forest after a few weeks and Roarabout and Wisselit were free to play all sorts of pranks again.','[]'::jsonb),
    (3,'King Lion finally came to the Wish Fairy to consult with her.','[]'::jsonb),
    (4,'“Wouldn’t it be possible to ask King Wind to exchange those boisterous boys for others?” he asked anxiously. “There’ll be a fight in the Sunshine and Shadow Forest soon. The twins are teaching the beasts to believe it was others that did the mischief and not themselves. Mr. Monkey is getting blamed for lots of things and he’s nearly cross enough to bite.”',jsonb_build_array('Rejoined paragraph across printed page break.','Normalized line-end hyphenation, apostrophes, and malformed closing quote.')),
    (5,'Miss Wish Fairy sighed.','[]'::jsonb),
    (6,'“I shouldn’t dare try,” she sighed. “King Wind might get angry and not let us have anybody, and Roarabout and Wisselit are better than nobody. Besides I have an idea that none are any better than these two. They’re all mischievous.”',jsonb_build_array('Normalized OCR quote marks and split word.')),
    (7,'“But we must have something to protect us in the Sunshine and Shadow Forest,” said King Lion as he scratched his head in thought.','[]'::jsonb),
    (8,'Just then Dewy Dear slipped up.','[]'::jsonb),
    (9,'“I know,” she said quietly. “I know just what to do. If you will go with me on the eagle’s back to my home in the Cloud Kingdom I think I might be able to arrange something.”',jsonb_build_array('Removed illustration/page OCR debris between paragraph context.','Normalized OCR “*’1 know” and apostrophe.')),
    (10,'The Wish Fairy was only too glad to do so, and off they started. With Dewy Dear guiding them on their way, it did not take them long to make the trip, and before many hours they stood before the stern gray King of the Cloud Kingdom.','[]'::jsonb),
    (11,'“Is Dewy Dear not doing her work well?” he asked at once.','[]'::jsonb),
    (12,'“Oh, perfectly,” Miss Wish Fairy hastened to say. “She is, in fact, the best worker we have. She and Twinkletoes. We all love them both. But there is another reason why we came back. You tell, Dewy Dear.”',jsonb_build_array('Normalized sentence punctuation in “You tell, Dewy Dear.”')),
    (13,'So Dewy Dear told and then nodded significantly toward a door in the wall behind the King.',jsonb_build_array('Rejoined paragraph across printed page break.')),
    (14,'“Perhaps so,” he said. “I do not like to let them loose, but—it may be best.”',jsonb_build_array('Normalized malformed OCR punctuation.')),
    (15,'He clapped his hands and, at the sound, the door behind him flew open and out dashed two fairies. Miss Wish Fairy gasped. They looked queer and frightening.','[]'::jsonb),
    (16,'One was dressed all in black and her bare white arms and white face and white hair were startling in contrast. She kept something hidden in a fold of her dress, as she stood obediently before the king.','[]'::jsonb),
    (17,'The other was dressed all in black too, but his face and hands and hair were as black as night and his hands were huge. Miss Wish Fairy looked at his hands hanging at his sides and she shuddered.',jsonb_build_array('Normalized line-end hyphenation.')),
    (18,'“Go with Dewy Dear,” the Cloud King commanded, “and hide in a cave that she will show you, and come out only when she calls.”',jsonb_build_array('Rejoined paragraph across printed page break and normalized quote marks.')),
    (19,'They nodded without a word and went with Miss Wish Fairy and Dewy Dear on the eagle’s back down to the Sunshine and Shadow Forest where all the beasts and birds stood waiting with many fresh grievances to relate. While they talked Dewy Dear and the two new fairies slipped out of sight.','[]'::jsonb),
    (20,'Miss Wish Fairy listened patiently to the story of how Miss Pussy Foot had climbed to the tip-top branch of a tree and along came the wind twins and blew the tree down, almost breaking Miss Pussy Foot’s neck and legs; and she heard soberly how they had twisted vines about the giraffe’s long neck until he had almost choked to death; and how they had tangled the underbrush so that ten wee chickabiddies could not get out and their mother had clucked herself into a fever in fright.',jsonb_build_array('Rejoined paragraph across printed page break and normalized line-end hyphenation.')),
    (21,'Finally she summoned the wind twins. She could not keep them out of mischief, but she could send them about their business in the Sunshine and Shadow Forest and they were commanded to blow up a big storm.','[]'::jsonb),
    (22,'Soon great white clouds were piled up in the sky over the Sunshine and Shadow Forest, darkening it and shutting out the sun. As the twins came roaring and whistling to earth again Dewy Dear stood out in the open and waved her wand. Immediately the clouds opened and the rain came down in sheets and the wind twins danced with glee.',jsonb_build_array('Normalized line-end hyphenation.')),
    (23,'Silently then Dewy Dear ran off to the cave, where she had hidden Black Face and White Face, and summoned them to her side, and in haste they ran back to the place where the twins were whistling and twirling.',jsonb_build_array('Rejoined paragraph across printed page break and normalized line-end hyphenation.')),
    (24,'At a signal from Dewy Dear, White Face suddenly darted forward and flashed out the thing hidden in her skirt. It crackled and snapped like a jagged streak of lightning, and then was hidden again in the fold of her black dress. But not before Roarabout and Wisselit had been half blinded by its light and had fallen stunned to the ground.',jsonb_build_array('Normalized line-end hyphenation.')),
    (25,'There they lay, trembling and afraid to move, when suddenly Black Face ran forward and clapped his huge hands together three or four times. The noise was deafening as thunder, and the wind twins cowered shaking on the wet earth with their ears covered.',jsonb_build_array('Rejoined paragraph across printed page break and illustration/page OCR debris.')),
    (26,'At last Twinkletoes ran out and dismissed Black Face and White Face, and the wind twins rose from the ground scared and mild and subdued. Miss Wish Fairy from her window in the toadstool cottage saw them and came out.',jsonb_build_array('Normalized line-end hyphenation.')),
    (27,'“You see, Roarabout and Wisselit,” she said, “we must have law and order in the Sunshine and Shadow Forest and so long as you could not keep it yourselves we have secured fairy policemen who will see that you do keep it the whole year round.”',jsonb_build_array('Normalized split name and malformed closing quote.')),
    (28,'The wind twins nodded quietly.','[]'::jsonb),
    (29,'“Yes, Ma’am,” they said. “We think p’raps we will remember to be good so long as Black Face and White Face and Bumps and Star and Silver Nose are here.”',jsonb_build_array('Normalized apostrophes and malformed closing quote.')),
    (30,'And it was true. The seasons rolled round and the fairies in the Sunshine and Shadow Forest did their tasks, and there was never any more trouble after that. So the beasts and birds thrived and little Miss Wish Fairy was happy.',jsonb_build_array('Rejoined paragraph across printed page break.')),
    (31,'I think she deserved to be, don’t you?','[]'::jsonb)
  ) as v(ordinal,text_content,repairs)
  loop
    perform public.wnph_record_publication_expression_block_v2(
      'wish-fairy-dewy-dear:wnph-publication-e1',format('dewy:publication-expression:chapter6:paragraph:%s:v1',lpad(r.ordinal::text,3,'0')),format('wnph:dewy:chapter:6:paragraph:%s',lpad(r.ordinal::text,3,'0')),
      'wnph:dewy:chapter:6',r.ordinal,'paragraph','body_paragraph',r.text_content,'admitted','editorial_reconstruction_high_confidence',0.99,
      'wnph_publication_expression_same_surrogate_ocr_collation_v2',array['dewy:chapter:6:paragraph-stream'],
      jsonb_build_array(jsonb_build_object('source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','evidence_role','same_surrogate_derivative','notes','Internet Archive DjVu OCR derivative of the same governed LOC/IA surrogate; zero additional historical-witness count and not source-image verification.')),
      jsonb_build_object('publication_admission',true,'publication_expression_only',true,'raw_ocr_sha256','7e9006f7f96af55c5ef4acb7f8572d6247c4573ce0bbc5cc8da6c2870be648fc','same_surrogate_derivative',true,'historical_witness_count_delta',0,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_forensic_stream_unchanged',true,'printed_page_range',jsonb_build_array(53,63),'page_furniture_removed',true,'line_end_hyphenation_normalized',true,'paragraph_boundary_reconstruction',true,'editorial_repairs',r.repairs),null
    );
  end loop;
  perform public.wnph_refresh_expression_manifestation_derivations_v1('wish-fairy-dewy-dear:wnph-publication-e1');
end;
$block$;