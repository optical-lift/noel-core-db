-- WNPH canonical text admission membrane + Dewy Chapter I verified transcription pass 1
--
-- Canonical prose may not enter a Publication Source Package merely by assertion.
-- A text-bearing block must carry page-image verification provenance immediately and,
-- by transaction end, must be a governed output of a canonical-text-admission
-- Transmission Act with a source surrogate and supporting evidence.
--
-- Dewy pass 1 admits only the fourteen complete paragraphs directly verified against
-- page images through printed page 10. Chapter I remains explicitly incomplete.

create or replace function wnph.validate_publication_source_block_insert_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_parent_package uuid;
  v_superseded_package uuid;
  v_superseded_key text;
begin
  if new.parent_block_id is not null then
    select b.source_package_id into v_parent_package
    from wnph.publication_source_blocks b
    where b.id=new.parent_block_id;

    if v_parent_package is null or v_parent_package <> new.source_package_id then
      raise exception 'WNPH publication source block: parent block must belong to the same source package';
    end if;
  end if;

  if new.supersedes_block_id is not null then
    select b.source_package_id,b.block_key
      into v_superseded_package,v_superseded_key
    from wnph.publication_source_blocks b
    where b.id=new.supersedes_block_id;

    if v_superseded_package is null or v_superseded_package <> new.source_package_id then
      raise exception 'WNPH publication source block: superseded block must belong to the same source package';
    end if;
    if new.block_key <> v_superseded_key then
      raise exception 'WNPH publication source block: supersession must retain the logical block_key';
    end if;
    if exists(
      select 1 from wnph.publication_source_blocks b
      where b.supersedes_block_id=new.supersedes_block_id
    ) then
      raise exception 'WNPH publication source block: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1 from wnph.publication_source_blocks b
    where b.source_package_id=new.source_package_id
      and b.block_key=new.block_key
  ) then
    raise exception 'WNPH publication source block: duplicate unsuperseded block_key %',new.block_key;
  end if;

  if new.text_content is not null then
    if btrim(new.text_content)='' then
      raise exception 'WNPH canonical text admission: text_content may not be blank';
    end if;
    if coalesce(new.source_provenance->>'verification_status','') <> 'source_image_verified' then
      raise exception 'WNPH canonical text admission: text-bearing block requires verification_status=source_image_verified';
    end if;
    if jsonb_typeof(new.source_provenance->'source_locators') <> 'array'
       or jsonb_array_length(new.source_provenance->'source_locators')=0 then
      raise exception 'WNPH canonical text admission: text-bearing block requires at least one source locator';
    end if;
    if coalesce(new.source_provenance->>'text_authority','')='' then
      raise exception 'WNPH canonical text admission: text-bearing block requires explicit text_authority';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_block_insert_v1() from public,anon,authenticated,service_role;

create trigger publication_source_blocks_insert_validation_v1
before insert on wnph.publication_source_blocks
for each row execute function wnph.validate_publication_source_block_insert_v1();

create unique index publication_source_blocks_one_successor_uq
  on wnph.publication_source_blocks(supersedes_block_id)
  where supersedes_block_id is not null;

create or replace function wnph.validate_canonical_text_admission_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_case uuid;
begin
  if new.text_content is null then
    return null;
  end if;

  select p.recovery_case_id into v_case
  from wnph.publication_source_packages p
  where p.id=new.source_package_id;

  if v_case is null then
    raise exception 'WNPH canonical text admission: source package recovery case not found';
  end if;

  if not exists(
    select 1
    from wnph.transmission_act_objects out_obj
    join wnph.transmission_acts act on act.id=out_obj.transmission_act_id
    where out_obj.publication_source_block_id=new.id
      and out_obj.direction='output'
      and act.recovery_case_id=v_case
      and coalesce((act.metadata->>'canonical_text_admission')::boolean,false)=true
      and exists(
        select 1
        from wnph.transmission_act_objects in_obj
        where in_obj.transmission_act_id=act.id
          and in_obj.direction='input'
          and in_obj.surrogate_id is not null
      )
      and exists(
        select 1
        from wnph.transmission_act_evidence ev
        where ev.transmission_act_id=act.id
          and ev.support_role='supports'
      )
  ) then
    raise exception 'WNPH canonical text admission: text block % lacks a governed canonical-text-admission Transmission Act with source surrogate and supporting evidence',new.block_key;
  end if;

  return null;
end;
$function$;

revoke all on function wnph.validate_canonical_text_admission_v1() from public,anon,authenticated,service_role;

create constraint trigger publication_source_blocks_canonical_text_admission_v1
after insert on wnph.publication_source_blocks
deferrable initially deferred
for each row
when (new.text_content is not null)
execute function wnph.validate_canonical_text_admission_v1();

comment on function wnph.validate_canonical_text_admission_v1() is
  'Deferred admission membrane for canonical WNPH reading text. By transaction end every text-bearing source block must be the governed output of a canonical-text-admission Transmission Act with a source surrogate and supporting evidence.';

do $$
declare
  v_case uuid;
  v_work uuid;
  v_package uuid;
  v_stream uuid;
  v_surrogate uuid;
  v_loc_source uuid;
  v_ocr_source uuid;
  v_page_source uuid;
  v_agent uuid;
  v_act uuid;
  v_block uuid;
  v_count integer;
begin
  select c.id,c.work_id into v_case,v_work
  from wnph.recovery_cases c
  where c.canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';

  select p.id into v_package
  from wnph.publication_source_packages p
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);

  select b.id into v_stream
  from wnph.publication_source_blocks b
  where b.source_package_id=v_package
    and b.block_key='dewy:chapter:1:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  select s.id into v_surrogate from wnph.surrogates s where s.canonical_key='wish-fairy-dewy-dear:loc-digital';
  select es.id into v_loc_source from wnph.evidence_sources es where es.canonical_key='loc:item:22008427';
  select es.id into v_ocr_source from wnph.evidence_sources es where es.canonical_key='internet-archive:ia:wishfairydewydea00colv:djvu-text';
  select es.id into v_page_source from wnph.evidence_sources es where es.canonical_key='wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders';
  select a.id into v_agent from wnph.transmission_agents a
  where a.canonical_key='wnph:recovery-process'
    and not exists(select 1 from wnph.transmission_agents n where n.supersedes_agent_id=a.id);

  if v_case is null or v_work is null or v_package is null or v_stream is null or v_surrogate is null
     or v_loc_source is null or v_ocr_source is null or v_page_source is null or v_agent is null then
    raise exception 'WNPH Dewy Chapter I pass 1: governed inputs incomplete';
  end if;

  if exists(
    select 1 from wnph.publication_source_blocks b
    where b.parent_block_id=v_stream and b.text_content is not null
      and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  ) then
    raise exception 'WNPH Dewy Chapter I pass 1: paragraph stream must be empty before first admission';
  end if;

  insert into wnph.transmission_acts(
    canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values(
    'wish-fairy-dewy-dear:transmission:chapter-1-source-image-verification-pass-1:v1',v_case,v_work,'verified_transcription',
    'Admit the first source-image-verified reading text into Dewy Chapter I.',
    'Internet Archive OCR is used only as a candidate transcription. Canonical readings and paragraph boundaries in this pass are admitted from direct inspection of page images of the governed LOC/IA witness accessed through Wikimedia Commons page renders. Historical line-end hyphenation is resolved as line wrapping rather than textual intervention. This pass stops after printed page 10 because page-image access for printed pages 11–16 was not available through the active access route.',
    'system_recorded','certain',
    jsonb_build_object(
      'canonical_text_admission',true,
      'source_image_verified',true,
      'chapter_number',1,
      'chapter_completion',false,
      'canonical_paragraphs_admitted',14,
      'printed_page_scope',jsonb_build_array(7,8,9,10),
      'pending_printed_pages',jsonb_build_array(11,12,13,14,15,16),
      'ocr_is_authority',false,
      'page_image_is_authority',true
    )
  ) returning id into v_act;

  insert into wnph.transmission_act_agents(transmission_act_id,agent_id,agent_role)
  values(v_act,v_agent,'source_image_transcription_and_verification');

  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id,locator)
  values(v_act,'input','preferred_historical_source',v_surrogate,jsonb_build_object('printed_pages',jsonb_build_array(7,8,9,10),'source_pdf_pages',jsonb_build_array(11,12,13,14)));
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id)
  values(v_act,'input','ocr_candidate_transcription',v_ocr_source);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id)
  values(v_act,'input','page_image_access_render',v_page_source);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id)
  values(v_act,'context','canonical_publication_source',v_package);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id)
  values(v_act,'context','chapter_1_paragraph_stream',v_stream);

  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_act,v_page_source,'supports','certain','Direct page-image inspection is the reading and paragraph-boundary authority for every paragraph admitted in this pass.');
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_act,v_loc_source,'context','high','Library of Congress item record anchors the governed historical exemplar/surrogate identity.');
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_act,v_ocr_source,'context','high','IA OCR supplies candidate text for comparison only and is not canonical authority.');

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:001',v_stream,1,'paragraph','body_paragraph',
    'The Wish Fairy stood on the tip-top branch of a small Christmas tree and looked about her. Below her and above her were grouped all the beasts and birds of the great Sunshine and Shadow Forest, and on the face of each was seen worry and distress.',
    jsonb_build_object('chapter_number',1,'paragraph_number',1,'canonical_status','admitted'),
    jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',7,'source_pdf_page',11))))
  returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',1));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:002',v_stream,2,'paragraph','body_paragraph',
    '“Well, what is it?” the Wish Fairy asked.',
    jsonb_build_object('chapter_number',1,'paragraph_number',2,'canonical_status','admitted'),
    jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',7,'source_pdf_page',11))))
  returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',2));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:003',v_stream,3,'paragraph','body_paragraph',
    '“It’s the dryness,” King Lion said. “We’re nearly dead of thirst. I can’t speak above a whisper. The pools are dried up, and if we don’t have rain soon the forest will be afire and there’ll be no way to put it out.”',
    jsonb_build_object('chapter_number',1,'paragraph_number',3,'canonical_status','admitted'),
    jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',7,'source_pdf_page',11),jsonb_build_object('printed_page',8,'source_pdf_page',12))))
  returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',3));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:004',v_stream,4,'paragraph','body_paragraph','The Wish Fairy looked worried.',jsonb_build_object('chapter_number',1,'paragraph_number',4,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',4));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:005',v_stream,5,'paragraph','body_paragraph','“Can’t you wish for the rain to come?” Mr. Elephant asked.',jsonb_build_object('chapter_number',1,'paragraph_number',5,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',5));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:006',v_stream,6,'paragraph','body_paragraph','The Wish Fairy shook her head.',jsonb_build_object('chapter_number',1,'paragraph_number',6,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',6));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:007',v_stream,7,'paragraph','body_paragraph','“I have no power over the elements,” she said. “I cannot make it rain or stop raining.”',jsonb_build_object('chapter_number',1,'paragraph_number',7,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',7));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:008',v_stream,8,'paragraph','body_paragraph','“Who can?” asked the duck. “My feet are sore from walking on dry land.”',jsonb_build_object('chapter_number',1,'paragraph_number',8,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',8));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:009',v_stream,9,'paragraph','body_paragraph','“I can visit the Cloud Kingdom,” the Wish Fairy said doubtfully, “and ask—”',jsonb_build_object('chapter_number',1,'paragraph_number',9,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',9));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:010',v_stream,10,'paragraph','body_paragraph','“Oh! Then hurry! Hurry!” they all cried together.',jsonb_build_object('chapter_number',1,'paragraph_number',10,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',10));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:011',v_stream,11,'paragraph','body_paragraph','So the Wish Fairy summoned the eagle to her. He was allowed to take the last drink from the last pool of water before he started on his long journey to the Cloud Kingdom with the Wish Fairy tucked deep in the hollow of his back. Then, amidst shouts and wavings of tails and wings, up they flew; up above the tree tops; up above the forest; up—up—up—till little Miss Wish Fairy shut her eyes to keep out the glare of the sun and the sky.',jsonb_build_object('chapter_number',1,'paragraph_number',11,'canonical_status','admitted','historical_page_interruption','color_plate_printed_page_9'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',8,'source_pdf_page',12),jsonb_build_object('printed_page',10,'source_pdf_page',14)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',11,'historical_page_interruption','plate_page_9'));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:012',v_stream,12,'paragraph','body_paragraph','All day long they travelled up—up—up—with great strong sweeps of the eagle’s wings. By late afternoon the eagle was breathless and weary.',jsonb_build_object('chapter_number',1,'paragraph_number',12,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',10,'source_pdf_page',14)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',12));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:013',v_stream,13,'paragraph','body_paragraph','“I see no clouds!” he quavered. “What shall I do?”',jsonb_build_object('chapter_number',1,'paragraph_number',13,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',10,'source_pdf_page',14)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',13));

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,properties,source_provenance)
  values(v_package,'dewy:chapter:1:paragraph:014',v_stream,14,'paragraph','body_paragraph','“Fly toward the sunset,” the Wish Fairy said. “You’ll find some there.”',jsonb_build_object('chapter_number',1,'paragraph_number',14,'canonical_status','admitted'),jsonb_build_object('verification_status','source_image_verified','text_authority','governed_same_witness_page_image','preferred_surrogate_key','wish-fairy-dewy-dear:loc-digital','page_image_access_key','wikimedia-commons:ia:wishfairydewydea00colv:file-page-renders','ocr_candidate_source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','source_locators',jsonb_build_array(jsonb_build_object('printed_page',10,'source_pdf_page',14)))) returning id into v_block;
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator) values(v_act,'output','canonical_paragraph',v_block,jsonb_build_object('chapter',1,'paragraph',14));

  insert into wnph.transmission_interventions(
    transmission_act_id,intervention_key,intervention_type,subject_locator,before_value,after_value,rationale,certainty,decision_status,reader_facing_effect,metadata
  ) values(
    v_act,'chapter-1:paragraph-13:ocr-t-to-i','ocr_correction',
    jsonb_build_object('chapter',1,'paragraph',13,'printed_page',10,'source_pdf_page',14),
    'T see no clouds!','I see no clouds!',
    'Direct visual inspection of the source page image shows a capital I. The machine OCR misread the initial I as T.',
    'certain','accepted',true,
    jsonb_build_object('changes_historical_text',false,'correction_target','machine_ocr_only')
  );

  select count(*) into v_count
  from wnph.publication_source_blocks b
  where b.parent_block_id=v_stream and b.text_content is not null
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);
  if v_count <> 14 then raise exception 'WNPH Dewy Chapter I pass 1: expected 14 admitted paragraphs, found %',v_count; end if;

  if (select count(*) from wnph.transmission_act_objects o where o.transmission_act_id=v_act and o.direction='output' and o.publication_source_block_id is not null) <> 14 then
    raise exception 'WNPH Dewy Chapter I pass 1: expected 14 governed paragraph outputs';
  end if;

  if (select count(*) from wnph.transmission_interventions i where i.transmission_act_id=v_act) <> 1 then
    raise exception 'WNPH Dewy Chapter I pass 1: expected exactly one evidenced OCR intervention';
  end if;

  if exists(
    select 1 from wnph.publication_source_blocks b
    join wnph.publication_source_blocks p on p.id=b.parent_block_id
    where p.block_key like 'dewy:chapter:%:paragraph-stream'
      and p.block_key <> 'dewy:chapter:1:paragraph-stream'
      and b.text_content is not null
  ) then
    raise exception 'WNPH Dewy Chapter I pass 1: later chapters must remain unpopulated';
  end if;
end $$;