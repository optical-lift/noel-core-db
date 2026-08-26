create or replace function public.wnph_ingest_source_surface_batch_v1(
  p_source_package_key text,
  p_input_kind text,
  p_source_ref text,
  p_surfaces jsonb,
  p_batch_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_pkg_id uuid;
  v_surface jsonb;
  v_obs jsonb;
  v_asset_id uuid;
  v_existing wnph.publication_source_assets%rowtype;
  v_existing_obs wnph.publication_source_observations%rowtype;
  v_asset_key text;
  v_storage_uri text;
  v_locator jsonb;
  v_media_type text;
  v_surface_metadata jsonb;
  v_observation_key text;
  v_inserted_surfaces integer := 0;
  v_skipped_surfaces integer := 0;
  v_inserted_observations integer := 0;
  v_skipped_observations integer := 0;
  v_surface_count integer;
begin
  if coalesce(btrim(p_source_package_key),'')='' then
    raise exception 'WNPH batch intake: source package key is required';
  end if;
  if p_input_kind not in ('iiif_manifest','image_list','photo_batch','pdf_pages') then
    raise exception 'WNPH batch intake: unsupported input_kind %',p_input_kind;
  end if;
  if coalesce(btrim(p_source_ref),'')='' then
    raise exception 'WNPH batch intake: source_ref is required';
  end if;
  if jsonb_typeof(p_surfaces) <> 'array' then
    raise exception 'WNPH batch intake: surfaces must be a JSON array';
  end if;
  v_surface_count := jsonb_array_length(p_surfaces);
  if v_surface_count < 1 or v_surface_count > 5000 then
    raise exception 'WNPH batch intake: surface count % is outside supported range 1..5000',v_surface_count;
  end if;
  if jsonb_typeof(coalesce(p_batch_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'WNPH batch intake: batch metadata must be an object';
  end if;

  select p.id into v_pkg_id
  from wnph.publication_source_packages p
  where p.canonical_key=p_source_package_key
    and not exists(
      select 1 from wnph.publication_source_packages child
      where child.supersedes_package_id=p.id
    )
  order by p.created_at desc
  limit 1;

  if v_pkg_id is null then
    raise exception 'WNPH batch intake: active source package not found for %',p_source_package_key;
  end if;

  for v_surface in select value from jsonb_array_elements(p_surfaces)
  loop
    if jsonb_typeof(v_surface) <> 'object' then
      raise exception 'WNPH batch intake: each surface must be an object';
    end if;

    v_asset_key := btrim(coalesce(v_surface->>'asset_key',''));
    if v_asset_key='' then
      raise exception 'WNPH batch intake: each surface requires asset_key';
    end if;

    v_storage_uri := nullif(btrim(coalesce(v_surface->>'storage_uri','')),'');
    v_locator := coalesce(v_surface->'source_locator','{}'::jsonb);
    if jsonb_typeof(v_locator) <> 'object' then
      raise exception 'WNPH batch intake: source_locator for % must be an object',v_asset_key;
    end if;
    if v_storage_uri is null
       and coalesce(v_locator->>'image_uri','')=''
       and coalesce(v_locator->>'iiif_canvas_uri','')=''
       and coalesce(v_locator->>'iiif_image_service_uri','')='' then
      raise exception 'WNPH batch intake: surface % lacks a durable image/storage address',v_asset_key;
    end if;

    v_media_type := nullif(btrim(coalesce(v_surface->>'media_type','')),'');
    if v_media_type is null then v_media_type := 'image/jpeg'; end if;
    v_surface_metadata := coalesce(v_surface->'metadata','{}'::jsonb);
    if jsonb_typeof(v_surface_metadata) <> 'object' then
      raise exception 'WNPH batch intake: metadata for % must be an object',v_asset_key;
    end if;

    select a.* into v_existing
    from wnph.publication_source_assets a
    where a.source_package_id=v_pkg_id
      and a.asset_key=v_asset_key
      and a.asset_role='source_surface'
      and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id)
    order by a.created_at desc
    limit 1;

    if v_existing.id is not null then
      if coalesce(v_existing.storage_uri,'') <> coalesce(v_storage_uri,'')
         or v_existing.source_locator <> v_locator then
        raise exception 'WNPH batch intake: active surface % already exists with different source address/locator',v_asset_key;
      end if;
      v_asset_id := v_existing.id;
      v_skipped_surfaces := v_skipped_surfaces + 1;
    else
      insert into wnph.publication_source_assets(
        source_package_id,asset_key,asset_role,source_locator,storage_uri,media_type,metadata
      ) values (
        v_pkg_id,v_asset_key,'source_surface',v_locator,v_storage_uri,v_media_type,
        v_surface_metadata || jsonb_build_object(
          'batch_input_kind',p_input_kind,
          'batch_source_ref',p_source_ref,
          'batch_metadata',coalesce(p_batch_metadata,'{}'::jsonb)
        )
      ) returning id into v_asset_id;
      v_inserted_surfaces := v_inserted_surfaces + 1;
    end if;

    if v_surface ? 'observations' then
      if jsonb_typeof(v_surface->'observations') <> 'array' then
        raise exception 'WNPH batch intake: observations for % must be an array',v_asset_key;
      end if;

      for v_obs in select value from jsonb_array_elements(v_surface->'observations')
      loop
        if jsonb_typeof(v_obs) <> 'object' then
          raise exception 'WNPH batch intake: observation under % must be an object',v_asset_key;
        end if;
        v_observation_key := btrim(coalesce(v_obs->>'observation_key',''));
        if v_observation_key='' then
          raise exception 'WNPH batch intake: observation under % requires observation_key',v_asset_key;
        end if;

        select o.* into v_existing_obs
        from wnph.publication_source_observations o
        where o.source_asset_id=v_asset_id
          and o.observation_key=v_observation_key
          and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id)
        order by o.created_at desc
        limit 1;

        if v_existing_obs.id is not null then
          if v_existing_obs.observation_kind <> coalesce(v_obs->>'observation_kind','')
             or coalesce(v_existing_obs.text_candidate,'') <> coalesce(v_obs->>'text_candidate','')
             or v_existing_obs.source_format <> coalesce(v_obs->>'source_format','')
             or v_existing_obs.processor <> coalesce(v_obs->'processor','{}'::jsonb) then
            raise exception 'WNPH batch intake: active observation % on % exists with different content/provenance',v_observation_key,v_asset_key;
          end if;
          v_skipped_observations := v_skipped_observations + 1;
        else
          insert into wnph.publication_source_observations(
            source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,
            x,y,width,height,confidence,derivation_method,source_format,processor,external_locator,metadata
          ) values (
            v_asset_id,
            v_observation_key,
            coalesce(v_obs->>'observation_kind','page_text'),
            case when v_obs ? 'ordinal' then (v_obs->>'ordinal')::integer else null end,
            v_obs->>'text_candidate',
            coalesce(v_obs->>'coordinate_unit','surface'),
            case when v_obs ? 'x' then (v_obs->>'x')::numeric else null end,
            case when v_obs ? 'y' then (v_obs->>'y')::numeric else null end,
            case when v_obs ? 'width' then (v_obs->>'width')::numeric else null end,
            case when v_obs ? 'height' then (v_obs->>'height')::numeric else null end,
            case when v_obs ? 'confidence' then (v_obs->>'confidence')::numeric else null end,
            coalesce(v_obs->>'derivation_method','batch_import'),
            coalesce(v_obs->>'source_format','plain_text'),
            coalesce(v_obs->'processor','{}'::jsonb),
            coalesce(v_obs->'external_locator','{}'::jsonb),
            coalesce(v_obs->'metadata','{}'::jsonb) || jsonb_build_object(
              'batch_input_kind',p_input_kind,
              'batch_source_ref',p_source_ref
            )
          );
          v_inserted_observations := v_inserted_observations + 1;
        end if;
      end loop;
    end if;

    v_existing := null;
  end loop;

  return jsonb_build_object(
    'source_package_key',p_source_package_key,
    'input_kind',p_input_kind,
    'source_ref',p_source_ref,
    'surface_count',v_surface_count,
    'inserted_surfaces',v_inserted_surfaces,
    'skipped_surfaces',v_skipped_surfaces,
    'inserted_observations',v_inserted_observations,
    'skipped_observations',v_skipped_observations
  );
end;
$function$;

revoke all on function public.wnph_ingest_source_surface_batch_v1(text,text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.wnph_ingest_source_surface_batch_v1(text,text,text,jsonb,jsonb) to service_role;

comment on function public.wnph_ingest_source_surface_batch_v1(text,text,text,jsonb,jsonb) is
  'Atomic, idempotent normalized batch intake boundary for WNPH source surfaces and located observations. External adapters normalize IIIF manifests, image/photo lists, or PDF page inventories into this contract; semantic publication blocks are intentionally untouched.';

do $verify$
declare
  v_result jsonb;
  v_surface_count_before integer;
  v_surface_count_after integer;
begin
  select count(*) into v_surface_count_before
  from wnph.publication_source_assets
  where source_package_id=(select id from wnph.publication_source_packages where canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1' order by created_at desc limit 1)
    and asset_role='source_surface';

  select public.wnph_ingest_source_surface_batch_v1(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'image_list',
    'fixture://existing-dewy-surface',
    jsonb_build_array(jsonb_build_object(
      'asset_key','dewy:loc:source-surface:0015',
      'media_type','image/jpeg',
      'source_locator',(select source_locator from wnph.publication_source_assets where asset_key='dewy:loc:source-surface:0015' order by created_at desc limit 1),
      'metadata',jsonb_build_object('fixture','idempotency')
    )),
    jsonb_build_object('fixture','idempotency')
  ) into v_result;

  if (v_result->>'inserted_surfaces')::integer<>0 or (v_result->>'skipped_surfaces')::integer<>1 then
    raise exception 'WNPH batch intake idempotency fixture failed: %',v_result;
  end if;

  select count(*) into v_surface_count_after
  from wnph.publication_source_assets
  where source_package_id=(select id from wnph.publication_source_packages where canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1' order by created_at desc limit 1)
    and asset_role='source_surface';

  if v_surface_count_before<>v_surface_count_after then
    raise exception 'WNPH batch intake idempotency fixture changed surface count % -> %',v_surface_count_before,v_surface_count_after;
  end if;
end;
$verify$;