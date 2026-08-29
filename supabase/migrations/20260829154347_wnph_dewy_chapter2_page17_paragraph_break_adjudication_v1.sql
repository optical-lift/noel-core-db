with start_target as (
  select
    p.id as source_package_id,
    a.id as start_asset_id,
    o.id as start_observation_id,
    a.asset_key as start_asset_key,
    a.source_locator as start_source_locator,
    o.text_candidate as start_text
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id=p.id
  join wnph.publication_source_observations o on o.source_asset_id=a.id
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key='dewy:loc:source-surface:0021'
    and o.observation_kind='line'
    and o.source_format='alto_xml'
    and o.ordinal=20
    and o.text_candidate='heresy,'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id)
    and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
    and not exists(select 1 from wnph.publication_source_observations n where n.supersedes_observation_id=o.id)
),
end_target as (
  select
    p.id as source_package_id,
    a.id as end_asset_id,
    o.id as end_observation_id,
    a.asset_key as end_asset_key,
    a.source_locator as end_source_locator,
    o.text_candidate as end_text
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id=p.id
  join wnph.publication_source_observations o on o.source_asset_id=a.id
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key='dewy:loc:source-surface:0022'
    and o.observation_kind='line'
    and o.source_format='alto_xml'
    and o.ordinal=1
    and o.text_candidate='So the Wish Fairy summoned'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id)
    and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
    and not exists(select 1 from wnph.publication_source_observations n where n.supersedes_observation_id=o.id)
),
target as (
  select s.*,e.end_asset_id,e.end_observation_id,e.end_asset_key,e.end_source_locator,e.end_text
  from start_target s join end_target e using(source_package_id)
)
insert into wnph.publication_source_reading_adjudications(
  source_package_id,adjudication_key,adjudication_kind,
  start_asset_id,start_observation_id,end_asset_id,end_observation_id,
  result,adjudicated_text,adjudication_authority,derivation_method,
  confidence,rationale,evidence
)
select
  source_package_id,
  'dewy:reading-adjudication:chapter2:page17-to-page18:paragraph-break',
  'paragraph_continuity',
  start_asset_id,start_observation_id,end_asset_id,end_observation_id,
  'break_at_boundary',null,
  'source_collation_adjudication',
  'loc_observation_plus_independent_full_text_paragraph_structure_v1',
  0.99,
  'The governed reading correction resolves the final line of printed page 17 as “here.” The independent Internet Archive full-text derivative preserves a blank paragraph boundary after that sentence, followed by the signature mark and folio, and then a new paragraph beginning “So the Wish Fairy summoned” on printed page 18. This decision records the paragraph break separately from the reading-text correction rather than inferring structure from punctuation alone.',
  jsonb_build_object(
    'start_source_asset_key',start_asset_key,
    'start_source_pdf_page',start_source_locator->>'source_pdf_page',
    'start_printed_page',start_source_locator->>'printed_page',
    'preserved_start_ocr_text',start_text,
    'governed_start_reading','here.”',
    'end_source_asset_key',end_asset_key,
    'end_source_pdf_page',end_source_locator->>'source_pdf_page',
    'end_printed_page',end_source_locator->>'printed_page',
    'preserved_end_ocr_text',end_text,
    'independent_source',jsonb_build_object(
      'provider','Internet Archive',
      'item_identifier','wishfairydewydea00colv',
      'derivative','full_text',
      'source_uri','https://archive.org/stream/wishfairydewydea00colv/wishfairydewydea00colv_djvu.txt',
      'observed_structure',jsonb_build_array(
        'King Wind to bring the clouds',
        'here.”',
        'blank paragraph boundary',
        '2—Wish Fairy and Dewy Dear',
        '17',
        'blank paragraph boundary',
        'So the Wish Fairy summoned'
      )
    ),
    'raw_observation_rewritten',false,
    'reading_text_adjudication_key','dewy:reading-adjudication:chapter2:scan0021:line20:here'
  )
from target;

do $verify$
declare
  v_packet jsonb;
  v_count integer;
  v_ch2_proposals integer;
  v_ch2_blocks integer;
  v_ch1_paragraphs integer;
begin
  v_packet:=public.wnph_reconstruction_source_packet_v5(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:2:paragraph-stream',
    null
  );
  v_count:=jsonb_array_length(v_packet->'reading_adjudications');
  if v_count<>3 then
    raise exception 'WNPH Chapter II packet expected 3 active reading adjudication facts after paragraph-break decision; got %',v_count;
  end if;

  if not exists(
    select 1
    from wnph.publication_source_reading_adjudications a
    where a.adjudication_key='dewy:reading-adjudication:chapter2:page17-to-page18:paragraph-break'
      and a.adjudication_kind='paragraph_continuity'
      and a.result='break_at_boundary'
      and not exists(select 1 from wnph.publication_source_reading_adjudications n where n.supersedes_adjudication_id=a.id)
  ) then
    raise exception 'WNPH Chapter II page17-to-page18 paragraph-break adjudication missing';
  end if;

  if not exists(
    select 1 from wnph.publication_source_observations o
    join wnph.publication_source_assets a on a.id=o.source_asset_id
    where a.asset_key='dewy:loc:source-surface:0021'
      and o.observation_kind='line' and o.source_format='alto_xml'
      and o.ordinal=20 and o.text_candidate='heresy,'
      and not exists(select 1 from wnph.publication_source_observations n where n.supersedes_observation_id=o.id)
  ) then
    raise exception 'WNPH paragraph-break adjudication must not rewrite preserved LOC heresy observation';
  end if;

  select count(*) into v_ch2_proposals
  from wnph.publication_source_reconstruction_proposals p
  join wnph.publication_source_blocks parent on parent.id=p.target_parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals n where n.supersedes_proposal_id=p.id);

  select count(*) into v_ch2_blocks
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  select count(*) into v_ch1_paragraphs
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:1:paragraph-stream'
    and b.block_type='paragraph'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  if v_ch2_proposals<>0 or v_ch2_blocks<>0 or v_ch1_paragraphs<>24 then
    raise exception 'WNPH adjudication-only migration changed reading state: ch2 proposals %, ch2 blocks %, ch1 paragraphs %',v_ch2_proposals,v_ch2_blocks,v_ch1_paragraphs;
  end if;
end;
$verify$;