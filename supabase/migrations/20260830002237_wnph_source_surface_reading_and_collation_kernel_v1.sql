create table wnph.publication_source_surface_readings (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  source_asset_id uuid not null references wnph.publication_source_assets(id),
  reading_key text not null unique check (btrim(reading_key) <> ''),
  reading_kind text not null check (reading_kind in ('text','mixed','nontext')),
  reading_state text not null check (reading_state in ('proposed','verified','needs_adjudication','rejected','unresolved')),
  reading_text text,
  reading_text_sha256 text,
  source_image_sha256 text,
  verification_authority text not null check (btrim(verification_authority) <> ''),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  supersedes_reading_id uuid references wnph.publication_source_surface_readings(id),
  created_at timestamptz not null default now(),
  constraint publication_source_surface_readings_not_self_ck check (supersedes_reading_id is null or supersedes_reading_id <> id),
  constraint publication_source_surface_readings_text_shape_ck check (
    (reading_kind='nontext' and reading_text is null and reading_text_sha256 is null)
    or
    (reading_kind in ('text','mixed') and coalesce(btrim(reading_text),'') <> '' and reading_text_sha256 ~ '^[0-9a-f]{64}$')
  ),
  constraint publication_source_surface_readings_image_hash_ck check (
    source_image_sha256 is null or source_image_sha256 ~ '^[0-9a-f]{64}$'
  ),
  constraint publication_source_surface_readings_verified_evidence_ck check (
    reading_state <> 'verified'
    or (
      source_image_sha256 ~ '^[0-9a-f]{64}$'
      and evidence->>'pixel_inspected' = 'true'
    )
  )
);

create unique index publication_source_surface_readings_one_root_per_asset_uidx
  on wnph.publication_source_surface_readings(source_asset_id)
  where supersedes_reading_id is null;
create unique index publication_source_surface_readings_one_child_uidx
  on wnph.publication_source_surface_readings(supersedes_reading_id)
  where supersedes_reading_id is not null;
create index publication_source_surface_readings_package_idx
  on wnph.publication_source_surface_readings(source_package_id,created_at desc);
create index publication_source_surface_readings_asset_idx
  on wnph.publication_source_surface_readings(source_asset_id,created_at desc);

create table wnph.publication_source_surface_reading_spans (
  id uuid primary key default gen_random_uuid(),
  surface_reading_id uuid not null references wnph.publication_source_surface_readings(id),
  ordinal integer not null check (ordinal >= 1),
  span_kind text not null check (span_kind in ('line','region','page_furniture','uncertain','nontext')),
  text_content text,
  coordinate_unit text not null default 'surface' check (coordinate_unit in ('pixel','percent','alto_1_1200in','alto_1_10mm','surface')),
  x numeric,
  y numeric,
  width numeric,
  height numeric,
  source_observation_ids uuid[] not null default '{}'::uuid[],
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  created_at timestamptz not null default now(),
  constraint publication_source_surface_reading_spans_ordinal_uq unique(surface_reading_id,ordinal),
  constraint publication_source_surface_reading_spans_text_shape_ck check (
    (span_kind='nontext' and text_content is null)
    or
    (span_kind<>'nontext' and coalesce(btrim(text_content),'') <> '')
  ),
  constraint publication_source_surface_reading_spans_geometry_ck check (
    ((x is null) and (y is null) and (width is null) and (height is null))
    or
    ((x is not null) and (y is not null) and (width is not null) and (height is not null) and x >= 0 and y >= 0 and width > 0 and height > 0)
  ),
  constraint publication_source_surface_reading_spans_surface_geometry_ck check (
    coordinate_unit <> 'surface' or (x is null and y is null and width is null and height is null)
  )
);
create index publication_source_surface_reading_spans_reading_idx
  on wnph.publication_source_surface_reading_spans(surface_reading_id,ordinal);
create index publication_source_surface_reading_spans_observation_ids_gin
  on wnph.publication_source_surface_reading_spans using gin(source_observation_ids);

alter table wnph.publication_source_surface_readings enable row level security;
alter table wnph.publication_source_surface_reading_spans enable row level security;

revoke all on table wnph.publication_source_surface_readings from public, anon, authenticated, service_role;
revoke all on table wnph.publication_source_surface_reading_spans from public, anon, authenticated, service_role;

create or replace function wnph.prevent_source_surface_reading_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','wnph'
as $$
begin
  raise exception 'WNPH source surface readings are append-only; supersede with a new governed reading instead' using errcode='55000';
end;
$$;

create trigger publication_source_surface_readings_append_only_trg
before update or delete on wnph.publication_source_surface_readings
for each row execute function wnph.prevent_source_surface_reading_mutation_v1();

create trigger publication_source_surface_reading_spans_append_only_trg
before update or delete on wnph.publication_source_surface_reading_spans
for each row execute function wnph.prevent_source_surface_reading_mutation_v1();

create or replace function public.wnph_record_source_surface_reading_v1(
  p_source_package_key text,
  p_asset_key text,
  p_reading_key text,
  p_reading_kind text,
  p_reading_state text,
  p_reading_text text,
  p_source_image_sha256 text,
  p_verification_authority text,
  p_derivation_method text,
  p_confidence numeric,
  p_evidence jsonb,
  p_spans jsonb default '[]'::jsonb,
  p_supersedes_reading_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','wnph','public'
as $$
declare
  v_package wnph.publication_source_packages%rowtype;
  v_asset wnph.publication_source_assets%rowtype;
  v_old wnph.publication_source_surface_readings%rowtype;
  v_reading_id uuid;
  v_span jsonb;
  v_span_kind text;
  v_span_ordinal integer;
  v_obs_keys text[];
  v_obs_ids uuid[];
  v_obs_count integer;
  v_span_count integer := 0;
  v_text_hash text;
begin
  if coalesce(btrim(p_source_package_key),'')='' or coalesce(btrim(p_asset_key),'')='' or coalesce(btrim(p_reading_key),'')='' then
    raise exception 'WNPH surface reading: package key, asset key, and reading key are required' using errcode='22023';
  end if;
  if p_reading_kind not in ('text','mixed','nontext') then
    raise exception 'WNPH surface reading: unsupported reading_kind %',p_reading_kind using errcode='22023';
  end if;
  if p_reading_state not in ('proposed','verified','needs_adjudication','rejected','unresolved') then
    raise exception 'WNPH surface reading: unsupported reading_state %',p_reading_state using errcode='22023';
  end if;
  if coalesce(btrim(p_verification_authority),'')='' or coalesce(btrim(p_derivation_method),'')='' then
    raise exception 'WNPH surface reading: verification authority and derivation method are required' using errcode='22023';
  end if;
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then
    raise exception 'WNPH surface reading: confidence must be between 0 and 1' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then
    raise exception 'WNPH surface reading: evidence must be an object' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_spans,'[]'::jsonb)) <> 'array' then
    raise exception 'WNPH surface reading: spans must be an array' using errcode='22023';
  end if;

  select * into v_package
  from wnph.publication_source_packages p
  where p.canonical_key=p_source_package_key
    and not exists(select 1 from wnph.publication_source_packages child where child.supersedes_package_id=p.id)
  order by p.created_at desc limit 1;
  if v_package.id is null then raise exception 'WNPH surface reading: active source package not found' using errcode='P0002'; end if;

  select * into v_asset
  from wnph.publication_source_assets a
  where a.source_package_id=v_package.id and a.asset_key=p_asset_key and a.asset_role='source_surface'
    and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id)
  order by a.created_at desc limit 1;
  if v_asset.id is null then raise exception 'WNPH surface reading: active source surface not found' using errcode='P0002'; end if;

  if p_reading_kind='nontext' then
    if p_reading_text is not null then raise exception 'WNPH surface reading: nontext reading cannot carry reading_text' using errcode='22023'; end if;
    v_text_hash := null;
  else
    if coalesce(btrim(p_reading_text),'')='' then raise exception 'WNPH surface reading: text/mixed reading requires reading_text' using errcode='22023'; end if;
    v_text_hash := encode(extensions.digest(convert_to(p_reading_text,'UTF8'),'sha256'),'hex');
  end if;

  if p_reading_state='verified' then
    if coalesce(p_source_image_sha256,'') !~ '^[0-9a-f]{64}$' then
      raise exception 'WNPH surface reading: verified reading requires exact source-image SHA-256' using errcode='22023';
    end if;
    if coalesce((p_evidence->>'pixel_inspected')::boolean,false) is not true then
      raise exception 'WNPH surface reading: verified reading requires evidence.pixel_inspected=true' using errcode='55000';
    end if;
  elsif p_source_image_sha256 is not null and p_source_image_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'WNPH surface reading: source-image SHA-256 is malformed' using errcode='22023';
  end if;

  if p_supersedes_reading_key is null then
    if exists(select 1 from wnph.publication_source_surface_readings r where r.source_asset_id=v_asset.id) then
      raise exception 'WNPH surface reading: this surface already has a reading lineage; supersede the active leaf explicitly' using errcode='23505';
    end if;
  else
    select * into v_old
    from wnph.publication_source_surface_readings r
    where r.reading_key=p_supersedes_reading_key;
    if v_old.id is null then raise exception 'WNPH surface reading: superseded reading not found' using errcode='P0002'; end if;
    if v_old.source_package_id<>v_package.id or v_old.source_asset_id<>v_asset.id then
      raise exception 'WNPH surface reading: supersession cannot cross package or source surface' using errcode='55000';
    end if;
    if exists(select 1 from wnph.publication_source_surface_readings child where child.supersedes_reading_id=v_old.id) then
      raise exception 'WNPH surface reading: superseded reading is not the active leaf' using errcode='55000';
    end if;
  end if;

  insert into wnph.publication_source_surface_readings(
    source_package_id,source_asset_id,reading_key,reading_kind,reading_state,reading_text,reading_text_sha256,
    source_image_sha256,verification_authority,derivation_method,confidence,evidence,supersedes_reading_id
  ) values(
    v_package.id,v_asset.id,p_reading_key,p_reading_kind,p_reading_state,p_reading_text,v_text_hash,
    p_source_image_sha256,p_verification_authority,p_derivation_method,p_confidence,
    coalesce(p_evidence,'{}'::jsonb) || jsonb_build_object(
      'source_asset_key',v_asset.asset_key,
      'source_locator_snapshot',v_asset.source_locator,
      'storage_uri_snapshot',v_asset.storage_uri,
      'page_image_is_authority',true,
      'ocr_is_not_verification_authority',true
    ),
    v_old.id
  ) returning id into v_reading_id;

  for v_span in select value from jsonb_array_elements(coalesce(p_spans,'[]'::jsonb))
  loop
    if jsonb_typeof(v_span)<>'object' then raise exception 'WNPH surface reading: every span must be an object' using errcode='22023'; end if;
    v_span_ordinal := nullif(v_span->>'ordinal','')::integer;
    v_span_kind := coalesce(v_span->>'span_kind','line');
    if v_span_ordinal is null or v_span_ordinal < 1 then raise exception 'WNPH surface reading: every span requires ordinal >= 1' using errcode='22023'; end if;
    if v_span_kind not in ('line','region','page_furniture','uncertain','nontext') then raise exception 'WNPH surface reading: invalid span_kind %',v_span_kind using errcode='22023'; end if;
    if p_reading_state='verified' and coalesce((coalesce(v_span->'evidence','{}'::jsonb)->>'pixel_verified')::boolean,false) is not true then
      raise exception 'WNPH surface reading: every span in a verified reading requires evidence.pixel_verified=true' using errcode='55000';
    end if;

    v_obs_keys := '{}';
    if v_span ? 'source_observation_keys' then
      if jsonb_typeof(v_span->'source_observation_keys') <> 'array' then raise exception 'WNPH surface reading: source_observation_keys must be an array' using errcode='22023'; end if;
      select coalesce(array_agg(x),'{}'::text[]) into v_obs_keys from jsonb_array_elements_text(v_span->'source_observation_keys') x;
    end if;
    if cardinality(v_obs_keys)>0 then
      select coalesce(array_agg(o.id order by o.observation_key),'{}'::uuid[]),count(*)
      into v_obs_ids,v_obs_count
      from wnph.publication_source_observations o
      where o.source_asset_id=v_asset.id and o.observation_key=any(v_obs_keys)
        and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
      if v_obs_count <> cardinality(v_obs_keys) then
        raise exception 'WNPH surface reading: one or more span observation keys are not active observations on this surface' using errcode='22023';
      end if;
    else
      v_obs_ids := '{}';
    end if;

    insert into wnph.publication_source_surface_reading_spans(
      surface_reading_id,ordinal,span_kind,text_content,coordinate_unit,x,y,width,height,source_observation_ids,evidence
    ) values(
      v_reading_id,v_span_ordinal,v_span_kind,
      case when v_span_kind='nontext' then null else v_span->>'text_content' end,
      coalesce(v_span->>'coordinate_unit','surface'),
      nullif(v_span->>'x','')::numeric,nullif(v_span->>'y','')::numeric,
      nullif(v_span->>'width','')::numeric,nullif(v_span->>'height','')::numeric,
      v_obs_ids,coalesce(v_span->'evidence','{}'::jsonb)
    );
    v_span_count := v_span_count + 1;
  end loop;

  if p_reading_state='verified' and p_reading_kind in ('text','mixed') and v_span_count=0 then
    raise exception 'WNPH surface reading: verified text/mixed reading requires at least one pixel-verified span' using errcode='55000';
  end if;

  return jsonb_build_object(
    'surface_reading_id',v_reading_id,
    'reading_key',p_reading_key,
    'asset_key',p_asset_key,
    'reading_kind',p_reading_kind,
    'reading_state',p_reading_state,
    'reading_text_sha256',v_text_hash,
    'source_image_sha256',p_source_image_sha256,
    'span_count',v_span_count,
    'supersedes_reading_id',v_old.id
  );
end;
$$;

create or replace function public.wnph_source_surface_reading_packet_v1(
  p_source_package_key text,
  p_asset_keys text[] default null
)
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','wnph','public'
as $$
  with pkg as (
    select p.* from wnph.publication_source_packages p
    where p.canonical_key=p_source_package_key
      and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id)
    order by p.created_at desc limit 1
  ), assets as (
    select a.* from wnph.publication_source_assets a join pkg p on p.id=a.source_package_id
    where a.asset_role='source_surface'
      and (p_asset_keys is null or a.asset_key=any(p_asset_keys))
      and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id)
  )
  select jsonb_build_object(
    'contract_version','wnph_source_surface_reading_packet_v1',
    'truth_boundary',jsonb_build_object(
      'source_surface_is_verification_unit',true,
      'page_image_must_be_literally_inspected',true,
      'ocr_is_observation_not_authority',true,
      'verified_reading_is_append_only',true,
      'candidate_blocks_must_collate_against_verified_surface_readings',true,
      'surface_verification_does_not_itself_admit_canonical_text',true
    ),
    'source_package_key',p_source_package_key,
    'surfaces',coalesce(jsonb_agg(jsonb_build_object(
      'id',a.id,
      'asset_key',a.asset_key,
      'media_type',a.media_type,
      'storage_uri',a.storage_uri,
      'source_locator',a.source_locator,
      'metadata',a.metadata,
      'observations',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',o.id,'observation_key',o.observation_key,'observation_kind',o.observation_kind,'ordinal',o.ordinal,
          'text_candidate',o.text_candidate,'coordinate_unit',o.coordinate_unit,
          'x',o.x,'y',o.y,'width',o.width,'height',o.height,'confidence',o.confidence,
          'derivation_method',o.derivation_method,'source_format',o.source_format,'processor',o.processor,
          'external_locator',o.external_locator,'metadata',o.metadata
        ) order by o.ordinal nulls last,o.y nulls last,o.x nulls last,o.created_at)
        from wnph.publication_source_observations o
        where o.source_asset_id=a.id
          and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id)
      ),'[]'::jsonb),
      'active_surface_reading',(
        select jsonb_build_object(
          'id',r.id,'reading_key',r.reading_key,'reading_kind',r.reading_kind,'reading_state',r.reading_state,
          'reading_text',r.reading_text,'reading_text_sha256',r.reading_text_sha256,'source_image_sha256',r.source_image_sha256,
          'verification_authority',r.verification_authority,'derivation_method',r.derivation_method,'confidence',r.confidence,
          'evidence',r.evidence,'created_at',r.created_at,
          'spans',coalesce((select jsonb_agg(to_jsonb(s) order by s.ordinal) from wnph.publication_source_surface_reading_spans s where s.surface_reading_id=r.id),'[]'::jsonb)
        )
        from wnph.publication_source_surface_readings r
        where r.source_asset_id=a.id
          and not exists(select 1 from wnph.publication_source_surface_readings c where c.supersedes_reading_id=r.id)
        order by r.created_at desc limit 1
      ),
      'reading_history',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'reading_key',r.reading_key,'reading_kind',r.reading_kind,'reading_state',r.reading_state,'reading_text_sha256',r.reading_text_sha256,'source_image_sha256',r.source_image_sha256,'supersedes_reading_id',r.supersedes_reading_id,'created_at',r.created_at) order by r.created_at) from wnph.publication_source_surface_readings r where r.source_asset_id=a.id),'[]'::jsonb)
    ) order by coalesce((a.source_locator->>'source_pdf_page')::int,2147483647),a.asset_key),'[]'::jsonb)
  )
  from assets a;
$$;

create or replace function public.wnph_surface_collation_normalize_ws_v1(p_text text)
returns text
language sql
immutable
security invoker
set search_path='pg_catalog'
as $$
  select btrim(regexp_replace(coalesce(p_text,''),'\s+',' ','g'));
$$;

create or replace function public.wnph_collate_source_block_against_surface_readings_v1(p_block_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','wnph','public'
as $$
declare
  v_block wnph.publication_source_blocks%rowtype;
  v_proposal wnph.publication_source_reconstruction_proposals%rowtype;
  v_surface_keys text[];
  v_surface_count integer;
  v_verified_count integer;
  v_verified_text text;
  v_candidate_norm text;
  v_surface_norm text;
  v_match boolean;
  v_result text;
begin
  select * into v_block from wnph.publication_source_blocks b
  where b.block_key=p_block_key
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;
  if v_block.id is null then raise exception 'WNPH surface collation: active block not found' using errcode='P0002'; end if;

  select * into v_proposal from wnph.publication_source_reconstruction_proposals p
  where p.source_package_id=v_block.source_package_id and p.proposed_block_key=v_block.block_key
    and p.proposed_text_content is not distinct from v_block.text_content
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id)
  order by p.created_at desc limit 1;
  if v_proposal.id is null then raise exception 'WNPH surface collation: active reconstruction proposal not found' using errcode='P0002'; end if;

  select coalesce(array_agg(distinct x order by x),'{}'::text[]) into v_surface_keys
  from jsonb_array_elements_text(coalesce(v_block.properties->'source_surface_keys','[]'::jsonb)) x;
  if cardinality(v_surface_keys)=0 then
    select coalesce(array_agg(distinct a.asset_key order by a.asset_key),'{}'::text[]) into v_surface_keys
    from wnph.publication_source_observations o
    join wnph.publication_source_assets a on a.id=o.source_asset_id
    where o.id=any(v_proposal.source_observation_ids);
  end if;

  v_surface_count := cardinality(v_surface_keys);

  with chosen as (
    select a.asset_key,a.source_locator,r.reading_text,r.reading_state
    from wnph.publication_source_assets a
    left join lateral (
      select rr.* from wnph.publication_source_surface_readings rr
      where rr.source_asset_id=a.id
        and not exists(select 1 from wnph.publication_source_surface_readings c where c.supersedes_reading_id=rr.id)
      order by rr.created_at desc limit 1
    ) r on true
    where a.source_package_id=v_block.source_package_id and a.asset_key=any(v_surface_keys)
      and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id)
  )
  select count(*) filter(where reading_state='verified'),
         string_agg(reading_text,E'\n' order by coalesce((source_locator->>'source_pdf_page')::int,2147483647),asset_key) filter(where reading_state='verified' and reading_text is not null)
  into v_verified_count,v_verified_text
  from chosen;

  v_candidate_norm := public.wnph_surface_collation_normalize_ws_v1(v_block.text_content);
  v_surface_norm := public.wnph_surface_collation_normalize_ws_v1(v_verified_text);
  v_match := v_surface_count>0 and v_verified_count=v_surface_count and v_candidate_norm<>'' and position(v_candidate_norm in v_surface_norm)>0;

  if v_surface_count=0 then v_result:='no_source_surfaces';
  elsif v_verified_count<v_surface_count then v_result:='pending_surface_readings';
  elsif v_match then v_result:='literal_text_match_after_whitespace_collapse';
  else v_result:='needs_adjudication';
  end if;

  return jsonb_build_object(
    'contract_version','wnph_collate_source_block_against_surface_readings_v1',
    'block_key',v_block.block_key,
    'block_id',v_block.id,
    'candidate_text_sha256',encode(extensions.digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex'),
    'source_surface_keys',to_jsonb(v_surface_keys),
    'source_surface_count',v_surface_count,
    'verified_surface_count',v_verified_count,
    'all_source_surfaces_verified',(v_surface_count>0 and v_verified_count=v_surface_count),
    'literal_match_after_whitespace_collapse',v_match,
    'collation_result',v_result,
    'canonical_admission_allowed_by_this_function',false,
    'note','This function performs deterministic collation only. It does not create a block verification or admit canonical text.'
  );
end;
$$;

revoke all on function public.wnph_record_source_surface_reading_v1(text,text,text,text,text,text,text,text,text,numeric,jsonb,jsonb,text) from public, anon, authenticated;
grant execute on function public.wnph_record_source_surface_reading_v1(text,text,text,text,text,text,text,text,text,numeric,jsonb,jsonb,text) to service_role;
revoke all on function public.wnph_source_surface_reading_packet_v1(text,text[]) from public, anon, authenticated;
grant execute on function public.wnph_source_surface_reading_packet_v1(text,text[]) to service_role;
revoke all on function public.wnph_collate_source_block_against_surface_readings_v1(text) from public, anon, authenticated;
grant execute on function public.wnph_collate_source_block_against_surface_readings_v1(text) to service_role;
revoke all on function public.wnph_surface_collation_normalize_ws_v1(text) from public, anon;
grant execute on function public.wnph_surface_collation_normalize_ws_v1(text) to authenticated, service_role;

comment on table wnph.publication_source_surface_readings is 'Append-only governed readings of individual source surfaces. A verified row certifies what the pixels on one source surface literally support; it is evidence, not canonical prose.';
comment on table wnph.publication_source_surface_reading_spans is 'Coordinate/observation-addressable spans belonging to one governed surface reading version.';
