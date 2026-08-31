create table wnph.publication_media_receipt_requests(
  id uuid primary key default gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  placement_id uuid not null references wnph.publication_expression_media_placements(id),
  token_sha256 text not null check(token_sha256 ~ '^[0-9a-f]{64}$'),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
create index publication_media_receipt_requests_active_idx on wnph.publication_media_receipt_requests(placement_id,expires_at) where consumed_at is null;
alter table wnph.publication_media_receipt_requests enable row level security;
revoke all on wnph.publication_media_receipt_requests from public,anon,authenticated,service_role;

create table wnph.publication_expression_media_source_receipts(
  id uuid primary key default gen_random_uuid(),
  expression_id uuid not null references wnph.expressions(id),
  placement_id uuid not null references wnph.publication_expression_media_placements(id),
  source_asset_id uuid not null references wnph.publication_source_assets(id),
  receipt_key text not null,
  fetch_uri text not null,
  media_type text not null,
  byte_length bigint not null check(byte_length>0),
  sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
  request_id uuid not null references wnph.publication_media_receipt_requests(id),
  evidence jsonb not null default '{}'::jsonb check(jsonb_typeof(evidence)='object'),
  supersedes_receipt_id uuid references wnph.publication_expression_media_source_receipts(id),
  created_at timestamptz not null default now(),
  check(supersedes_receipt_id is null or supersedes_receipt_id<>id)
);
create unique index publication_media_receipts_one_root_uidx on wnph.publication_expression_media_source_receipts(expression_id,placement_id,receipt_key) where supersedes_receipt_id is null;
create unique index publication_media_receipts_one_child_uidx on wnph.publication_expression_media_source_receipts(supersedes_receipt_id) where supersedes_receipt_id is not null;
create index publication_media_receipts_expression_idx on wnph.publication_expression_media_source_receipts(expression_id,placement_id,created_at desc);
alter table wnph.publication_expression_media_source_receipts enable row level security;
revoke all on wnph.publication_expression_media_source_receipts from public,anon,authenticated,service_role;

create or replace function wnph.validate_publication_media_source_receipt_v1()
returns trigger language plpgsql set search_path='pg_catalog','wnph','public' as $$
declare v_p wnph.publication_expression_media_placements%rowtype; v_req wnph.publication_media_receipt_requests%rowtype;
begin
 if tg_op='UPDATE' then raise exception 'WNPH publication media receipt: immutable; supersede explicitly' using errcode='55000'; end if;
 select * into v_p from wnph.publication_expression_media_placements where id=new.placement_id;
 if v_p.id is null or v_p.expression_id<>new.expression_id or v_p.source_asset_id<>new.source_asset_id then raise exception 'WNPH publication media receipt: placement, Expression, and source asset must agree' using errcode='55000'; end if;
 select * into v_req from wnph.publication_media_receipt_requests where id=new.request_id;
 if v_req.id is null or v_req.expression_id<>new.expression_id or v_req.placement_id<>new.placement_id then raise exception 'WNPH publication media receipt: request does not authorize this placement' using errcode='55000'; end if;
 if new.supersedes_receipt_id is not null then
   if not exists(select 1 from wnph.publication_expression_media_source_receipts r where r.id=new.supersedes_receipt_id and r.expression_id=new.expression_id and r.placement_id=new.placement_id and r.receipt_key=new.receipt_key) then raise exception 'WNPH publication media receipt: supersession must preserve Expression, placement, and receipt key' using errcode='55000'; end if;
   if exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=new.supersedes_receipt_id) then raise exception 'WNPH publication media receipt: supersession fork is not allowed' using errcode='55000'; end if;
 end if;
 return new;
end; $$;
create trigger publication_media_source_receipt_validate before insert or update on wnph.publication_expression_media_source_receipts for each row execute function wnph.validate_publication_media_source_receipt_v1();
create trigger publication_media_source_receipt_append_only before delete on wnph.publication_expression_media_source_receipts for each row execute function wnph.reject_append_only_mutation();

create or replace function public.wnph_issue_publication_media_receipt_ticket_v1(p_expression_key text,p_placement_key text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_expr uuid; v_placement uuid; v_token text; v_id uuid; v_exp timestamptz;
begin
 select id into v_expr from wnph.expressions where canonical_key=p_expression_key;
 if v_expr is null then raise exception 'WNPH media receipt ticket: Expression not found' using errcode='P0002'; end if;
 select p.id into v_placement from wnph.publication_expression_media_placements p where p.expression_id=v_expr and p.placement_key=p_placement_key and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=p.id) order by p.created_at desc limit 1;
 if v_placement is null then raise exception 'WNPH media receipt ticket: active placement not found' using errcode='P0002'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex'); v_exp:=now()+interval '5 minutes';
 insert into wnph.publication_media_receipt_requests(expression_id,placement_id,token_sha256,expires_at) values(v_expr,v_placement,encode(extensions.digest(v_token,'sha256'),'hex'),v_exp) returning id into v_id;
 return jsonb_build_object('request_id',v_id,'token',v_token,'expires_at',v_exp,'expression_key',p_expression_key,'placement_key',p_placement_key);
end; $$;
revoke all on function public.wnph_issue_publication_media_receipt_ticket_v1(text,text) from public,anon,authenticated;
grant execute on function public.wnph_issue_publication_media_receipt_ticket_v1(text,text) to service_role;

create or replace function public.wnph_resolve_publication_media_receipt_request_v1(p_request_id uuid,p_token text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_req wnph.publication_media_receipt_requests%rowtype; v_p wnph.publication_expression_media_placements%rowtype; v_a wnph.publication_source_assets%rowtype; v_e wnph.expressions%rowtype;
begin
 select * into v_req from wnph.publication_media_receipt_requests where id=p_request_id for update;
 if v_req.id is null or v_req.consumed_at is not null or v_req.expires_at<=now() or v_req.token_sha256<>encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') then raise exception 'WNPH media receipt request unauthorized, expired, or consumed' using errcode='42501'; end if;
 select * into v_p from wnph.publication_expression_media_placements where id=v_req.placement_id and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=publication_expression_media_placements.id);
 select * into v_a from wnph.publication_source_assets where id=v_p.source_asset_id and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=publication_source_assets.id);
 select * into v_e from wnph.expressions where id=v_req.expression_id;
 if v_p.id is null or v_a.id is null or v_e.id is null then raise exception 'WNPH media receipt request no longer resolves to active governed objects' using errcode='55000'; end if;
 return jsonb_build_object('request_id',v_req.id,'expression_id',v_e.id,'expression_key',v_e.canonical_key,'placement_id',v_p.id,'placement_key',v_p.placement_key,'source_asset_id',v_a.id,'source_asset_key',v_a.asset_key,'media_type',v_a.media_type,'source_locator',v_a.source_locator,'expires_at',v_req.expires_at);
end; $$;
revoke all on function public.wnph_resolve_publication_media_receipt_request_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.wnph_resolve_publication_media_receipt_request_v1(uuid,text) to service_role;

create or replace function public.wnph_commit_publication_media_source_receipt_v1(p_request_id uuid,p_token text,p_fetch_uri text,p_media_type text,p_byte_length bigint,p_sha256 text,p_evidence jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='pg_catalog','wnph','public' as $$
declare v_req wnph.publication_media_receipt_requests%rowtype; v_p wnph.publication_expression_media_placements%rowtype; v_a wnph.publication_source_assets%rowtype; v_old wnph.publication_expression_media_source_receipts%rowtype; v_id uuid; v_receipt_key text:='source-raster:full-max:v1';
begin
 if coalesce(p_sha256,'') !~ '^[0-9a-f]{64}$' or coalesce(p_byte_length,0)<=0 or coalesce(p_media_type,'')<>'image/jpeg' then raise exception 'WNPH media receipt: malformed byte receipt' using errcode='22023'; end if;
 if jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' then raise exception 'WNPH media receipt: evidence must be object' using errcode='22023'; end if;
 select * into v_req from wnph.publication_media_receipt_requests where id=p_request_id for update;
 if v_req.id is null or v_req.consumed_at is not null or v_req.expires_at<=now() or v_req.token_sha256<>encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex') then raise exception 'WNPH media receipt commit unauthorized, expired, or consumed' using errcode='42501'; end if;
 select * into v_p from wnph.publication_expression_media_placements where id=v_req.placement_id and not exists(select 1 from wnph.publication_expression_media_placements c where c.supersedes_placement_id=publication_expression_media_placements.id);
 select * into v_a from wnph.publication_source_assets where id=v_p.source_asset_id and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=publication_source_assets.id);
 if v_p.id is null or v_a.id is null then raise exception 'WNPH media receipt commit lost governed placement or source asset' using errcode='55000'; end if;
 if p_fetch_uri is distinct from (v_a.source_locator->>'image_uri') then raise exception 'WNPH media receipt: fetch URI must equal governed source asset image_uri' using errcode='55000'; end if;
 if p_fetch_uri !~ '^https://tile[.]loc[.]gov/image-services/iiif/public:gdcmassbookdig:wishfairydewydea00colv:wishfairydewydea00colv_[0-9]{4}/full/max/0/default[.]jpg$' then raise exception 'WNPH media receipt: fetch URI outside bounded LOC source path' using errcode='55000'; end if;
 select * into v_old from wnph.publication_expression_media_source_receipts r where r.expression_id=v_req.expression_id and r.placement_id=v_p.id and r.receipt_key=v_receipt_key and not exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=r.id) order by r.created_at desc limit 1;
 if v_old.id is not null and v_old.sha256=p_sha256 and v_old.byte_length=p_byte_length and v_old.fetch_uri=p_fetch_uri then update wnph.publication_media_receipt_requests set consumed_at=now() where id=v_req.id; return jsonb_build_object('receipt_id',v_old.id,'action','unchanged','sha256',v_old.sha256,'byte_length',v_old.byte_length); end if;
 insert into wnph.publication_expression_media_source_receipts(expression_id,placement_id,source_asset_id,receipt_key,fetch_uri,media_type,byte_length,sha256,request_id,evidence,supersedes_receipt_id)
 values(v_req.expression_id,v_p.id,v_a.id,v_receipt_key,p_fetch_uri,p_media_type,p_byte_length,p_sha256,v_req.id,coalesce(p_evidence,'{}'::jsonb)||jsonb_build_object('byte_receipt',true,'source_authority','Library of Congress governed source asset','source_asset_key',v_a.asset_key,'placement_key',v_p.placement_key),v_old.id)
 returning id into v_id;
 update wnph.publication_media_receipt_requests set consumed_at=now() where id=v_req.id;
 return jsonb_build_object('receipt_id',v_id,'action',case when v_old.id is null then 'created' else 'superseded' end,'sha256',p_sha256,'byte_length',p_byte_length,'supersedes_receipt_id',v_old.id);
end; $$;
revoke all on function public.wnph_commit_publication_media_source_receipt_v1(uuid,text,text,text,bigint,text,jsonb) from public,anon,authenticated;
grant execute on function public.wnph_commit_publication_media_source_receipt_v1(uuid,text,text,text,bigint,text,jsonb) to service_role;

create or replace view public.v_wnph_expression_media_receipts_v1 as
select e.canonical_key expression_key,p.placement_key,a.asset_key source_asset_key,r.receipt_key,r.fetch_uri,r.media_type,r.byte_length,r.sha256,r.evidence,r.created_at
from wnph.publication_expression_media_source_receipts r join wnph.expressions e on e.id=r.expression_id join wnph.publication_expression_media_placements p on p.id=r.placement_id join wnph.publication_source_assets a on a.id=r.source_asset_id
where not exists(select 1 from wnph.publication_expression_media_source_receipts c where c.supersedes_receipt_id=r.id);
grant select on public.v_wnph_expression_media_receipts_v1 to service_role;