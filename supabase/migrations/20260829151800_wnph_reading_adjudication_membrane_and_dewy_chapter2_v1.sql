create table wnph.publication_source_reading_adjudications (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  adjudication_key text not null unique check (btrim(adjudication_key) <> ''),
  adjudication_kind text not null check (adjudication_kind in ('reading_text','paragraph_continuity')),
  start_asset_id uuid not null references wnph.publication_source_assets(id),
  start_observation_id uuid not null references wnph.publication_source_observations(id),
  end_asset_id uuid references wnph.publication_source_assets(id),
  end_observation_id uuid references wnph.publication_source_observations(id),
  result text not null check (result in (
    'replace_reading_text',
    'retain_observed_text',
    'join_across_boundary',
    'break_at_boundary',
    'unresolved'
  )),
  adjudicated_text text,
  adjudication_authority text not null check (btrim(adjudication_authority) <> ''),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  rationale text not null check (btrim(rationale) <> ''),
  evidence jsonb not null default '{}'::jsonb,
  supersedes_adjudication_id uuid references wnph.publication_source_reading_adjudications(id),
  created_at timestamptz not null default now(),
  constraint publication_source_reading_adjudications_shape_ck check (
    (
      adjudication_kind = 'reading_text'
      and end_asset_id is null
      and end_observation_id is null
      and result in ('replace_reading_text','retain_observed_text','unresolved')
      and (
        (result = 'replace_reading_text' and coalesce(btrim(adjudicated_text),'') <> '')
        or (result <> 'replace_reading_text' and adjudicated_text is null)
      )
    )
    or
    (
      adjudication_kind = 'paragraph_continuity'
      and end_asset_id is not null
      and end_observation_id is not null
      and result in ('join_across_boundary','break_at_boundary','unresolved')
      and adjudicated_text is null
      and start_observation_id <> end_observation_id
    )
  ),
  constraint publication_source_reading_adjudications_supersedes_not_self_ck check (
    supersedes_adjudication_id is null or supersedes_adjudication_id <> id
  )
);

create index publication_source_reading_adjudications_package_idx
  on wnph.publication_source_reading_adjudications(source_package_id);
create index publication_source_reading_adjudications_start_observation_idx
  on wnph.publication_source_reading_adjudications(start_observation_id);
create index publication_source_reading_adjudications_end_observation_idx
  on wnph.publication_source_reading_adjudications(end_observation_id)
  where end_observation_id is not null;
create index publication_source_reading_adjudications_supersedes_idx
  on wnph.publication_source_reading_adjudications(supersedes_adjudication_id)
  where supersedes_adjudication_id is not null;

alter table wnph.publication_source_reading_adjudications enable row level security;
revoke all on wnph.publication_source_reading_adjudications from public,anon,authenticated,service_role;

create or replace function wnph.validate_publication_source_reading_adjudication_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_package wnph.publication_source_packages%rowtype;
  v_start_asset wnph.publication_source_assets%rowtype;
  v_end_asset wnph.publication_source_assets%rowtype;
  v_start_observation wnph.publication_source_observations%rowtype;
  v_end_observation wnph.publication_source_observations%rowtype;
  v_old wnph.publication_source_reading_adjudications%rowtype;
begin
  if jsonb_typeof(new.evidence) <> 'object' then
    raise exception 'WNPH reading adjudication: evidence must be an object';
  end if;

  if new.result <> 'unresolved' and new.evidence = '{}'::jsonb then
    raise exception 'WNPH reading adjudication: resolved decisions require evidence';
  end if;

  select * into v_package
  from wnph.publication_source_packages p
  where p.id = new.source_package_id
    and not exists (
      select 1 from wnph.publication_source_packages child
      where child.supersedes_package_id = p.id
    );

  if v_package.id is null then
    raise exception 'WNPH reading adjudication: source package must be active';
  end if;

  select * into v_start_asset
  from wnph.publication_source_assets a
  where a.id = new.start_asset_id
    and not exists (
      select 1 from wnph.publication_source_assets child
      where child.supersedes_asset_id = a.id
    );

  select * into v_start_observation
  from wnph.publication_source_observations o
  where o.id = new.start_observation_id
    and not exists (
      select 1 from wnph.publication_source_observations child
      where child.supersedes_observation_id = o.id
    );

  if v_start_asset.id is null or v_start_observation.id is null then
    raise exception 'WNPH reading adjudication: start asset and observation must both be active';
  end if;

  if v_start_asset.source_package_id <> new.source_package_id
     or v_start_observation.source_asset_id <> new.start_asset_id then
    raise exception 'WNPH reading adjudication: start observation lineage must remain inside source package';
  end if;

  if new.end_asset_id is not null then
    select * into v_end_asset
    from wnph.publication_source_assets a
    where a.id = new.end_asset_id
      and not exists (
        select 1 from wnph.publication_source_assets child
        where child.supersedes_asset_id = a.id
      );

    select * into v_end_observation
    from wnph.publication_source_observations o
    where o.id = new.end_observation_id
      and not exists (
        select 1 from wnph.publication_source_observations child
        where child.supersedes_observation_id = o.id
      );

    if v_end_asset.id is null or v_end_observation.id is null then
      raise exception 'WNPH reading adjudication: end asset and observation must both be active';
    end if;

    if v_end_asset.source_package_id <> new.source_package_id
       or v_end_observation.source_asset_id <> new.end_asset_id then
      raise exception 'WNPH reading adjudication: end observation lineage must remain inside source package';
    end if;
  end if;

  if new.supersedes_adjudication_id is not null then
    select * into v_old
    from wnph.publication_source_reading_adjudications
    where id = new.supersedes_adjudication_id;

    if v_old.id is null
       or v_old.source_package_id <> new.source_package_id
       or v_old.adjudication_kind <> new.adjudication_kind
       or v_old.start_asset_id <> new.start_asset_id
       or v_old.start_observation_id <> new.start_observation_id
       or v_old.end_asset_id is distinct from new.end_asset_id
       or v_old.end_observation_id is distinct from new.end_observation_id then
      raise exception 'WNPH reading adjudication: supersession must preserve package, kind and source anchors';
    end if;

    if exists (
      select 1
      from wnph.publication_source_reading_adjudications child
      where child.supersedes_adjudication_id = v_old.id
    ) then
      raise exception 'WNPH reading adjudication: supersession fork is not allowed';
    end if;
  elsif exists (
    select 1
    from wnph.publication_source_reading_adjudications a
    where a.source_package_id = new.source_package_id
      and a.adjudication_kind = new.adjudication_kind
      and a.start_observation_id = new.start_observation_id
      and a.end_observation_id is not distinct from new.end_observation_id
      and not exists (
        select 1
        from wnph.publication_source_reading_adjudications child
        where child.supersedes_adjudication_id = a.id
      )
  ) then
    raise exception 'WNPH reading adjudication: source anchors already have an active % decision', new.adjudication_kind;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_reading_adjudication_v1() from public,anon,authenticated,service_role;

create trigger publication_source_reading_adjudications_insert_validation_v1
before insert on wnph.publication_source_reading_adjudications
for each row execute function wnph.validate_publication_source_reading_adjudication_v1();

create trigger publication_source_reading_adjudications_append_only
before update or delete on wnph.publication_source_reading_adjudications
for each row execute function wnph.reject_append_only_mutation();

create or replace function public.wnph_reconstruction_source_packet_v5(
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
  v_packet jsonb;
  v_adjudications jsonb;
begin
  v_packet := public.wnph_reconstruction_source_packet_v4(
    p_source_package_key,
    p_target_parent_block_key,
    p_asset_keys
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'source_package_id', a.source_package_id,
        'adjudication_key', a.adjudication_key,
        'adjudication_kind', a.adjudication_kind,
        'start_asset_id', a.start_asset_id,
        'start_observation_id', a.start_observation_id,
        'end_asset_id', a.end_asset_id,
        'end_observation_id', a.end_observation_id,
        'result', a.result,
        'adjudicated_text', a.adjudicated_text,
        'adjudication_authority', a.adjudication_authority,
        'derivation_method', a.derivation_method,
        'confidence', a.confidence,
        'rationale', a.rationale,
        'evidence', a.evidence
      )
      order by a.adjudication_kind, a.start_asset_id, a.start_observation_id, a.created_at
    ),
    '[]'::jsonb
  ) into v_adjudications
  from wnph.publication_source_reading_adjudications a
  where a.source_package_id = (v_packet->>'source_package_id')::uuid
    and not exists (
      select 1 from wnph.publication_source_reading_adjudications child
      where child.supersedes_adjudication_id = a.id
    )
    and exists (
      select 1
      from jsonb_array_elements(v_packet->'surfaces') s
      where (s->>'id')::uuid = a.start_asset_id
    )
    and (
      a.end_asset_id is null
      or exists (
        select 1
        from jsonb_array_elements(v_packet->'surfaces') s
        where (s->>'id')::uuid = a.end_asset_id
      )
    );

  return v_packet || jsonb_build_object('reading_adjudications', v_adjudications);
end;
$function$;

revoke all on function public.wnph_reconstruction_source_packet_v5(text,text,text[]) from public,anon,authenticated;
grant execute on function public.wnph_reconstruction_source_packet_v5(text,text,text[]) to service_role;

comment on table wnph.publication_source_reading_adjudications is
'Append-only governed reading decisions over preserved source observations. This layer may correct semantic reading text or decide paragraph continuity without rewriting OCR/layout observations and without itself promoting reconstruction proposals into publication source blocks.';

comment on function public.wnph_reconstruction_source_packet_v5(text,text,text[]) is
'Service-role reconstruction packet v5. Extends v4 with active governed reading adjudications for source observations and cross-surface paragraph continuity while preserving physical observations unchanged.';

with target as (
  select
    p.id as source_package_id,
    a.id as start_asset_id,
    o.id as start_observation_id,
    a.asset_key,
    a.source_locator,
    o.text_candidate,
    o.external_locator
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id = p.id
  join wnph.publication_source_observations o on o.source_asset_id = a.id
  where p.canonical_key = 'wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key = 'dewy:loc:source-surface:0021'
    and o.observation_kind = 'line'
    and o.source_format = 'alto_xml'
    and o.ordinal = 20
    and o.text_candidate = 'heresy,'
    and not exists (select 1 from wnph.publication_source_packages n where n.supersedes_package_id = p.id)
    and not exists (select 1 from wnph.publication_source_assets n where n.supersedes_asset_id = a.id)
    and not exists (select 1 from wnph.publication_source_observations n where n.supersedes_observation_id = o.id)
)
insert into wnph.publication_source_reading_adjudications (
  source_package_id,
  adjudication_key,
  adjudication_kind,
  start_asset_id,
  start_observation_id,
  result,
  adjudicated_text,
  adjudication_authority,
  derivation_method,
  confidence,
  rationale,
  evidence
)
select
  source_package_id,
  'dewy:reading-adjudication:chapter2:scan0021:line20:here',
  'reading_text',
  start_asset_id,
  start_observation_id,
  'replace_reading_text',
  'here.”',
  'source_collation_adjudication',
  'loc_observation_plus_independent_full_text_collation_v1',
  0.99,
  'The preserved LOC ALTO observation reads "heresy," but an independent full-text derivative of the same public-domain source reads "here.”"; the preceding physical line reads "King Wind to bring the clouds". The semantic reading is therefore adjudicated as "here.”" while the LOC observation remains unchanged.',
  jsonb_build_object(
    'source_asset_key', asset_key,
    'printed_page_locator', source_locator->>'printed_page',
    'source_pdf_page', source_locator->>'source_pdf_page',
    'loc_observed_ocr_text', text_candidate,
    'loc_observation_external_locator', external_locator,
    'independent_source', jsonb_build_object(
      'provider', 'Internet Archive',
      'item_identifier', 'wishfairydewydea00colv',
      'derivative', 'full_text',
      'reading', 'here.”'
    ),
    'preceding_observed_line', 'King Wind to bring the clouds',
    'raw_observation_rewritten', false
  )
from target;

with start_target as (
  select
    p.id as source_package_id,
    a.id as start_asset_id,
    o.id as start_observation_id,
    a.asset_key as start_asset_key,
    a.source_locator as start_source_locator,
    o.text_candidate as start_text
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id = p.id
  join wnph.publication_source_observations o on o.source_asset_id = a.id
  where p.canonical_key = 'wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key = 'dewy:loc:source-surface:0022'
    and o.observation_kind = 'line'
    and o.source_format = 'alto_xml'
    and o.ordinal = 24
    and o.text_candidate = 'Then she crept along on her'
    and not exists (select 1 from wnph.publication_source_packages n where n.supersedes_package_id = p.id)
    and not exists (select 1 from wnph.publication_source_assets n where n.supersedes_asset_id = a.id)
    and not exists (select 1 from wnph.publication_source_observations n where n.supersedes_observation_id = o.id)
),
end_target as (
  select
    p.id as source_package_id,
    a.id as end_asset_id,
    o.id as end_observation_id,
    a.asset_key as end_asset_key,
    a.source_locator as end_source_locator,
    o.text_candidate as end_text
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id = p.id
  join wnph.publication_source_observations o on o.source_asset_id = a.id
  where p.canonical_key = 'wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key = 'dewy:loc:source-surface:0024'
    and o.observation_kind = 'line'
    and o.source_format = 'alto_xml'
    and o.ordinal = 1
    and o.text_candidate = 'hands and knees, and finally made'
    and not exists (select 1 from wnph.publication_source_packages n where n.supersedes_package_id = p.id)
    and not exists (select 1 from wnph.publication_source_assets n where n.supersedes_asset_id = a.id)
    and not exists (select 1 from wnph.publication_source_observations n where n.supersedes_observation_id = o.id)
),
plate as (
  select
    p.id as source_package_id,
    a.id as plate_asset_id,
    a.asset_key as plate_asset_key,
    a.source_locator as plate_source_locator,
    (
      select count(*)
      from wnph.publication_source_observations o
      where o.source_asset_id = a.id
        and o.observation_kind = 'line'
        and coalesce(btrim(o.text_candidate),'') <> ''
        and not exists (
          select 1 from wnph.publication_source_observations n
          where n.supersedes_observation_id = o.id
        )
        and not exists (
          select 1
          from wnph.publication_source_observation_classifications c
          where c.observation_id = o.id
            and c.classification_scope = 'page_furniture'
            and c.reading_disposition = 'exclude'
            and c.classification_state in ('verified','adjudicated')
            and not exists (
              select 1 from wnph.publication_source_observation_classifications child
              where child.supersedes_classification_id = c.id
            )
        )
    ) as retained_reading_line_count
  from wnph.publication_source_packages p
  join wnph.publication_source_assets a on a.source_package_id = p.id
  where p.canonical_key = 'wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and a.asset_key = 'dewy:loc:source-surface:0023'
    and not exists (select 1 from wnph.publication_source_packages n where n.supersedes_package_id = p.id)
    and not exists (select 1 from wnph.publication_source_assets n where n.supersedes_asset_id = a.id)
)
insert into wnph.publication_source_reading_adjudications (
  source_package_id,
  adjudication_key,
  adjudication_kind,
  start_asset_id,
  start_observation_id,
  end_asset_id,
  end_observation_id,
  result,
  adjudication_authority,
  derivation_method,
  confidence,
  rationale,
  evidence
)
select
  s.source_package_id,
  'dewy:reading-adjudication:chapter2:plate-boundary:p18-to-p20',
  'paragraph_continuity',
  s.start_asset_id,
  s.start_observation_id,
  e.end_asset_id,
  e.end_observation_id,
  'join_across_boundary',
  'source_collation_adjudication',
  'physical_sentence_continuity_across_intervening_plate_v1',
  0.99,
  'Printed page 18 ends mid-sentence with "Then she crept along on her"; the intervening printed page 19 surface has no retained semantic reading text after governed page-furniture exclusion; printed page 20 resumes in lower case with "hands and knees, and finally made". An independent full-text derivative preserves the same continuation. The paragraph therefore continues across the illustration plate.',
  jsonb_build_object(
    'start_asset_key', s.start_asset_key,
    'start_printed_page', s.start_source_locator->>'printed_page',
    'start_text', s.start_text,
    'intervening_plate_asset_key', pl.plate_asset_key,
    'intervening_plate_printed_page', pl.plate_source_locator->>'printed_page',
    'intervening_plate_retained_reading_line_count', pl.retained_reading_line_count,
    'end_asset_key', e.end_asset_key,
    'end_printed_page', e.end_source_locator->>'printed_page',
    'end_text', e.end_text,
    'independent_source', jsonb_build_object(
      'provider', 'Internet Archive',
      'item_identifier', 'wishfairydewydea00colv',
      'derivative', 'full_text',
      'continuity_preserved', true
    ),
    'raw_observation_rewritten', false
  )
from start_target s
join end_target e on e.source_package_id = s.source_package_id
join plate pl on pl.source_package_id = s.source_package_id;

do $verify$
declare
  v_package_id uuid;
  v_adjudication_count integer;
  v_packet jsonb;
  v_raw_text text;
  v_ch2_proposal_count integer;
  v_ch2_block_count integer;
  v_ch1_paragraph_count integer;
begin
  select p.id into v_package_id
  from wnph.publication_source_packages p
  where p.canonical_key = 'wish-fairy-and-dewy-dear:canonical-publication-source:v1'
    and not exists (
      select 1 from wnph.publication_source_packages child
      where child.supersedes_package_id = p.id
    )
  order by p.created_at desc
  limit 1;

  select count(*) into v_adjudication_count
  from wnph.publication_source_reading_adjudications a
  where a.source_package_id = v_package_id
    and not exists (
      select 1 from wnph.publication_source_reading_adjudications child
      where child.supersedes_adjudication_id = a.id
    );

  if v_adjudication_count <> 2 then
    raise exception 'WNPH Chapter II reading adjudication seed expected exactly 2 active decisions; got %', v_adjudication_count;
  end if;

  if not exists (
    select 1
    from wnph.publication_source_reading_adjudications a
    where a.source_package_id = v_package_id
      and a.adjudication_kind = 'reading_text'
      and a.result = 'replace_reading_text'
      and a.adjudicated_text = 'here.”'
      and not exists (
        select 1 from wnph.publication_source_reading_adjudications child
        where child.supersedes_adjudication_id = a.id
      )
  ) then
    raise exception 'WNPH Chapter II reading-text adjudication was not seeded';
  end if;

  if not exists (
    select 1
    from wnph.publication_source_reading_adjudications a
    where a.source_package_id = v_package_id
      and a.adjudication_kind = 'paragraph_continuity'
      and a.result = 'join_across_boundary'
      and not exists (
        select 1 from wnph.publication_source_reading_adjudications child
        where child.supersedes_adjudication_id = a.id
      )
  ) then
    raise exception 'WNPH Chapter II plate-boundary continuity adjudication was not seeded';
  end if;

  select o.text_candidate into v_raw_text
  from wnph.publication_source_assets a
  join wnph.publication_source_observations o on o.source_asset_id = a.id
  where a.source_package_id = v_package_id
    and a.asset_key = 'dewy:loc:source-surface:0021'
    and o.observation_kind = 'line'
    and o.source_format = 'alto_xml'
    and o.ordinal = 20
    and not exists (select 1 from wnph.publication_source_observations child where child.supersedes_observation_id = o.id)
  limit 1;

  if v_raw_text <> 'heresy,' then
    raise exception 'WNPH reading adjudication must not rewrite preserved LOC observation; got %', v_raw_text;
  end if;

  v_packet := public.wnph_reconstruction_source_packet_v5(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:2:paragraph-stream',
    null
  );

  if jsonb_array_length(v_packet->'reading_adjudications') <> 2 then
    raise exception 'WNPH Chapter II packet v5 expected 2 reading adjudications; got %',
      jsonb_array_length(v_packet->'reading_adjudications');
  end if;

  select count(*) into v_ch2_proposal_count
  from wnph.publication_source_reconstruction_proposals p
  join wnph.publication_source_blocks parent on parent.id = p.target_parent_block_id
  where parent.block_key = 'dewy:chapter:2:paragraph-stream'
    and not exists (
      select 1 from wnph.publication_source_reconstruction_proposals child
      where child.supersedes_proposal_id = p.id
    );

  if v_ch2_proposal_count <> 0 then
    raise exception 'WNPH reading adjudication migration must not create Chapter II reconstruction proposals; got %', v_ch2_proposal_count;
  end if;

  select count(*) into v_ch2_block_count
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id = b.parent_block_id
  where parent.block_key = 'dewy:chapter:2:paragraph-stream'
    and not exists (
      select 1 from wnph.publication_source_blocks child
      where child.supersedes_block_id = b.id
    );

  if v_ch2_block_count <> 0 then
    raise exception 'WNPH reading adjudication migration must not create Chapter II paragraph blocks; got %', v_ch2_block_count;
  end if;

  select count(*) into v_ch1_paragraph_count
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id = b.parent_block_id
  where parent.block_key = 'dewy:chapter:1:paragraph-stream'
    and b.block_type = 'paragraph'
    and not exists (
      select 1 from wnph.publication_source_blocks child
      where child.supersedes_block_id = b.id
    );

  if v_ch1_paragraph_count <> 24 then
    raise exception 'WNPH Chapter I custody changed unexpectedly; expected 24 paragraphs, got %', v_ch1_paragraph_count;
  end if;
end;
$verify$;
