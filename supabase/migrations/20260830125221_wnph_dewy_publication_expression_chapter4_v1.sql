do $block$
declare r record;
begin
  perform public.wnph_record_publication_expression_block_v2(
    'wish-fairy-dewy-dear:wnph-publication-e1','dewy:publication-expression:chapter4:v1','wnph:dewy:chapter:4',null,4,
    'chapter','chapter','CHAPTER IV','admitted','structural_adjudication',0.99,
    'wnph_publication_expression_structural_adjudication_v2',array['dewy:chapter:4'],'[]'::jsonb,
    jsonb_build_object('publication_admission',true,'observed_title','Silver Nose and Star','printed_page_start',35,'printed_page_end',44,'publication_expression_only',true,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_skeleton_unchanged',true),null
  );

  for r in select * from (values
    (1,'The Wish Fairy was stretched out in her cobweb hammock resting. Near her, perched on a toadstool, sat the Little Fairy That Knew It All.',jsonb_build_array('Recovered dropped decorative initial from OCR.')),
    (2,'“Well,” sighed the Wish Fairy, “I do hope things are running smoothly at last. First we had no rain, then we had too much. I should think, with Dewy Dear, and Roarabout and Wisselit, and Twinkletoes to regulate the weather, we should all be happy. We have been for a month or so now.”',jsonb_build_array('Normalized OCR quote marks, run-together words, and line-end name hyphenation.')),
    (3,'“Well, we’re not any more!” the Little Fairy That Knew It All remarked. “Those wind twins are mischief makers. Here come some folks to tell you so.”',jsonb_build_array('Normalized OCR quote marks and line-end hyphenation.')),
    (4,'The Wish Fairy sat up and looked. Sure enough, down through a shaded path in the woods marched a solemn procession. First came the peacock with his head indignantly high and his tail feathers all ruffled crooked; then came little Miss Bunnie Rabbit with the remains of her bonnet over her ear; then came Mr. and Mrs. Robin with tears running down their bills; and Mr. Rattlesnake and Mr. and Mrs. Duck and a great many others. They made a big circle about the Wish Fairy’s hammock and sat down. Then Mr. Peacock spoke:',jsonb_build_array('Normalized line-end hyphenation.')),
    (5,'“Miss Wish Fairy, we love Dewy Dear and Twinkletoes, but we do not love Roarabout and Wisselit. They are monkey-mischief makers and they are causing great annoyance and sorrow. For myself they have blown my bee-yootiful tail feathers into a horrible tangle, and Miss Pussy Foot will have to comb them out with her sharp claws. You can see for yourself what a mess I’m in.”',jsonb_build_array('Rejoined paragraph across printed page break.','Preserved dialect spelling “bee-yootiful”.','Corrected OCR “Fm” to “I’m”.')),
    (6,'He turned himself about slowly and sadly and sat down. Miss Bunnie Rabbit rose:','[]'::jsonb),
    (7,'“And my bonnet is blown to bits.” She cocked one ear on which a leaf and a violet and a piece of grass still clung. “And this is the sixth I’ve made. I’m worn out and mad as a March hare.” Her fat sides puffed out in honest anger as she spoke.',jsonb_build_array('Corrected OCR “Fve” to “I’ve” and “Fm” to “I’m”.')),
    (8,'Mr. and Mrs. Robin rose:','[]'::jsonb),
    (9,'“They have done worse to us than to all the others. They blew our home from its tree and all our would-be family was smashed to bits and little pieces.”','[]'::jsonb),
    (10,'Mr. Rattlesnake reared up his head and rattled a warning:','[]'::jsonb),
    (11,'“They’ve blown sand over my hole ninety-seven times!” he said briefly.',jsonb_build_array('Normalized malformed OCR closing punctuation.')),
    (12,'Mr. and Mrs. Duck waddled forward:',jsonb_build_array('Normalized spacing before colon.')),
    (13,'“They blew up such big waves in the still pool that we can’t teach our children to swim, and they act like silly chickens in the water.”','[]'::jsonb),
    (14,'One by one they all made their complaint, and the poor little Wish Fairy’s face grew sadder and sadder. At the end she waved them away.',jsonb_build_array('Normalized line-end hyphenation.')),
    (15,'“I must think,” she said, “what is best to do.”','[]'::jsonb),
    (16,'When they were gone Twinkletoes danced to her and Dewy Dear slipped up quietly.',jsonb_build_array('Normalized line-end hyphenation.')),
    (17,'“We think we know what is best to do,” they said softly. “Go visit Jack Frost and ask him to send a frost fairy here. He could keep those wind twins in order!”','[]'::jsonb),
    (18,'“I believe you’re right,” said the Wish Fairy, and straightway she rose from the hammock and made for the twinkling stream. She followed its singing, winding way swiftly on wing, and at last came to a cool cavern, deep and dark, which sunny Twinkletoes could never penetrate. She wrapped a warm leaf about herself and entered.','[]'::jsonb),
    (19,'At its far end she came to a white room, all lit up with a frosty radiance. In the air was a silver tinkling sound like cracklings and snappings. From the rocky ceiling hung icicles and star-shaped snowflakes, and the floor was a warm carpet of snow cut in half by the winding stream that was frozen into solid ice. In the distance sat Jack Frost on his sparkling throne of snow and ice. He was dressed completely in white as were all the inhabitants of the Winter Kingdom, and his crown was capped with snow, and an icicle flashed from his wand, and the only warm spots in the whole white cave were sprigs of bright red and green holly.',jsonb_build_array('Rejoined paragraph across printed page break and removed page furniture.','Normalized line-end hyphenation.')),
    (20,'“Greetings!” said Miss Wish Fairy, bowing low before Jack Frost. And all the whirling tinkling snow fairies stopped their dancing to listen as she told her tale. At the end of it Jack Frost nodded his head.',jsonb_build_array('Normalized line-end hyphenation.')),
    (21,'“I often have trouble with Roarabout and Wisselit,” he said. “They think they’re the strongest of the weather fairies. I shall send two of my subjects back with you to put them in their proper places.”',jsonb_build_array('Normalized line-end hyphenation.')),
    (22,'So he summoned a Frost Fairy and a Snow Fairy. Silver Nose was the frost fairy and was so named because his nose was an icicle! Star was the snow fairy, and was so named because her dress was made of star-shaped snowflakes, and on her forehead gleamed one perfect one. Miss Wish Fairy thanked Jack Frost, and with her two companions started back for the Sunshine and Shadow Forest.',jsonb_build_array('Rejoined paragraph across printed page break.')),
    (23,'It was dark when they reached it, and at its edge Silver Nose and Star parted from the Wish Fairy.','[]'::jsonb),
    (24,'“I hear Roarabout and Wisselit,” said Silver Nose. “Star and I will each of us go a different way and capture them, and by morning they will be harmless.”',jsonb_build_array('Normalized split name, OCR “difl*erent,” and quote marks.')),
    (25,'So Miss Wish Fairy went home to her toadstool cottage and went to bed.','[]'::jsonb),
    (26,'In the morning when she waked she went to the window and looked out, and what do you think?','[]'::jsonb),
    (27,'The whole Sunshine and Shadow Forest had been touched lightly by Star and Silver Nose in the night, and on the ground was a fine sprinkle of white stars and in the stream was a thin coating of silver ice. But the most amazing thing was the sight of Roarabout and Wisselit huddled close together at her feet on the doorstep, with frost-bitten noses and ears and toes.',jsonb_build_array('Rejoined paragraph across printed page break.','Removed stray OCR comma in “silver ice”.','Normalized line-end hyphenation.')),
    (28,'They lifted their heads as she stood above them.','[]'::jsonb),
    (29,'“Please, Miss Wish Fairy,” they whispered, “let us come in and get warm. We’ll be good for as long as we can — honest.”',jsonb_build_array('Normalized malformed OCR quotation mark.'))
  ) as v(ordinal,text_content,repairs)
  loop
    perform public.wnph_record_publication_expression_block_v2(
      'wish-fairy-dewy-dear:wnph-publication-e1',format('dewy:publication-expression:chapter4:paragraph:%s:v1',lpad(r.ordinal::text,3,'0')),format('wnph:dewy:chapter:4:paragraph:%s',lpad(r.ordinal::text,3,'0')),
      'wnph:dewy:chapter:4',r.ordinal,'paragraph','body_paragraph',r.text_content,'admitted','editorial_reconstruction_high_confidence',0.99,
      'wnph_publication_expression_same_surrogate_ocr_collation_v2',array['dewy:chapter:4:paragraph-stream'],
      jsonb_build_array(jsonb_build_object('source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','evidence_role','same_surrogate_derivative','notes','Internet Archive DjVu OCR derivative of the same governed LOC/IA surrogate; zero additional historical-witness count and not source-image verification.')),
      jsonb_build_object('publication_admission',true,'publication_expression_only',true,'raw_ocr_sha256','7e9006f7f96af55c5ef4acb7f8572d6247c4573ce0bbc5cc8da6c2870be648fc','same_surrogate_derivative',true,'historical_witness_count_delta',0,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_forensic_stream_unchanged',true,'printed_page_range',jsonb_build_array(35,44),'page_furniture_removed',true,'line_end_hyphenation_normalized',true,'paragraph_boundary_reconstruction',true,'editorial_repairs',r.repairs),null
    );
  end loop;

  perform public.wnph_refresh_expression_manifestation_derivations_v1('wish-fairy-dewy-dear:wnph-publication-e1');
end;
$block$;