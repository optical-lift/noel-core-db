create or replace view public.v_wnph_expression_publication_raster_input_v1 as
with active_placements as (
  select p.*
  from wnph.publication_expression_media_placements p
  where not exists (
    select 1 from wnph.publication_expression_media_placements c
    where c.supersedes_placement_id=p.id
  )
), active_receipts as (
  select r.*
  from wnph.publication_expression_media_source_receipts r
  where r.receipt_key='publication-raster:full-1800:v1'
    and not exists (
      select 1 from wnph.publication_expression_media_source_receipts c
      where c.supersedes_receipt_id=r.id
    )
)
select
  e.canonical_key as expression_key,
  p.id as placement_id,
  p.placement_key,
  p.sequence_ordinal,
  p.media_role,
  a.asset_key as source_asset_key,
  r.id as receipt_id,
  r.receipt_key,
  r.fetch_uri,
  r.media_type as receipt_media_type,
  r.byte_length,
  r.sha256 as raster_sha256,
  r.created_at as receipt_created_at
from active_placements p
join wnph.expressions e on e.id=p.expression_id
join wnph.publication_source_assets a on a.id=p.source_asset_id
left join active_receipts r
  on r.expression_id=p.expression_id
 and r.placement_id=p.id
 and r.source_asset_id=p.source_asset_id;

create or replace function public.wnph_publication_expression_snapshot_v3(p_expression_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','wnph','public'
as $$
declare
  v_expr uuid;
  v_blocks integer;
  v_text integer;
  v_media integer;
  v_receipts integer;
  v_missing integer;
  v_text_payload text;
  v_media_payload text;
  v_hash text;
begin
  select id into v_expr from wnph.expressions where canonical_key=p_expression_key;
  if v_expr is null then
    raise exception 'WNPH expression snapshot v3: Expression not found' using errcode='P0002';
  end if;

  select count(*),
         count(*) filter(where text_content is not null),
         string_agg(render_path||'|'||block_key||'|'||block_type||'|'||semantic_role||'|'||coalesce(text_content,''),E'\n' order by render_path)
  into v_blocks,v_text,v_text_payload
  from public.v_wnph_expression_render_input_v1
  where expression_key=p_expression_key;

  select count(*),
         count(*) filter(where raster_sha256 is not null),
         count(*) filter(where raster_sha256 is null),
         string_agg(
           lpad(sequence_ordinal::text,6,'0')||'|'||placement_key||'|'||media_role||'|'||source_asset_key||'|'||
           coalesce(receipt_key,'MISSING')||'|'||coalesce(fetch_uri,'MISSING')||'|'||coalesce(receipt_media_type,'MISSING')||'|'||
           coalesce(byte_length::text,'MISSING')||'|'||coalesce(raster_sha256,'MISSING'),
           E'\n' order by sequence_ordinal,placement_key
         )
  into v_media,v_receipts,v_missing,v_media_payload
  from public.v_wnph_expression_publication_raster_input_v1
  where expression_key=p_expression_key;

  v_hash:=encode(extensions.digest(convert_to(
    'WNPH_PUBLICATION_EXPRESSION_SNAPSHOT_V3'||E'\nTEXT\n'||coalesce(v_text_payload,'')||
    E'\nMEDIA_WITH_RASTER_RECEIPTS\n'||coalesce(v_media_payload,''),
    'UTF8'),'sha256'),'hex');

  return jsonb_build_object(
    'contract_version','wnph_publication_expression_snapshot_v3',
    'expression_key',p_expression_key,
    'admitted_block_count',coalesce(v_blocks,0),
    'text_block_count',coalesce(v_text,0),
    'media_placement_count',coalesce(v_media,0),
    'media_receipt_count',coalesce(v_receipts,0),
    'unreceipted_media_count',coalesce(v_missing,0),
    'reproducible_build_ready',coalesce(v_missing,0)=0,
    'publication_raster_contract','publication-raster:full-1800:v1',
    'render_master_sha256',v_hash
  );
end;
$$;

create or replace function public.wnph_refresh_expression_manifestation_derivations_v2(p_expression_key text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public'
as $$
declare
  v_expression wnph.expressions%rowtype;
  v_snapshot jsonb;
  v_current_hash text;
  v_old record;
  v_new_id uuid;
  v_results jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  select * into v_expression from wnph.expressions where canonical_key=p_expression_key;
  if v_expression.id is null then
    raise exception 'WNPH manifestation fanout v2: Expression not found' using errcode='P0002';
  end if;

  v_snapshot:=public.wnph_publication_expression_snapshot_v3(p_expression_key);
  if coalesce((v_snapshot->>'reproducible_build_ready')::boolean,false) is not true then
    raise exception 'WNPH manifestation fanout v2: publication master has % unreceipted media placements',v_snapshot->>'unreceipted_media_count' using errcode='55000';
  end if;
  v_current_hash:=v_snapshot->>'render_master_sha256';
  if coalesce(v_current_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'WNPH manifestation fanout v2: Expression snapshot hash missing or malformed' using errcode='55000';
  end if;

  for v_old in
    select d.*,r.canonical_key as render_profile_key,r.output_family,m.canonical_key as manifestation_key
    from wnph.publication_manifestation_derivations d
    join wnph.publication_render_profiles r on r.id=d.render_profile_id
    join wnph.manifestations m on m.id=d.manifestation_id
    where d.publication_expression_id=v_expression.id
      and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id)
    order by r.canonical_key,m.canonical_key
  loop
    v_count:=v_count+1;
    if coalesce(v_old.build_metadata->'master_snapshot'->>'render_master_sha256','')=v_current_hash
       and coalesce(v_old.build_metadata->'master_snapshot'->>'contract_version','')='wnph_publication_expression_snapshot_v3' then
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'render_profile_key',v_old.render_profile_key,
        'manifestation_key',v_old.manifestation_key,
        'derivation_id',v_old.id,
        'action','unchanged',
        'render_master_sha256',v_current_hash
      ));
    else
      insert into wnph.publication_manifestation_derivations(
        source_package_id,publication_expression_id,render_profile_id,manifestation_id,
        derivation_status,build_metadata,supersedes_derivation_id
      ) values(
        null,v_expression.id,v_old.render_profile_id,v_old.manifestation_id,
        'planned',
        coalesce(v_old.build_metadata,'{}'::jsonb)||jsonb_build_object(
          'master_snapshot',v_snapshot,
          'master_authority','publication_expression',
          'publication_raster_contract','publication-raster:full-1800:v1',
          'exact_media_bytes_receipted',true,
          'source_image_verification_is_parallel_not_blocking',true,
          'fanout_contract','wnph_refresh_expression_manifestation_derivations_v2',
          'output_family',v_old.output_family,
          'supersession_reason','publication_expression_snapshot_v3_or_raster_receipt_changed',
          'previous_render_master_sha256',v_old.build_metadata->'master_snapshot'->>'render_master_sha256',
          'refreshed_at',now()
        ),
        v_old.id
      ) returning id into v_new_id;

      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'render_profile_key',v_old.render_profile_key,
        'manifestation_key',v_old.manifestation_key,
        'derivation_id',v_new_id,
        'supersedes_derivation_id',v_old.id,
        'action','superseded_to_current_snapshot_v3',
        'render_master_sha256',v_current_hash
      ));
    end if;
  end loop;

  if v_count=0 then
    raise exception 'WNPH manifestation fanout v2: no active manifestation derivations are attached to Expression %',p_expression_key using errcode='P0002';
  end if;

  return jsonb_build_object(
    'contract_version','wnph_refresh_expression_manifestation_derivations_v2',
    'expression_key',p_expression_key,
    'master_snapshot',v_snapshot,
    'manifestation_count',v_count,
    'results',v_results
  );
end;
$$;

create or replace function public.wnph_publication_render_packet_v2(p_expression_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','wnph','public'
as $$
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
  if v_expr.id is null then raise exception 'WNPH render packet v2: Expression not found' using errcode='P0002'; end if;
  select * into v_work from wnph.historical_works where id=v_expr.work_id;
  v_snapshot:=public.wnph_publication_expression_snapshot_v3(p_expression_key);

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
  left join public.v_wnph_expression_publication_raster_input_v1 r
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
    'contract_version','wnph_publication_render_packet_v2',
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
      'exact_publication_raster_bytes_content_addressed',true,
      'reproducible_build_requires_zero_unreceipted_media',true
    )
  );
end;
$$;

revoke all on function public.wnph_publication_expression_snapshot_v3(text) from public,anon,authenticated;
grant execute on function public.wnph_publication_expression_snapshot_v3(text) to service_role;
revoke all on function public.wnph_refresh_expression_manifestation_derivations_v2(text) from public,anon,authenticated;
grant execute on function public.wnph_refresh_expression_manifestation_derivations_v2(text) to service_role;
revoke all on function public.wnph_publication_render_packet_v2(text) from public,anon,authenticated;
grant execute on function public.wnph_publication_render_packet_v2(text) to service_role;
grant select on public.v_wnph_expression_publication_raster_input_v1 to service_role;

comment on function public.wnph_publication_expression_snapshot_v3(text) is 'Content-addressed WNPH Publication Expression snapshot over admitted text, semantic media placements, and exact active publication raster receipts. Reports unreceipted_media_count and reproducible_build_ready.';
comment on function public.wnph_publication_render_packet_v2(text) is 'Single renderer handoff packet for a WNPH Publication Expression, including exact content-addressed publication raster receipts and deterministic per-target build fingerprints.';

select public.wnph_refresh_expression_manifestation_derivations_v2('wish-fairy-dewy-dear:wnph-publication-e1');