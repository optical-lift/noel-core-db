alter table wnph.publication_manifestation_derivations
  add column if not exists publication_expression_id uuid references wnph.expressions(id);

alter table wnph.publication_manifestation_derivations
  alter column source_package_id drop not null;

alter table wnph.publication_manifestation_derivations
  drop constraint if exists publication_manifestation_derivations_one_master_input;
alter table wnph.publication_manifestation_derivations
  add constraint publication_manifestation_derivations_one_master_input
  check (num_nonnulls(source_package_id, publication_expression_id)=1);

create index if not exists publication_manifestation_derivations_expression_idx
on wnph.publication_manifestation_derivations(publication_expression_id, render_profile_id);

create or replace view public.v_wnph_expression_render_input_v1 as
with recursive active as (
  select b.*
  from wnph.publication_expression_blocks b
  where not exists(select 1 from wnph.publication_expression_blocks c where c.supersedes_block_id=b.id)
    and b.publication_state='admitted'
), tree as (
  select a.id,a.expression_id,a.block_key,a.parent_block_id,a.ordinal,a.block_type,a.semantic_role,a.text_content,
         lpad(a.ordinal::text,6,'0') as render_path
  from active a
  where a.parent_block_id is null
  union all
  select c.id,c.expression_id,c.block_key,c.parent_block_id,c.ordinal,c.block_type,c.semantic_role,c.text_content,
         t.render_path||'.'||lpad(c.ordinal::text,6,'0')
  from active c join tree t on t.id=c.parent_block_id
)
select e.canonical_key expression_key,t.render_path,t.block_key,t.ordinal,t.block_type,t.semantic_role,t.text_content
from tree t join wnph.expressions e on e.id=t.expression_id;

create or replace function public.wnph_publication_expression_snapshot_v1(p_expression_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,wnph,public
as $$
declare
  v_expression_id uuid;
  v_count integer;
  v_text_count integer;
  v_payload text;
  v_hash text;
begin
  select id into v_expression_id from wnph.expressions where canonical_key=p_expression_key;
  if v_expression_id is null then raise exception 'WNPH expression snapshot: Expression not found' using errcode='P0002'; end if;
  select count(*),count(*) filter(where text_content is not null),
         string_agg(render_path||'|'||block_key||'|'||block_type||'|'||coalesce(text_content,''),E'\n' order by render_path)
  into v_count,v_text_count,v_payload
  from public.v_wnph_expression_render_input_v1 where expression_key=p_expression_key;
  v_hash:=encode(extensions.digest(convert_to(coalesce(v_payload,''),'UTF8'),'sha256'),'hex');
  return jsonb_build_object('contract_version','wnph_publication_expression_snapshot_v1','expression_key',p_expression_key,
    'admitted_block_count',v_count,'text_block_count',v_text_count,'render_master_sha256',v_hash);
end;
$$;

insert into wnph.publication_render_profiles(canonical_key,output_family,profile_version,rules,profile_status,notes)
values
('wnph:render:paperback:v1','paperback','1',jsonb_build_object('master_contract','publication_expression','input_view','v_wnph_expression_render_input_v1','require_single_expression_snapshot',true,'physical_output',true,'requires_print_interior',true),'active','Paperback is a Manifestation of the publication Expression; typography and trim are manifestation rules, not master-text edits.'),
('wnph:render:print-pdf:v1','print_pdf','1',jsonb_build_object('master_contract','publication_expression','input_view','v_wnph_expression_render_input_v1','require_single_expression_snapshot',true,'paginated',true),'active','Print-ready PDF derives from the same publication Expression snapshot.'),
('wnph:render:epub3:v1','epub3','1',jsonb_build_object('master_contract','publication_expression','input_view','v_wnph_expression_render_input_v1','require_single_expression_snapshot',true,'reflowable',true,'standard','EPUB 3'),'active','EPUB 3 derives from the same publication Expression snapshot.'),
('wnph:render:web:v1','web','1',jsonb_build_object('master_contract','publication_expression','input_view','v_wnph_expression_render_input_v1','require_single_expression_snapshot',true,'reflowable',true,'semantic_html',true),'active','Web edition derives from the same publication Expression snapshot.')
on conflict (canonical_key) do nothing;

insert into wnph.manifestations(canonical_key,publisher_name,publication_statement,format_statement,status,notes)
values
('wish-fairy-dewy-dear:wnph-paperback-v1','Write Now Publishing House','WNPH publication manifestation planned from the governed publication Expression.','paperback','planned','Physical paperback manifestation; text authority is the publication Expression master.'),
('wish-fairy-dewy-dear:wnph-print-pdf-v1','Write Now Publishing House','WNPH publication manifestation planned from the governed publication Expression.','print-ready PDF','planned','Paginated print PDF manifestation; text authority is the publication Expression master.'),
('wish-fairy-dewy-dear:wnph-epub3-v1','Write Now Publishing House','WNPH publication manifestation planned from the governed publication Expression.','EPUB 3','planned','Reflowable EPUB manifestation; text authority is the publication Expression master.'),
('wish-fairy-dewy-dear:wnph-web-v1','Write Now Publishing House','WNPH publication manifestation planned from the governed publication Expression.','semantic web edition','planned','Web manifestation; text authority is the publication Expression master.')
on conflict (canonical_key) do nothing;

insert into wnph.expression_manifestations(expression_id,manifestation_id,relationship_type,status,confidence,notes)
select e.id,m.id,'embodied_in','planned','high','Planned manifestation derives from the WNPH publication Expression; no source-verification claim is implied by this relationship.'
from wnph.expressions e
join wnph.manifestations m on m.canonical_key in (
 'wish-fairy-dewy-dear:wnph-paperback-v1','wish-fairy-dewy-dear:wnph-print-pdf-v1','wish-fairy-dewy-dear:wnph-epub3-v1','wish-fairy-dewy-dear:wnph-web-v1')
where e.canonical_key='wish-fairy-dewy-dear:wnph-publication-e1'
  and not exists(select 1 from wnph.expression_manifestations x where x.expression_id=e.id and x.manifestation_id=m.id and not exists(select 1 from wnph.expression_manifestations c where c.supersedes_relationship_id=x.id));

with x as (
 select e.id expression_id,
        public.wnph_publication_expression_snapshot_v1(e.canonical_key) snapshot
 from wnph.expressions e where e.canonical_key='wish-fairy-dewy-dear:wnph-publication-e1'
), pairs as (
 select * from (values
  ('wnph:render:paperback:v1','wish-fairy-dewy-dear:wnph-paperback-v1'),
  ('wnph:render:print-pdf:v1','wish-fairy-dewy-dear:wnph-print-pdf-v1'),
  ('wnph:render:epub3:v1','wish-fairy-dewy-dear:wnph-epub3-v1'),
  ('wnph:render:web:v1','wish-fairy-dewy-dear:wnph-web-v1')
 ) v(profile_key,manifestation_key)
)
insert into wnph.publication_manifestation_derivations(source_package_id,publication_expression_id,render_profile_id,manifestation_id,derivation_status,build_metadata)
select null,x.expression_id,r.id,m.id,'planned',jsonb_build_object('master_snapshot',x.snapshot,'master_authority','publication_expression','source_image_verification_is_parallel_not_blocking',true)
from x cross join pairs p
join wnph.publication_render_profiles r on r.canonical_key=p.profile_key
join wnph.manifestations m on m.canonical_key=p.manifestation_key
where not exists(select 1 from wnph.publication_manifestation_derivations d where d.publication_expression_id=x.expression_id and d.render_profile_id=r.id and d.manifestation_id=m.id and not exists(select 1 from wnph.publication_manifestation_derivations c where c.supersedes_derivation_id=d.id));

grant select on public.v_wnph_expression_render_input_v1 to service_role;
revoke all on function public.wnph_publication_expression_snapshot_v1(text) from public,anon,authenticated;
grant execute on function public.wnph_publication_expression_snapshot_v1(text) to service_role;