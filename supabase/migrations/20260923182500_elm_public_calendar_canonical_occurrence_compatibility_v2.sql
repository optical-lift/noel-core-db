-- Atlas Elm public calendar canonical-occurrence compatibility v2
-- The public Elm calendar remains a compatibility projection, but canonical
-- local_intel.occurrences is now the sole event identity/source of truth.
-- Atlas community_events and Organization purpose contexts contribute only
-- private/operational projection overlays.

alter table public.elm_local_calendar_events_v1
  add column if not exists occurrence_id uuid;

update public.elm_local_calendar_events_v1 p
set occurrence_id = case
  when p.source_system='local_intel' then (
    select o.id
    from local_intel.occurrences o
    where o.stable_key=p.source_stable_key
    limit 1
  )
  when p.source_system='atlas' then (
    select b.occurrence_id
    from atlas.community_events ce
    join atlas.organization_occurrence_bindings b
      on b.id=ce.occurrence_binding_id
    where ce.stable_key=p.source_stable_key
    limit 1
  )
  else null
end
where p.occurrence_id is null;

do $$
begin
  if exists(
    select 1
    from public.elm_local_calendar_events_v1
    where occurrence_id is null
  ) then
    raise exception 'Public Elm calendar contains rows without canonical occurrence identity.'
      using errcode='23514';
  end if;

  if exists(
    select occurrence_id
    from public.elm_local_calendar_events_v1
    group by occurrence_id
    having count(*) > 1
  ) then
    raise exception 'Public Elm calendar contains duplicate rows for a canonical occurrence.'
      using errcode='23514';
  end if;
end
$$;

alter table public.elm_local_calendar_events_v1
  alter column occurrence_id set not null;

do $$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.elm_local_calendar_events_v1'::regclass
      and conname='elm_local_calendar_events_v1_occurrence_fk_v2'
  ) then
    alter table public.elm_local_calendar_events_v1
      add constraint elm_local_calendar_events_v1_occurrence_fk_v2
      foreign key (occurrence_id)
      references local_intel.occurrences(id)
      on delete cascade;
  end if;

  if not exists(
    select 1 from pg_constraint
    where conrelid='public.elm_local_calendar_events_v1'::regclass
      and conname='elm_local_calendar_events_v1_occurrence_uq_v2'
  ) then
    alter table public.elm_local_calendar_events_v1
      add constraint elm_local_calendar_events_v1_occurrence_uq_v2
      unique (occurrence_id);
  end if;
end
$$;

create or replace function local_intel.refresh_elm_local_calendar_occurrence_v2(
  p_occurrence_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel','atlas','public'
as $function$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_occ local_intel.occurrences%rowtype;
  v_host_name text;
  v_host_stable_key text;
  v_binding_id uuid;
  v_overlay atlas.community_events%rowtype;
  v_is_elm_owned boolean := false;
  v_include boolean := false;
  v_public_id text;
  v_legacy_source_system text;
  v_legacy_source_stable_key text;
  v_existing_details jsonb := '{}'::jsonb;
  v_time_precision text;
  v_cost jsonb := '{}'::jsonb;
  v_audience jsonb := '{}'::jsonb;
  v_details jsonb := '{}'::jsonb;
  v_categories text[] := '{}'::text[];
  v_feature_rank integer;
  v_feature_note text;
  v_series_key text;
  v_series_title text;
  v_series_summary text;
  v_publication_status text;
  v_source_updated_at timestamptz;
begin
  select *
  into v_occ
  from local_intel.occurrences o
  where o.id=p_occurrence_id;

  if v_occ.id is null then
    delete from public.elm_local_calendar_events_v1
    where occurrence_id=p_occurrence_id;
    return;
  end if;

  select e.name,e.stable_key
  into v_host_name,v_host_stable_key
  from local_intel.entities e
  where e.id=v_occ.entity_id;

  select b.id
  into v_binding_id
  from atlas.organization_occurrence_bindings b
  where b.organization_id=v_org
    and b.occurrence_id=v_occ.id
  limit 1;

  if v_binding_id is not null then
    select ce.*
    into v_overlay
    from atlas.community_events ce
    join atlas.farms f on f.id=ce.farm_id
    where ce.occurrence_binding_id=v_binding_id
      and f.organization_id=v_org
    order by ce.updated_at desc,ce.id
    limit 1;
  end if;

  v_is_elm_owned := coalesce(v_host_stable_key='elm-farm',false)
                    or v_overlay.id is not null;

  if v_is_elm_owned then
    v_include := v_overlay.id is not null
      and v_overlay.event_date >= date '2026-08-29'
      and v_overlay.visibility_scope='farm_shared'
      and v_overlay.status in ('planned','scheduled');
  else
    v_include := v_occ.start_at >= timestamptz '2026-08-29 00:00:00-05'
      and local_intel.occurrence_in_elm_local_coverage_v1(v_occ.city,v_occ.state)
      and v_occ.status in ('scheduled','announced_save_the_date','conditional');
  end if;

  if not v_include then
    delete from public.elm_local_calendar_events_v1
    where occurrence_id=v_occ.id;
    return;
  end if;

  select
    p.public_id,
    p.source_system,
    p.source_stable_key,
    p.details
  into
    v_public_id,
    v_legacy_source_system,
    v_legacy_source_stable_key,
    v_existing_details
  from public.elm_local_calendar_events_v1 p
  where p.occurrence_id=v_occ.id;

  v_public_id := coalesce(v_public_id,'local_' || pg_catalog.md5(v_occ.id::text));
  -- Retained only as compatibility provenance. occurrence_id is authoritative.
  v_legacy_source_system := coalesce(v_legacy_source_system,'local_intel');
  v_legacy_source_stable_key := coalesce(v_legacy_source_stable_key,v_occ.stable_key);

  if v_is_elm_owned then
    v_time_precision := 'exact';

    v_cost := case
      when v_occ.price is not null and v_occ.price <> '{}'::jsonb then v_occ.price
      when v_overlay.metadata ? 'season_price' then v_overlay.metadata -> 'season_price'
      when v_overlay.metadata ? 'ticket_types'
        then pg_catalog.jsonb_build_object('ticket_types',v_overlay.metadata->'ticket_types')
      else '{}'::jsonb
    end;

    v_audience := case
      when v_occ.audience is not null and v_occ.audience <> '{}'::jsonb then v_occ.audience
      when pg_catalog.lower(coalesce(v_overlay.metadata->>'household_program','')) in ('true','1','yes')
        then pg_catalog.jsonb_build_object('audience','families')
      else '{}'::jsonb
    end;

    v_details := coalesce(v_existing_details,'{}'::jsonb)
      || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'public_format',v_overlay.metadata->>'public_format',
        'public_theme',v_overlay.metadata->>'public_theme',
        'baked_good_pairing',v_overlay.metadata->>'baked_good_pairing',
        'program_detail',v_overlay.metadata->>'program_detail',
        'sport',v_overlay.metadata->>'sport',
        'canonicalOccurrenceId',v_occ.id,
        'projectionAuthority','canonical_occurrence_plus_organization_overlay'
      ));

    v_publication_status := v_overlay.status;
    v_source_updated_at := pg_catalog.greatest(v_occ.updated_at,v_overlay.updated_at);
  else
    v_time_precision := case
      when v_occ.status='conditional'
        or v_occ.metadata ? 'conditional'
        or pg_catalog.lower(v_occ.title) like '%if needed%'
        then 'conditional'
      when v_occ.status='announced_save_the_date'
        or pg_catalog.lower(coalesce(v_occ.metadata->>'all_day_placeholder','')) in ('true','1','yes')
        or pg_catalog.lower(coalesce(v_occ.metadata->>'exact_times_unknown','')) in ('true','1','yes')
        or v_occ.metadata ? 'deadline_local_date'
        or pg_catalog.lower(coalesce(v_occ.metadata->>'time_status','')) like '%not exact time%'
        or pg_catalog.lower(coalesce(v_occ.metadata->>'time_status','')) like '%date but not exact time%'
        or ((v_occ.start_at at time zone 'America/Chicago')::time = time '00:00:00')
        then 'date_only'
      else 'exact'
    end;

    v_cost := coalesce(v_occ.price,'{}'::jsonb);
    v_audience := coalesce(v_occ.audience,'{}'::jsonb);
    v_details := coalesce(v_existing_details,'{}'::jsonb)
      || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'deadline_local_date',v_occ.metadata->>'deadline_local_date',
        'publication_note',v_occ.metadata->>'publication_note',
        'local_time',v_occ.metadata->>'local_time',
        'start_note',v_occ.metadata->>'start_note',
        'canonicalOccurrenceId',v_occ.id,
        'projectionAuthority','canonical_occurrence'
      ));
    v_publication_status := v_occ.status;
    v_source_updated_at := v_occ.updated_at;
  end if;

  v_categories := local_intel.elm_local_categories_for_event_v1(
    v_occ.occurrence_type,
    v_audience,
    v_cost,
    v_details
  );

  if v_binding_id is not null then
    select
      nullif(m.payload->>'featureRank','')::integer,
      nullif(m.payload->>'featureNote','')
    into v_feature_rank,v_feature_note
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_purpose_contexts c
      on c.id=m.context_id
     and c.organization_id=m.organization_id
    where m.organization_id=v_org
      and m.occurrence_binding_id=v_binding_id
      and m.membership_state='active'
      and c.stable_key='community_calendar'
      and c.context_state='active'
      and coalesce((m.payload->>'featured')::boolean,false)
      and (
        nullif(m.payload->>'activeFrom','') is null
        or (m.payload->>'activeFrom')::date <= (v_occ.start_at at time zone 'America/Chicago')::date
      )
      and (
        nullif(m.payload->>'activeThrough','') is null
        or (m.payload->>'activeThrough')::date >= (v_occ.start_at at time zone 'America/Chicago')::date
      )
    limit 1;

    select c.stable_key,c.title,c.description
    into v_series_key,v_series_title,v_series_summary
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_purpose_contexts c
      on c.id=m.context_id
     and c.organization_id=m.organization_id
    where m.organization_id=v_org
      and m.occurrence_binding_id=v_binding_id
      and m.membership_state='active'
      and c.context_state='active'
      and c.context_kind='occurrence_series'
    order by coalesce(nullif(c.metadata->>'priority','')::integer,999999),c.stable_key
    limit 1;
  end if;

  insert into public.elm_local_calendar_events_v1(
    public_id,
    source_system,
    source_stable_key,
    occurrence_id,
    is_elm_owned,
    title,
    event_kind,
    starts_at,
    ends_at,
    time_precision,
    host_name,
    venue_name,
    city,
    state,
    cost,
    audience,
    categories,
    featured_rank,
    featured_note,
    publication_status,
    public_url,
    details,
    last_verified_at,
    source_updated_at,
    projected_at,
    series_key,
    series_title,
    series_summary
  )
  values(
    v_public_id,
    v_legacy_source_system,
    v_legacy_source_stable_key,
    v_occ.id,
    v_is_elm_owned,
    v_occ.title,
    v_occ.occurrence_type,
    v_occ.start_at,
    v_occ.end_at,
    v_time_precision,
    v_host_name,
    v_occ.venue_name,
    v_occ.city,
    v_occ.state,
    v_cost,
    v_audience,
    coalesce(v_categories,'{}'::text[]),
    v_feature_rank,
    v_feature_note,
    v_publication_status,
    v_occ.public_url,
    v_details,
    v_occ.last_verified_at,
    v_source_updated_at,
    pg_catalog.now(),
    v_series_key,
    v_series_title,
    v_series_summary
  )
  on conflict (occurrence_id)
  do update set
    is_elm_owned=excluded.is_elm_owned,
    title=excluded.title,
    event_kind=excluded.event_kind,
    starts_at=excluded.starts_at,
    ends_at=excluded.ends_at,
    time_precision=excluded.time_precision,
    host_name=excluded.host_name,
    venue_name=excluded.venue_name,
    city=excluded.city,
    state=excluded.state,
    cost=excluded.cost,
    audience=excluded.audience,
    categories=excluded.categories,
    featured_rank=excluded.featured_rank,
    featured_note=excluded.featured_note,
    publication_status=excluded.publication_status,
    public_url=excluded.public_url,
    details=excluded.details,
    last_verified_at=excluded.last_verified_at,
    source_updated_at=excluded.source_updated_at,
    projected_at=excluded.projected_at,
    series_key=excluded.series_key,
    series_title=excluded.series_title,
    series_summary=excluded.series_summary;
end
$function$;

create or replace function local_intel.sync_elm_local_calendar_from_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel','public'
as $function$
begin
  if tg_op='DELETE' then
    delete from public.elm_local_calendar_events_v1
    where occurrence_id=old.id;
    return old;
  end if;

  perform local_intel.refresh_elm_local_calendar_occurrence_v2(new.id);
  return new;
end
$function$;

create or replace function local_intel.sync_elm_local_calendar_from_atlas_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel','atlas'
as $function$
declare
  v_old_occurrence uuid;
  v_new_occurrence uuid;
begin
  if tg_op in ('UPDATE','DELETE') and old.occurrence_binding_id is not null then
    select b.occurrence_id
    into v_old_occurrence
    from atlas.organization_occurrence_bindings b
    where b.id=old.occurrence_binding_id;
  end if;

  if tg_op in ('INSERT','UPDATE') and new.occurrence_binding_id is not null then
    select b.occurrence_id
    into v_new_occurrence
    from atlas.organization_occurrence_bindings b
    where b.id=new.occurrence_binding_id;
  end if;

  if v_old_occurrence is not null then
    perform local_intel.refresh_elm_local_calendar_occurrence_v2(v_old_occurrence);
  end if;

  if v_new_occurrence is not null
     and v_new_occurrence is distinct from v_old_occurrence then
    perform local_intel.refresh_elm_local_calendar_occurrence_v2(v_new_occurrence);
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$function$;

create or replace function atlas.refresh_elm_public_calendar_from_purpose_membership_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_old_occurrence uuid;
  v_new_occurrence uuid;
begin
  if tg_op in ('UPDATE','DELETE')
     and old.organization_id=v_org
     and old.member_kind='occurrence_binding'
     and old.occurrence_binding_id is not null then
    select b.occurrence_id
    into v_old_occurrence
    from atlas.organization_occurrence_bindings b
    where b.id=old.occurrence_binding_id;
  end if;

  if tg_op in ('INSERT','UPDATE')
     and new.organization_id=v_org
     and new.member_kind='occurrence_binding'
     and new.occurrence_binding_id is not null then
    select b.occurrence_id
    into v_new_occurrence
    from atlas.organization_occurrence_bindings b
    where b.id=new.occurrence_binding_id;
  end if;

  if v_old_occurrence is not null then
    perform local_intel.refresh_elm_local_calendar_occurrence_v2(v_old_occurrence);
  end if;

  if v_new_occurrence is not null
     and v_new_occurrence is distinct from v_old_occurrence then
    perform local_intel.refresh_elm_local_calendar_occurrence_v2(v_new_occurrence);
  end if;

  return case when tg_op='DELETE' then old else new end;
end
$function$;

drop trigger if exists refresh_elm_public_calendar_from_purpose_membership_v1
  on atlas.organization_purpose_context_memberships;

create trigger refresh_elm_public_calendar_from_purpose_membership_v1
after insert or update or delete
on atlas.organization_purpose_context_memberships
for each row
execute function atlas.refresh_elm_public_calendar_from_purpose_membership_v1();

create or replace function atlas.refresh_elm_public_calendar_from_purpose_context_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_context_id uuid;
  v_occurrence_id uuid;
begin
  if tg_op='DELETE' then
    v_context_id := old.id;
    if old.organization_id is distinct from v_org then
      return old;
    end if;
  else
    v_context_id := new.id;
    if new.organization_id is distinct from v_org then
      return new;
    end if;
  end if;

  for v_occurrence_id in
    select b.occurrence_id
    from atlas.organization_purpose_context_memberships m
    join atlas.organization_occurrence_bindings b
      on b.id=m.occurrence_binding_id
     and b.organization_id=m.organization_id
    where m.context_id=v_context_id
      and m.organization_id=v_org
      and m.member_kind='occurrence_binding'
  loop
    perform local_intel.refresh_elm_local_calendar_occurrence_v2(v_occurrence_id);
  end loop;

  return case when tg_op='DELETE' then old else new end;
end
$function$;

drop trigger if exists refresh_elm_public_calendar_from_purpose_context_v1
  on atlas.organization_purpose_contexts;

create trigger refresh_elm_public_calendar_from_purpose_context_v1
after update
on atlas.organization_purpose_contexts
for each row
execute function atlas.refresh_elm_public_calendar_from_purpose_context_v1();

-- Retire the old second-authority and legacy configuration trigger paths.
drop trigger if exists apply_elm_local_series_projection_v1
  on public.elm_local_calendar_events_v1;

drop trigger if exists sync_elm_local_calendar_from_curation_v1
  on local_intel.elm_local_event_curations_v1;

drop trigger if exists sync_elm_local_series_rule_v1
  on local_intel.elm_local_event_series_rules_v1;

-- Reproject every existing public row through canonical occurrence authority.
do $$
declare
  v_before integer;
  v_after integer;
  v_occurrence_id uuid;
begin
  select count(*) into v_before
  from public.elm_local_calendar_events_v1;

  for v_occurrence_id in
    select occurrence_id
    from public.elm_local_calendar_events_v1
    order by occurrence_id
  loop
    perform local_intel.refresh_elm_local_calendar_occurrence_v2(v_occurrence_id);
  end loop;

  select count(*) into v_after
  from public.elm_local_calendar_events_v1;

  if v_after <> v_before then
    raise exception
      'Canonical calendar reprojection changed public row count from % to %; refusing compatibility cutover.',
      v_before,v_after
      using errcode='23514';
  end if;
end
$$;

comment on column public.elm_local_calendar_events_v1.occurrence_id is
  'Authoritative canonical event identity. Every public Elm calendar row resolves to exactly one local_intel occurrence.';
comment on column public.elm_local_calendar_events_v1.source_system is
  'Legacy compatibility provenance only. It no longer selects event authority; occurrence_id is authoritative.';
comment on column public.elm_local_calendar_events_v1.source_stable_key is
  'Legacy compatibility provenance for pre-v2 consumers. It is not event identity authority.';
comment on table public.elm_local_calendar_events_v1 is
  'Non-canonical public Elm calendar compatibility projection. Canonical event identity is local_intel.occurrences. Elm operational visibility comes from Atlas Organization overlays; curation and series come from Organization purpose contexts.';
comment on function local_intel.refresh_elm_local_calendar_occurrence_v2(uuid) is
  'Canonical public Elm calendar projector: one local_intel occurrence plus authorized Elm Organization overlays/purpose contexts. This supersedes the former Atlas-vs-local_intel split authority.';
