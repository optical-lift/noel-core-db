-- Reality entity appellations v1
--
-- Names are evidence about an entity; they are not the entity itself.
-- This layer preserves literal source-observed names while keeping one
-- canonical Reality entity identity. Name equality never merges entities.

create or replace function reality.normalize_entity_appellation_v1(p_value text)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select lower(regexp_replace(btrim(p_value), '[[:space:]]+', ' ', 'g'));
$$;

create table if not exists reality.entity_appellations (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references reality.entities(id) on delete restrict,
  appellation_kind text not null,
  literal_value text not null,
  normalized_value text not null,
  appellation_state text not null default 'observed',
  source_kind text not null,
  source_key text not null,
  source_locator jsonb not null default '{}'::jsonb,
  confidence numeric,
  observed_at timestamptz,
  verified_at timestamptz,
  retired_at timestamptz,
  evidence jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_appellations_kind_check check (
    appellation_kind in (
      'source_observed_name',
      'legal_name',
      'preferred_name',
      'former_name',
      'historical_name',
      'provider_display_name',
      'nickname',
      'spelling_variant'
    )
  ),
  constraint entity_appellations_literal_nonempty check (btrim(literal_value) <> ''),
  constraint entity_appellations_normalized_nonempty check (btrim(normalized_value) <> ''),
  constraint entity_appellations_state_check check (
    appellation_state in ('observed','verified','disputed','retired')
  ),
  constraint entity_appellations_source_kind_nonempty check (btrim(source_kind) <> ''),
  constraint entity_appellations_source_key_nonempty check (btrim(source_key) <> ''),
  constraint entity_appellations_confidence_check check (
    confidence is null or (confidence >= 0 and confidence <= 1)
  ),
  constraint entity_appellations_verified_state_check check (
    verified_at is null or appellation_state in ('verified','retired')
  ),
  constraint entity_appellations_retired_state_check check (
    retired_at is null or appellation_state = 'retired'
  ),
  constraint entity_appellations_source_locator_object_check check (
    jsonb_typeof(source_locator) = 'object'
  ),
  constraint entity_appellations_evidence_object_check check (
    jsonb_typeof(evidence) = 'object'
  ),
  constraint entity_appellations_metadata_object_check check (
    jsonb_typeof(metadata) = 'object'
  ),
  unique (entity_id, appellation_kind, source_kind, source_key, normalized_value)
);

create index if not exists entity_appellations_entity_state_idx
  on reality.entity_appellations(entity_id, appellation_state);

create index if not exists entity_appellations_normalized_state_idx
  on reality.entity_appellations(normalized_value, appellation_state);

alter table reality.entity_appellations enable row level security;

revoke all on table reality.entity_appellations from public, anon, authenticated;
revoke all on function reality.normalize_entity_appellation_v1(text) from public, anon, authenticated;
grant execute on function reality.normalize_entity_appellation_v1(text) to service_role;

create or replace function reality.guard_entity_appellation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, reality
as $$
begin
  new.normalized_value := reality.normalize_entity_appellation_v1(new.literal_value);
  new.source_kind := btrim(new.source_kind);
  new.source_key := btrim(new.source_key);
  new.updated_at := now();

  if tg_op = 'UPDATE' and new.entity_id is distinct from old.entity_id then
    raise exception 'Entity appellation identity binding is immutable.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.literal_value is distinct from old.literal_value then
    raise exception 'Entity appellation literal source value is immutable provenance.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.source_kind is distinct from old.source_kind then
    raise exception 'Entity appellation source kind is immutable provenance.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.source_key is distinct from old.source_key then
    raise exception 'Entity appellation source key is immutable provenance.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' and new.source_locator is distinct from old.source_locator then
    raise exception 'Entity appellation source locator is immutable provenance.' using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function reality.guard_entity_appellation_v1() from public, anon, authenticated;

drop trigger if exists entity_appellations_guard_v1 on reality.entity_appellations;
create trigger entity_appellations_guard_v1
before insert or update on reality.entity_appellations
for each row execute function reality.guard_entity_appellation_v1();

create or replace function reality.record_entity_appellation_v1(
  p_entity_id uuid,
  p_appellation_kind text,
  p_literal_value text,
  p_source_kind text,
  p_source_key text,
  p_source_locator jsonb default '{}'::jsonb,
  p_appellation_state text default 'observed',
  p_confidence numeric default null,
  p_observed_at timestamptz default null,
  p_evidence jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, reality
as $$
declare
  v_id uuid;
  v_normalized text;
  v_verified_at timestamptz;
  v_retired_at timestamptz;
begin
  if not exists(select 1 from reality.entities e where e.id = p_entity_id) then
    raise exception 'Canonical Reality entity required.' using errcode = '23503';
  end if;

  if p_appellation_kind not in (
    'source_observed_name','legal_name','preferred_name','former_name',
    'historical_name','provider_display_name','nickname','spelling_variant'
  ) then
    raise exception 'Unsupported entity appellation kind.' using errcode = '22023';
  end if;

  if p_appellation_state not in ('observed','verified','disputed','retired') then
    raise exception 'Unsupported entity appellation state.' using errcode = '22023';
  end if;

  if p_source_locator is null or jsonb_typeof(p_source_locator) <> 'object'
     or p_evidence is null or jsonb_typeof(p_evidence) <> 'object'
     or p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Appellation locator, evidence, and metadata must be JSON objects.' using errcode = '22023';
  end if;

  v_normalized := reality.normalize_entity_appellation_v1(p_literal_value);
  v_verified_at := case when p_appellation_state = 'verified' then now() else null end;
  v_retired_at := case when p_appellation_state = 'retired' then now() else null end;

  insert into reality.entity_appellations(
    entity_id, appellation_kind, literal_value, normalized_value,
    appellation_state, source_kind, source_key, source_locator,
    confidence, observed_at, verified_at, retired_at, evidence, metadata
  ) values (
    p_entity_id, p_appellation_kind, p_literal_value, v_normalized,
    p_appellation_state, p_source_kind, p_source_key, p_source_locator,
    p_confidence, p_observed_at, v_verified_at, v_retired_at, p_evidence, p_metadata
  )
  on conflict (entity_id, appellation_kind, source_kind, source_key, normalized_value)
  do update set
    appellation_state = excluded.appellation_state,
    confidence = excluded.confidence,
    observed_at = coalesce(reality.entity_appellations.observed_at, excluded.observed_at),
    verified_at = case
      when excluded.appellation_state = 'verified' then coalesce(reality.entity_appellations.verified_at, now())
      when excluded.appellation_state = 'retired' then reality.entity_appellations.verified_at
      else null
    end,
    retired_at = case
      when excluded.appellation_state = 'retired' then coalesce(reality.entity_appellations.retired_at, now())
      else null
    end,
    evidence = reality.entity_appellations.evidence || excluded.evidence,
    metadata = reality.entity_appellations.metadata || excluded.metadata,
    updated_at = now()
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'reality_entity_appellation_v1',
    'appellationId', v_id,
    'entityId', p_entity_id,
    'literalValue', p_literal_value,
    'normalizedValue', v_normalized,
    'appellationState', p_appellation_state,
    'identityMutation', false,
    'entityMerge', false
  );
end;
$$;

revoke all on function reality.record_entity_appellation_v1(
  uuid,text,text,text,text,jsonb,text,numeric,timestamptz,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function reality.record_entity_appellation_v1(
  uuid,text,text,text,text,jsonb,text,numeric,timestamptz,jsonb,jsonb
) to service_role;

create or replace function reality.resolve_entity_appellation_v1(
  p_literal_value text,
  p_entity_kind text default null,
  p_candidate_entity_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, reality
as $$
declare
  v_normalized text;
  v_matches jsonb;
  v_count integer;
  v_entity_id uuid;
begin
  v_normalized := reality.normalize_entity_appellation_v1(p_literal_value);

  with candidate_matches as (
    select e.id as entity_id, e.entity_kind, e.display_name, 'canonical_display_name'::text as match_kind
    from reality.entities e
    where reality.normalize_entity_appellation_v1(e.display_name) = v_normalized
      and (p_entity_kind is null or e.entity_kind = p_entity_kind)
      and (p_candidate_entity_ids is null or e.id = any(p_candidate_entity_ids))

    union all

    select e.id, e.entity_kind, e.display_name, a.appellation_kind
    from reality.entity_appellations a
    join reality.entities e on e.id = a.entity_id
    where a.normalized_value = v_normalized
      and a.appellation_state in ('observed','verified')
      and (p_entity_kind is null or e.entity_kind = p_entity_kind)
      and (p_candidate_entity_ids is null or e.id = any(p_candidate_entity_ids))
  ), distinct_entities as (
    select entity_id, entity_kind, display_name,
           jsonb_agg(distinct match_kind order by match_kind) as match_kinds
    from candidate_matches
    group by entity_id, entity_kind, display_name
  )
  select count(*)::integer,
         coalesce(jsonb_agg(jsonb_build_object(
           'entityId', entity_id,
           'entityKind', entity_kind,
           'displayName', display_name,
           'matchKinds', match_kinds
         ) order by display_name, entity_id), '[]'::jsonb),
         (array_agg(entity_id order by entity_id::text))[1]
  into v_count, v_matches, v_entity_id
  from distinct_entities;

  return jsonb_build_object(
    'ok', true,
    'contractVersion', 'reality_entity_appellation_resolution_v1',
    'literalValue', p_literal_value,
    'normalizedValue', v_normalized,
    'resolutionState', case
      when v_count = 0 then 'unresolved'
      when v_count = 1 then 'resolved'
      else 'ambiguous'
    end,
    'resolvedEntityId', case when v_count = 1 then v_entity_id else null end,
    'matchCount', v_count,
    'matches', v_matches,
    'automaticMerge', false
  );
end;
$$;

revoke all on function reality.resolve_entity_appellation_v1(text,text,uuid[]) from public, anon, authenticated;
grant execute on function reality.resolve_entity_appellation_v1(text,text,uuid[]) to service_role;

comment on table reality.entity_appellations is
  'Source-observed or governed names for a canonical Reality entity. Appellations preserve naming evidence; they do not create, merge, or replace entity identity.';
comment on function reality.resolve_entity_appellation_v1(text,text,uuid[]) is
  'Exact normalized-name resolver. Returns resolved, ambiguous, or unresolved and never merges entities or selects among ambiguous matches.';
