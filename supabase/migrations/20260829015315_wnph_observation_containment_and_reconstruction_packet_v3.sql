create table wnph.publication_source_observation_relations (
  id uuid primary key default gen_random_uuid(),
  source_asset_id uuid not null references wnph.publication_source_assets(id),
  container_observation_id uuid not null references wnph.publication_source_observations(id),
  child_observation_id uuid not null references wnph.publication_source_observations(id),
  relation_kind text not null check (relation_kind in ('contains')),
  ordinal integer check (ordinal is null or ordinal > 0),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  evidence jsonb not null default '{}'::jsonb,
  supersedes_relation_id uuid references wnph.publication_source_observation_relations(id),
  created_at timestamptz not null default now(),
  constraint publication_source_observation_relations_not_self_ck check (container_observation_id <> child_observation_id),
  constraint publication_source_observation_relations_supersedes_not_self_ck check (supersedes_relation_id is null or supersedes_relation_id <> id)
);

create index publication_source_observation_relations_asset_idx on wnph.publication_source_observation_relations(source_asset_id);
create index publication_source_observation_relations_container_idx on wnph.publication_source_observation_relations(container_observation_id);
create index publication_source_observation_relations_child_idx on wnph.publication_source_observation_relations(child_observation_id);
create index publication_source_observation_relations_supersedes_idx on wnph.publication_source_observation_relations(supersedes_relation_id) where supersedes_relation_id is not null;
alter table wnph.publication_source_observation_relations enable row level security;
revoke all on wnph.publication_source_observation_relations from public,anon,authenticated,service_role;

create or replace function wnph.validate_publication_source_observation_relation_v1()
returns trigger language plpgsql set search_path to 'pg_catalog','wnph' as $function$
declare
  v_container wnph.publication_source_observations%rowtype;
  v_child wnph.publication_source_observations%rowtype;
  v_old wnph.publication_source_observation_relations%rowtype;
begin
  if jsonb_typeof(new.evidence) <> 'object' then raise exception 'WNPH observation relation: evidence must be an object'; end if;
  select * into v_container from wnph.publication_source_observations o
    where o.id=new.container_observation_id and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id);
  select * into v_child from wnph.publication_source_observations o
    where o.id=new.child_observation_id and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id);
  if v_container.id is null or v_child.id is null then raise exception 'WNPH observation relation: endpoints must be active observations'; end if;
  if v_container.source_asset_id<>new.source_asset_id or v_child.source_asset_id<>new.source_asset_id then raise exception 'WNPH observation relation: endpoints must belong to source_asset_id'; end if;
  if new.relation_kind='contains' and v_container.observation_kind not in ('region','layout_region','line') then raise exception 'WNPH observation relation: contains container kind % is not supported',v_container.observation_kind; end if;
  if new.supersedes_relation_id is not null then
    select * into v_old from wnph.publication_source_observation_relations where id=new.supersedes_relation_id;
    if v_old.id is null or v_old.source_asset_id<>new.source_asset_id or v_old.child_observation_id<>new.child_observation_id or v_old.relation_kind<>new.relation_kind then
      raise exception 'WNPH observation relation: supersession must preserve asset, child and relation kind';
    end if;
    if exists(select 1 from wnph.publication_source_observation_relations r where r.supersedes_relation_id=v_old.id) then raise exception 'WNPH observation relation: supersession fork is not allowed'; end if;
  elsif exists(
    select 1 from wnph.publication_source_observation_relations r
    where r.child_observation_id=new.child_observation_id and r.relation_kind=new.relation_kind
      and not exists(select 1 from wnph.publication_source_observation_relations c where c.supersedes_relation_id=r.id)
  ) then raise exception 'WNPH observation relation: child % already has an active % parent',new.child_observation_id,new.relation_kind;
  end if;
  return new;
end;$function$;
revoke all on function wnph.validate_publication_source_observation_relation_v1() from public,anon,authenticated,service_role;
create trigger publication_source_observation_relations_insert_validation_v1 before insert on wnph.publication_source_observation_relations for each row execute function wnph.validate_publication_source_observation_relation_v1();
create trigger publication_source_observation_relations_append_only before update or delete on wnph.publication_source_observation_relations for each row execute function wnph.reject_append_only_mutation();

create or replace function wnph.capture_source_observation_containment_v1()
returns trigger language plpgsql set search_path to 'pg_catalog','wnph' as $function$
declare
  v_container_id uuid;
  v_start_ordinal integer;
  v_end_ordinal integer;
  v_local_ordinal integer;
begin
  if new.source_format<>'alto_xml' or new.ordinal is null then return new; end if;
  if new.observation_kind='line' then
    with regions as (
      select r.id,r.ordinal,(r.metadata->>'child_line_count')::integer as child_count,
        sum((r.metadata->>'child_line_count')::integer) over(order by r.ordinal rows unbounded preceding) as end_line
      from wnph.publication_source_observations r
      where r.source_asset_id=new.source_asset_id and r.source_format=new.source_format and r.processor=new.processor
        and r.observation_kind in ('region','layout_region') and nullif(r.metadata->>'child_line_count','') is not null
        and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=r.id)
    )
    select id,(end_line-child_count+1)::integer,end_line::integer into v_container_id,v_start_ordinal,v_end_ordinal
    from regions where new.ordinal between end_line-child_count+1 and end_line order by ordinal limit 1;
    if v_container_id is not null then
      v_local_ordinal:=new.ordinal-v_start_ordinal+1;
      if not exists(select 1 from wnph.publication_source_observation_relations r where r.child_observation_id=new.id and r.relation_kind='contains' and not exists(select 1 from wnph.publication_source_observation_relations c where c.supersedes_relation_id=r.id)) then
        insert into wnph.publication_source_observation_relations(source_asset_id,container_observation_id,child_observation_id,relation_kind,ordinal,derivation_method,evidence)
        values(new.source_asset_id,v_container_id,new.id,'contains',v_local_ordinal,'source_native_alto_textblock_line_order_v1',jsonb_build_object('authority','alto_textblock_child_order','line_global_ordinal',new.ordinal));
      end if;
    end if;
  elsif new.observation_kind in ('region','layout_region') and nullif(new.metadata->>'child_line_count','') is not null then
    with regions as (
      select r.id,r.ordinal,(r.metadata->>'child_line_count')::integer as child_count,
        sum((r.metadata->>'child_line_count')::integer) over(order by r.ordinal rows unbounded preceding) as end_line
      from wnph.publication_source_observations r
      where r.source_asset_id=new.source_asset_id and r.source_format=new.source_format and r.processor=new.processor
        and r.observation_kind in ('region','layout_region') and nullif(r.metadata->>'child_line_count','') is not null
        and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=r.id)
    ) select (end_line-child_count+1)::integer,end_line::integer into v_start_ordinal,v_end_ordinal from regions where id=new.id;
    if v_start_ordinal is not null then
      insert into wnph.publication_source_observation_relations(source_asset_id,container_observation_id,child_observation_id,relation_kind,ordinal,derivation_method,evidence)
      select new.source_asset_id,new.id,l.id,'contains',l.ordinal-v_start_ordinal+1,'source_native_alto_textblock_line_order_v1',jsonb_build_object('authority','alto_textblock_child_order','line_global_ordinal',l.ordinal)
      from wnph.publication_source_observations l
      where l.source_asset_id=new.source_asset_id and l.source_format=new.source_format and l.processor=new.processor and l.observation_kind='line'
        and l.ordinal between v_start_ordinal and v_end_ordinal
        and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=l.id)
        and not exists(select 1 from wnph.publication_source_observation_relations r where r.child_observation_id=l.id and r.relation_kind='contains' and not exists(select 1 from wnph.publication_source_observation_relations c where c.supersedes_relation_id=r.id));
    end if;
  end if;
  return new;
end;$function$;
revoke all on function wnph.capture_source_observation_containment_v1() from public,anon,authenticated,service_role;
create trigger publication_source_observations_capture_containment_v1 after insert on wnph.publication_source_observations for each row execute function wnph.capture_source_observation_containment_v1();

with regions as (
  select r.source_asset_id,r.id container_id,r.ordinal,(r.metadata->>'child_line_count')::integer child_count,
    sum((r.metadata->>'child_line_count')::integer) over(partition by r.source_asset_id,r.source_format,r.processor order by r.ordinal rows unbounded preceding) as end_line,
    r.source_format,r.processor
  from wnph.publication_source_observations r
  where r.source_format='alto_xml' and r.observation_kind in ('region','layout_region') and nullif(r.metadata->>'child_line_count','') is not null
    and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=r.id)
), mapped as (
  select rg.source_asset_id,rg.container_id,l.id child_id,l.ordinal-(rg.end_line-rg.child_count+1)+1 local_ordinal,l.ordinal global_ordinal
  from regions rg join wnph.publication_source_observations l on l.source_asset_id=rg.source_asset_id and l.source_format=rg.source_format and l.processor=rg.processor and l.observation_kind='line'
    and l.ordinal between rg.end_line-rg.child_count+1 and rg.end_line
  where not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=l.id)
)
insert into wnph.publication_source_observation_relations(source_asset_id,container_observation_id,child_observation_id,relation_kind,ordinal,derivation_method,evidence)
select source_asset_id,container_id,child_id,'contains',local_ordinal,'source_native_alto_textblock_line_order_v1',jsonb_build_object('authority','alto_textblock_child_order','line_global_ordinal',global_ordinal)
from mapped;

create or replace function public.wnph_reconstruction_source_packet_v3(p_source_package_key text,p_target_parent_block_key text,p_asset_keys text[] default null)
returns jsonb language plpgsql security definer stable set search_path to 'pg_catalog','public','wnph' as $function$
declare v_packet jsonb; v_relations jsonb;
begin
  v_packet:=public.wnph_reconstruction_source_packet_v2(p_source_package_key,p_target_parent_block_key,p_asset_keys);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'source_asset_id',r.source_asset_id,'container_observation_id',r.container_observation_id,'child_observation_id',r.child_observation_id,
    'relation_kind',r.relation_kind,'ordinal',r.ordinal,'derivation_method',r.derivation_method,'evidence',r.evidence
  ) order by r.source_asset_id,r.container_observation_id,r.ordinal nulls last,r.created_at),'[]'::jsonb) into v_relations
  from wnph.publication_source_observation_relations r
  where not exists(select 1 from wnph.publication_source_observation_relations c where c.supersedes_relation_id=r.id)
    and exists(select 1 from jsonb_array_elements(v_packet->'surfaces') s where (s->>'id')::uuid=r.source_asset_id);
  return v_packet || jsonb_build_object('observation_relations',v_relations);
end;$function$;
revoke all on function public.wnph_reconstruction_source_packet_v3(text,text,text[]) from public,anon,authenticated;
grant execute on function public.wnph_reconstruction_source_packet_v3(text,text,text[]) to service_role;

comment on table wnph.publication_source_observation_relations is 'Append-only source-native observation hierarchy. Records immediate containment such as ALTO TextBlock region -> physical TextLine so semantic source boundaries may cut through a coarse layout container without discarding its retained children.';
comment on function public.wnph_reconstruction_source_packet_v3(text,text,text[]) is 'Service-role reconstruction packet v3. Extends v2 with active source-observation containment relations needed for boundary fragmentation while preserving region-first reconstruction evidence.';

do $seed$
declare v_stream uuid; v_start_asset uuid; v_end_asset uuid; v_heading_line uuid; v_container uuid; v_body_line uuid;
begin
  select id into v_stream from wnph.publication_source_blocks b where b.block_key='dewy:chapter:2:paragraph-stream' and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id) order by created_at desc limit 1;
  select id into v_start_asset from wnph.publication_source_assets a where a.asset_key='dewy:loc:source-surface:0021' and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id) order by created_at desc limit 1;
  select id into v_end_asset from wnph.publication_source_assets a where a.asset_key='dewy:loc:source-surface:0030' and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id) order by created_at desc limit 1;
  select id into v_heading_line from wnph.publication_source_observations o where o.source_asset_id=v_start_asset and o.observation_kind='line' and o.ordinal=1 and o.source_format='alto_xml' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by created_at desc limit 1;
  select r.container_observation_id into v_container from wnph.publication_source_observation_relations r where r.child_observation_id=v_heading_line and r.relation_kind='contains' and not exists(select 1 from wnph.publication_source_observation_relations c where c.supersedes_relation_id=r.id) order by r.created_at desc limit 1;
  select id into v_body_line from wnph.publication_source_observations o where o.source_asset_id=v_start_asset and o.observation_kind='line' and o.ordinal=2 and o.source_format='alto_xml' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by created_at desc limit 1;
  if v_stream is null or v_start_asset is null or v_end_asset is null or v_heading_line is null or v_container is null or v_body_line is null then raise exception 'WNPH Chapter II boundary seed prerequisites missing'; end if;
  if not exists(select 1 from wnph.publication_source_observation_relations r where r.container_observation_id=v_container and r.child_observation_id=v_body_line and r.relation_kind='contains' and not exists(select 1 from wnph.publication_source_observation_relations c where c.supersedes_relation_id=r.id)) then raise exception 'WNPH Chapter II mixed region does not contain both heading and first prose lines'; end if;
  if exists(select 1 from wnph.publication_source_block_spans s where s.block_id=v_stream and not exists(select 1 from wnph.publication_source_block_spans c where c.supersedes_span_id=s.id)) then raise exception 'WNPH Chapter II paragraph stream unexpectedly already has a source span'; end if;
  insert into wnph.publication_source_block_spans(source_package_id,block_id,span_key,start_asset_id,start_observation_id,start_boundary,end_asset_id,end_observation_id,end_boundary,boundary_authority,derivation_method,evidence)
  select b.source_package_id,v_stream,'dewy:chapter:2:paragraph-stream:source-span:v1',v_start_asset,v_heading_line,'after_observation',v_end_asset,null,'asset_end','source_observed_semantic_structure','source_native_observation_containment_boundary_v1',
    jsonb_build_object('opening_container_observation_id',v_container,'excluded_heading_observation_id',v_heading_line,'retained_first_body_observation_id',v_body_line,'boundary_crosses_layout_container',true)
  from wnph.publication_source_blocks b where b.id=v_stream;
  if exists(select 1 from wnph.publication_source_reconstruction_proposals p where not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id)) then raise exception 'WNPH containment migration must not create live reconstruction proposals'; end if;
  if exists(select 1 from wnph.publication_source_blocks b where b.parent_block_id=v_stream and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)) then raise exception 'WNPH containment migration must not create Chapter II paragraph blocks'; end if;
end;$seed$;