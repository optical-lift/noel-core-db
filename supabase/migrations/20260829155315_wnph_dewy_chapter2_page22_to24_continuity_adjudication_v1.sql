with start_target as (
  select p.id source_package_id,a.id start_asset_id,o.id start_observation_id,
         a.asset_key start_asset_key,a.source_locator start_source_locator,o.text_candidate start_text
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id=p.id
  join wnph.publication_source_observations o on o.source_asset_id=a.id
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key='dewy:loc:source-surface:0026'
    and o.observation_kind='line' and o.source_format='alto_xml'
    and o.ordinal=24 and o.text_candidate='needed. But there are no clouds.'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id)
    and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
    and not exists(select 1 from wnph.publication_source_observations n where n.supersedes_observation_id=o.id)
),
end_target as (
  select p.id source_package_id,a.id end_asset_id,o.id end_observation_id,
         a.asset_key end_asset_key,a.source_locator end_source_locator,o.text_candidate end_text
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id=p.id
  join wnph.publication_source_observations o on o.source_asset_id=a.id
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key='dewy:loc:source-surface:0028'
    and o.observation_kind='line' and o.source_format='alto_xml'
    and o.ordinal=1 and o.text_candidate='Could you not spare one of your'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id)
    and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
    and not exists(select 1 from wnph.publication_source_observations n where n.supersedes_observation_id=o.id)
), target as (
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
  'dewy:reading-adjudication:chapter2:page22-to-page24:paragraph-continuity',
  'paragraph_continuity',
  start_asset_id,start_observation_id,end_asset_id,end_observation_id,
  'join_across_boundary',null,
  'source_collation_adjudication',
  'loc_observation_plus_independent_full_text_paragraph_structure_v1',
  0.99,
  'Printed page 22 ends the Wish Fairy’s quoted request with “needed. But there are no clouds.” The independent Internet Archive full-text derivative continues the same quoted paragraph after the intervening illustrated surface with “Could you not spare one of your subjects…” and does not introduce a paragraph boundary. The semantic paragraph therefore continues across the plate.',
  jsonb_build_object(
    'start_source_asset_key',start_asset_key,
    'start_source_pdf_page',start_source_locator->>'source_pdf_page',
    'start_printed_page',start_source_locator->>'printed_page',
    'preserved_start_text',start_text,
    'end_source_asset_key',end_asset_key,
    'end_source_pdf_page',end_source_locator->>'source_pdf_page',
    'end_printed_page',end_source_locator->>'printed_page',
    'preserved_end_text',end_text,
    'intervening_source_asset_key','dewy:loc:source-surface:0027',
    'independent_source',jsonb_build_object(
      'provider','Internet Archive',
      'item_identifier','wishfairydewydea00colv',
      'derivative','full_text',
      'source_uri','https://archive.org/stream/wishfairydewydea00colv/wishfairydewydea00colv_djvu.txt',
      'continuation',jsonb_build_array(
        'needed. But there are no clouds.',
        '22',
        'Could you not spare one of your',
        'subjects to stay with us and let',
        'him blow up some clouds for us',
        'now and then?’'
      )
    ),
    'raw_observation_rewritten',false
  )
from target;

do $verify$
declare
  v_packet jsonb;
  v_adjudications integer;
  v_ch2_proposals integer;
  v_ch2_blocks integer;
  v_ch1_paragraphs integer;
begin
  v_packet:=public.wnph_reconstruction_source_packet_v6(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:2:paragraph-stream',null
  );
  v_adjudications:=jsonb_array_length(v_packet->'reading_adjudications');
  if v_adjudications<>4 then
    raise exception 'WNPH Chapter II packet expected 4 active governed reading facts; got %',v_adjudications;
  end if;
  if not exists(
    select 1 from wnph.publication_source_reading_adjudications a
    where a.adjudication_key='dewy:reading-adjudication:chapter2:page22-to-page24:paragraph-continuity'
      and a.result='join_across_boundary'
      and not exists(select 1 from wnph.publication_source_reading_adjudications n where n.supersedes_adjudication_id=a.id)
  ) then
    raise exception 'WNPH Chapter II page22-to-page24 continuity adjudication missing';
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
    raise exception 'WNPH continuity adjudication changed reading state: ch2 proposals %, ch2 blocks %, ch1 paragraphs %',v_ch2_proposals,v_ch2_blocks,v_ch1_paragraphs;
  end if;
end;
$verify$;