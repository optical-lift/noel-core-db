create or replace function local_intel.elm_local_categories_for_event_v1(
  p_event_kind text,
  p_audience jsonb,
  p_cost jsonb,
  p_details jsonb
)
returns text[]
language plpgsql
immutable
set search_path to pg_catalog
as $function$
declare
  v_kind text := pg_catalog.lower(coalesce(p_event_kind,''));
  v_audience jsonb := coalesce(p_audience,'{}'::jsonb);
  v_cost jsonb := coalesce(p_cost,'{}'::jsonb);
  v_categories text[] := '{}'::text[];
  v_amount numeric;
  v_ages text := pg_catalog.lower(coalesce(v_audience->>'ages',''));
begin
  if v_kind in ('family_event','family_field_club_session')
     or pg_catalog.lower(coalesce(v_audience->>'family_friendly','')) in ('true','1','yes')
     or pg_catalog.lower(coalesce(v_audience->>'school_families','')) in ('true','1','yes')
     or pg_catalog.lower(coalesce(v_audience->>'audience','')) = 'families'
     or v_audience ? 'grades'
     or v_ages like '%birth%'
     or v_ages ~ '(^|[^0-9])(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17)(-|–| to )(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17)([^0-9]|$)' then
    v_categories := pg_catalog.array_append(v_categories,'kids-family');
  end if;

  if v_kind = 'free_community_morning'
     or pg_catalog.lower(coalesce(v_cost->>'spectator_admission','')) = 'free' then
    v_categories := pg_catalog.array_append(v_categories,'free');
  elsif (v_cost ? 'amount') then
    begin
      v_amount := (v_cost->>'amount')::numeric;
      if v_amount = 0 then
        v_categories := pg_catalog.array_append(v_categories,'free');
      end if;
    exception when others then
      null;
    end;
  end if;

  if v_kind in ('festival','cultural_festival','arts_crafts_festival','food_festival','expo','swap_meet','market','farmers_market','fair') then
    v_categories := pg_catalog.array_append(v_categories,'markets-festivals');
  end if;
  if v_kind in ('food_festival','food_event','dining_event') then v_categories := pg_catalog.array_append(v_categories,'food'); end if;
  if v_kind in ('concert','live_music','music_event','music_festival') then v_categories := pg_catalog.array_append(v_categories,'music'); end if;
  if v_kind in ('audition','theatre_performance','theater_performance','performance','arts_crafts_festival','art_show') then v_categories := pg_catalog.array_append(v_categories,'arts-theater'); end if;
  if v_kind in ('craft_workshop','workshop','class','ticketed_seasonal_evening') then v_categories := pg_catalog.array_append(v_categories,'classes-workshops'); end if;
  if v_kind in ('public_movement_session','equestrian_event','outdoor_event','hike','nature_program') then v_categories := pg_catalog.array_append(v_categories,'outdoors'); end if;
  if v_kind in ('school_sports','family_field_club_session','equestrian_event','sports_event','tournament','race') then v_categories := pg_catalog.array_append(v_categories,'sports'); end if;
  if v_kind in ('community_event','community_program','club_meeting','benefit_auction','free_community_morning') then v_categories := pg_catalog.array_append(v_categories,'community'); end if;

  return array(select distinct x from pg_catalog.unnest(v_categories) as x order by x);
end;
$function$;

update local_intel.occurrences set updated_at=updated_at where start_at >= timestamptz '2026-08-29 00:00:00-05';
update atlas.community_events set updated_at=updated_at where event_date >= date '2026-08-29';