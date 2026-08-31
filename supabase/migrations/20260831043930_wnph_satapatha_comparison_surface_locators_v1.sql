begin;

-- WNPH Satapatha Brahmana / Eggeling 1882 comparison surface locators v1.
--
-- Adds a second, independently paginated scan-backed witness for the already-selected
-- I.3.1.1-11 recovery.  This migration DOES NOT claim source-image verification and
-- DOES NOT admit any reading text.  It records only a deterministic page-label to scan-
-- sequence mapping for printed pp. 67-71 in the 1882 Sacred Books of the East Vol. XII
-- DjVu used by Wikisource/Wikimedia Commons.
--
-- The governed Robarts/Internet Archive surrogate remains the preferred historical
-- recovery source.  This comparison witness is added so that page identity can be
-- checked without guessing an Internet Archive BookReader leaf offset.

insert into wnph.evidence_sources(
  canonical_key,source_type,title,repository_name,url,external_identifier,
  retrieved_at,rights_note,provenance_note,metadata
) values
(
  'wikisource:index:sacred-books-east-volume12',
  'scan_backed_page_index',
  'Index: Sacred Books of the East - Volume 12.djvu',
  'Wikisource',
  'https://en.wikisource.org/wiki/Index:Sacred_Books_of_the_East_-_Volume_12.djvu',
  'Index:Sacred Books of the East - Volume 12.djvu',now(),
  'The underlying 1882 Eggeling translation is public domain in the United States. This record uses the current Wikisource index only as page-sequence evidence and makes no claim to rights in modern Wikisource transcription or interface text.',
  'Scan-backed index identifies Sacred Books of the East Vol. XII, Julius Eggeling translator, Clarendon Press, Oxford, 1882. Its displayed page sequence contains six unnumbered leaves, roman i-iv, the title leaf, roman vi-xlviii, then Arabic page 1 onward. Therefore Arabic printed page 1 is scan sequence 55 and printed pp. 67-71 are sequences 121-125. Wikisource marks the transcription project To be proofread, so its text layer is not a reading authority.',
  jsonb_build_object(
    'work','Satapatha Brahmana',
    'series','Sacred Books of the East',
    'series_volume',12,
    'translator','Julius Eggeling',
    'publisher','The Clarendon Press',
    'publication_place','Oxford',
    'publication_year',1882,
    'source_format','djvu',
    'transcription_progress','to_be_proofread',
    'printed_page_1_scan_sequence',55,
    'mapping_rule','scan_sequence = printed_page + 54 for Arabic pagination in this witness',
    'target_printed_pages',jsonb_build_array(67,68,69,70,71),
    'target_scan_sequences',jsonb_build_array(121,122,123,124,125),
    'visual_verification_complete',false,
    'role','comparison_page_locator'
  )
),
(
  'wikimedia-commons:sacred-books-east-volume12-djvu',
  'digital_surrogate_record',
  'Sacred Books of the East - Volume 12.djvu',
  'Wikimedia Commons',
  'https://commons.wikimedia.org/wiki/File:Sacred_Books_of_the_East_-_Volume_12.djvu',
  'Sacred Books of the East - Volume 12.djvu',now(),
  'The historical 1882 publication is public domain in the United States. WNPH records this Commons-hosted scan as a comparison/verification input and makes no ownership claim over repository presentation or modern metadata.',
  'Wikimedia Commons lists the Volume XII DjVu as a 516-page scan, 3246 by 4975 pixels, approximately 14.33 MB. The file is the scan surface underlying the corresponding Wikisource index. Physical-copy holding provenance is intentionally unresolved at this stage.',
  jsonb_build_object(
    'series_volume',12,
    'publication_year',1882,
    'format','image/vnd.djvu',
    'page_count',516,
    'pixel_width',3246,
    'pixel_height',4975,
    'role','comparison_scan_surrogate',
    'physical_copy_provenance','unresolved'
  )
)
on conflict(canonical_key) do nothing;

do $$
declare
  v_case uuid;
  v_manifestation uuid;
  v_package uuid;
  v_index_source uuid;
  v_commons_source uuid;
  v_item uuid;
  v_surrogate uuid;
  v_page integer;
  v_sequence integer;
  v_asset_key text;
  v_page_uri text;
begin
  select c.id into strict v_case
  from wnph.recovery_cases c
  where c.canonical_key='satapatha-brahmana:eggeling-part1-vessel-cleansing-recovery-1';

  select m.id into strict v_manifestation
  from wnph.manifestations m
  where m.canonical_key='satapatha-brahmana:oxford-clarendon-sbe12-1882';

  select p.id into strict v_package
  from wnph.publication_source_packages p
  where p.canonical_key='satapatha-brahmana:eggeling-1882-part1-i-3-1-canonical-source:v1'
    and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);

  select id into strict v_index_source
  from wnph.evidence_sources
  where canonical_key='wikisource:index:sacred-books-east-volume12';

  select id into strict v_commons_source
  from wnph.evidence_sources
  where canonical_key='wikimedia-commons:sacred-books-east-volume12-djvu';

  insert into wnph.items(
    canonical_key,manifestation_id,holding_institution,call_number,external_identifier,
    status,copy_note,provenance_note
  ) values(
    'satapatha-brahmana:commons-sbe12-volume12-scan-item',
    v_manifestation,null,null,'Sacred Books of the East - Volume 12.djvu',
    'digitized_item_confirmed',
    'Digital exemplar represented by the Commons/Wikisource Volume XII scan. This row does not assert that it is the same physical copy as Internet Archive satapathabrhma01eggeuoft.',
    'Physical holding institution and call number remain unresolved. The digital scan is kept as a distinct Item identity specifically to prevent silent conflation with the governed Robarts/University of Toronto copy.'
  ) on conflict(canonical_key) do nothing;

  select id into strict v_item
  from wnph.items
  where canonical_key='satapatha-brahmana:commons-sbe12-volume12-scan-item';

  insert into wnph.surrogates(
    canonical_key,item_id,source_id,surrogate_type,image_count,formats,status,quality_note
  ) values(
    'satapatha-brahmana:commons-sbe12-volume12-djvu-surrogate',
    v_item,v_commons_source,'repository_page_image_surrogate',516,
    array['djvu','page_images']::text[],'available',
    'Comparison scan surface with an explicit Wikisource page index. It is not promoted to preferred-source status and no target page has yet been visually adjudicated in WNPH.'
  ) on conflict(canonical_key) do nothing;

  select id into strict v_surrogate
  from wnph.surrogates
  where canonical_key='satapatha-brahmana:commons-sbe12-volume12-djvu-surrogate';

  insert into wnph.evidence_links(source_id,item_id,confidence,note)
  select v_commons_source,v_item,'medium',
    'Commons identifies the digital Volume XII scan; physical-copy provenance remains unresolved.'
  where not exists(
    select 1 from wnph.evidence_links
    where source_id=v_commons_source and item_id=v_item and supersedes_evidence_link_id is null
  );

  insert into wnph.evidence_links(source_id,surrogate_id,confidence,note)
  select v_commons_source,v_surrogate,'high',
    'Commons supplies the 516-page Volume XII DjVu represented by this comparison surrogate.'
  where not exists(
    select 1 from wnph.evidence_links
    where source_id=v_commons_source and surrogate_id=v_surrogate and supersedes_evidence_link_id is null
  );

  if not exists(
    select 1 from wnph.recovery_case_targets t
    where t.recovery_case_id=v_case and t.target_role='comparison'
      and t.surrogate_id=v_surrogate and t.supersedes_target_id is null
  ) then
    insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale)
    values(
      v_case,'comparison',v_surrogate,
      'Independent scan-backed comparison witness for locating printed pp. 67-71 as scan sequences 121-125. The Robarts/IA surrogate remains preferred; this target may corroborate page identity but cannot authorize canonical text without visual source verification.'
    );
  end if;

  -- Persist exact page locators as comparison locator assets, NOT source_surface assets.
  -- Their storage_uri is the scan-backed Wikisource page view; a later verified image
  -- URI may be admitted as a true source_surface after direct visual inspection.
  for v_page in 67..71 loop
    v_sequence := v_page + 54;
    v_asset_key := 'satapatha-eggeling1882:commons-sbe12:printed-p' || lpad(v_page::text,4,'0');
    v_page_uri := 'https://en.wikisource.org/wiki/Page:Sacred_Books_of_the_East_-_Volume_12.djvu/' || v_sequence::text;

    if not exists(
      select 1 from wnph.publication_source_assets a
      where a.source_package_id=v_package and a.asset_key=v_asset_key
        and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
    ) then
      insert into wnph.publication_source_assets(
        source_package_id,asset_key,asset_role,source_surrogate_id,evidence_source_id,
        source_locator,storage_uri,media_type,metadata
      ) values(
        v_package,v_asset_key,'comparison_surface_locator',v_surrogate,v_index_source,
        jsonb_build_object(
          'printed_page',v_page,
          'scan_sequence',v_sequence,
          'wikisource_page',v_page_uri,
          'mapping_rule','scan_sequence = printed_page + 54',
          'mapping_basis','scan-backed Wikisource index page-label sequence',
          'visual_verification_complete',false
        ),
        v_page_uri,'text/html',
        jsonb_build_object(
          'surface_status','locator_only_unverified',
          'canonical_text_authority',false,
          'ocr_or_transcription_authority',false,
          'preferred_source',false,
          'comparison_witness',true,
          'promotion_rule','Do not recast as source_surface or use for reading admission until the corresponding scan image has been directly inspected and source-image verification is recorded.'
        )
      );
    end if;
  end loop;

  if (
    select count(*)
    from wnph.publication_source_assets a
    where a.source_package_id=v_package
      and a.asset_role='comparison_surface_locator'
      and a.asset_key like 'satapatha-eggeling1882:commons-sbe12:printed-p%'
      and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id)
  ) <> 5 then
    raise exception 'Expected exactly five active Satapatha comparison page locators for printed pp. 67-71';
  end if;
end $$;

commit;
