create or replace function public.wnph_publication_render_packet_v3(p_expression_key text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','wnph','public'
as $function$
declare
  v_expr wnph.expressions%rowtype;
  v_work wnph.historical_works%rowtype;
  v_snapshot jsonb;
  v_creators jsonb;
  v_rights jsonb;
  v_blocks jsonb;
  v_media jsonb;
  v_chapters jsonb;
  v_targets jsonb;
begin
  select * into v_expr from wnph.expressions where canonical_key=p_expression_key;
  if v_expr.id is null then raise exception 'WNPH render packet v3: Expression not found' using errcode='P0002'; end if;
  select * into v_work from wnph.historical_works where id=v_expr.work_id;
  v_snapshot:=public.wnph_publication_expression_snapshot_v4(p_expression_key);

  select coalesce(jsonb_agg(jsonb_build_object('creator_key',ca.canonical_key,'label',ca.preferred_label,'role',c.role,'credit_status',c.credit_status) order by c.role,ca.preferred_label),'[]'::jsonb)
  into v_creators
  from wnph.work_creator_credits c join wnph.creator_authorities ca on ca.id=c.creator_id
  where c.work_id=v_expr.work_id and not exists(select 1 from wnph.work_creator_credits x where x.supersedes_credit_id=c.id);

  select coalesce(jsonb_agg(jsonb_build_object('component_type',rc.component_type,'component_status',rc.component_status,'use_scope',rc.use_scope,'rationale',rc.rationale) order by rc.component_type,rc.created_at),'[]'::jsonb)
  into v_rights
  from wnph.rights_components rc
  where rc.work_id=v_expr.work_id and not exists(select 1 from wnph.rights_components x where x.supersedes_component_id=rc.id);

  select coalesce(jsonb_agg(jsonb_build_object('render_path',render_path,'block_key',block_key,'ordinal',ordinal,'block_type',block_type,'semantic_role',semantic_role,'text_content',text_content) order by render_path),'[]'::jsonb)
  into v_blocks from public.v_wnph_expression_render_input_v1 where expression_key=p_expression_key;

  select coalesce(jsonb_agg(jsonb_build_object(
    'placement_key',m.placement_key,
    'sequence_ordinal',m.sequence_ordinal,
    'media_role',m.media_role,
    'anchor_kind',m.anchor_kind,
    'anchor_block_key',m.anchor_block_key,
    'anchor_data',m.anchor_data,
    'placement_policy',m.placement_policy,
    'accessibility',m.accessibility,
    'source_asset_key',m.source_asset_key,
    'source_media_type',m.media_type,
    'source_locator',m.source_locator,
    'storage_uri',m.storage_uri,
    'publication_raster',jsonb_build_object(
      'receipt_key',r.receipt_key,
      'fetch_uri',r.fetch_uri,
      'media_type',r.receipt_media_type,
      'byte_length',r.byte_length,
      'sha256',r.raster_sha256
    )
  ) order by m.sequence_ordinal,m.placement_key),'[]'::jsonb)
  into v_media
  from public.v_wnph_expression_media_input_v1 m
  left join public.v_wnph_expression_selected_publication_raster_v1 r
    on r.expression_key=m.expression_key and r.placement_key=m.placement_key
  where m.expression_key=p_expression_key;

  with active as (
    select b.* from wnph.publication_expression_blocks b
    where b.expression_id=v_expr.id
      and not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id)
      and b.publication_state='admitted'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'chapter_number',c.ordinal,
    'chapter_block_key',c.block_key,
    'chapter_label',c.text_content,
    'chapter_title',t.text_content,
    'paragraph_count',(select count(*) from active p where p.parent_block_id=c.id and p.block_type='paragraph')
  ) order by c.ordinal),'[]'::jsonb)
  into v_chapters
  from active c left join active t on t.parent_block_id=c.id and t.semantic_role='chapter_title'
  where c.block_type='chapter';

  select coalesce(jsonb_agg(jsonb_build_object(
    'output_family',r.output_family,
    'render_profile_key',r.canonical_key,
    'profile_version',r.profile_version,
    'profile_rules',r.rules,
    'profile_sha256',encode(extensions.digest(convert_to(r.canonical_key||'|'||r.profile_version||'|'||r.rules::text,'UTF8'),'sha256'),'hex'),
    'manifestation_key',m.canonical_key,
    'manifestation_status',m.status,
    'derivation_status',d.derivation_status,
    'build_fingerprint_sha256',encode(extensions.digest(convert_to((v_snapshot->>'render_master_sha256')||'|'||r.canonical_key||'|'||r.profile_version||'|'||r.rules::text,'UTF8'),'sha256'),'hex')
  ) order by r.output_family),'[]'::jsonb)
  into v_targets
  from wnph.publication_manifestation_derivations d
  join wnph.publication_render_profiles r on r.id=d.render_profile_id
  join wnph.manifestations m on m.id=d.manifestation_id
  where d.publication_expression_id=v_expr.id
    and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id);

  return jsonb_build_object(
    'contract_version','wnph_publication_render_packet_v3',
    'reproducible_build_ready',coalesce((v_snapshot->>'reproducible_build_ready')::boolean,false),
    'master_snapshot',v_snapshot,
    'bibliographic',jsonb_build_object('work_key',v_work.canonical_key,'title',v_work.canonical_label,'work_type',v_work.work_type,'language_code',v_work.language_code,'expression_key',v_expr.canonical_key,'expression_type',v_expr.expression_type,'creators',v_creators),
    'rights',v_rights,
    'chapters',v_chapters,
    'ordered_blocks',v_blocks,
    'media_placements',v_media,
    'render_targets',v_targets,
    'truth_boundaries',jsonb_build_object(
      'publication_expression_is_render_authority',true,
      'source_image_verification_is_parallel_not_blocking',true,
      'media_geometry_owned_by_manifestation',true,
      'same_master_for_all_targets',true,
      'selected_publication_raster_bytes_content_addressed',true,
      'reproducible_build_requires_zero_unreceipted_media',true
    )
  );
end;
$function$;

revoke all on function public.wnph_publication_render_packet_v3(text) from public, anon, authenticated;
grant execute on function public.wnph_publication_render_packet_v3(text) to service_role;

create or replace function public.wnph_create_publication_release_v2(
  p_expression_key text,
  p_public_slug text,
  p_release_key text,
  p_supersedes_release_key text default null,
  p_decision_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','wnph','public','extensions'
as $function$
declare
  v_expr wnph.expressions%rowtype;
  v_work wnph.historical_works%rowtype;
  v_packet jsonb;
  v_snapshot jsonb;
  v_prior wnph.publication_releases%rowtype;
  v_active wnph.publication_releases%rowtype;
  v_release_sequence integer;
  v_released_at timestamptz := clock_timestamp();
  v_public_media jsonb;
  v_public_rights jsonb;
  v_payload jsonb;
  v_payload_sha text;
  v_new_id uuid;
begin
  if p_public_slug is null or p_public_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'WNPH publication release v2: invalid public slug' using errcode='22023';
  end if;
  if p_release_key is null or btrim(p_release_key)='' then
    raise exception 'WNPH publication release v2: release key required' using errcode='22023';
  end if;

  select * into v_expr from wnph.expressions where canonical_key=p_expression_key;
  if v_expr.id is null then raise exception 'WNPH publication release v2: Expression not found' using errcode='P0002'; end if;
  select * into v_work from wnph.historical_works where id=v_expr.work_id;

  v_packet := public.wnph_publication_render_packet_v3(p_expression_key);
  v_snapshot := v_packet->'master_snapshot';
  if coalesce((v_packet->>'reproducible_build_ready')::boolean,false) is not true
     or coalesce((v_snapshot->>'unreceipted_media_count')::integer,0) <> 0 then
    raise exception 'WNPH publication release v2: Expression is not reproducible-build ready' using errcode='55000';
  end if;

  select r.* into v_active
  from wnph.publication_releases r
  where r.work_id=v_work.id
    and not exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id)
  order by r.release_sequence desc limit 1;

  if p_supersedes_release_key is null then
    if v_active.id is not null then raise exception 'WNPH publication release v2: active release exists; explicit supersession required' using errcode='55000'; end if;
    v_release_sequence := 1;
  else
    select * into v_prior from wnph.publication_releases where release_key=p_supersedes_release_key;
    if v_prior.id is null then raise exception 'WNPH publication release v2: superseded release not found' using errcode='P0002'; end if;
    if v_prior.work_id <> v_work.id then raise exception 'WNPH publication release v2: supersession cannot cross Works' using errcode='55000'; end if;
    if exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=v_prior.id) then raise exception 'WNPH publication release v2: superseded release is no longer active' using errcode='55000'; end if;
    if v_active.id is distinct from v_prior.id then raise exception 'WNPH publication release v2: supersession target is not the active Work release' using errcode='55000'; end if;
    v_release_sequence := v_prior.release_sequence + 1;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'placement_key',m->>'placement_key',
      'sequence_ordinal',(m->>'sequence_ordinal')::integer,
      'media_role',m->>'media_role',
      'anchor_kind',m->>'anchor_kind',
      'anchor_block_key',m->'anchor_block_key',
      'anchor_data',coalesce(m->'anchor_data','{}'::jsonb),
      'placement_policy',coalesce(m->'placement_policy','{}'::jsonb),
      'accessibility',coalesce(m->'accessibility','{}'::jsonb),
      'image',jsonb_build_object(
        'url',m#>>'{publication_raster,fetch_uri}',
        'media_type',m#>>'{publication_raster,media_type}',
        'byte_length',(m#>>'{publication_raster,byte_length}')::bigint,
        'sha256',m#>>'{publication_raster,sha256}'
      )
    ) order by (m->>'sequence_ordinal')::integer, m->>'placement_key'
  ),'[]'::jsonb)
  into v_public_media
  from jsonb_array_elements(v_packet->'media_placements') m;

  select coalesce(jsonb_agg(
    jsonb_build_object('component_type',r->>'component_type','status',r->>'component_status','use_scope',r->>'use_scope')
    order by r->>'component_type'
  ),'[]'::jsonb)
  into v_public_rights
  from jsonb_array_elements(v_packet->'rights') r;

  v_payload := jsonb_build_object(
    'contract_version','wnph_publication_public_release_payload_v1',
    'release',jsonb_build_object(
      'release_key',p_release_key,
      'public_slug',p_public_slug,
      'release_sequence',v_release_sequence,
      'released_at',to_jsonb(v_released_at),
      'render_master_sha256',v_snapshot->>'render_master_sha256',
      'frozen',true,
      'read_only',true
    ),
    'bibliographic',v_packet->'bibliographic',
    'rights',v_public_rights,
    'chapters',v_packet->'chapters',
    'ordered_blocks',v_packet->'ordered_blocks',
    'media_placements',v_public_media,
    'public_provenance',jsonb_build_object(
      'publisher','Write Now Publishing House',
      'publication_expression_is_private_authority',true,
      'public_release_is_downstream_manifestation',true,
      'source_and_editorial_custody_not_exposed',true,
      'content_addressed_master',true,
      'selected_raster_contract','explicit-selected-governed-raster:v1'
    )
  );

  v_payload_sha := encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');

  insert into wnph.publication_releases(
    release_key,public_slug,work_id,expression_id,release_sequence,release_state,
    render_master_sha256,public_payload,payload_sha256,supersedes_release_id,
    decision_basis,released_at
  ) values (
    p_release_key,p_public_slug,v_work.id,v_expr.id,v_release_sequence,'released',
    v_snapshot->>'render_master_sha256',v_payload,v_payload_sha,v_prior.id,
    coalesce(p_decision_basis,'{}'::jsonb),v_released_at
  ) returning id into v_new_id;

  return jsonb_build_object(
    'release_id',v_new_id,
    'release_key',p_release_key,
    'release_sequence',v_release_sequence,
    'render_master_sha256',v_snapshot->>'render_master_sha256',
    'payload_sha256',v_payload_sha,
    'public_slug',p_public_slug
  );
end;
$function$;

revoke all on function public.wnph_create_publication_release_v2(text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.wnph_create_publication_release_v2(text,text,text,text,jsonb) to service_role;