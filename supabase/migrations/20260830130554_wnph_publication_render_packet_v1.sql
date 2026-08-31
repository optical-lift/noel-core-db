create or replace function public.wnph_publication_render_packet_v1(p_expression_key text)
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
  if v_expr.id is null then raise exception 'WNPH render packet: Expression not found' using errcode='P0002'; end if;
  select * into v_work from wnph.historical_works where id=v_expr.work_id;
  v_snapshot:=public.wnph_publication_expression_snapshot_v2(p_expression_key);

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

  select coalesce(jsonb_agg(jsonb_build_object('placement_key',placement_key,'sequence_ordinal',sequence_ordinal,'media_role',media_role,'anchor_kind',anchor_kind,'anchor_block_key',anchor_block_key,'anchor_data',anchor_data,'placement_policy',placement_policy,'accessibility',accessibility,'source_asset_key',source_asset_key,'media_type',media_type,'source_locator',source_locator,'storage_uri',storage_uri) order by sequence_ordinal,placement_key),'[]'::jsonb)
  into v_media from public.v_wnph_expression_media_input_v1 where expression_key=p_expression_key;

  with active as (
    select b.* from wnph.publication_expression_blocks b where b.expression_id=v_expr.id and not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id) and b.publication_state='admitted'
  )
  select coalesce(jsonb_agg(jsonb_build_object('chapter_number',c.ordinal,'chapter_block_key',c.block_key,'chapter_label',c.text_content,'chapter_title',t.text_content,'paragraph_count',(select count(*) from active p where p.parent_block_id=c.id and p.block_type='paragraph')) order by c.ordinal),'[]'::jsonb)
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
  where d.publication_expression_id=v_expr.id and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id);

  return jsonb_build_object(
    'contract_version','wnph_publication_render_packet_v1',
    'master_snapshot',v_snapshot,
    'bibliographic',jsonb_build_object('work_key',v_work.canonical_key,'title',v_work.canonical_label,'work_type',v_work.work_type,'language_code',v_work.language_code,'expression_key',v_expr.canonical_key,'expression_type',v_expr.expression_type,'creators',v_creators),
    'rights',v_rights,
    'chapters',v_chapters,
    'ordered_blocks',v_blocks,
    'media_placements',v_media,
    'render_targets',v_targets,
    'truth_boundaries',jsonb_build_object('publication_expression_is_render_authority',true,'source_image_verification_is_parallel_not_blocking',true,'media_geometry_owned_by_manifestation',true,'same_master_for_all_targets',true)
  );
end;
$$;
revoke all on function public.wnph_publication_render_packet_v1(text) from public,anon,authenticated;
grant execute on function public.wnph_publication_render_packet_v1(text) to service_role;
comment on function public.wnph_publication_render_packet_v1(text) is 'Returns one deterministic WNPH publication handoff packet: bibliographic authority, ordered Expression blocks, governed media placements, rights, chapter structure, and all active Manifestation render targets with per-profile build fingerprints.';