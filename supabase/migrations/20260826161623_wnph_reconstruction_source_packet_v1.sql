create or replace function public.wnph_reconstruction_source_packet_v1(
  p_source_package_key text,
  p_target_parent_block_key text,
  p_asset_keys text[] default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_pkg_id uuid;
  v_parent wnph.publication_source_blocks%rowtype;
  v_surfaces jsonb;
  v_max_ordinal integer;
  v_child_count integer;
begin
  if coalesce(btrim(p_source_package_key),'')='' or coalesce(btrim(p_target_parent_block_key),'')='' then
    raise exception 'WNPH reconstruction packet: source package key and target parent block key are required';
  end if;

  select p.id into v_pkg_id
  from wnph.publication_source_packages p
  where p.canonical_key=p_source_package_key
    and not exists(select 1 from wnph.publication_source_packages child where child.supersedes_package_id=p.id)
  order by p.created_at desc
  limit 1;

  if v_pkg_id is null then
    raise exception 'WNPH reconstruction packet: active source package not found for %',p_source_package_key;
  end if;

  select b.* into v_parent
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg_id
    and b.block_key=p_target_parent_block_key
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id)
  order by b.created_at desc
  limit 1;

  if v_parent.id is null then
    raise exception 'WNPH reconstruction packet: active target parent block not found for %',p_target_parent_block_key;
  end if;

  select coalesce(max(b.ordinal),0),count(*)
    into v_max_ordinal,v_child_count
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg_id
    and b.parent_block_id=v_parent.id
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

  select coalesce(jsonb_agg(surface_packet order by sort_sequence,sort_page,asset_key),'[]'::jsonb)
    into v_surfaces
  from (
    select
      a.asset_key,
      coalesce(nullif(a.source_locator->>'sequence_index','')::numeric,
               nullif(a.source_locator->>'printed_page','')::numeric,
               nullif(a.source_locator->>'source_pdf_page','')::numeric,
               nullif(a.source_locator->>'pdf_page','')::numeric,
               999999999::numeric) as sort_sequence,
      coalesce(nullif(a.source_locator->>'printed_page','')::numeric,
               nullif(a.source_locator->>'source_pdf_page','')::numeric,
               nullif(a.source_locator->>'pdf_page','')::numeric,
               999999999::numeric) as sort_page,
      jsonb_build_object(
        'id',a.id,
        'asset_key',a.asset_key,
        'media_type',a.media_type,
        'storage_uri',a.storage_uri,
        'source_locator',a.source_locator,
        'metadata',a.metadata,
        'observations',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id',o.id,
              'observation_key',o.observation_key,
              'observation_kind',o.observation_kind,
              'ordinal',o.ordinal,
              'text_candidate',o.text_candidate,
              'coordinate_unit',o.coordinate_unit,
              'x',o.x,'y',o.y,'width',o.width,'height',o.height,
              'confidence',o.confidence,
              'derivation_method',o.derivation_method,
              'source_format',o.source_format,
              'processor',o.processor,
              'external_locator',o.external_locator,
              'metadata',o.metadata
            )
            order by
              case o.observation_kind when 'layout_region' then 1 when 'region' then 2 when 'line' then 3 when 'word' then 4 when 'page_text' then 5 else 6 end,
              o.ordinal nulls last,o.y nulls last,o.x nulls last,o.created_at
          )
          from wnph.publication_source_observations o
          where o.source_asset_id=a.id
            and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id)
        ),'[]'::jsonb)
      ) as surface_packet
    from wnph.publication_source_assets a
    where a.source_package_id=v_pkg_id
      and a.asset_role='source_surface'
      and (p_asset_keys is null or a.asset_key=any(p_asset_keys))
      and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id)
  ) s;

  if jsonb_array_length(v_surfaces)=0 then
    raise exception 'WNPH reconstruction packet: no active source surfaces matched the request';
  end if;

  return jsonb_build_object(
    'source_package_key',p_source_package_key,
    'source_package_id',v_pkg_id,
    'target_parent_block',jsonb_build_object(
      'id',v_parent.id,
      'block_key',v_parent.block_key,
      'block_type',v_parent.block_type,
      'semantic_role',v_parent.semantic_role,
      'properties',v_parent.properties
    ),
    'existing_child_count',v_child_count,
    'existing_max_ordinal',v_max_ordinal,
    'surfaces',v_surfaces
  );
end;
$function$;

revoke all on function public.wnph_reconstruction_source_packet_v1(text,text,text[]) from public,anon,authenticated;
grant execute on function public.wnph_reconstruction_source_packet_v1(text,text,text[]) to service_role;

comment on function public.wnph_reconstruction_source_packet_v1(text,text,text[]) is
  'Service-only ordered read packet for the WNPH reconstruction worker. Exposes active source surfaces and active located observations for one source package and semantic parent without granting direct table access.';

do $verify$
declare
  v_packet jsonb;
begin
  select public.wnph_reconstruction_source_packet_v1(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:1:paragraph-stream',
    array['dewy:loc:source-surface:0015']::text[]
  ) into v_packet;

  if jsonb_array_length(v_packet->'surfaces')<>1
     or jsonb_array_length(v_packet->'surfaces'->0->'observations')<>1
     or v_packet->'target_parent_block'->>'block_key'<>'dewy:chapter:1:paragraph-stream' then
    raise exception 'WNPH reconstruction packet fixture failed: %',v_packet;
  end if;
end;
$verify$;