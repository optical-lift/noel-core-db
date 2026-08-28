create table wnph.publication_source_block_spans (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  block_id uuid not null references wnph.publication_source_blocks(id),
  span_key text not null check (btrim(span_key) <> ''),
  start_asset_id uuid not null references wnph.publication_source_assets(id),
  start_observation_id uuid references wnph.publication_source_observations(id),
  start_boundary text not null check (start_boundary in ('asset_start','at_observation','after_observation')),
  end_asset_id uuid not null references wnph.publication_source_assets(id),
  end_observation_id uuid references wnph.publication_source_observations(id),
  end_boundary text not null check (end_boundary in ('asset_end','at_observation','before_observation')),
  boundary_authority text not null check (btrim(boundary_authority) <> ''),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  evidence jsonb not null default '{}'::jsonb,
  supersedes_span_id uuid references wnph.publication_source_block_spans(id),
  created_at timestamptz not null default now(),
  constraint publication_source_block_spans_start_anchor_ck check (
    (start_boundary='asset_start' and start_observation_id is null)
    or (start_boundary in ('at_observation','after_observation') and start_observation_id is not null)
  ),
  constraint publication_source_block_spans_end_anchor_ck check (
    (end_boundary='asset_end' and end_observation_id is null)
    or (end_boundary in ('at_observation','before_observation') and end_observation_id is not null)
  ),
  constraint publication_source_block_spans_supersedes_not_self_ck check (
    supersedes_span_id is null or supersedes_span_id <> id
  )
);

comment on table wnph.publication_source_block_spans is
  'Append-only governed source-to-semantic span. Binds one semantic publication block to exact source-surface boundaries, optionally anchored at located observations, so reconstruction receives only evidence belonging to that semantic parent.';

create index publication_source_block_spans_package_idx
  on wnph.publication_source_block_spans(source_package_id);
create index publication_source_block_spans_block_idx
  on wnph.publication_source_block_spans(block_id);
create index publication_source_block_spans_start_asset_idx
  on wnph.publication_source_block_spans(start_asset_id);
create index publication_source_block_spans_start_observation_idx
  on wnph.publication_source_block_spans(start_observation_id)
  where start_observation_id is not null;
create index publication_source_block_spans_end_asset_idx
  on wnph.publication_source_block_spans(end_asset_id);
create index publication_source_block_spans_end_observation_idx
  on wnph.publication_source_block_spans(end_observation_id)
  where end_observation_id is not null;
create index publication_source_block_spans_supersedes_idx
  on wnph.publication_source_block_spans(supersedes_span_id)
  where supersedes_span_id is not null;

alter table wnph.publication_source_block_spans enable row level security;
revoke all on wnph.publication_source_block_spans from public,anon,authenticated,service_role;

create or replace function wnph.validate_publication_source_block_span_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_block wnph.publication_source_blocks%rowtype;
  v_start_asset wnph.publication_source_assets%rowtype;
  v_end_asset wnph.publication_source_assets%rowtype;
  v_start_observation wnph.publication_source_observations%rowtype;
  v_end_observation wnph.publication_source_observations%rowtype;
  v_old wnph.publication_source_block_spans%rowtype;
  v_start_sort numeric;
  v_end_sort numeric;
begin
  if jsonb_typeof(new.evidence) <> 'object' then
    raise exception 'WNPH source span: evidence must be an object';
  end if;

  select * into v_block
  from wnph.publication_source_blocks b
  where b.id=new.block_id
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);
  if v_block.id is null or v_block.source_package_id<>new.source_package_id then
    raise exception 'WNPH source span: block must be active and belong to the same source package';
  end if;

  select * into v_start_asset
  from wnph.publication_source_assets a
  where a.id=new.start_asset_id
    and a.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id);
  select * into v_end_asset
  from wnph.publication_source_assets a
  where a.id=new.end_asset_id
    and a.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id);

  if v_start_asset.id is null or v_start_asset.source_package_id<>new.source_package_id
     or v_end_asset.id is null or v_end_asset.source_package_id<>new.source_package_id then
    raise exception 'WNPH source span: boundary assets must be active source surfaces in the same source package';
  end if;

  v_start_sort:=coalesce(nullif(v_start_asset.source_locator->>'sequence_index','')::numeric,
                         nullif(v_start_asset.source_locator->>'printed_page','')::numeric,
                         nullif(v_start_asset.source_locator->>'source_pdf_page','')::numeric,
                         nullif(v_start_asset.source_locator->>'pdf_page','')::numeric);
  v_end_sort:=coalesce(nullif(v_end_asset.source_locator->>'sequence_index','')::numeric,
                       nullif(v_end_asset.source_locator->>'printed_page','')::numeric,
                       nullif(v_end_asset.source_locator->>'source_pdf_page','')::numeric,
                       nullif(v_end_asset.source_locator->>'pdf_page','')::numeric);
  if v_start_sort is null or v_end_sort is null or v_start_sort>v_end_sort then
    raise exception 'WNPH source span: boundary assets require ordered source locators with start <= end';
  end if;

  if new.start_observation_id is not null then
    select * into v_start_observation
    from wnph.publication_source_observations o
    where o.id=new.start_observation_id
      and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
    if v_start_observation.id is null or v_start_observation.source_asset_id<>new.start_asset_id then
      raise exception 'WNPH source span: start observation must be active and belong to the start asset';
    end if;
  end if;

  if new.end_observation_id is not null then
    select * into v_end_observation
    from wnph.publication_source_observations o
    where o.id=new.end_observation_id
      and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
    if v_end_observation.id is null or v_end_observation.source_asset_id<>new.end_asset_id then
      raise exception 'WNPH source span: end observation must be active and belong to the end asset';
    end if;
  end if;

  if new.supersedes_span_id is not null then
    select * into v_old from wnph.publication_source_block_spans where id=new.supersedes_span_id;
    if v_old.id is null
       or v_old.source_package_id<>new.source_package_id
       or v_old.block_id<>new.block_id
       or v_old.span_key<>new.span_key then
      raise exception 'WNPH source span: supersession must preserve package, block and span_key';
    end if;
    if exists(select 1 from wnph.publication_source_block_spans s where s.supersedes_span_id=v_old.id) then
      raise exception 'WNPH source span: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1 from wnph.publication_source_block_spans s
    where s.block_id=new.block_id
      and not exists(select 1 from wnph.publication_source_block_spans child where child.supersedes_span_id=s.id)
  ) then
    raise exception 'WNPH source span: block % already has an active source span',new.block_id;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_block_span_v1() from public,anon,authenticated,service_role;

create trigger publication_source_block_spans_insert_validation_v1
before insert on wnph.publication_source_block_spans
for each row execute function wnph.validate_publication_source_block_span_v1();

create trigger publication_source_block_spans_append_only
before update or delete on wnph.publication_source_block_spans
for each row execute function wnph.reject_append_only_mutation();

create or replace function public.wnph_reconstruction_source_packet_v2(
  p_source_package_key text,
  p_target_parent_block_key text,
  p_asset_keys text[] default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_pkg_id uuid;
  v_parent wnph.publication_source_blocks%rowtype;
  v_span wnph.publication_source_block_spans%rowtype;
  v_start_asset wnph.publication_source_assets%rowtype;
  v_end_asset wnph.publication_source_assets%rowtype;
  v_surfaces jsonb;
  v_max_ordinal integer;
  v_child_count integer;
  v_start_sort numeric;
  v_end_sort numeric;
begin
  if coalesce(btrim(p_source_package_key),'')='' or coalesce(btrim(p_target_parent_block_key),'')='' then
    raise exception 'WNPH reconstruction packet v2: source package key and target parent block key are required';
  end if;

  select p.id into v_pkg_id
  from wnph.publication_source_packages p
  where p.canonical_key=p_source_package_key
    and not exists(select 1 from wnph.publication_source_packages child where child.supersedes_package_id=p.id)
  order by p.created_at desc
  limit 1;
  if v_pkg_id is null then
    raise exception 'WNPH reconstruction packet v2: active source package not found for %',p_source_package_key;
  end if;

  select b.* into v_parent
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg_id
    and b.block_key=p_target_parent_block_key
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id)
  order by b.created_at desc
  limit 1;
  if v_parent.id is null then
    raise exception 'WNPH reconstruction packet v2: active target parent block not found for %',p_target_parent_block_key;
  end if;

  select s.* into v_span
  from wnph.publication_source_block_spans s
  where s.block_id=v_parent.id
    and not exists(select 1 from wnph.publication_source_block_spans child where child.supersedes_span_id=s.id)
  order by s.created_at desc
  limit 1;

  if v_span.id is not null then
    select * into v_start_asset from wnph.publication_source_assets where id=v_span.start_asset_id;
    select * into v_end_asset from wnph.publication_source_assets where id=v_span.end_asset_id;
    v_start_sort:=coalesce(nullif(v_start_asset.source_locator->>'sequence_index','')::numeric,
                           nullif(v_start_asset.source_locator->>'printed_page','')::numeric,
                           nullif(v_start_asset.source_locator->>'source_pdf_page','')::numeric,
                           nullif(v_start_asset.source_locator->>'pdf_page','')::numeric);
    v_end_sort:=coalesce(nullif(v_end_asset.source_locator->>'sequence_index','')::numeric,
                         nullif(v_end_asset.source_locator->>'printed_page','')::numeric,
                         nullif(v_end_asset.source_locator->>'source_pdf_page','')::numeric,
                         nullif(v_end_asset.source_locator->>'pdf_page','')::numeric);
  end if;

  select coalesce(max(b.ordinal),0),count(*) into v_max_ordinal,v_child_count
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg_id
    and b.parent_block_id=v_parent.id
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);

  select coalesce(jsonb_agg(surface_packet order by sort_sequence,sort_page,asset_key),'[]'::jsonb)
    into v_surfaces
  from (
    select asset_key,sort_sequence,sort_page,
      jsonb_build_object(
        'id',id,
        'asset_key',asset_key,
        'media_type',media_type,
        'storage_uri',storage_uri,
        'source_locator',source_locator,
        'metadata',metadata,
        'observations',coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id',o.id,
              'observation_key',o.observation_key,
              'observation_kind',o.observation_kind,
              'ordinal',o.ordinal,
              'text_candidate',o.text_candidate,
              'coordinate_unit',o.coordinate_unit,
              'x',o.x,'y',o.y,'width',o.width,'height',o.height,
              'confidence',o.confidence,
              'derivation_method',o.derivation_method,
              'source_format',o.source_format,
              'processor',o.processor,
              'external_locator',o.external_locator,
              'metadata',o.metadata
            )
            order by
              case o.observation_kind when 'layout_region' then 1 when 'region' then 2 when 'line' then 3 when 'word' then 4 when 'page_text' then 5 else 6 end,
              o.ordinal nulls last,o.y nulls last,o.x nulls last,o.created_at
          )
          from wnph.publication_source_observations o
          where o.source_asset_id=id
            and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id)
        ),'[]'::jsonb)
      ) as surface_packet
    from (
      select a.*,
        coalesce(nullif(a.source_locator->>'sequence_index','')::numeric,
                 nullif(a.source_locator->>'printed_page','')::numeric,
                 nullif(a.source_locator->>'source_pdf_page','')::numeric,
                 nullif(a.source_locator->>'pdf_page','')::numeric,
                 999999999::numeric) as sort_sequence,
        coalesce(nullif(a.source_locator->>'printed_page','')::numeric,
                 nullif(a.source_locator->>'source_pdf_page','')::numeric,
                 nullif(a.source_locator->>'pdf_page','')::numeric,
                 999999999::numeric) as sort_page
      from wnph.publication_source_assets a
      where a.source_package_id=v_pkg_id
        and a.asset_role='source_surface'
        and (p_asset_keys is null or a.asset_key=any(p_asset_keys))
        and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id)
    ) bounded
    where v_span.id is null or (sort_sequence>=v_start_sort and sort_sequence<=v_end_sort)
  ) s;

  if jsonb_array_length(v_surfaces)=0 then
    raise exception 'WNPH reconstruction packet v2: no active source surfaces matched the request and governed span';
  end if;

  return jsonb_build_object(
    'source_package_key',p_source_package_key,
    'source_package_id',v_pkg_id,
    'target_parent_block',jsonb_build_object(
      'id',v_parent.id,
      'block_key',v_parent.block_key,
      'block_type',v_parent.block_type,
      'semantic_role',v_parent.semantic_role,
      'properties',v_parent.properties
    ),
    'source_span',case when v_span.id is null then null else jsonb_build_object(
      'id',v_span.id,
      'span_key',v_span.span_key,
      'start_asset_id',v_span.start_asset_id,
      'start_asset_key',v_start_asset.asset_key,
      'start_observation_id',v_span.start_observation_id,
      'start_boundary',v_span.start_boundary,
      'end_asset_id',v_span.end_asset_id,
      'end_asset_key',v_end_asset.asset_key,
      'end_observation_id',v_span.end_observation_id,
      'end_boundary',v_span.end_boundary,
      'boundary_authority',v_span.boundary_authority,
      'derivation_method',v_span.derivation_method,
      'evidence',v_span.evidence
    ) end,
    'existing_child_count',v_child_count,
    'existing_max_ordinal',v_max_ordinal,
    'surfaces',v_surfaces
  );
end;
$function$;

revoke all on function public.wnph_reconstruction_source_packet_v2(text,text,text[]) from public,anon,authenticated;
grant execute on function public.wnph_reconstruction_source_packet_v2(text,text,text[]) to service_role;

comment on function public.wnph_reconstruction_source_packet_v2(text,text,text[]) is
  'Service-only reconstruction packet with governed semantic source-span custody. Source surfaces are bounded to the target semantic block before the reconstruction worker receives them.';

with basis as (
  select p.id as source_package_id,
         stream.id as block_id,
         start_asset.id as start_asset_id,
         heading.id as start_observation_id,
         end_asset.id as end_asset_id,
         chapter.properties as chapter_properties
  from wnph.publication_source_packages p
  join wnph.publication_source_blocks chapter
    on chapter.source_package_id=p.id and chapter.block_key='dewy:chapter:1'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=chapter.id)
  join wnph.publication_source_blocks stream
    on stream.source_package_id=p.id and stream.block_key='dewy:chapter:1:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=stream.id)
  join wnph.publication_source_assets start_asset
    on start_asset.source_package_id=p.id and start_asset.asset_key='dewy:loc:source-surface:0011'
    and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=start_asset.id)
  join wnph.publication_source_observations heading
    on heading.source_asset_id=start_asset.id
    and heading.observation_kind in ('region','layout_region')
    and btrim(heading.text_candidate)='CHAPTER I'
    and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=heading.id)
  join wnph.publication_source_assets end_asset
    on end_asset.source_package_id=p.id and end_asset.asset_key='dewy:loc:source-surface:0020'
    and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=end_asset.id)
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id)
    and chapter.properties->>'printed_page_start'='7'
    and chapter.properties->>'printed_page_end'='16'
  limit 1
)
insert into wnph.publication_source_block_spans(
  source_package_id,block_id,span_key,start_asset_id,start_observation_id,start_boundary,
  end_asset_id,end_observation_id,end_boundary,boundary_authority,derivation_method,evidence
)
select source_package_id,block_id,'dewy:chapter:1:paragraph-stream:source-span:v1',
       start_asset_id,start_observation_id,'after_observation',
       end_asset_id,null,'asset_end',
       'source_observed_semantic_structure',
       'chapter_heading_anchor_plus_governed_chapter_surface_span',
       jsonb_build_object(
         'start_marker_text','CHAPTER I',
         'printed_page_start',chapter_properties->'printed_page_start',
         'printed_page_end',chapter_properties->'printed_page_end',
         'purpose','exclude pre-chapter title material from Chapter I paragraph reconstruction'
       )
from basis;

do $verify$
declare
  v_packet jsonb;
  v_span_count integer;
  v_rejected boolean:=false;
begin
  select count(*) into v_span_count
  from wnph.publication_source_block_spans s
  join wnph.publication_source_blocks b on b.id=s.block_id
  where b.block_key='dewy:chapter:1:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_block_spans c where c.supersedes_span_id=s.id);
  if v_span_count<>1 then
    raise exception 'WNPH semantic source span fixture expected 1 active Chapter I span, got %',v_span_count;
  end if;

  select public.wnph_reconstruction_source_packet_v2(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:1:paragraph-stream',
    null
  ) into v_packet;

  if jsonb_array_length(v_packet->'surfaces')<>10
     or v_packet->'surfaces'->0->>'asset_key'<>'dewy:loc:source-surface:0011'
     or v_packet->'surfaces'->9->>'asset_key'<>'dewy:loc:source-surface:0020'
     or v_packet->'source_span'->>'start_boundary'<>'after_observation'
     or v_packet->'source_span'->>'end_boundary'<>'asset_end' then
    raise exception 'WNPH reconstruction packet v2 span fixture failed: %',v_packet;
  end if;

  begin
    insert into wnph.publication_source_block_spans(
      source_package_id,block_id,span_key,start_asset_id,start_observation_id,start_boundary,
      end_asset_id,end_boundary,boundary_authority,derivation_method
    )
    select b.source_package_id,b.id,'fixture:wrong-observation-asset',a11.id,o12.id,'after_observation',a20.id,'asset_end','fixture','fixture'
    from wnph.publication_source_blocks b
    join wnph.publication_source_assets a11 on a11.source_package_id=b.source_package_id and a11.asset_key='dewy:loc:source-surface:0011'
    join wnph.publication_source_assets a12 on a12.source_package_id=b.source_package_id and a12.asset_key='dewy:loc:source-surface:0012'
    join wnph.publication_source_observations o12 on o12.source_asset_id=a12.id and o12.observation_kind='region'
    join wnph.publication_source_assets a20 on a20.source_package_id=b.source_package_id and a20.asset_key='dewy:loc:source-surface:0020'
    where b.block_key='dewy:chapter:1'
    limit 1;
  exception when others then
    v_rejected:=true;
  end;
  if not v_rejected then
    raise exception 'WNPH source span negative control accepted observation from wrong boundary asset';
  end if;

  begin
    update wnph.publication_source_block_spans
    set boundary_authority='rewritten'
    where span_key='dewy:chapter:1:paragraph-stream:source-span:v1';
    raise exception 'WNPH source span append-only negative control unexpectedly allowed update';
  exception when others then
    if sqlerrm='WNPH source span append-only negative control unexpectedly allowed update' then raise; end if;
  end;
end;
$verify$;