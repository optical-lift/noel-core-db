create table if not exists wnph.publication_expression_media_raster_selections (
  id uuid primary key default extensions.gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  placement_id uuid not null references wnph.publication_expression_media_placements(id),
  receipt_id uuid not null references wnph.publication_expression_media_source_receipts(id),
  selection_reason jsonb not null default '{}'::jsonb,
  supersedes_selection_id uuid null references wnph.publication_expression_media_raster_selections(id),
  created_at timestamptz not null default now(),
  constraint publication_expression_media_raster_selections_supersedes_uk unique(supersedes_selection_id)
);

revoke all on wnph.publication_expression_media_raster_selections from anon, authenticated;

create or replace function wnph.guard_publication_media_raster_selection_v1()
returns trigger language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_r wnph.publication_expression_media_source_receipts%rowtype; v_old wnph.publication_expression_media_raster_selections%rowtype;
begin
  if tg_op <> 'INSERT' then raise exception 'WNPH raster selections are append-only' using errcode='55000'; end if;
  select * into v_r from wnph.publication_expression_media_source_receipts where id=new.receipt_id;
  if v_r.id is null or v_r.expression_id<>new.expression_id or v_r.placement_id<>new.placement_id then
    raise exception 'WNPH raster selection receipt must match Expression and placement' using errcode='55000';
  end if;
  if exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=v_r.id) then
    raise exception 'WNPH raster selection cannot select a superseded receipt' using errcode='55000';
  end if;
  if new.supersedes_selection_id is null then
    if exists(select 1 from wnph.publication_expression_media_raster_selections s where s.expression_id=new.expression_id and s.placement_id=new.placement_id and not exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=s.id)) then
      raise exception 'WNPH raster selection requires explicit supersession' using errcode='55000';
    end if;
  else
    select * into v_old from wnph.publication_expression_media_raster_selections where id=new.supersedes_selection_id;
    if v_old.id is null or v_old.expression_id<>new.expression_id or v_old.placement_id<>new.placement_id then
      raise exception 'WNPH raster selection supersession cannot cross Expression or placement' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=v_old.id) then
      raise exception 'WNPH raster selection supersession target is no longer active' using errcode='55000';
    end if;
  end if;
  return new;
end;$$;

drop trigger if exists trg_guard_publication_media_raster_selection_v1 on wnph.publication_expression_media_raster_selections;
create trigger trg_guard_publication_media_raster_selection_v1 before insert or update or delete on wnph.publication_expression_media_raster_selections for each row execute function wnph.guard_publication_media_raster_selection_v1();

insert into wnph.publication_expression_media_raster_selections(expression_id,placement_id,receipt_id,selection_reason)
select r.expression_id,r.placement_id,r.id,jsonb_build_object('selection_basis','existing_governed_publication_raster_backfill','receipt_key',r.receipt_key)
from wnph.publication_expression_media_source_receipts r
where r.receipt_key='publication-raster:full-1800:v1'
  and not exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=r.id)
  and not exists(select 1 from wnph.publication_expression_media_raster_selections s where s.expression_id=r.expression_id and s.placement_id=r.placement_id);

create or replace function public.wnph_select_publication_media_raster_v1(p_expression_key text,p_placement_key text,p_receipt_id uuid,p_reason jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_e uuid; v_p uuid; v_r wnph.publication_expression_media_source_receipts%rowtype; v_old wnph.publication_expression_media_raster_selections%rowtype; v_id uuid;
begin
 select id into v_e from wnph.expressions where canonical_key=p_expression_key;
 select p.id into v_p from wnph.publication_expression_media_placements p where p.expression_id=v_e and p.placement_key=p_placement_key and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id) order by p.created_at desc limit 1;
 select * into v_r from wnph.publication_expression_media_source_receipts where id=p_receipt_id;
 if v_e is null or v_p is null or v_r.id is null or v_r.expression_id<>v_e or v_r.placement_id<>v_p then raise exception 'WNPH raster selection objects do not match' using errcode='55000'; end if;
 if exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=v_r.id) then raise exception 'WNPH raster selection receipt is superseded' using errcode='55000'; end if;
 select * into v_old from wnph.publication_expression_media_raster_selections s where s.expression_id=v_e and s.placement_id=v_p and not exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=s.id) order by s.created_at desc limit 1;
 if v_old.id is not null and v_old.receipt_id=v_r.id then return jsonb_build_object('action','unchanged','selection_id',v_old.id,'receipt_id',v_r.id); end if;
 insert into wnph.publication_expression_media_raster_selections(expression_id,placement_id,receipt_id,selection_reason,supersedes_selection_id) values(v_e,v_p,v_r.id,coalesce(p_reason,'{}'::jsonb),v_old.id) returning id into v_id;
 return jsonb_build_object('action',case when v_old.id is null then 'created' else 'superseded' end,'selection_id',v_id,'receipt_id',v_r.id,'supersedes_selection_id',v_old.id);
end;$$;
revoke all on function public.wnph_select_publication_media_raster_v1(text,text,uuid,jsonb) from public,anon,authenticated;

create or replace function public.wnph_commit_publication_media_source_receipt_v2(p_request_id uuid,p_token text,p_receipt_key text,p_fetch_uri text,p_media_type text,p_byte_length bigint,p_sha256 text,p_evidence jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_req wnph.publication_media_receipt_requests%rowtype; v_p wnph.publication_expression_media_placements%rowtype; v_a wnph.publication_source_assets%rowtype; v_old wnph.publication_expression_media_source_receipts%rowtype; v_id uuid; v_expected_uri text;
begin
 if coalesce(p_sha256,'') !~ '^[0-9a-f]{64}$' or coalesce(p_byte_length,0)<=0 or coalesce(p_media_type,'')<>'image/jpeg' then raise exception 'WNPH media receipt v2: malformed byte receipt' using errcode='22023'; end if;
 select * into v_req from wnph.publication_media_receipt_requests where id=p_request_id for update;
 if v_req.id is null or v_req.consumed_at is not null or v_req.expires_at<=now() or v_req.token_sha256<>encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') then raise exception 'WNPH media receipt v2 unauthorized, expired, or consumed' using errcode='42501'; end if;
 select * into v_p from wnph.publication_expression_media_placements where id=v_req.placement_id and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=publication_expression_media_placements.id);
 select * into v_a from wnph.publication_source_assets where id=v_p.source_asset_id and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=publication_source_assets.id);
 if v_p.id is null or v_a.id is null then raise exception 'WNPH media receipt v2 lost governed placement or source asset' using errcode='55000'; end if;
 if p_receipt_key='publication-raster:ia-bookreader-w1600:v1' then
   if v_p.placement_key<>'dewy:plate:page-9' or v_a.asset_key<>'dewy:loc:source-surface:0013' then raise exception 'WNPH IA raster v1 currently authorized only for confirmed Dewy page-9 plate' using errcode='55000'; end if;
   v_expected_uri:='https://archive.org/download/wishfairydewydea00colv/page/n12_w1600.jpg';
 else
   raise exception 'WNPH media receipt v2 unsupported receipt contract' using errcode='55000';
 end if;
 if p_fetch_uri is distinct from v_expected_uri then raise exception 'WNPH media receipt v2 fetch URI outside governed rendition contract' using errcode='55000'; end if;
 select * into v_old from wnph.publication_expression_media_source_receipts r where r.expression_id=v_req.expression_id and r.placement_id=v_p.id and r.receipt_key=p_receipt_key and not exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=r.id) order by r.created_at desc limit 1;
 if v_old.id is not null and v_old.sha256=p_sha256 and v_old.byte_length=p_byte_length and v_old.fetch_uri=p_fetch_uri then update wnph.publication_media_receipt_requests set consumed_at=now() where id=v_req.id; return jsonb_build_object('receipt_id',v_old.id,'action','unchanged','receipt_key',p_receipt_key,'sha256',v_old.sha256,'byte_length',v_old.byte_length); end if;
 insert into wnph.publication_expression_media_source_receipts(expression_id,placement_id,source_asset_id,receipt_key,fetch_uri,media_type,byte_length,sha256,request_id,evidence,supersedes_receipt_id)
 values(v_req.expression_id,v_p.id,v_a.id,p_receipt_key,p_fetch_uri,p_media_type,p_byte_length,p_sha256,v_req.id,coalesce(p_evidence,'{}'::jsonb)||jsonb_build_object('byte_receipt',true,'source_asset_key',v_a.asset_key,'placement_key',v_p.placement_key,'same_surrogate_derivative',true,'historical_witness_count_delta',0,'source_image_verification_claim',false),v_old.id) returning id into v_id;
 update wnph.publication_media_receipt_requests set consumed_at=now() where id=v_req.id;
 return jsonb_build_object('receipt_id',v_id,'action',case when v_old.id is null then 'created' else 'superseded' end,'receipt_key',p_receipt_key,'sha256',p_sha256,'byte_length',p_byte_length,'supersedes_receipt_id',v_old.id);
end;$$;
revoke all on function public.wnph_commit_publication_media_source_receipt_v2(uuid,text,text,text,text,bigint,text,jsonb) from public,anon,authenticated;

create or replace view public.v_wnph_expression_selected_publication_raster_v1 as
with active_placements as (
 select p.* from wnph.publication_expression_media_placements p where not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id)
), active_selections as (
 select s.* from wnph.publication_expression_media_raster_selections s where not exists(select 1 from wnph.publication_expression_media_raster_selections c where c.supersedes_selection_id=s.id)
)
select e.canonical_key expression_key,p.id placement_id,p.placement_key,p.sequence_ordinal,p.media_role,a.asset_key source_asset_key,r.id receipt_id,r.receipt_key,r.fetch_uri,r.media_type receipt_media_type,r.byte_length,r.sha256 raster_sha256,r.created_at receipt_created_at,s.id selection_id,s.created_at selection_created_at
from active_placements p join wnph.expressions e on e.id=p.expression_id join wnph.publication_source_assets a on a.id=p.source_asset_id left join active_selections s on s.expression_id=p.expression_id and s.placement_id=p.id left join wnph.publication_expression_media_source_receipts r on r.id=s.receipt_id;
revoke all on public.v_wnph_expression_selected_publication_raster_v1 from anon,authenticated;

grant select on public.v_wnph_expression_selected_publication_raster_v1 to service_role;

create or replace function public.wnph_publication_expression_snapshot_v4(p_expression_key text)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','wnph','public' as $$
declare v_expr uuid;v_blocks integer;v_text integer;v_media integer;v_receipts integer;v_missing integer;v_text_payload text;v_media_payload text;v_hash text;
begin
 select id into v_expr from wnph.expressions where canonical_key=p_expression_key; if v_expr is null then raise exception 'WNPH expression snapshot v4: Expression not found' using errcode='P0002'; end if;
 select count(*),count(*) filter(where text_content is not null),string_agg(render_path||'|'||block_key||'|'||block_type||'|'||semantic_role||'|'||coalesce(text_content,''),E'\n' order by render_path) into v_blocks,v_text,v_text_payload from public.v_wnph_expression_render_input_v1 where expression_key=p_expression_key;
 select count(*),count(*) filter(where r.raster_sha256 is not null),count(*) filter(where r.raster_sha256 is null),string_agg(lpad(m.sequence_ordinal::text,6,'0')||'|'||m.placement_key||'|'||m.media_role||'|'||m.anchor_kind||'|'||coalesce(m.anchor_block_key,'')||'|'||m.source_asset_key||'|'||m.anchor_data::text||'|'||m.placement_policy::text||'|'||m.accessibility::text||'|'||coalesce(r.receipt_key,'MISSING')||'|'||coalesce(r.fetch_uri,'MISSING')||'|'||coalesce(r.receipt_media_type,'MISSING')||'|'||coalesce(r.byte_length::text,'MISSING')||'|'||coalesce(r.raster_sha256,'MISSING'),E'\n' order by m.sequence_ordinal,m.placement_key) into v_media,v_receipts,v_missing,v_media_payload from public.v_wnph_expression_media_input_v1 m left join public.v_wnph_expression_selected_publication_raster_v1 r on r.expression_key=m.expression_key and r.placement_key=m.placement_key where m.expression_key=p_expression_key;
 v_hash:=encode(extensions.digest(convert_to('WNPH_PUBLICATION_EXPRESSION_SNAPSHOT_V4'||E'\nTEXT\n'||coalesce(v_text_payload,'')||E'\nSEMANTIC_MEDIA_WITH_SELECTED_RASTER_RECEIPTS\n'||coalesce(v_media_payload,''),'UTF8'),'sha256'),'hex');
 return jsonb_build_object('contract_version','wnph_publication_expression_snapshot_v4','expression_key',p_expression_key,'admitted_block_count',coalesce(v_blocks,0),'text_block_count',coalesce(v_text,0),'media_placement_count',coalesce(v_media,0),'media_receipt_count',coalesce(v_receipts,0),'unreceipted_media_count',coalesce(v_missing,0),'reproducible_build_ready',coalesce(v_missing,0)=0,'publication_raster_contract','explicit-selected-governed-raster:v1','semantic_media_fields_hashed',jsonb_build_array('sequence_ordinal','placement_key','media_role','anchor_kind','anchor_block_key','source_asset_key','anchor_data','placement_policy','accessibility'),'render_master_sha256',v_hash);
end;$$;

create or replace function public.wnph_refresh_expression_manifestation_derivations_v3(p_expression_key text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_expression wnph.expressions%rowtype;v_snapshot jsonb;v_current_hash text;v_old record;v_new_id uuid;v_results jsonb:='[]'::jsonb;v_count integer:=0;
begin
 select * into v_expression from wnph.expressions where canonical_key=p_expression_key;if v_expression.id is null then raise exception 'WNPH manifestation fanout v3: Expression not found' using errcode='P0002';end if;
 v_snapshot:=public.wnph_publication_expression_snapshot_v4(p_expression_key);if coalesce((v_snapshot->>'reproducible_build_ready')::boolean,false) is not true then raise exception 'WNPH manifestation fanout v3: publication master has % unreceipted media placements',v_snapshot->>'unreceipted_media_count' using errcode='55000';end if;v_current_hash:=v_snapshot->>'render_master_sha256';
 for v_old in select d.*,r.canonical_key render_profile_key,r.output_family,m.canonical_key manifestation_key from wnph.publication_manifestation_derivations d join wnph.publication_render_profiles r on r.id=d.render_profile_id join wnph.manifestations m on m.id=d.manifestation_id where d.publication_expression_id=v_expression.id and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id) order by r.canonical_key,m.canonical_key loop
  v_count:=v_count+1;
  if coalesce(v_old.build_metadata->'master_snapshot'->>'render_master_sha256','')=v_current_hash and coalesce(v_old.build_metadata->'master_snapshot'->>'contract_version','')='wnph_publication_expression_snapshot_v4' then v_results:=v_results||jsonb_build_array(jsonb_build_object('render_profile_key',v_old.render_profile_key,'manifestation_key',v_old.manifestation_key,'derivation_id',v_old.id,'action','unchanged','render_master_sha256',v_current_hash));
  else insert into wnph.publication_manifestation_derivations(source_package_id,publication_expression_id,render_profile_id,manifestation_id,derivation_status,build_metadata,supersedes_derivation_id) values(null,v_expression.id,v_old.render_profile_id,v_old.manifestation_id,'planned',coalesce(v_old.build_metadata,'{}'::jsonb)||jsonb_build_object('master_snapshot',v_snapshot,'master_authority','publication_expression','publication_raster_contract','explicit-selected-governed-raster:v1','exact_media_bytes_receipted',true,'source_image_verification_is_parallel_not_blocking',true,'fanout_contract','wnph_refresh_expression_manifestation_derivations_v3','output_family',v_old.output_family,'supersession_reason','publication_expression_snapshot_v4_or_selected_raster_changed','previous_render_master_sha256',v_old.build_metadata->'master_snapshot'->>'render_master_sha256','refreshed_at',now()),v_old.id) returning id into v_new_id;v_results:=v_results||jsonb_build_array(jsonb_build_object('render_profile_key',v_old.render_profile_key,'manifestation_key',v_old.manifestation_key,'derivation_id',v_new_id,'supersedes_derivation_id',v_old.id,'action','superseded_to_current_snapshot_v4','render_master_sha256',v_current_hash));end if;
 end loop;
 if v_count=0 then raise exception 'WNPH manifestation fanout v3: no active manifestation derivations attached' using errcode='P0002';end if;
 return jsonb_build_object('contract_version','wnph_refresh_expression_manifestation_derivations_v3','expression_key',p_expression_key,'master_snapshot',v_snapshot,'manifestation_count',v_count,'results',v_results);
end;$$;

create or replace function public.wnph_publication_render_packet_v3(p_expression_key text)
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','wnph','public' as $$
declare v_base jsonb;v_snapshot jsonb;v_media jsonb;v_targets jsonb;
begin
 v_base:=public.wnph_publication_render_packet_v2(p_expression_key);v_snapshot:=public.wnph_publication_expression_snapshot_v4(p_expression_key);
 select coalesce(jsonb_agg(jsonb_build_object('placement_key',m.placement_key,'sequence_ordinal',m.sequence_ordinal,'media_role',m.media_role,'anchor_kind',m.anchor_kind,'anchor_block_key',m.anchor_block_key,'anchor_data',m.anchor_data,'placement_policy',m.placement_policy,'accessibility',m.accessibility,'source_asset_key',m.source_asset_key,'source_media_type',m.media_type,'source_locator',m.source_locator,'storage_uri',m.storage_uri,'publication_raster',jsonb_build_object('receipt_key',r.receipt_key,'fetch_uri',r.fetch_uri,'media_type',r.receipt_media_type,'byte_length',r.byte_length,'sha256',r.raster_sha256)) order by m.sequence_ordinal,m.placement_key),'[]'::jsonb) into v_media from public.v_wnph_expression_media_input_v1 m left join public.v_wnph_expression_selected_publication_raster_v1 r on r.expression_key=m.expression_key and r.placement_key=m.placement_key where m.expression_key=p_expression_key;
 select coalesce(jsonb_agg(jsonb_build_object('output_family',r.output_family,'render_profile_key',r.canonical_key,'profile_version',r.profile_version,'profile_rules',r.rules,'profile_sha256',encode(extensions.digest(convert_to(r.canonical_key||'|'||r.profile_version||'|'||r.rules::text,'UTF8'),'sha256'),'hex'),'manifestation_key',m.canonical_key,'manifestation_status',m.status,'derivation_status',d.derivation_status,'build_fingerprint_sha256',encode(extensions.digest(convert_to((v_snapshot->>'render_master_sha256')||'|'||r.canonical_key||'|'||r.profile_version||'|'||r.rules::text,'UTF8'),'sha256'),'hex')) order by r.output_family),'[]'::jsonb) into v_targets from wnph.publication_manifestation_derivations d join wnph.publication_render_profiles r on r.id=d.render_profile_id join wnph.manifestations m on m.id=d.manifestation_id join wnph.expressions e on e.id=d.publication_expression_id where e.canonical_key=p_expression_key and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id);
 return v_base||jsonb_build_object('contract_version','wnph_publication_render_packet_v3','reproducible_build_ready',coalesce((v_snapshot->>'reproducible_build_ready')::boolean,false),'master_snapshot',v_snapshot,'media_placements',v_media,'render_targets',v_targets);
end;$$;

create or replace function public.wnph_create_publication_release_v2(p_expression_key text,p_public_slug text,p_release_key text,p_supersedes_release_key text default null,p_decision_basis jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public','extensions' as $$
declare v_expr wnph.expressions%rowtype;v_work wnph.historical_works%rowtype;v_packet jsonb;v_snapshot jsonb;v_prior wnph.publication_releases%rowtype;v_active wnph.publication_releases%rowtype;v_release_sequence integer;v_released_at timestamptz:=clock_timestamp();v_public_media jsonb;v_public_rights jsonb;v_payload jsonb;v_payload_sha text;v_new_id uuid;
begin
 if p_public_slug is null or p_public_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then raise exception 'WNPH publication release v2: invalid public slug' using errcode='22023';end if;
 select * into v_expr from wnph.expressions where canonical_key=p_expression_key;if v_expr.id is null then raise exception 'WNPH publication release v2: Expression not found' using errcode='P0002';end if;select * into v_work from wnph.historical_works where id=v_expr.work_id;
 v_packet:=public.wnph_publication_render_packet_v3(p_expression_key);v_snapshot:=v_packet->'master_snapshot';if coalesce((v_packet->>'reproducible_build_ready')::boolean,false) is not true or coalesce((v_snapshot->>'unreceipted_media_count')::integer,0)<>0 then raise exception 'WNPH publication release v2: Expression is not reproducible-build ready' using errcode='55000';end if;
 select r.* into v_active from wnph.publication_releases r where r.work_id=v_work.id and not exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=r.id) order by r.release_sequence desc limit 1;
 if p_supersedes_release_key is null then if v_active.id is not null then raise exception 'WNPH publication release v2: active release exists; explicit supersession required' using errcode='55000';end if;v_release_sequence:=1;else select * into v_prior from wnph.publication_releases where release_key=p_supersedes_release_key;if v_prior.id is null or v_prior.work_id<>v_work.id or exists(select 1 from wnph.publication_releases s where s.supersedes_release_id=v_prior.id) or v_active.id is distinct from v_prior.id then raise exception 'WNPH publication release v2: invalid supersession target' using errcode='55000';end if;v_release_sequence:=v_prior.release_sequence+1;end if;
 select coalesce(jsonb_agg(jsonb_build_object('placement_key',m->>'placement_key','sequence_ordinal',(m->>'sequence_ordinal')::integer,'media_role',m->>'media_role','anchor_kind',m->>'anchor_kind','anchor_block_key',m->'anchor_block_key','anchor_data',coalesce(m->'anchor_data','{}'::jsonb),'placement_policy',coalesce(m->'placement_policy','{}'::jsonb),'accessibility',coalesce(m->'accessibility','{}'::jsonb),'image',jsonb_build_object('url',m#>>'{publication_raster,fetch_uri}','media_type',m#>>'{publication_raster,media_type}','byte_length',(m#>>'{publication_raster,byte_length}')::bigint,'sha256',m#>>'{publication_raster,sha256}')) order by (m->>'sequence_ordinal')::integer,m->>'placement_key'),'[]'::jsonb) into v_public_media from jsonb_array_elements(v_packet->'media_placements') m;
 select coalesce(jsonb_agg(jsonb_build_object('component_type',r->>'component_type','status',r->>'component_status','use_scope',r->>'use_scope') order by r->>'component_type'),'[]'::jsonb) into v_public_rights from jsonb_array_elements(v_packet->'rights') r;
 v_payload:=jsonb_build_object('contract_version','wnph_publication_public_release_payload_v1','release',jsonb_build_object('release_key',p_release_key,'public_slug',p_public_slug,'release_sequence',v_release_sequence,'released_at',to_jsonb(v_released_at),'render_master_sha256',v_snapshot->>'render_master_sha256','frozen',true,'read_only',true),'bibliographic',v_packet->'bibliographic','rights',v_public_rights,'chapters',v_packet->'chapters','ordered_blocks',v_packet->'ordered_blocks','media_placements',v_public_media,'public_provenance',jsonb_build_object('publisher','Write Now Publishing House','publication_expression_is_private_authority',true,'public_release_is_downstream_manifestation',true,'source_and_editorial_custody_not_exposed',true,'content_addressed_master',true,'selected_publication_rasters',true));
 v_payload_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');insert into wnph.publication_releases(release_key,public_slug,work_id,expression_id,release_sequence,release_state,render_master_sha256,public_payload,payload_sha256,supersedes_release_id,decision_basis,released_at) values(p_release_key,p_public_slug,v_work.id,v_expr.id,v_release_sequence,'released',v_snapshot->>'render_master_sha256',v_payload,v_payload_sha,v_prior.id,coalesce(p_decision_basis,'{}'::jsonb),v_released_at) returning id into v_new_id;
 return jsonb_build_object('release_id',v_new_id,'release_key',p_release_key,'release_sequence',v_release_sequence,'render_master_sha256',v_snapshot->>'render_master_sha256','payload_sha256',v_payload_sha,'public_slug',p_public_slug);
end;$$;
revoke all on function public.wnph_create_publication_release_v2(text,text,text,text,jsonb) from public,anon,authenticated;