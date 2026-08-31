create table wnph.publication_expression_media_placements(
  id uuid primary key default gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  placement_key text not null,
  source_asset_id uuid not null references wnph.publication_source_assets(id),
  media_role text not null check(media_role in ('frontispiece','interior_color_plate','illustration','decorative','facsimile','cover_art')),
  sequence_ordinal integer not null check(sequence_ordinal>=0),
  anchor_kind text not null check(anchor_kind in ('front_matter','source_surface_boundary','before_block','after_block','within_block_source_boundary','expression_end')),
  anchor_block_id uuid references wnph.publication_expression_blocks(id),
  anchor_data jsonb not null default '{}'::jsonb,
  placement_policy jsonb not null default '{}'::jsonb,
  accessibility jsonb not null default '{}'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  supersedes_placement_id uuid references wnph.publication_expression_media_placements(id),
  created_at timestamptz not null default now(),
  check(supersedes_placement_id is null or supersedes_placement_id<>id),
  check(jsonb_typeof(anchor_data)='object'),
  check(jsonb_typeof(placement_policy)='object'),
  check(jsonb_typeof(accessibility)='object'),
  check(jsonb_typeof(evidence)='object')
);

create unique index publication_expression_media_one_root_uidx
on wnph.publication_expression_media_placements(expression_id,placement_key)
where supersedes_placement_id is null;
create unique index publication_expression_media_one_child_uidx
on wnph.publication_expression_media_placements(supersedes_placement_id)
where supersedes_placement_id is not null;
create index publication_expression_media_expression_idx
on wnph.publication_expression_media_placements(expression_id,sequence_ordinal);

create or replace function wnph.validate_publication_expression_media_placement_v1()
returns trigger language plpgsql set search_path='pg_catalog','wnph','public' as $$
declare v_expr_work uuid; v_asset_work uuid; v_anchor_expr uuid;
begin
  if tg_op='UPDATE' then raise exception 'WNPH expression media placement: immutable; supersede with a new row' using errcode='55000'; end if;
  select work_id into v_expr_work from wnph.expressions where id=new.expression_id;
  select e.work_id into v_asset_work
  from wnph.publication_source_assets a
  join wnph.publication_source_packages sp on sp.id=a.source_package_id
  join wnph.expressions e on e.id=sp.expression_id
  where a.id=new.source_asset_id;
  if v_expr_work is null or v_asset_work is null or v_expr_work is distinct from v_asset_work then
    raise exception 'WNPH expression media placement: media asset must belong to the same Work' using errcode='55000';
  end if;
  if new.anchor_block_id is not null then
    select expression_id into v_anchor_expr from wnph.publication_expression_blocks where id=new.anchor_block_id;
    if v_anchor_expr is distinct from new.expression_id then raise exception 'WNPH expression media placement: anchor block must belong to the same Expression' using errcode='55000'; end if;
  elsif new.anchor_kind in ('before_block','after_block','within_block_source_boundary') then
    raise exception 'WNPH expression media placement: block anchor kind requires anchor_block_id' using errcode='22023';
  end if;
  if new.supersedes_placement_id is not null then
    if not exists(select 1 from wnph.publication_expression_media_placements p where p.id=new.supersedes_placement_id and p.expression_id=new.expression_id and p.placement_key=new.placement_key) then
      raise exception 'WNPH expression media placement: supersession must preserve Expression and placement key' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=new.supersedes_placement_id) then
      raise exception 'WNPH expression media placement: supersession fork is not allowed' using errcode='55000';
    end if;
  elsif exists(select 1 from wnph.publication_expression_media_placements p where p.expression_id=new.expression_id and p.placement_key=new.placement_key and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id)) then
    raise exception 'WNPH expression media placement: active placement key already exists; supersede explicitly' using errcode='23505';
  end if;
  return new;
end; $$;

create trigger publication_expression_media_validate
before insert or update on wnph.publication_expression_media_placements
for each row execute function wnph.validate_publication_expression_media_placement_v1();
create trigger publication_expression_media_append_only
before delete on wnph.publication_expression_media_placements
for each row execute function wnph.reject_append_only_mutation();

alter table wnph.publication_expression_media_placements enable row level security;
revoke all on wnph.publication_expression_media_placements from public,anon,authenticated,service_role;

create or replace function public.wnph_attach_publication_expression_media_v1(
 p_expression_key text,p_placement_key text,p_source_asset_key text,p_media_role text,p_sequence_ordinal integer,p_anchor_kind text,
 p_anchor_block_key text default null,p_anchor_data jsonb default '{}'::jsonb,p_placement_policy jsonb default '{}'::jsonb,
 p_accessibility jsonb default '{}'::jsonb,p_evidence jsonb default '{}'::jsonb,p_supersedes_placement_key text default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_expr wnph.expressions%rowtype; v_asset wnph.publication_source_assets%rowtype; v_anchor uuid; v_old uuid; v_id uuid;
begin
 select * into v_expr from wnph.expressions where canonical_key=p_expression_key;
 if v_expr.id is null then raise exception 'WNPH media placement: Expression not found' using errcode='P0002'; end if;
 select a.* into v_asset from wnph.publication_source_assets a join wnph.publication_source_packages sp on sp.id=a.source_package_id join wnph.expressions se on se.id=sp.expression_id
 where a.asset_key=p_source_asset_key and se.work_id=v_expr.work_id and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id)
 order by a.created_at desc limit 1;
 if v_asset.id is null then raise exception 'WNPH media placement: active source asset not found for this Work' using errcode='P0002'; end if;
 if p_anchor_block_key is not null then
   select b.id into v_anchor from wnph.publication_expression_blocks b where b.expression_id=v_expr.id and b.block_key=p_anchor_block_key and not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id) order by b.created_at desc limit 1;
   if v_anchor is null then raise exception 'WNPH media placement: active anchor block not found' using errcode='P0002'; end if;
 end if;
 if p_supersedes_placement_key is not null then
   select p.id into v_old from wnph.publication_expression_media_placements p where p.expression_id=v_expr.id and p.placement_key=p_supersedes_placement_key and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id) order by p.created_at desc limit 1;
   if v_old is null or p_supersedes_placement_key<>p_placement_key then raise exception 'WNPH media placement: supersession must target active placement with same key' using errcode='55000'; end if;
 end if;
 insert into wnph.publication_expression_media_placements(expression_id,placement_key,source_asset_id,media_role,sequence_ordinal,anchor_kind,anchor_block_id,anchor_data,placement_policy,accessibility,evidence,supersedes_placement_id)
 values(v_expr.id,p_placement_key,v_asset.id,p_media_role,p_sequence_ordinal,p_anchor_kind,v_anchor,coalesce(p_anchor_data,'{}'::jsonb),coalesce(p_placement_policy,'{}'::jsonb),coalesce(p_accessibility,'{}'::jsonb),coalesce(p_evidence,'{}'::jsonb),v_old)
 returning id into v_id;
 return jsonb_build_object('placement_id',v_id,'expression_key',p_expression_key,'placement_key',p_placement_key,'source_asset_key',p_source_asset_key,'media_role',p_media_role);
end; $$;
revoke all on function public.wnph_attach_publication_expression_media_v1(text,text,text,text,integer,text,text,jsonb,jsonb,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.wnph_attach_publication_expression_media_v1(text,text,text,text,integer,text,text,jsonb,jsonb,jsonb,jsonb,text) to service_role;

create or replace view public.v_wnph_expression_media_input_v1 as
select e.canonical_key expression_key,p.placement_key,p.sequence_ordinal,p.media_role,p.anchor_kind,b.block_key anchor_block_key,p.anchor_data,p.placement_policy,p.accessibility,a.asset_key source_asset_key,a.media_type,a.source_locator,a.storage_uri
from wnph.publication_expression_media_placements p
join wnph.expressions e on e.id=p.expression_id
join wnph.publication_source_assets a on a.id=p.source_asset_id
left join wnph.publication_expression_blocks b on b.id=p.anchor_block_id
where not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id);
grant select on public.v_wnph_expression_media_input_v1 to service_role;

create or replace function public.wnph_publication_expression_snapshot_v2(p_expression_key text)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','wnph','public' as $$
declare v_expr uuid; v_blocks integer; v_text integer; v_media integer; v_text_payload text; v_media_payload text; v_hash text;
begin
 select id into v_expr from wnph.expressions where canonical_key=p_expression_key;
 if v_expr is null then raise exception 'WNPH expression snapshot v2: Expression not found' using errcode='P0002'; end if;
 select count(*),count(*) filter(where text_content is not null),string_agg(render_path||'|'||block_key||'|'||block_type||'|'||semantic_role||'|'||coalesce(text_content,''),E'\n' order by render_path)
 into v_blocks,v_text,v_text_payload from public.v_wnph_expression_render_input_v1 where expression_key=p_expression_key;
 select count(*),string_agg(lpad(sequence_ordinal::text,6,'0')||'|'||placement_key||'|'||media_role||'|'||anchor_kind||'|'||coalesce(anchor_block_key,'')||'|'||source_asset_key||'|'||anchor_data::text||'|'||placement_policy::text||'|'||accessibility::text,E'\n' order by sequence_ordinal,placement_key)
 into v_media,v_media_payload from public.v_wnph_expression_media_input_v1 where expression_key=p_expression_key;
 v_hash:=encode(extensions.digest(convert_to('TEXT'||E'\n'||coalesce(v_text_payload,'')||E'\nMEDIA\n'||coalesce(v_media_payload,''),'UTF8'),'sha256'),'hex');
 return jsonb_build_object('contract_version','wnph_publication_expression_snapshot_v2','expression_key',p_expression_key,'admitted_block_count',coalesce(v_blocks,0),'text_block_count',coalesce(v_text,0),'media_placement_count',coalesce(v_media,0),'render_master_sha256',v_hash);
end; $$;
revoke all on function public.wnph_publication_expression_snapshot_v2(text) from public,anon,authenticated;
grant execute on function public.wnph_publication_expression_snapshot_v2(text) to service_role;

create or replace function public.wnph_refresh_expression_manifestation_derivations_v2(p_expression_key text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_expression wnph.expressions%rowtype; v_snapshot jsonb; v_hash text; v_old record; v_new uuid; v_results jsonb:='[]'::jsonb; v_count int:=0;
begin
 select * into v_expression from wnph.expressions where canonical_key=p_expression_key;
 if v_expression.id is null then raise exception 'WNPH manifestation fanout v2: Expression not found' using errcode='P0002'; end if;
 v_snapshot:=public.wnph_publication_expression_snapshot_v2(p_expression_key); v_hash:=v_snapshot->>'render_master_sha256';
 for v_old in select d.*,r.canonical_key render_profile_key,r.output_family,m.canonical_key manifestation_key from wnph.publication_manifestation_derivations d join wnph.publication_render_profiles r on r.id=d.render_profile_id join wnph.manifestations m on m.id=d.manifestation_id where d.publication_expression_id=v_expression.id and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id) order by r.canonical_key loop
  v_count:=v_count+1;
  if coalesce(v_old.build_metadata->'master_snapshot'->>'render_master_sha256','')=v_hash and coalesce(v_old.build_metadata->'master_snapshot'->>'contract_version','')='wnph_publication_expression_snapshot_v2' then
   v_results:=v_results||jsonb_build_array(jsonb_build_object('manifestation_key',v_old.manifestation_key,'action','unchanged','render_master_sha256',v_hash));
  else
   insert into wnph.publication_manifestation_derivations(source_package_id,publication_expression_id,render_profile_id,manifestation_id,derivation_status,build_metadata,supersedes_derivation_id)
   values(null,v_expression.id,v_old.render_profile_id,v_old.manifestation_id,'planned',coalesce(v_old.build_metadata,'{}'::jsonb)||jsonb_build_object('master_snapshot',v_snapshot,'master_authority','publication_expression','text_and_media_master',true,'source_image_verification_is_parallel_not_blocking',true,'fanout_contract','wnph_refresh_expression_manifestation_derivations_v2','previous_render_master_sha256',v_old.build_metadata->'master_snapshot'->>'render_master_sha256','refreshed_at',now()),v_old.id) returning id into v_new;
   v_results:=v_results||jsonb_build_array(jsonb_build_object('manifestation_key',v_old.manifestation_key,'action','superseded_to_current_snapshot','derivation_id',v_new,'render_master_sha256',v_hash));
  end if;
 end loop;
 if v_count=0 then raise exception 'WNPH manifestation fanout v2: no active manifestation derivations attached' using errcode='P0002'; end if;
 return jsonb_build_object('contract_version','wnph_refresh_expression_manifestation_derivations_v2','expression_key',p_expression_key,'master_snapshot',v_snapshot,'manifestation_count',v_count,'results',v_results);
end; $$;
revoke all on function public.wnph_refresh_expression_manifestation_derivations_v2(text) from public,anon,authenticated;
grant execute on function public.wnph_refresh_expression_manifestation_derivations_v2(text) to service_role;
