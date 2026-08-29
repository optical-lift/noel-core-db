do $admit$
declare
  v_pkg_id uuid;
  v_surrogate_id uuid;
  v_evidence_id uuid;
  v_existing integer;
begin
  select p.id into v_pkg_id
  from wnph.publication_source_packages p
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id)
  order by p.created_at desc limit 1;
  if v_pkg_id is null then raise exception 'Dewy active source package missing'; end if;

  select a.source_surrogate_id, a.evidence_source_id
    into v_surrogate_id, v_evidence_id
  from wnph.publication_source_assets a
  where a.source_package_id=v_pkg_id and a.asset_key='historical-source-surrogate'
  order by a.created_at desc limit 1;
  if v_surrogate_id is null or v_evidence_id is null then
    raise exception 'Dewy historical source custody basis missing';
  end if;

  select count(*) into v_existing
  from wnph.publication_source_assets a
  where a.source_package_id=v_pkg_id and a.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id);
  if v_existing <> 10 then raise exception 'Expected 10 active Dewy source surfaces before whole-book admission, found %', v_existing; end if;

  if exists(
    select 1 from wnph.publication_source_assets a
    where a.source_package_id=v_pkg_id and a.asset_role='source_surface'
      and a.asset_key between 'dewy:loc:source-surface:0011' and 'dewy:loc:source-surface:0020'
      and (nullif(a.source_locator->>'source_pdf_page','')::int < 11 or nullif(a.source_locator->>'source_pdf_page','')::int > 20)
  ) then raise exception 'Existing Chapter I source surface locator mismatch'; end if;

  insert into wnph.publication_source_assets(
    source_package_id, asset_key, asset_role, source_surrogate_id, evidence_source_id,
    source_locator, storage_uri, media_type, metadata
  )
  select
    v_pkg_id,
    format('dewy:loc:source-surface:%s', lpad(g.n::text,4,'0')),
    'source_surface',
    v_surrogate_id,
    v_evidence_id,
    jsonb_strip_nulls(jsonb_build_object(
      'alto_uri', format('https://tile.loc.gov/text-services/word-coordinates-service?segment=/public/gdcmassbookdig/wishfairydewydea00colv/wishfairydewydea00colv_%s.alto.xml&format=alto_xml&full_text=1', lpad(g.n::text,4,'0')),
      'item_uri', 'https://www.loc.gov/item/22008427/',
      'image_uri', format('https://tile.loc.gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_%s/full/max/0/default.jpg', lpad(g.n::text,4,'0')),
      'loc_image', g.n,
      'repository', 'Library of Congress',
      'printed_page', case when g.n between 11 and 67 then g.n-4 else null end,
      'iiif_info_uri', format('https://tile.loc.gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_%s/info.json', lpad(g.n::text,4,'0')),
      'source_pdf_page', g.n,
      'iiif_image_service_uri', format('https://tile.loc.gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_%s', lpad(g.n::text,4,'0'))
    )),
    null,
    'image/jpeg',
    jsonb_build_object(
      'fixture_scope','dewy_whole_book_source_skeleton',
      'remote_custody',true,
      'byte_copy_required',false,
      'addressing_standard','iiif_image_api',
      'reading_admission',false
    )
  from generate_series(1,72) g(n)
  where not exists(
    select 1 from wnph.publication_source_assets a
    where a.source_package_id=v_pkg_id
      and a.asset_key=format('dewy:loc:source-surface:%s', lpad(g.n::text,4,'0'))
      and a.asset_role='source_surface'
      and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id)
  );

  select count(*) into v_existing
  from wnph.publication_source_assets a
  where a.source_package_id=v_pkg_id and a.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id);
  if v_existing <> 72 then raise exception 'Expected 72 active Dewy source surfaces after whole-book admission, found %', v_existing; end if;
end
$admit$;

with span_spec(block_key,span_key,start_page,start_boundary,start_observation_key,end_page,end_boundary,end_observation_key,structural_basis) as (
  values
    ('dewy:document','dewy:document:source-span:v1',1,'asset_start',null::text,72,'asset_end',null::text,'complete_72_scan_source_object'),
    ('dewy:front-matter','dewy:front-matter:source-span:v1',1,'asset_start',null,10,'asset_end',null,'pre_body_scan_sequence'),
    ('dewy:plate:frontispiece','dewy:plate:frontispiece:source-span:v1',6,'asset_start',null,6,'asset_end',null,'source_observed_frontispiece'),
    ('dewy:title-page','dewy:title-page:source-span:v1',7,'asset_start',null,7,'asset_end',null,'source_observed_title_page'),
    ('dewy:copyright-page','dewy:copyright-page:source-span:v1',8,'asset_start',null,8,'asset_end',null,'source_observed_copyright_page'),
    ('dewy:contents','dewy:contents:source-span:v1',9,'asset_start',null,9,'asset_end',null,'source_observed_table_of_contents'),
    ('dewy:body','dewy:body:source-span:v1',11,'asset_start',null,67,'asset_end',null,'printed_body_pages_7_through_63'),
    ('dewy:body-title','dewy:body-title:source-span:v1',11,'at_observation','upstream-ocr:2af485cbff16708e:region:v3:00001',11,'before_observation','upstream-ocr:2af485cbff16708e:region:v3:00004','source_observed_body_title_before_chapter_i'),
    ('dewy:chapter:1','dewy:chapter:1:source-span:v1',11,'asset_start',null,20,'asset_end',null,'toc_and_printed_pagination'),
    ('dewy:chapter:2','dewy:chapter:2:source-span:v1',21,'asset_start',null,30,'asset_end',null,'toc_and_printed_pagination'),
    ('dewy:chapter:3','dewy:chapter:3:source-span:v1',31,'asset_start',null,38,'asset_end',null,'toc_and_printed_pagination'),
    ('dewy:chapter:4','dewy:chapter:4:source-span:v1',39,'asset_start',null,48,'asset_end',null,'toc_and_printed_pagination'),
    ('dewy:chapter:5','dewy:chapter:5:source-span:v1',49,'asset_start',null,56,'asset_end',null,'toc_and_printed_pagination'),
    ('dewy:chapter:6','dewy:chapter:6:source-span:v1',57,'asset_start',null,67,'asset_end',null,'toc_and_printed_pagination'),
    ('dewy:plate:page-9','dewy:plate:page-9:source-span:v1',13,'asset_start',null,13,'asset_end',null,'source_observed_interior_plate'),
    ('dewy:plate:page-19','dewy:plate:page-19:source-span:v1',23,'asset_start',null,23,'asset_end',null,'source_observed_interior_plate'),
    ('dewy:plate:page-29','dewy:plate:page-29:source-span:v1',33,'asset_start',null,33,'asset_end',null,'source_observed_interior_plate'),
    ('dewy:plate:page-37','dewy:plate:page-37:source-span:v1',41,'asset_start',null,41,'asset_end',null,'source_observed_interior_plate'),
    ('dewy:plate:page-47','dewy:plate:page-47:source-span:v1',51,'asset_start',null,51,'asset_end',null,'source_observed_interior_plate'),
    ('dewy:plate:page-55','dewy:plate:page-55:source-span:v1',59,'asset_start',null,59,'asset_end',null,'source_observed_interior_plate')
), resolved as (
  select
    p.id as source_package_id,
    b.id as block_id,
    s.span_key,
    sa.id as start_asset_id,
    so.id as start_observation_id,
    s.start_boundary,
    ea.id as end_asset_id,
    eo.id as end_observation_id,
    s.end_boundary,
    s.block_key,
    s.start_page,
    s.end_page,
    s.structural_basis
  from span_spec s
  join wnph.publication_source_packages p on p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages pc where pc.supersedes_package_id=p.id)
  join wnph.publication_source_blocks b on b.source_package_id=p.id and b.block_key=s.block_key
    and not exists(select 1 from wnph.publication_source_blocks bc where bc.supersedes_block_id=b.id)
  join wnph.publication_source_assets sa on sa.source_package_id=p.id
    and sa.asset_key=format('dewy:loc:source-surface:%s',lpad(s.start_page::text,4,'0'))
    and sa.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets sac where sac.supersedes_asset_id=sa.id)
  join wnph.publication_source_assets ea on ea.source_package_id=p.id
    and ea.asset_key=format('dewy:loc:source-surface:%s',lpad(s.end_page::text,4,'0'))
    and ea.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets eac where eac.supersedes_asset_id=ea.id)
  left join wnph.publication_source_observations so on so.source_asset_id=sa.id and so.observation_key=s.start_observation_key
    and not exists(select 1 from wnph.publication_source_observations soc where soc.supersedes_observation_id=so.id)
  left join wnph.publication_source_observations eo on eo.source_asset_id=ea.id and eo.observation_key=s.end_observation_key
    and not exists(select 1 from wnph.publication_source_observations eoc where eoc.supersedes_observation_id=eo.id)
)
insert into wnph.publication_source_block_spans(
  source_package_id,block_id,span_key,start_asset_id,start_observation_id,start_boundary,
  end_asset_id,end_observation_id,end_boundary,boundary_authority,derivation_method,evidence
)
select
  source_package_id,block_id,span_key,start_asset_id,start_observation_id,start_boundary,
  end_asset_id,end_observation_id,end_boundary,
  'source_observed_semantic_structure',
  'loc_scan_sequence_and_source_toc_mapping_v1',
  jsonb_build_object(
    'mapping_scope','dewy_whole_book_source_skeleton_v1',
    'structural_basis',structural_basis,
    'source_package','wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'loc_item','22008427',
    'source_scan_start',start_page,
    'source_scan_end',end_page,
    'chapter_start_printed_pages',jsonb_build_array(7,17,27,35,45,53),
    'body_printed_page_range',jsonb_build_array(7,63),
    'canonical_reading_admitted',false
  )
from resolved;

do $verify$
declare
  v_pkg_id uuid;
  v_surface_count integer;
  v_new_span_count integer;
  v_proposals integer;
  v_ch2_paragraphs integer;
begin
  select id into v_pkg_id from wnph.publication_source_packages p
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id)
  order by p.created_at desc limit 1;

  select count(*) into v_surface_count from wnph.publication_source_assets a
  where a.source_package_id=v_pkg_id and a.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id);
  if v_surface_count<>72 then raise exception 'Whole-book source skeleton expected 72 active surfaces, found %',v_surface_count; end if;

  select count(*) into v_new_span_count from wnph.publication_source_block_spans s
  where s.source_package_id=v_pkg_id
    and s.evidence->>'mapping_scope'='dewy_whole_book_source_skeleton_v1'
    and not exists(select 1 from wnph.publication_source_block_spans c where c.supersedes_span_id=s.id);
  if v_new_span_count<>20 then raise exception 'Whole-book source skeleton expected 20 new active structural spans, found %',v_new_span_count; end if;

  select count(*) into v_proposals from wnph.publication_source_reconstruction_proposals rp
  where rp.source_package_id=v_pkg_id
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=rp.id);
  if v_proposals<>0 then raise exception 'Whole-book structural mapping must not create reconstruction proposals'; end if;

  select count(*) into v_ch2_paragraphs
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg_id and b.block_key like 'dewy:chapter:2:paragraph:%'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);
  if v_ch2_paragraphs<>0 then raise exception 'Whole-book structural mapping must not admit Chapter II reading blocks'; end if;
end
$verify$;