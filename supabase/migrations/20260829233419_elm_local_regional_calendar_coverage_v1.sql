create or replace function local_intel.occurrence_in_elm_local_coverage_v1(p_city text, p_state text)
returns boolean
language sql
stable
security definer
set search_path to pg_catalog, local_intel
as $function$
  select exists (
    select 1
    from local_intel.geographic_areas ga
    where ga.area_type = 'locality'
      and pg_catalog.lower(pg_catalog.btrim(coalesce(ga.name,''))) = pg_catalog.lower(pg_catalog.btrim(coalesce(p_city,'')))
      and pg_catalog.upper(pg_catalog.btrim(coalesce(ga.state,''))) = pg_catalog.upper(pg_catalog.btrim(coalesce(p_state,'')))
      and ga.verification_state = 'source_verified'
      and (
        ga.metadata ->> 'market_role' = 'origin_locality'
        or exists (
          select 1
          from local_intel.regional_ingestion_targets rit
          where rit.geographic_area_id = ga.id
            and rit.target_scope = 'full_locality_reality_census'
            and rit.status in ('active','in_process')
        )
      )
  );
$function$;

revoke all on function local_intel.occurrence_in_elm_local_coverage_v1(text,text) from public, anon, authenticated;

grant execute on function local_intel.occurrence_in_elm_local_coverage_v1(text,text) to service_role;

create or replace function local_intel.sync_elm_local_calendar_from_occurrence_v1()
returns trigger
language plpgsql
security definer
set search_path to pg_catalog
as $function$
declare
  v_public_id text;
  v_host_name text;
  v_host_stable_key text;
  v_time_precision text;
begin
  if tg_op = 'DELETE' then
    v_public_id := 'local_' || pg_catalog.md5(old.id::text);
    delete from public.elm_local_calendar_events_v1 where public_id = v_public_id;
    return old;
  end if;

  v_public_id := 'local_' || pg_catalog.md5(new.id::text);
  delete from public.elm_local_calendar_events_v1 where public_id = v_public_id;

  select e.name, e.stable_key
    into v_host_name, v_host_stable_key
  from local_intel.entities e
  where e.id = new.entity_id;

  if new.start_at >= timestamptz '2026-08-29 00:00:00-05'
     and local_intel.occurrence_in_elm_local_coverage_v1(new.city,new.state)
     and coalesce(v_host_stable_key,'') <> 'elm-farm'
     and new.status in ('scheduled','announced_save_the_date','conditional') then
    v_time_precision := case
      when new.status = 'conditional'
        or new.metadata ? 'conditional'
        or pg_catalog.lower(new.title) like '%if needed%'
        then 'conditional'
      when new.status = 'announced_save_the_date'
        or pg_catalog.lower(coalesce(new.metadata ->> 'all_day_placeholder','')) in ('true','1','yes')
        or pg_catalog.lower(coalesce(new.metadata ->> 'exact_times_unknown','')) in ('true','1','yes')
        or new.metadata ? 'deadline_local_date'
        or pg_catalog.lower(coalesce(new.metadata ->> 'time_status','')) like '%not exact time%'
        or pg_catalog.lower(coalesce(new.metadata ->> 'time_status','')) like '%date but not exact time%'
        or ((new.start_at at time zone 'America/Chicago')::time = time '00:00:00')
        then 'date_only'
      else 'exact'
    end;

    insert into public.elm_local_calendar_events_v1 (
      public_id, source_system, is_elm_owned, title, event_kind,
      starts_at, ends_at, time_precision, host_name, venue_name,
      city, state, cost, audience, publication_status, public_url,
      details, last_verified_at, source_updated_at, projected_at
    ) values (
      v_public_id,
      'local_intel',
      false,
      new.title,
      new.occurrence_type,
      new.start_at,
      new.end_at,
      v_time_precision,
      v_host_name,
      new.venue_name,
      new.city,
      new.state,
      coalesce(new.price, '{}'::jsonb),
      coalesce(new.audience, '{}'::jsonb),
      new.status,
      new.public_url,
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'deadline_local_date', new.metadata ->> 'deadline_local_date',
        'publication_note', new.metadata ->> 'publication_note',
        'local_time', new.metadata ->> 'local_time',
        'start_note', new.metadata ->> 'start_note'
      )),
      new.last_verified_at,
      new.updated_at,
      pg_catalog.now()
    );
  end if;

  return new;
end;
$function$;

-- Re-project the governed future external occurrence set through the trigger
-- without changing canonical occurrence timestamps or verification evidence.
update local_intel.occurrences o
set updated_at = o.updated_at
where o.start_at >= timestamptz '2026-08-29 00:00:00-05'
  and o.status in ('scheduled','announced_save_the_date','conditional');