do $ingest$
declare
  v_pkg_id uuid;
  v_asset record;
  v_surface_count integer := 0;
  v_surfaces jsonb := '[]'::jsonb;
  v_observations jsonb;
  v_region_observations jsonb;
  v_line_observations jsonb;
  v_requested_uri text;
  v_segment text;
  v_resolved_uri text;
  v_xml_text text;
  v_xml xml;
  v_measurement text;
  v_coordinate_unit text;
  v_key_hash text;
  v_page_text text;
  v_block_count integer;
  v_line_count integer;
  v_word_count integer;
  v_bi integer;
  v_li integer;
  v_wi integer;
  v_region_index integer;
  v_line_index integer;
  v_word text;
  v_wc numeric;
  v_wc_sum numeric;
  v_wc_count integer;
  v_line_conf numeric;
  v_region_conf numeric;
  v_line_text text;
  v_region_text text;
  v_first_alpha text;
  v_bx numeric;
  v_by numeric;
  v_bw numeric;
  v_bh numeric;
  v_lx numeric;
  v_ly numeric;
  v_lw numeric;
  v_lh numeric;
  v_min_x numeric;
  v_min_y numeric;
  v_max_right numeric;
  v_max_bottom numeric;
  v_child_lines integer;
  v_generated_observations integer := 0;
  v_result jsonb;
begin
  select p.id into v_pkg_id
  from wnph.publication_source_packages p
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id)
  order by p.created_at desc limit 1;
  if v_pkg_id is null then raise exception 'Dewy active source package missing'; end if;

  for v_asset in
    select a.id,a.asset_key,a.storage_uri,a.media_type,a.source_locator
    from wnph.publication_source_assets a
    where a.source_package_id=v_pkg_id
      and a.asset_role='source_surface'
      and (a.source_locator->>'loc_image')::integer between 21 and 30
      and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id)
    order by (a.source_locator->>'loc_image')::integer
  loop
    v_surface_count := v_surface_count + 1;
    v_requested_uri := nullif(v_asset.source_locator->>'alto_uri','');
    if v_requested_uri is null then raise exception 'Chapter II surface % lacks ALTO URI',v_asset.asset_key; end if;
    if v_requested_uri !~ '^https://tile[.]loc[.]gov/text-services/word-coordinates-service[?]'
       or v_requested_uri !~ 'format=alto_xml'
    then
      raise exception 'Chapter II surface % has unsupported ALTO URI %',v_asset.asset_key,v_requested_uri;
    end if;
    v_segment := substring(v_requested_uri from 'segment=([^&]+)');
    if v_segment is null or left(v_segment,8)<>'/public/' or v_segment !~ '[.]alto[.]xml$' or v_segment like '%..%' or position(chr(92) in v_segment)>0 then
      raise exception 'Chapter II surface % has unsafe ALTO segment %',v_asset.asset_key,v_segment;
    end if;
    v_resolved_uri := 'https://tile.loc.gov/storage-services'||v_segment;

    select (extensions.http_get(v_resolved_uri)).content into v_xml_text;
    if coalesce(v_xml_text,'')='' or v_xml_text !~ '<alto[ >]' then
      raise exception 'Chapter II ALTO fetch failed for %',v_asset.asset_key;
    end if;
    v_xml := xmlparse(document v_xml_text);
    v_measurement := lower(coalesce((xpath('string((//*[local-name()="MeasurementUnit"])[1])',v_xml))[1]::text,'pixel'));
    v_coordinate_unit := case v_measurement when 'inch1200' then 'alto_1_1200in' when 'mm10' then 'alto_1_10mm' else 'pixel' end;
    v_key_hash := substr(encode(extensions.digest(v_requested_uri,'sha256'),'hex'),1,16);

    v_page_text := '';
    v_region_observations := '[]'::jsonb;
    v_line_observations := '[]'::jsonb;
    v_region_index := 0;
    v_line_index := 0;
    v_block_count := cardinality(xpath('//*[local-name()="TextBlock"]',v_xml));

    for v_bi in 1..v_block_count loop
      v_line_count := cardinality(xpath(format('(//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"]',v_bi),v_xml));
      if v_line_count=0 then continue; end if;

      v_bx := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/@HPOS)',v_bi),v_xml))[1]::text,'')::numeric;
      v_by := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/@VPOS)',v_bi),v_xml))[1]::text,'')::numeric;
      v_bw := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/@WIDTH)',v_bi),v_xml))[1]::text,'')::numeric;
      v_bh := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/@HEIGHT)',v_bi),v_xml))[1]::text,'')::numeric;
      v_region_text := '';
      v_region_conf := null;
      v_child_lines := 0;
      v_min_x := null; v_min_y := null; v_max_right := null; v_max_bottom := null;

      for v_li in 1..v_line_count loop
        v_word_count := cardinality(xpath(format('(//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/*[local-name()="String"]',v_bi,v_li),v_xml));
        v_line_text := '';
        v_wc_sum := 0;
        v_wc_count := 0;

        for v_wi in 1..v_word_count loop
          v_word := coalesce((xpath(format('string((//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/*[local-name()="String"][%s]/@CONTENT)',v_bi,v_li,v_wi),v_xml))[1]::text,'');
          if v_word<>'' then
            if v_line_text<>'' then v_line_text := v_line_text||' '; end if;
            v_line_text := v_line_text||v_word;
          end if;
          v_wc := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/*[local-name()="String"][%s]/@WC)',v_bi,v_li,v_wi),v_xml))[1]::text,'')::numeric;
          if v_wc between 0 and 1 then v_wc_sum:=v_wc_sum+v_wc; v_wc_count:=v_wc_count+1; end if;
        end loop;

        v_line_text := btrim(regexp_replace(v_line_text,'[[:space:]]+',' ','g'));
        if v_line_text='' then continue; end if;
        v_line_conf := case when v_wc_count>0 then v_wc_sum/v_wc_count else null end;
        v_lx := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/@HPOS)',v_bi,v_li),v_xml))[1]::text,'')::numeric;
        v_ly := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/@VPOS)',v_bi,v_li),v_xml))[1]::text,'')::numeric;
        v_lw := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/@WIDTH)',v_bi,v_li),v_xml))[1]::text,'')::numeric;
        v_lh := nullif((xpath(format('string((//*[local-name()="TextBlock"])[%s]/*[local-name()="TextLine"][%s]/@HEIGHT)',v_bi,v_li),v_xml))[1]::text,'')::numeric;

        v_line_index := v_line_index + 1;
        v_child_lines := v_child_lines + 1;
        if v_page_text<>'' then v_page_text:=v_page_text||chr(10); end if;
        v_page_text:=v_page_text||v_line_text;

        if v_region_text='' then
          v_region_text:=v_line_text;
        else
          v_first_alpha:=substring(v_line_text from '[A-Za-z]');
          if right(v_region_text,1)='-' and v_first_alpha is not null and v_first_alpha ~ '[a-z]' then
            v_region_text:=left(v_region_text,length(v_region_text)-1)||v_line_text;
          else
            v_region_text:=v_region_text||' '||v_line_text;
          end if;
        end if;
        v_region_text:=btrim(regexp_replace(v_region_text,'[[:space:]]+',' ','g'));
        if v_line_conf is not null then v_region_conf:=case when v_region_conf is null then v_line_conf else least(v_region_conf,v_line_conf) end; end if;
        if v_lx is not null and v_ly is not null and v_lw is not null and v_lh is not null then
          v_min_x:=case when v_min_x is null then v_lx else least(v_min_x,v_lx) end;
          v_min_y:=case when v_min_y is null then v_ly else least(v_min_y,v_ly) end;
          v_max_right:=case when v_max_right is null then v_lx+v_lw else greatest(v_max_right,v_lx+v_lw) end;
          v_max_bottom:=case when v_max_bottom is null then v_ly+v_lh else greatest(v_max_bottom,v_ly+v_lh) end;
        end if;

        v_line_observations:=v_line_observations||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'observation_key',format('upstream-ocr:%s:line:v2:%s',v_key_hash,lpad(v_line_index::text,5,'0')),
          'observation_kind','line','ordinal',v_line_index,'text_candidate',v_line_text,
          'coordinate_unit',case when v_lx is not null and v_ly is not null and v_lw is not null and v_lh is not null then v_coordinate_unit else 'surface' end,
          'x',v_lx,'y',v_ly,'width',v_lw,'height',v_lh,'confidence',v_line_conf,
          'derivation_method','external_ocr_line_import_without_semantic_normalization','source_format','alto_xml',
          'processor',jsonb_build_object('provider','tile.loc.gov','engine','upstream_ocr','version','unknown'),
          'external_locator',jsonb_build_object('uri',v_requested_uri,'resolved_uri',v_resolved_uri,'line_index',v_line_index),
          'metadata',jsonb_build_object('canonical_text_asserted',false)
        )));
      end loop;

      if v_child_lines>0 then
        v_region_index:=v_region_index+1;
        if v_bx is null or v_by is null or v_bw is null or v_bh is null then
          v_bx:=v_min_x; v_by:=v_min_y;
          if v_min_x is not null and v_max_right is not null then v_bw:=v_max_right-v_min_x; end if;
          if v_min_y is not null and v_max_bottom is not null then v_bh:=v_max_bottom-v_min_y; end if;
        end if;
        v_region_observations:=v_region_observations||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'observation_key',format('upstream-ocr:%s:region:v3:%s',v_key_hash,lpad(v_region_index::text,5,'0')),
          'observation_kind','region','ordinal',v_region_index,'text_candidate',v_region_text,
          'coordinate_unit',case when v_bx is not null and v_by is not null and v_bw is not null and v_bh is not null then v_coordinate_unit else 'surface' end,
          'x',v_bx,'y',v_by,'width',v_bw,'height',v_bh,'confidence',v_region_conf,
          'derivation_method','external_ocr_layout_region_import_without_semantic_normalization','source_format','alto_xml',
          'processor',jsonb_build_object('provider','tile.loc.gov','engine','upstream_ocr','version','unknown'),
          'external_locator',jsonb_build_object('uri',v_requested_uri,'resolved_uri',v_resolved_uri,'region_index',v_region_index),
          'metadata',jsonb_build_object('canonical_text_asserted',false,'source_layout_element','TextBlock','child_line_count',v_child_lines)
        )));
      end if;
    end loop;

    if v_line_index=0 or v_page_text='' then raise exception 'Chapter II ALTO produced no text for %',v_asset.asset_key; end if;
    v_observations:=jsonb_build_array(jsonb_build_object(
      'observation_key',format('upstream-ocr:%s:page:v2',v_key_hash),
      'observation_kind','page_text','ordinal',0,'text_candidate',v_page_text,'coordinate_unit','surface',
      'derivation_method','external_ocr_resource_import_preserving_line_structure','source_format','alto_xml',
      'processor',jsonb_build_object('provider','tile.loc.gov','engine','upstream_ocr','version','unknown'),
      'external_locator',jsonb_build_object('uri',v_requested_uri,'resolved_uri',v_resolved_uri),
      'metadata',jsonb_build_object('canonical_text_asserted',false,'line_observation_count',v_line_index,'layout_region_observation_count',v_region_index)
    ))||v_region_observations||v_line_observations;
    v_generated_observations:=v_generated_observations+jsonb_array_length(v_observations);

    v_surfaces:=v_surfaces||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'asset_key',v_asset.asset_key,
      'storage_uri',v_asset.storage_uri,
      'media_type',v_asset.media_type,
      'source_locator',v_asset.source_locator,
      'metadata',jsonb_build_object('remote_custody',true,'byte_copy_required',false,'upstream_text_refs',jsonb_build_array(jsonb_build_object('uri',v_requested_uri,'format','alto_xml'))),
      'observations',v_observations
    )));
  end loop;

  if v_surface_count<>10 then raise exception 'Chapter II ALTO intake expected 10 active surfaces, found %',v_surface_count; end if;

  select public.wnph_ingest_source_surface_batch_v1(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'image_list',
    'https://www.loc.gov/item/22008427/',
    v_surfaces,
    jsonb_build_object('intake_adapter','wnph-source-batch-intake','adapter_version',3,'prospective_reconstruction_scope','dewy_chapter_2')
  ) into v_result;

  if (v_result->>'inserted_surfaces')::integer<>0 or (v_result->>'skipped_surfaces')::integer<>10 then
    raise exception 'Chapter II ALTO intake changed source-surface custody unexpectedly: %',v_result;
  end if;
  if (v_result->>'inserted_observations')::integer<>v_generated_observations then
    raise exception 'Chapter II ALTO intake observation count mismatch generated %, result %',v_generated_observations,v_result;
  end if;
  if exists(select 1 from wnph.publication_source_reconstruction_proposals p where not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id)) then
    raise exception 'Chapter II ALTO intake must not create reconstruction proposals';
  end if;
  if exists(select 1 from wnph.publication_source_blocks b where b.parent_block_id='136a2898-8fee-4e79-9493-44ec534dc8c9'::uuid and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)) then
    raise exception 'Chapter II ALTO intake must not create paragraph blocks';
  end if;
end;
$ingest$;