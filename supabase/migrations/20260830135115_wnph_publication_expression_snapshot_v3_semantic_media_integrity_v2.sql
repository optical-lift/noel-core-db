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
  if v_expr is null then raise exception 'WNPH expression snapshot v3: Expression not found' using errcode='P0002'; end if;

  select count(*),count(*) filter(where text_content is not null),
         string_agg(render_path||'|'||block_key||'|'||block_type||'|'||semantic_role||'|'||coalesce(text_content,''),E'\n' order by render_path)
  into v_blocks,v_text,v_text_payload
  from public.v_wnph_expression_render_input_v1
  where expression_key=p_expression_key;

  select count(*),
         count(*) filter(where r.raster_sha256 is not null),
         count(*) filter(where r.raster_sha256 is null),
         string_agg(
           lpad(m.sequence_ordinal::text,6,'0')||'|'||m.placement_key||'|'||m.media_role||'|'||m.anchor_kind||'|'||
           coalesce(m.anchor_block_key,'')||'|'||m.source_asset_key||'|'||m.anchor_data::text||'|'||m.placement_policy::text||'|'||m.accessibility::text||'|'||
           coalesce(r.receipt_key,'MISSING')||'|'||coalesce(r.fetch_uri,'MISSING')||'|'||coalesce(r.receipt_media_type,'MISSING')||'|'||
           coalesce(r.byte_length::text,'MISSING')||'|'||coalesce(r.raster_sha256,'MISSING'),
           E'\n' order by m.sequence_ordinal,m.placement_key
         )
  into v_media,v_receipts,v_missing,v_media_payload
  from public.v_wnph_expression_media_input_v1 m
  left join public.v_wnph_expression_publication_raster_input_v1 r
    on r.expression_key=m.expression_key and r.placement_key=m.placement_key
  where m.expression_key=p_expression_key;

  v_hash:=encode(extensions.digest(convert_to(
    'WNPH_PUBLICATION_EXPRESSION_SNAPSHOT_V3'||E'\nTEXT\n'||coalesce(v_text_payload,'')||
    E'\nSEMANTIC_MEDIA_WITH_RASTER_RECEIPTS\n'||coalesce(v_media_payload,''),'UTF8'),'sha256'),'hex');

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
    'semantic_media_fields_hashed',jsonb_build_array('sequence_ordinal','placement_key','media_role','anchor_kind','anchor_block_key','source_asset_key','anchor_data','placement_policy','accessibility'),
    'render_master_sha256',v_hash
  );
end;
$$;

select public.wnph_refresh_expression_manifestation_derivations_v2('wish-fairy-dewy-dear:wnph-publication-e1');