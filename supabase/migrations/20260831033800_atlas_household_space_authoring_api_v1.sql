-- Atlas Household Space Authoring API v1
-- Authenticated Principal authoring for canonical dwellings and physical household spaces.

begin;

create or replace function atlas.principal_current_household_id_v1()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
  select h.id
  from atlas.households h
  join atlas.principals p on p.id = h.principal_id
  where p.user_id = auth.uid()
    and p.status = 'active'
    and h.status = 'active'
  order by
    case when p.active_household_id = h.id then 0 else 1 end,
    h.created_at,
    h.id
  limit 1;
$$;

revoke all on function atlas.principal_current_household_id_v1() from public, anon, authenticated;
grant execute on function atlas.principal_current_household_id_v1() to service_role;

create or replace function atlas.principal_upsert_dwelling_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_id uuid;
  v_stable_key text;
  v_name text;
  v_kind text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  v_stable_key := btrim(coalesce(p_payload->>'stableKey',''));
  v_name := btrim(coalesce(p_payload->>'name',''));
  v_kind := btrim(coalesce(nullif(p_payload->>'dwellingKind',''), 'dwelling'));

  if v_stable_key = '' or v_name = '' then
    raise exception 'stableKey and name are required.' using errcode = '22023';
  end if;

  insert into atlas.dwellings (
    household_id,
    stable_key,
    name,
    dwelling_kind,
    active,
    metadata
  )
  values (
    v_household_id,
    v_stable_key,
    v_name,
    v_kind,
    coalesce((p_payload->>'active')::boolean, true),
    coalesce(p_payload->'metadata','{}'::jsonb)
  )
  on conflict (household_id, stable_key)
  do update set
    name = excluded.name,
    dwelling_kind = excluded.dwelling_kind,
    active = excluded.active,
    metadata = coalesce(atlas.dwellings.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = now()
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'householdId', v_household_id,
    'dwellingId', v_id,
    'stableKey', v_stable_key
  );
end;
$$;

revoke all on function atlas.principal_upsert_dwelling_api_v1(jsonb) from public, anon;
grant execute on function atlas.principal_upsert_dwelling_api_v1(jsonb) to authenticated, service_role;

create or replace function atlas.principal_upsert_household_space_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_household_id uuid;
  v_dwelling_id uuid;
  v_parent_space_id uuid;
  v_space_id uuid;
  v_stable_key text;
  v_name text;
  v_space_type text;
  v_tags text[] := '{}'::text[];
  v_confidence text;
  v_confirmed_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode = '42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode = '42501';
  end if;

  if nullif(p_payload->>'dwellingId','') is not null then
    v_dwelling_id := (p_payload->>'dwellingId')::uuid;
  else
    select d.id
      into v_dwelling_id
    from atlas.dwellings d
    where d.household_id = v_household_id
      and d.stable_key = p_payload->>'dwellingStableKey'
      and d.active
    limit 1;
  end if;

  if v_dwelling_id is null
     or not exists (
       select 1 from atlas.dwellings d
       where d.id = v_dwelling_id
         and d.household_id = v_household_id
     ) then
    raise exception 'Dwelling does not belong to the active household.' using errcode = '22023';
  end if;

  if nullif(p_payload->>'parentSpaceId','') is not null then
    v_parent_space_id := (p_payload->>'parentSpaceId')::uuid;
    if not exists (
      select 1
      from atlas.household_spaces ps
      where ps.id = v_parent_space_id
        and ps.dwelling_id = v_dwelling_id
        and ps.household_id = v_household_id
    ) then
      raise exception 'Parent space must belong to the same dwelling.' using errcode = '22023';
    end if;
  end if;

  v_stable_key := btrim(coalesce(p_payload->>'stableKey',''));
  v_name := btrim(coalesce(p_payload->>'name',''));
  v_space_type := btrim(coalesce(p_payload->>'spaceType',''));

  if v_stable_key = '' or v_name = '' or v_space_type = '' then
    raise exception 'stableKey, name, and spaceType are required.' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_payload->'functionalTags','[]'::jsonb)) <> 'array' then
    raise exception 'functionalTags must be an array.' using errcode = '22023';
  end if;

  select coalesce(array_agg(tag order by tag), '{}'::text[])
    into v_tags
  from (
    select distinct btrim(value) as tag
    from jsonb_array_elements_text(coalesce(p_payload->'functionalTags','[]'::jsonb))
    where btrim(value) <> ''
  ) x;

  v_confidence := coalesce(nullif(p_payload->>'confidence',''), 'confirmed');
  if v_confidence not in ('candidate','confirmed') then
    raise exception 'confidence must be candidate or confirmed.' using errcode = '22023';
  end if;
  v_confirmed_at := case
    when v_confidence = 'confirmed'
      then coalesce((nullif(p_payload->>'confirmedAt','')::timestamptz), now())
    else null
  end;

  insert into atlas.household_spaces (
    household_id,
    dwelling_id,
    parent_space_id,
    stable_key,
    name,
    space_type,
    functional_tags,
    floor_level,
    care_relevant,
    active,
    source_kind,
    confidence,
    confirmed_at,
    metadata
  )
  values (
    v_household_id,
    v_dwelling_id,
    v_parent_space_id,
    v_stable_key,
    v_name,
    v_space_type,
    v_tags,
    nullif(btrim(coalesce(p_payload->>'floorLevel','')), ''),
    coalesce((p_payload->>'careRelevant')::boolean, true),
    coalesce((p_payload->>'active')::boolean, true),
    coalesce(nullif(btrim(p_payload->>'sourceKind'), ''), 'principal_authoring'),
    v_confidence,
    v_confirmed_at,
    coalesce(p_payload->'metadata','{}'::jsonb)
  )
  on conflict (dwelling_id, stable_key)
  do update set
    parent_space_id = excluded.parent_space_id,
    name = excluded.name,
    space_type = excluded.space_type,
    functional_tags = excluded.functional_tags,
    floor_level = excluded.floor_level,
    care_relevant = excluded.care_relevant,
    active = excluded.active,
    source_kind = excluded.source_kind,
    confidence = excluded.confidence,
    confirmed_at = excluded.confirmed_at,
    metadata = coalesce(atlas.household_spaces.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = now()
  returning id into v_space_id;

  return jsonb_build_object(
    'ok', true,
    'householdId', v_household_id,
    'dwellingId', v_dwelling_id,
    'spaceId', v_space_id,
    'stableKey', v_stable_key,
    'functionalTags', to_jsonb(v_tags),
    'confidence', v_confidence
  );
end;
$$;

revoke all on function atlas.principal_upsert_household_space_api_v1(jsonb) from public, anon;
grant execute on function atlas.principal_upsert_household_space_api_v1(jsonb) to authenticated, service_role;

commit;
