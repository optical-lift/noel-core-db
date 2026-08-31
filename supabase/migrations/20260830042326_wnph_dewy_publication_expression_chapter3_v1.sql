do $block$
declare
  r record;
begin
  perform public.wnph_record_publication_expression_block_v2(
    'wish-fairy-dewy-dear:wnph-publication-e1',
    'dewy:publication-expression:chapter3:v1',
    'wnph:dewy:chapter:3',
    null,
    3,
    'chapter',
    'chapter',
    'CHAPTER III',
    'admitted',
    'structural_adjudication',
    0.99,
    'wnph_publication_expression_structural_adjudication_v2',
    array['dewy:chapter:3'],
    '[]'::jsonb,
    jsonb_build_object(
      'publication_admission',true,
      'observed_title','Twinkletoes',
      'printed_page_start',27,
      'printed_page_end',34,
      'publication_expression_only',true,
      'source_image_verification',false,
      'canonical_admission',false,
      'source_skeleton_unchanged',true
    ),
    null
  );

  for r in
    select * from (values
      (1, 'It rained all that night, and all the next day, and all the next night, and all the next day, and, by and by, the beasts and birds gathered about the Wish Fairy’s cottage in terror.', jsonb_build_array('Recovered dropped decorative initial: OCR “TT rained” → publication reading “It rained”.')),
      (2, '“Thank you very much, Miss Wish Fairy,” King Lion said. “We’ve had enough. Please turn it off.”', jsonb_build_array('Normalized vocative punctuation: OCR period after “much” → comma.')),
      (3, 'Miss Wish Fairy stood in her doorway and shook her head.', '[]'::jsonb),
      (4, '“I can’t. Dewy Dear!” she called.', '[]'::jsonb),
      (5, 'Dewy Dear came running through the mist and the rain, but when she heard of the trouble she too shook her head.', '[]'::jsonb),
      (6, '“I can’t,” she said. “I can only call the rain down. I can’t send it up. Call the wind twins and tell them to stop blowing clouds.”', jsonb_build_array('Rejoined paragraph split by printed page break between OCR chunks.')),
      (7, 'Poor Miss Wish Fairy sighed.', '[]'::jsonb),
      (8, '“It’s a great responsibility to be a ruler,” she thought. “I’ve got myself in a peck o’ trouble!” But she called bravely, “Roarabout and Wisselit!”', '[]'::jsonb),
      (9, 'And down through the tree tops came tumbling and giggling the twins.', '[]'::jsonb),
      (10, '“But we’ve blown enough clouds to last a month!” they shouted when they heard of the trouble. “We thought we’d do a good job.”', '[]'::jsonb),
      (11, 'Miss Wish Fairy was in dismay. If it rained a month everything and everybody would be drowned. Whatever should she do? As she was wondering, Dewy Dear slipped up to her and said with grave face:', jsonb_build_array('Normalized obvious sentence-break OCR punctuation: “wondering. Dewy” → “wondering, Dewy”.')),
      (12, '“I shall tell you a secret. I have to or I wouldn’t. The only thing that is strong enough to stop the rain is the sun. You will have to visit the great Sun King and ask him to shine through the bank of clouds that those foolish boys have blown up.”', jsonb_build_array('Rejoined paragraph split by printed page break.','Normalized malformed closing quote from OCR.')),
      (13, '“Of course!” the Wish Fairy sighed. “I’m tired, and my travelling dress is wrinkled and it will get soaked, but I shall have to go just the same.”', jsonb_build_array('Corrected OCR “Fm tired” → “I’m tired”.')),
      (14, 'So she summoned the eagle again, and once on his back she wrapped a big leaf about her to keep the rain off and held a toadstool for an umbrella over her head, and up — up — up they went.', '[]'::jsonb),
      (15, 'Finally their heads touched the clouds and into the dampness the eagle went, beating his way through the thick air with his great strong wings. Up — up — up until the rain became mist and the mist became fog and the fog disappeared. And lo! They were above the clouds and in the Realm of Sunshine.', jsonb_build_array('Corrected OCR “-the fog dis appeared” → “the fog disappeared”.')),
      (16, 'Miss Wish Fairy threw off her raincoat, and on foot made her way to the dazzling gold throne where sat the Sun King. On his head sparkled a crown that flashed brilliant gold light. In his hand he held a sceptre from the tip of which sunbeams danced in golden streams about the floor. And on the steps of his throne were grouped beautiful little sun fairies, all clad in yellow and all smiling, and all with golden hair and eyes as blue as the skies on a sunny day.', '[]'::jsonb),
      (17, 'Miss Wish Fairy thought she had never seen anything so beautiful. She made her way to the throne and dropped on one knee, and, at the Sun King''s gentle request, she told the story of her troubles.', '[]'::jsonb),
      (18, '“Hum!” said the wise old Sun King when she had finished. “King Wind was foolish to send two such youngsters as Roarabout and Wisselit. I know them. They are always up to tricks. Yes, I think I shall have to spare you little Twinkletoes. She can keep those wind twins in order, and she is active enough to dance her way through any clouds, I don’t care how thick they are.”', jsonb_build_array('Normalized malformed OCR punctuation in opening “Hum!” quotation.')),
      (19, 'So Twinkletoes was summoned, and as she came forward Miss Wish Fairy was nearly blinded. She danced along waving her wand like a flashing sunbeam, and her smile was so bright and her breath so warm and her gown and hair so golden, that Miss Wish Fairy was sure the clouds would vanish before her.', '[]'::jsonb),
      (20, 'And sure enough they did. For when they had mounted on the back of the eagle that was to take them back to the Sunshine and Shadow Forest, and had neared the mist and the fog and the rain, Twinkletoes hopped off and began to dance about on the clouds. And as she danced her twinkling toes made a rift, and through it a sunbeam shot from the tip of her wand; and the rift grew wider and wider until it was wide enough for the eagle to pass through. Then Twinkletoes hopped on his back again, and, while on their way down to the Sunshine and Shadow Forest, she kept her wand pointed straight at the clouds, and from it blazed such a glory of warm sunshine that, by the time they reached the ground, the clouds had all vanished, and the rain had stopped entirely, and all the beasts and birds of the Sunshine and Shadow Forest greeted her with joyous shouts.', jsonb_build_array('Rejoined paragraph across printed page break.','Removed running page furniture “3 — Wish Fairy and Dewy Dear”.'))
    ) as v(ordinal,text_content,repairs)
  loop
    perform public.wnph_record_publication_expression_block_v2(
      'wish-fairy-dewy-dear:wnph-publication-e1',
      format('dewy:publication-expression:chapter3:paragraph:%s:v1',lpad(r.ordinal::text,3,'0')),
      format('wnph:dewy:chapter:3:paragraph:%s',lpad(r.ordinal::text,3,'0')),
      'wnph:dewy:chapter:3',
      r.ordinal,
      'paragraph',
      'body_paragraph',
      r.text_content,
      'admitted',
      'editorial_reconstruction_high_confidence',
      0.99,
      'wnph_publication_expression_same_surrogate_ocr_collation_v2',
      array['dewy:chapter:3:paragraph-stream'],
      jsonb_build_array(jsonb_build_object(
        'source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text',
        'evidence_role','same_surrogate_derivative',
        'notes','Internet Archive DjVu OCR derivative of the same governed LOC/IA surrogate. Used as a machine-readable publication collation layer; contributes zero additional historical-witness count and is not source-image verification.'
      )),
      jsonb_build_object(
        'publication_admission',true,
        'publication_expression_only',true,
        'raw_ocr_sha256','7e9006f7f96af55c5ef4acb7f8572d6247c4573ce0bbc5cc8da6c2870be648fc',
        'same_surrogate_derivative',true,
        'historical_witness_count_delta',0,
        'source_image_verification',false,
        'canonical_admission',false,
        'source_forensic_stream_unchanged',true,
        'printed_page_range',jsonb_build_array(27,34),
        'page_furniture_removed',true,
        'line_end_hyphenation_normalized',true,
        'paragraph_boundary_reconstruction',true,
        'editorial_repairs',r.repairs
      ),
      null
    );
  end loop;
end;
$block$;