-- Atlas native Person capacity: confirmed zero weekday is not unknown.
-- Source-only guarded candidate; no production release.
begin;

alter table atlas.principal_capacity_policies
  alter column local_start drop not null,
  alter column local_end drop not null;
alter table atlas.principal_capacity_policies
  drop constraint principal_capacity_policies_check;
alter table atlas.principal_capacity_policies
  add constraint principal_capacity_policies_confirmed_interval_v1
  check (
    (local_start is null and local_end is null
     and default_discretionary_minutes=0 and maximum_planned_minutes=0)
    or
    (local_start is not null and local_end is not null and local_end>local_start)
  );
comment on column atlas.principal_capacity_policies.local_start is
  'Positive confirmed availability starts here; NULL with NULL end and zero planning minutes is explicitly unavailable, not unknown.';
comment on column atlas.principal_capacity_policies.local_end is
  'Positive confirmed availability ends here; NULL with NULL start and zero planning minutes is explicitly unavailable, not unknown.';

CREATE OR REPLACE FUNCTION atlas.personal_set_capacity_policy_self_api_v1(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth', 'personal'
AS $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_stable_key text;
  v_name text;
  v_weekdays smallint[];
  v_local_start time;
  v_local_end time;
  v_default integer;
  v_maximum integer;
  v_window_minutes integer;
  v_availability_state text;
  v_from date;
  v_through date;
  v_metadata jsonb;
  v_row atlas.principal_capacity_policies%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id
  into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal capacity compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Capacity policy input must be an object.' using errcode='22023';
  end if;

  v_stable_key:=nullif(trim(p_input->>'stableKey'),'');
  v_name:=nullif(trim(p_input->>'name'),'');
  if v_stable_key is null or v_name is null then
    raise exception 'stableKey and name are required.' using errcode='22023';
  end if;

  if jsonb_typeof(p_input->'weekdays')<>'array' then
    raise exception 'weekdays must be an array.' using errcode='22023';
  end if;

  select coalesce(array_agg(value::smallint order by ord),array[]::smallint[])
  into v_weekdays
  from jsonb_array_elements_text(p_input->'weekdays')
       with ordinality e(value,ord);

  if cardinality(v_weekdays)=0 then
    raise exception 'At least one weekday is required.' using errcode='22023';
  end if;

  if exists(select 1 from unnest(v_weekdays) d where d<0 or d>6) then
    raise exception 'weekdays values must be integers from 0 through 6.'
      using errcode='22023';
  end if;

  if (
    select count(*)<>count(distinct d)
    from unnest(v_weekdays) d
  ) then
    raise exception 'weekdays must not contain duplicates.' using errcode='22023';
  end if;

  v_availability_state:=coalesce(nullif(trim(p_input->>'availabilityState'),''),'confirmed_available');
  if v_availability_state not in ('confirmed_available','confirmed_unavailable') then
    raise exception 'Invalid confirmed availability state.' using errcode='22023';
  end if;
  if v_availability_state='confirmed_unavailable' then
    if nullif(trim(p_input->>'localStart'),'') is not null
      or nullif(trim(p_input->>'localEnd'),'') is not null then
      raise exception 'Explicitly unavailable weekdays must not have a fabricated time window.' using errcode='22023';
    end if;
    v_local_start:=null;
    v_local_end:=null;
    v_window_minutes:=0;
  else
  if nullif(p_input->>'localStart','') is null
     or nullif(p_input->>'localEnd','') is null then
    raise exception 'localStart and localEnd are required.' using errcode='22023';
  end if;

  begin
    v_local_start:=(p_input->>'localStart')::time;
    v_local_end:=(p_input->>'localEnd')::time;
  exception when others then
    raise exception 'localStart and localEnd must be valid local times.'
      using errcode='22023';
  end;

  if v_local_end<=v_local_start then
    raise exception 'localEnd must be later than localStart on the same local day.'
      using errcode='22023';
  end if;

  v_window_minutes:=round(
    extract(epoch from (v_local_end-v_local_start))/60.0
  )::integer;

  end if;

  if nullif(p_input->>'defaultDiscretionaryMinutes','') is null
     or nullif(p_input->>'maximumPlannedMinutes','') is null then
    raise exception 'defaultDiscretionaryMinutes and maximumPlannedMinutes are required.'
      using errcode='22023';
  end if;

  begin
    v_default:=(p_input->>'defaultDiscretionaryMinutes')::integer;
    v_maximum:=(p_input->>'maximumPlannedMinutes')::integer;
  exception when others then
    raise exception 'Capacity minute values must be integers.' using errcode='22023';
  end;

  if v_default<0 or v_maximum<0 then
    raise exception 'Capacity minute values cannot be negative.' using errcode='22023';
  end if;

  if v_default>v_maximum then
    raise exception 'defaultDiscretionaryMinutes cannot exceed maximumPlannedMinutes.'
      using errcode='22023';
  end if;

  if v_availability_state='confirmed_unavailable' and (v_default<>0 or v_maximum<>0) then
    raise exception 'Explicit unavailability must have zero discretionary and maximum planned minutes.' using errcode='22023';
  end if;
  if v_maximum>v_window_minutes then
    raise exception 'maximumPlannedMinutes cannot exceed the local capacity window itself.'
      using errcode='22023';
  end if;

  if nullif(p_input->>'effectiveFrom','') is null then
    raise exception 'effectiveFrom is required.' using errcode='22023';
  end if;

  begin
    v_from:=(p_input->>'effectiveFrom')::date;
    v_through:=case
      when nullif(p_input->>'effectiveThrough','') is null then null
      else (p_input->>'effectiveThrough')::date
    end;
  exception when others then
    raise exception 'Capacity policy dates must be valid dates.' using errcode='22023';
  end;

  if v_through is not null and v_through<v_from then
    raise exception 'effectiveThrough cannot be earlier than effectiveFrom.'
      using errcode='22023';
  end if;

  v_metadata:=case
    when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata'
    else '{}'::jsonb
  end;

  v_metadata:=v_metadata||jsonb_build_object(
    'availabilityState',v_availability_state,
    'explicitZeroHasNoTimeWindow',(v_availability_state='confirmed_unavailable')
  );
  -- Zero-capacity policy may not overlap a separate active source claim to
  -- positive capacity on the same weekday/date. Preserve existing behavior
  -- for positive-only policies, and allow same source-key/date retries.
  if exists (
    select 1 from atlas.principal_capacity_policies existing
    where existing.principal_id=v_compat_principal_id
      and existing.active
      and not (existing.stable_key=v_stable_key and existing.effective_from=v_from)
      and (existing.local_start is null or v_availability_state='confirmed_unavailable')
      and existing.effective_from<=coalesce(v_through,'infinity'::date)
      and coalesce(existing.effective_through,'infinity'::date)>=v_from
      and exists (select 1 from unnest(existing.weekdays) wd where wd=any(v_weekdays))
  ) then
    raise exception 'Explicit zero capacity conflicts with a distinct effective capacity policy.' using errcode='22023';
  end if;

  insert into atlas.principal_capacity_policies(
    principal_id,stable_key,name,weekdays,local_start,local_end,
    default_discretionary_minutes,maximum_planned_minutes,
    effective_from,effective_through,active,metadata
  ) values (
    v_compat_principal_id,v_stable_key,v_name,v_weekdays,v_local_start,v_local_end,
    v_default,v_maximum,v_from,v_through,true,
    v_metadata||jsonb_build_object(
      'source','personal_set_capacity_policy_self_api_v1',
      'personEntityId',v_person_id,
      'personalAtlasId',v_personal_atlas_id,
      'legacyPrincipalStorageOnly',true
    )
  )
  on conflict(principal_id,stable_key,effective_from) do update set
    name=excluded.name,
    weekdays=excluded.weekdays,
    local_start=excluded.local_start,
    local_end=excluded.local_end,
    default_discretionary_minutes=excluded.default_discretionary_minutes,
    maximum_planned_minutes=excluded.maximum_planned_minutes,
    effective_through=excluded.effective_through,
    active=true,
    metadata=atlas.principal_capacity_policies.metadata||excluded.metadata
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','personal_capacity_policy_authoring_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'policy',to_jsonb(v_row)-'principal_id',
    'capacityOnEffectiveFrom',atlas.principal_capacity_day_state_v1(
      v_compat_principal_id,v_from
    ),
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'principalDoesNotEstablishIdentity',true,
      'organizationRoleDoesNotEstablishAccess',true
    )
  );
end
$function$;

CREATE OR REPLACE FUNCTION atlas.personal_capacity_policies_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth', 'personal'
AS $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_policies jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id
  into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal capacity compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',p.id,
        'stableKey',p.stable_key,
        'name',p.name,
        'availabilityState',case when p.local_start is null and p.local_end is null then 'confirmed_unavailable' else 'confirmed_available' end,
        'weekdays',to_jsonb(p.weekdays),
        'localStart',to_char(p.local_start,'HH24:MI'),
        'localEnd',to_char(p.local_end,'HH24:MI'),
        'defaultDiscretionaryMinutes',p.default_discretionary_minutes,
        'maximumPlannedMinutes',p.maximum_planned_minutes,
        'effectiveFrom',p.effective_from,
        'effectiveThrough',p.effective_through,
        'active',p.active,
        'metadata',p.metadata,
        'createdAt',p.created_at,
        'updatedAt',p.updated_at
      )
      order by p.effective_from desc,p.created_at desc
    ),
    '[]'::jsonb
  )
  into v_policies
  from atlas.principal_capacity_policies p
  where p.principal_id=v_compat_principal_id
    and p.active;

  return jsonb_build_object(
    'contractVersion','personal_capacity_policies_self_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'policies',v_policies,
    'capacityToday',atlas.principal_capacity_day_state_v1(
      v_compat_principal_id,current_date
    ),
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'principalDoesNotEstablishIdentity',true,
      'organizationRoleDoesNotEstablishAccess',true
    )
  );
end
$function$;

CREATE OR REPLACE FUNCTION atlas.principal_capacity_day_state_v1(p_principal_id uuid, p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal atlas.principals%rowtype;
  v_policy atlas.principal_capacity_policies%rowtype;
  v_timezone text;
  v_start timestamptz;
  v_end timestamptz;
  v_elapsed integer:=0;
  v_blocked integer:=0;
  v_available integer:=0;
  v_adjusted_loss integer:=0;
  v_adjusted_available integer:=0;
  v_discretionary integer:=0;
  v_maximum integer:=0;
begin
  if p_day is null then raise exception 'A Principal capacity date is required.' using errcode='22023'; end if;
  select * into v_principal from atlas.principals where id=p_principal_id;
  if v_principal.id is null then raise exception 'Principal not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and v_principal.user_id<>auth.uid() then
    raise exception 'Principal capacity may only be read by that Principal.' using errcode='42501';
  end if;
  v_timezone:=atlas.principal_authoritative_timezone_v1(p_principal_id);

  select * into v_policy
  from atlas.principal_capacity_policies p
  where p.principal_id=p_principal_id and p.active
    and p.effective_from<=p_day
    and (p.effective_through is null or p.effective_through>=p_day)
    and extract(dow from p_day)::smallint=any(p.weekdays)
  order by p.effective_from desc,p.created_at desc
  limit 1;

  if v_policy.id is null then
    return jsonb_build_object(
      'contractVersion','principal_capacity_day_state_v2',
      'principalId',p_principal_id,'serviceDate',p_day,
      'state','anchor_required','capacityKnown',false,
      'timezone',v_timezone,
      'reason','No effective Principal Capacity policy defines this day.'
    );
  end if;

  if v_policy.local_start is null and v_policy.local_end is null then
    -- Source-affirmed zero has no positive time interval to fabricate.
    -- It is KNOWN, not a missing capacity anchor, and never free time.
    return jsonb_build_object(
      'contractVersion','principal_capacity_day_state_v2',
      'principalId',p_principal_id,'serviceDate',p_day,
      'state','resolved','capacityKnown',true,'timezone',v_timezone,
      'policyId',v_policy.id,'availabilityState','confirmed_unavailable',
      'startsAt',null,'endsAt',null,
      'elapsedMinutes',0,'blockedMinutes',0,
      'availableElapsedMinutesBeforeAdjustments',0,
      'reducedCapacityEquivalentMinutes',0,
      'availableElapsedMinutes',0,
      'discretionaryCapacityMinutes',0,'maximumPlannedMinutes',0,
      'truthBoundary',jsonb_build_object(
        'ownerConfirmedNoAvailability',true,
        'noFabricatedTimeInterval',true,
        'confirmedZeroCapacityLivesInPolicy',true,
        'noCapacityBlockWasSynthesized',true,
        'partialAvailabilityLivesInCapacityAdjustments',true,
        'adjustmentsDoNotCreateClockCandidates',true
      )
    );
  end if;

  v_start:=(p_day::timestamp+v_policy.local_start) at time zone v_timezone;
  v_end:=(p_day::timestamp+v_policy.local_end) at time zone v_timezone;
  v_elapsed:=greatest(0,round(extract(epoch from (v_end-v_start))/60.0)::integer);

  with spans as (
    select tstzrange(greatest(b.starts_at,v_start),least(b.ends_at,v_end),'[)') as span
    from atlas.principal_capacity_blocks_v1 b
    where b.principal_id=p_principal_id
      and b.ends_at>v_start and b.starts_at<v_end
  ), merged as (
    select range_agg(span) as spans from spans where not isempty(span)
  )
  select coalesce(sum(round(extract(epoch from (upper(r)-lower(r)))/60.0)::integer),0)
  into v_blocked
  from merged m
  cross join lateral unnest(m.spans) r;

  v_available:=greatest(v_elapsed-v_blocked,0);

  -- For each instant, only the strictest active availability fraction applies.
  -- This prevents overlapping causes from being multiplicatively double-counted.
  with bounds as (
    select v_start as t union select v_end
    union
    select greatest(a.starts_at,v_start)
    from atlas.principal_capacity_adjustments a
    where a.principal_id=p_principal_id and a.active and a.ends_at>v_start and a.starts_at<v_end
    union
    select least(a.ends_at,v_end)
    from atlas.principal_capacity_adjustments a
    where a.principal_id=p_principal_id and a.active and a.ends_at>v_start and a.starts_at<v_end
    union
    select greatest(b.starts_at,v_start)
    from atlas.principal_capacity_blocks_v1 b
    where b.principal_id=p_principal_id and b.ends_at>v_start and b.starts_at<v_end
    union
    select least(b.ends_at,v_end)
    from atlas.principal_capacity_blocks_v1 b
    where b.principal_id=p_principal_id and b.ends_at>v_start and b.starts_at<v_end
  ), segments as (
    select t as s,lead(t) over(order by t) as e from bounds
  ), rated as (
    select s,e,
      case when exists(
        select 1 from atlas.principal_capacity_blocks_v1 b
        where b.principal_id=p_principal_id and b.starts_at<e and b.ends_at>s
      ) then 0::numeric
      else coalesce((
        select min(a.availability_fraction)
        from atlas.principal_capacity_adjustments a
        where a.principal_id=p_principal_id and a.active and a.starts_at<e and a.ends_at>s
      ),1::numeric) end as fraction
    from segments where e is not null and e>s
  )
  select greatest(0,round(sum(extract(epoch from (e-s))/60.0*fraction))::integer)
  into v_adjusted_available
  from rated;

  v_adjusted_available:=coalesce(v_adjusted_available,v_available);
  v_adjusted_loss:=greatest(v_available-v_adjusted_available,0);
  v_discretionary:=least(v_policy.default_discretionary_minutes,v_adjusted_available);
  v_maximum:=least(v_policy.maximum_planned_minutes,v_adjusted_available);

  return jsonb_build_object(
    'contractVersion','principal_capacity_day_state_v2',
    'principalId',p_principal_id,'serviceDate',p_day,
    'state','resolved','capacityKnown',true,'timezone',v_timezone,
    'policyId',v_policy.id,'startsAt',v_start,'endsAt',v_end,
    'elapsedMinutes',v_elapsed,'blockedMinutes',v_blocked,
    'availableElapsedMinutesBeforeAdjustments',v_available,
    'reducedCapacityEquivalentMinutes',v_adjusted_loss,
    'availableElapsedMinutes',v_adjusted_available,
    'discretionaryCapacityMinutes',v_discretionary,
    'maximumPlannedMinutes',v_maximum,
    'truthBoundary',jsonb_build_object(
      'zeroAvailabilityLivesInCapacityBlocks',true,
      'partialAvailabilityLivesInCapacityAdjustments',true,
      'overlappingAdjustmentsUseStrictestFractionNotMultiplication',true,
      'adjustmentsDoNotCreateClockCandidates',true
    )
  );
end;
$function$;

commit;
