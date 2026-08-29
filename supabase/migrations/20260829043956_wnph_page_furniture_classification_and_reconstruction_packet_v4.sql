create table wnph.publication_source_observation_classifications (
  id uuid primary key default gen_random_uuid(),
  source_asset_id uuid not null references wnph.publication_source_assets(id),
  observation_id uuid not null references wnph.publication_source_observations(id),
  classification_key text not null unique check (btrim(classification_key) <> ''),
  classification_scope text not null check (classification_scope in ('page_furniture')),
  classification_kind text not null check (classification_kind in ('folio','running_head','running_footer','running_title','signature_mark','catchword','printer_mark','ornament','other')),
  classification_state text not null check (classification_state in ('candidate','verified','adjudicated')),
  reading_disposition text not null check (reading_disposition in ('retain','review','exclude')),
  classification_authority text not null check (btrim(classification_authority) <> ''),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  evidence jsonb not null default '{}'::jsonb,
  supersedes_classification_id uuid references wnph.publication_source_observation_classifications(id),
  created_at timestamptz not null default now(),
  constraint publication_source_observation_classifications_exclusion_ck check (
    reading_disposition <> 'exclude' or classification_state in ('verified','adjudicated')
  ),
  constraint publication_source_observation_classifications_supersedes_not_self_ck check (
    supersedes_classification_id is null or supersedes_classification_id <> id
  )
);

create index publication_source_observation_classifications_asset_idx
  on wnph.publication_source_observation_classifications(source_asset_id);
create index publication_source_observation_classifications_observation_idx
  on wnph.publication_source_observation_classifications(observation_id);
create index publication_source_observation_classifications_supersedes_idx
  on wnph.publication_source_observation_classifications(supersedes_classification_id)
  where supersedes_classification_id is not null;

alter table wnph.publication_source_observation_classifications enable row level security;
revoke all on wnph.publication_source_observation_classifications from public,anon,authenticated,service_role;

create or replace function wnph.validate_publication_source_observation_classification_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_asset wnph.publication_source_assets%rowtype;
  v_observation wnph.publication_source_observations%rowtype;
  v_old wnph.publication_source_observation_classifications%rowtype;
begin
  if jsonb_typeof(new.evidence) <> 'object' then
    raise exception 'WNPH observation classification: evidence must be an object';
  end if;

  if new.classification_state in ('verified','adjudicated') and new.evidence = '{}'::jsonb then
    raise exception 'WNPH observation classification: verified/adjudicated classifications require evidence';
  end if;

  select * into v_asset
  from wnph.publication_source_assets a
  where a.id = new.source_asset_id
    and not exists (
      select 1 from wnph.publication_source_assets c where c.supersedes_asset_id = a.id
    );

  select * into v_observation
  from wnph.publication_source_observations o
  where o.id = new.observation_id
    and not exists (
      select 1 from wnph.publication_source_observations c where c.supersedes_observation_id = o.id
    );

  if v_asset.id is null or v_observation.id is null then
    raise exception 'WNPH observation classification: source asset and observation must both be active';
  end if;

  if v_observation.source_asset_id <> new.source_asset_id then
    raise exception 'WNPH observation classification: observation must belong to source_asset_id';
  end if;

  if new.supersedes_classification_id is not null then
    select * into v_old
    from wnph.publication_source_observation_classifications
    where id = new.supersedes_classification_id;

    if v_old.id is null
       or v_old.source_asset_id <> new.source_asset_id
       or v_old.observation_id <> new.observation_id
       or v_old.classification_scope <> new.classification_scope then
      raise exception 'WNPH observation classification: supersession must preserve asset, observation and classification scope';
    end if;

    if exists (
      select 1 from wnph.publication_source_observation_classifications c
      where c.supersedes_classification_id = v_old.id
    ) then
      raise exception 'WNPH observation classification: supersession fork is not allowed';
    end if;
  elsif exists (
    select 1
    from wnph.publication_source_observation_classifications c
    where c.observation_id = new.observation_id
      and c.classification_scope = new.classification_scope
      and not exists (
        select 1 from wnph.publication_source_observation_classifications n
        where n.supersedes_classification_id = c.id
      )
  ) then
    raise exception 'WNPH observation classification: observation % already has an active % classification', new.observation_id, new.classification_scope;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_observation_classification_v1() from public,anon,authenticated,service_role;

create trigger publication_source_observation_classifications_insert_validation_v1
before insert on wnph.publication_source_observation_classifications
for each row execute function wnph.validate_publication_source_observation_classification_v1();

create trigger publication_source_observation_classifications_append_only
before update or delete on wnph.publication_source_observation_classifications
for each row execute function wnph.reject_append_only_mutation();

create or replace function public.wnph_reconstruction_source_packet_v4(
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
  v_classifications jsonb;
begin
  v_packet := public.wnph_reconstruction_source_packet_v3(
    p_source_package_key,
    p_target_parent_block_key,
    p_asset_keys
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'source_asset_id', c.source_asset_id,
        'observation_id', c.observation_id,
        'classification_key', c.classification_key,
        'classification_scope', c.classification_scope,
        'classification_kind', c.classification_kind,
        'classification_state', c.classification_state,
        'reading_disposition', c.reading_disposition,
        'classification_authority', c.classification_authority,
        'derivation_method', c.derivation_method,
        'confidence', c.confidence,
        'evidence', c.evidence
      )
      order by c.source_asset_id, c.classification_scope, c.classification_kind, c.created_at
    ),
    '[]'::jsonb
  ) into v_classifications
  from wnph.publication_source_observation_classifications c
  where not exists (
    select 1 from wnph.publication_source_observation_classifications n
    where n.supersedes_classification_id = c.id
  )
    and exists (
      select 1
      from jsonb_array_elements(v_packet->'surfaces') s
      where (s->>'id')::uuid = c.source_asset_id
    );

  return v_packet || jsonb_build_object('observation_classifications', v_classifications);
end;
$function$;

revoke all on function public.wnph_reconstruction_source_packet_v4(text,text,text[]) from public,anon,authenticated;
grant execute on function public.wnph_reconstruction_source_packet_v4(text,text,text[]) to service_role;

comment on table wnph.publication_source_observation_classifications is
'Append-only governed classifications of physical source observations. Page-furniture classifications preserve folios, running matter, signature marks, catchwords and related book artifacts in source custody while separately governing whether verified/adjudicated furniture may be excluded from semantic reading reconstruction.';

comment on function public.wnph_reconstruction_source_packet_v4(text,text,text[]) is
'Service-role reconstruction packet v4. Extends v3 with active governed source-observation classifications; verified/adjudicated page furniture may be excluded by a reconstruction worker without deleting or rewriting the source observation.';

insert into wnph.publication_source_observation_classifications (
  source_asset_id,
  observation_id,
  classification_key,
  classification_scope,
  classification_kind,
  classification_state,
  reading_disposition,
  classification_authority,
  derivation_method,
  confidence,
  evidence
)
select
  a.id,
  o.id,
  'dewy:page-furniture:folio:scan:' || lpad((a.source_locator->>'source_pdf_page')::text, 4, '0'),
  'page_furniture',
  'folio',
  'verified',
  'exclude',
  'source_observed_bibliographic_structure',
  'loc_alto_bottom_folio_with_source_locator_sequence_v1',
  1.0,
  jsonb_build_object(
    'source_asset_key', a.asset_key,
    'scan', (a.source_locator->>'source_pdf_page')::int,
    'printed_page_locator', a.source_locator->>'printed_page',
    'observed_ocr_text', o.text_candidate,
    'physical_position', jsonb_build_object('x',o.x,'y',o.y,'width',o.width,'height',o.height),
    'reading_text_corrected', false
  )
from wnph.publication_source_assets a
join wnph.publication_source_observations o on o.source_asset_id = a.id
where a.asset_key like 'dewy:loc:source-surface:%'
  and (a.source_locator->>'source_pdf_page')::int between 11 and 30
  and o.observation_kind = 'line'
  and o.source_format = 'alto_xml'
  and o.text_candidate ~ '^[0-9]{1,4}$'
  and o.y >= 2180
  and o.x between 700 and 950
  and o.height <= 70
  and not exists (select 1 from wnph.publication_source_assets n where n.supersedes_asset_id = a.id)
  and not exists (select 1 from wnph.publication_source_observations n where n.supersedes_observation_id = o.id);

insert into wnph.publication_source_observation_classifications (
  source_asset_id,
  observation_id,
  classification_key,
  classification_scope,
  classification_kind,
  classification_state,
  reading_disposition,
  classification_authority,
  derivation_method,
  confidence,
  evidence
)
select
  a.id,
  o.id,
  'dewy:page-furniture:signature-mark:scan:0021',
  'page_furniture',
  'signature_mark',
  'verified',
  'exclude',
  'source_observed_bibliographic_structure',
  'source_position_signature_numeral_and_short_title_v1',
  0.99,
  jsonb_build_object(
    'source_asset_key', a.asset_key,
    'scan', 21,
    'printed_page_locator', a.source_locator->>'printed_page',
    'observed_ocr_text', o.text_candidate,
    'physical_position', jsonb_build_object('x',o.x,'y',o.y,'width',o.width,'height',o.height),
    'classification_basis', jsonb_build_array('bottom_margin_position','leading_signature_numeral','short_work_title','separate_folio_below'),
    'reading_text_corrected', false
  )
from wnph.publication_source_assets a
join wnph.publication_source_observations o on o.source_asset_id = a.id
where a.asset_key = 'dewy:loc:source-surface:0021'
  and o.observation_kind = 'line'
  and o.source_format = 'alto_xml'
  and o.ordinal = 21
  and o.text_candidate = '2—Wish Fairy and Dewy Dear'
  and not exists (select 1 from wnph.publication_source_assets n where n.supersedes_asset_id = a.id)
  and not exists (select 1 from wnph.publication_source_observations n where n.supersedes_observation_id = o.id);

do $verify$
declare
  v_total integer;
  v_folios integer;
  v_signature integer;
  v_packet jsonb;
  v_ch2_classifications integer;
begin
  select count(*) into v_total
  from wnph.publication_source_observation_classifications c
  where not exists (
    select 1 from wnph.publication_source_observation_classifications n
    where n.supersedes_classification_id = c.id
  );

  select count(*) filter (where classification_kind='folio'),
         count(*) filter (where classification_kind='signature_mark')
    into v_folios, v_signature
  from wnph.publication_source_observation_classifications c
  where classification_key like 'dewy:page-furniture:%'
    and not exists (
      select 1 from wnph.publication_source_observation_classifications n
      where n.supersedes_classification_id = c.id
    );

  if v_folios <> 19 or v_signature <> 1 then
    raise exception 'WNPH page-furniture seed mismatch: expected 19 folios and 1 signature mark; got % and %', v_folios, v_signature;
  end if;

  v_packet := public.wnph_reconstruction_source_packet_v4(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:2:paragraph-stream',
    null
  );
  v_ch2_classifications := jsonb_array_length(v_packet->'observation_classifications');
  if v_ch2_classifications <> 11 then
    raise exception 'WNPH Chapter II packet expected 11 active page-furniture classifications; got %', v_ch2_classifications;
  end if;

  if exists (
    select 1 from wnph.publication_source_reconstruction_proposals p
    where not exists (
      select 1 from wnph.publication_source_reconstruction_proposals n
      where n.supersedes_proposal_id = p.id
    )
  ) then
    raise exception 'WNPH page-furniture migration must not create live reconstruction proposals';
  end if;

  if exists (
    select 1 from wnph.publication_source_blocks b
    join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
    where parent.block_key='dewy:chapter:2:paragraph-stream'
      and not exists (select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  ) then
    raise exception 'WNPH page-furniture migration must not create Chapter II paragraph blocks';
  end if;
end;
$verify$;