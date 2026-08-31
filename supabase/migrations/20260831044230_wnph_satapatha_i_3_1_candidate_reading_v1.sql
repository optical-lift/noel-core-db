begin;

-- WNPH Satapatha Brahmana / Eggeling 1882 I.3.1 candidate reading v1.
--
-- Stages the eleven prose paragraphs of the already-selected vessel-cleansing unit as
-- CANDIDATE witness readings only.  These rows are intentionally below canonical text
-- admission: no paragraph is source-image verified, footnote markers/editorial layout are
-- not claimed diplomatic, and the governed IA source images remain the final admission gate.
--
-- Candidate wording is collated from the public-domain Eggeling transcription exposed by
-- Internet Sacred Text Archive and checked against text extracted from a separate 1882
-- Volume XII scan surfaced through Wikimedia.  The preceding comparison-locator migration
-- fixes printed pp. 67-71 to scan sequences 121-125 in the Wikisource/Commons witness.

insert into wnph.evidence_sources(
  canonical_key,source_type,title,repository_name,url,external_identifier,
  retrieved_at,rights_note,provenance_note,metadata
) values(
  'wikimedia-commons:ia-1922707-0012-001-umich-pdf',
  'comparison_scan_pdf',
  'The sacred books of the East — Volume XII (1882 scan PDF)',
  'Wikimedia Commons / Internet Archive',
  'https://upload.wikimedia.org/wikipedia/commons/0/03/The_sacred_books_of_the_East_%28IA_1922707.0012.001.umich.edu%29.pdf',
  'IA 1922707.0012.001.umich.edu',now(),
  'The underlying 1882 Eggeling translation and historical publication are public domain in the United States. This evidence row is used only for comparison against a scan-derived text layer and makes no ownership claim over repository presentation.',
  'Independent 1882 Volume XII scan whose extracted text exposes printed-page boundaries and Eggeling wording for I.3.1. It is comparison evidence only; WNPH has not visually adjudicated the target scan pages from this PDF.',
  jsonb_build_object(
    'publication_year',1882,
    'series','Sacred Books of the East',
    'series_volume',12,
    'translator','Julius Eggeling',
    'role','candidate_text_comparison',
    'source_image_verification_complete',false
  )
)
on conflict(canonical_key) do nothing;

do $$
declare
  v_package uuid;
  v_stream uuid;
  r record;
  v_start_page integer;
  v_end_page integer;
  v_start_seq integer;
  v_end_seq integer;
  v_block_key text;
begin
  select p.id into strict v_package
  from wnph.publication_source_packages p
  where p.canonical_key='satapatha-brahmana:eggeling-1882-part1-i-3-1-canonical-source:v1'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);

  select b.id into strict v_stream
  from wnph.publication_source_blocks b
  where b.source_package_id=v_package
    and b.block_key='satapatha-eggeling1882:i-3-1:reading-stream'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  for r in
    select * from (values
      (1,67,68,$p1$He (the Âgnîdhra) now brushes the spoons (with the grass-ends). The reason why he brushes the spoons is that the course pursued among the gods is in accordance with that pursued among men. Now, when the serving up of food is at hand among men,--$p1$),
      (2,68,68,$p2$They rinse the vessels, and having rinsed them, they serve up the food with them: in the same way is treated the sacrifice to the gods, that is to say, the cooked oblations and the prepared altar; and those vessels of theirs, the sacrificial spoons.$p2$),
      (3,68,68,$p3$Now, when he brushes (the spoons), he in reality rinses them, thinking, 'with these rinsed ones I will proceed.' He thereby rinses them with two substances for the gods, and with one for men; viz. with water and the brahman (spirit of worship) for the gods,--for the water is (represented by) the sacrificial grass, and the brahman (by) the sacrificial formula;--and with one for men, that is with water alone: and thus this takes place separately.$p3$),
      (4,68,69,$p4$He, in the first place, takes the dipping-spoon (sruva, masc.) and makes it hot (on the Gârhapatya fire), with either of the texts (Vâg. S. I, 29), 'Scorched is the Rakshas, scorched are the enemies!' or, 'Burnt out is the Rakshas, burnt out are the enemies!'$p4$),
      (5,69,69,$p5$For when the gods were performing sacrifice they were afraid of a disturbance on the part of the Asuras and Rakshas. Hence by this means he, from the very opening of the sacrifice, expels from here the evil spirits, the Rakshas.$p5$),
      (6,69,69,$p6$He brushes it thus inside with the (grass-)tops (cut off from the grass in tying the veda), with the text (Vâg. S. I, 29), 'Not sharp art thou, (but yet) a destroyer of the enemies!' he says this in order that it may unceasingly destroy the enemies of the sacrificer. Further, 'Thee, the food-abounding (masc.), I cleanse for the kindling of food!'--'thee that art suitable for the sacrifice, I cleanse for the sacrifice,' he thereby says. In the same way he brushes all the spoons, saying, 'Thee, the food-abounding (fem.) . . .,' in the case of the offering-spoon (sruk, fem.). The prâsitraharana (he brushes) silently.$p6$),
      (7,70,70,$p7$Inside he brushes with the (grass-)tops thus (viz. from the handle to the top, or in a forward, eastward direction from himself); outside with the lower (grass-)ends thus (viz. in the opposite or backward direction, towards himself): for thus (viz. in the former way) goes the out-breathing, and thus (in the opposite way) the in-breathing. Thereby he obtains out-breathing and in-breathing (for the sacrificer): hence these hairs (on the upper side of the elbow) point that way, and these (on the lower side) point that way.$p7$),
      (8,70,70,$p8$Each time he has brushed and heated (a spoon), he hands it (to the Adhvaryu). Just as, after having rinsed (the eating vessels) while touching them, one would finally rinse them without touching them, so here: for this reason he hands over each (spoon) after heating it.$p8$),
      (9,71,71,$p9$The dipping-spoon (sruva, masc.) he brushes first, and then the other spoons (sruk, fem.). The offering-spoon (sruk), namely, is female, and the dipping-spoon is male, so that, although in this way several women meet together, the one that is, as it were, the only male youth among them, goes there first, and the others after him. This is the reason why he brushes the dipping-spoon first, and afterwards the other (offering-)spoons.$p9$),
      (10,71,71,$p10$Let him brush them so as not to spatter anything towards the fire, as he would thereby bespatter him, to whom he will be bringing food, with the slops of the vessels: therefore let him brush them so as not to spatter anything towards the fire, that is to say, after stepping outside (the Âhavanîya fire-house) towards the east.$p10$),
      (11,71,71,$p11$Here now some throw the grass-ends used for cleaning the spoons into the (Âhavanîya) fire. 'To the veda (grass-bunch) they assuredly belonged, and the spoons have been cleaned with them: hence it is something that belongs to the sacrifice, and (we throw it into the fire) in order that it should not become excluded from the sacrifice,' thus (they argue). Let him, however, not do so, since he would thereby make him to whom he will offer food, drink the slops of the vessels. Let him therefore throw them away (on the heap of rubbish).$p11$)
    ) as x(paragraph_no,printed_page_start,printed_page_end,candidate_text)
  loop
    v_start_page := r.printed_page_start;
    v_end_page := r.printed_page_end;
    v_start_seq := v_start_page + 54;
    v_end_seq := v_end_page + 54;
    v_block_key := 'satapatha-eggeling1882:i-3-1:p' || lpad(r.paragraph_no::text,2,'0');

    if not exists(
      select 1 from wnph.publication_source_blocks b
      where b.source_package_id=v_package and b.block_key=v_block_key
    ) then
      insert into wnph.publication_source_blocks(
        source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
        text_content,reading_state,properties,source_provenance
      ) values(
        v_package,v_block_key,v_stream,r.paragraph_no,'paragraph','witness_paragraph',
        r.candidate_text,'candidate',
        jsonb_build_object(
          'canonical_section_locator','I.3.1.' || r.paragraph_no::text,
          'printed_page_start',v_start_page,
          'printed_page_end',v_end_page,
          'comparison_scan_sequence_start',v_start_seq,
          'comparison_scan_sequence_end',v_end_seq,
          'candidate_only',true,
          'diplomatic_transcription',false,
          'footnote_markers_and_layout_admitted',false,
          'source_image_verification_required',true
        ),
        jsonb_build_object(
          'text_authority','comparison_transcription_candidate_only',
          'derivation_method','collated public-domain Eggeling transcription against printed-page cues and an independent scan-derived text extraction; no source-image verification',
          'verification_status','not_verified',
          'canonical_text_admission',false,
          'source_locators',jsonb_build_array(
            jsonb_build_object(
              'evidence_source_key','sacred-texts:sbe12:1-3-1',
              'section_locator','1:3:1:' || r.paragraph_no::text,
              'printed_page_start',v_start_page,
              'printed_page_end',v_end_page,
              'role','candidate_transcription'
            ),
            jsonb_build_object(
              'evidence_source_key','wikimedia-commons:ia-1922707-0012-001-umich-pdf',
              'printed_page_start',v_start_page,
              'printed_page_end',v_end_page,
              'role','scan_derived_text_comparison',
              'visual_verification_complete',false
            ),
            jsonb_build_object(
              'surrogate_key','satapatha-brahmana:ia-1882-part1-surrogate',
              'printed_page_start',v_start_page,
              'printed_page_end',v_end_page,
              'role','preferred_source_pending_exact_leaf_mapping',
              'source_image_verification_complete',false
            ),
            jsonb_build_object(
              'surrogate_key','satapatha-brahmana:commons-sbe12-volume12-djvu-surrogate',
              'scan_sequence_start',v_start_seq,
              'scan_sequence_end',v_end_seq,
              'printed_page_start',v_start_page,
              'printed_page_end',v_end_page,
              'role','comparison_surface_locator_pending_visual_verification',
              'source_image_verification_complete',false
            )
          )
        )
      );
    end if;
  end loop;

  if (
    select count(*)
    from wnph.publication_source_blocks b
    where b.source_package_id=v_package
      and b.parent_block_id=v_stream
      and b.semantic_role='witness_paragraph'
      and b.reading_state='candidate'
      and b.block_key like 'satapatha-eggeling1882:i-3-1:p%'
      and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  ) <> 11 then
    raise exception 'Expected exactly eleven active Satapatha I.3.1 candidate paragraph blocks';
  end if;

  if exists(
    select 1
    from wnph.publication_source_blocks b
    where b.source_package_id=v_package
      and b.block_key like 'satapatha-eggeling1882:i-3-1:p%'
      and b.reading_state in ('verified','adjudicated')
      and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  ) then
    raise exception 'Satapatha candidate migration must not create verified/adjudicated paragraph text';
  end if;
end $$;

commit;
