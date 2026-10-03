
create table reality.availability_profiles (
  id uuid primary key default gen_random_uuid(),
  subject_entity_id uuid null references reality.entities(id) on delete cascade,
  subject_resource_id uuid null references reality.resources(id) on delete cascade,
  timezone_name text not null,
  default_state text not null default 'available'
    check (default_state in ('available','unavailable')),
  profile_state text not null default 'active'
    check (profile_state in ('active','paused','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((subject_entity_id is not null)::int + (subject_resource_id is not null)::int = 1)
);
create unique index availability_profiles_entity_uq on reality.availability_profiles(subject_entity_id)
  where subject_entity_id is not null;
create unique index availability_profiles_resource_uq on reality.availability_profiles(subject_resource_id)
  where subject_resource_id is not null;
alter table reality.availability_profiles enable row level security;
create trigger availability_profiles_set_updated_at before update on reality.availability_profiles
for each row execute function atlas.set_updated_at();

create table reality.availability_rules (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references reality.availability_profiles(id) on delete cascade,
  stable_key text not null,
  rule_effect text not null check (rule_effect in ('available','unavailable')),
  effective_start_date date not null,
  effective_end_date date null,
  weekdays smallint[] not null default array[0,1,2,3,4,5,6]::smallint[],
  all_day boolean not null default false,
  local_start_time time null,
  local_end_time time null,
  priority integer not null default 0,
  rule_state text not null default 'active'
    check (rule_state in ('active','paused','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key) <> ''),
  check (effective_end_date is null or effective_end_date >= effective_start_date),
  check (weekdays <@ array[0,1,2,3,4,5,6]::smallint[] and cardinality(weekdays) > 0),
  check (
    (all_day and local_start_time is null and local_end_time is null)
    or
    (not all_day and local_start_time is not null and local_end_time is not null and local_start_time<>local_end_time)
  ),
  unique(profile_id,stable_key)
);
create index availability_rules_profile_state_idx on reality.availability_rules(profile_id,rule_state,effective_start_date,effective_end_date);
alter table reality.availability_rules enable row level security;
create trigger availability_rules_set_updated_at before update on reality.availability_rules
for each row execute function atlas.set_updated_at();

create table reality.availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references reality.availability_profiles(id) on delete cascade,
  stable_key text not null,
  local_date date not null,
  exception_effect text not null check (exception_effect in ('available','unavailable')),
  all_day boolean not null default true,
  local_start_time time null,
  local_end_time time null,
  priority integer not null default 100,
  exception_state text not null default 'active'
    check (exception_state in ('active','retired')),
  reason text null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key) <> ''),
  check (
    (all_day and local_start_time is null and local_end_time is null)
    or
    (not all_day and local_start_time is not null and local_end_time is not null and local_start_time<>local_end_time)
  ),
  unique(profile_id,stable_key)
);
create index availability_exceptions_profile_date_idx on reality.availability_exceptions(profile_id,local_date,exception_state);
alter table reality.availability_exceptions enable row level security;
create trigger availability_exceptions_set_updated_at before update on reality.availability_exceptions
for each row execute function atlas.set_updated_at();

create or replace function reality.guard_availability_profile_v1()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.subject_entity_id is not null
     and not exists(select 1 from reality.entities e where e.id=new.subject_entity_id and e.identity_state='canonical') then
    raise exception 'Availability Entity subject must be canonical.' using errcode='23514';
  end if;
  if new.subject_resource_id is not null
     and not exists(select 1 from reality.resources r where r.id=new.subject_resource_id and r.resource_state<>'retired') then
    raise exception 'Availability resource subject is missing or retired.' using errcode='23514';
  end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=new.timezone_name) then
    raise exception 'Unknown availability timezone: %',new.timezone_name using errcode='22023';
  end if;
  return new;
end;
$$;
create trigger availability_profiles_guard before insert or update
on reality.availability_profiles for each row execute function reality.guard_availability_profile_v1();

create table ledger.booking_policies (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  resource_id uuid null references reality.resources(id) on delete cascade,
  stable_key text not null,
  booking_kind text null,
  policy_kind text not null
    check (policy_kind in ('duration','booking_window','start_increment','buffer','approval','recurrence')),
  policy_state text not null default 'active'
    check (policy_state in ('active','paused','retired')),
  priority integer not null default 0,
  config jsonb not null default '{}'::jsonb check (jsonb_typeof(config)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key) <> ''),
  unique(ledger_id,stable_key)
);
create index booking_policies_match_idx on ledger.booking_policies(ledger_id,policy_state,policy_kind,booking_kind,resource_id);
alter table ledger.booking_policies enable row level security;
create trigger booking_policies_set_updated_at before update on ledger.booking_policies
for each row execute function atlas.set_updated_at();

create or replace function ledger.guard_booking_policy_v1()
returns trigger language plpgsql set search_path='' as $$
declare v_subject uuid;
begin
  select l.subject_entity_id into v_subject
  from ledger.ledgers l
  where l.id=new.ledger_id and l.ledger_state='active';

  if v_subject is null then
    raise exception 'Booking policy requires an active Ledger.' using errcode='23514';
  end if;

  if new.resource_id is not null and not exists(
    select 1 from reality.resources r
    where r.id=new.resource_id and r.owner_entity_id=v_subject and r.resource_state<>'retired'
  ) then
    raise exception 'Booking policy resource must belong to the Ledger subject Entity.'
      using errcode='23514';
  end if;

  if new.policy_kind='duration' then
    if (new.config ? 'minMinutes' and (new.config->>'minMinutes')::numeric < 0)
       or (new.config ? 'maxMinutes' and (new.config->>'maxMinutes')::numeric <= 0)
       or (
         new.config ? 'minMinutes' and new.config ? 'maxMinutes'
         and (new.config->>'maxMinutes')::numeric < (new.config->>'minMinutes')::numeric
       ) then
      raise exception 'Invalid duration policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='booking_window' then
    if (new.config ? 'minNoticeMinutes' and (new.config->>'minNoticeMinutes')::numeric < 0)
       or (new.config ? 'maxAdvanceMinutes' and (new.config->>'maxAdvanceMinutes')::numeric < 0) then
      raise exception 'Invalid booking-window policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='start_increment' then
    if not (new.config ? 'minutes') or (new.config->>'minutes')::integer <= 0 then
      raise exception 'Start-increment policy requires minutes > 0.' using errcode='22023';
    end if;
  elsif new.policy_kind='buffer' then
    if (new.config ? 'setupMinutes' and (new.config->>'setupMinutes')::numeric < 0)
       or (new.config ? 'teardownMinutes' and (new.config->>'teardownMinutes')::numeric < 0) then
      raise exception 'Invalid buffer policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='approval' then
    if new.config ? 'required' and jsonb_typeof(new.config->'required')<>'boolean' then
      raise exception 'Approval required must be boolean.' using errcode='22023';
    end if;
  elsif new.policy_kind='recurrence' then
    if new.config ? 'allowed' and jsonb_typeof(new.config->'allowed')<>'boolean' then
      raise exception 'Recurrence allowed must be boolean.' using errcode='22023';
    end if;
  end if;

  return new;
end;
$$;
create trigger booking_policies_guard before insert or update
on ledger.booking_policies for each row execute function ledger.guard_booking_policy_v1();

create or replace function reality.upsert_availability_profile_service_v1(
  p_subject_kind text,
  p_subject_id uuid,
  p_timezone_name text,
  p_default_state text default 'available',
  p_profile_state text default 'active',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_profile reality.availability_profiles%rowtype;
begin
  if p_subject_kind not in ('entity','resource') then
    raise exception 'Availability subject kind must be entity or resource.' using errcode='22023';
  end if;
  if p_default_state not in ('available','unavailable') then
    raise exception 'Unknown default availability state.' using errcode='22023';
  end if;
  if p_profile_state not in ('active','paused','retired') then
    raise exception 'Unknown availability profile state.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Availability metadata/provenance must be JSON objects.' using errcode='22023';
  end if;

  if p_subject_kind='entity' then
    select * into v_profile from reality.availability_profiles where subject_entity_id=p_subject_id;
  else
    select * into v_profile from reality.availability_profiles where subject_resource_id=p_subject_id;
  end if;

  if v_profile.id is null then
    insert into reality.availability_profiles(
      subject_entity_id,subject_resource_id,timezone_name,default_state,profile_state,metadata,provenance
    ) values(
      case when p_subject_kind='entity' then p_subject_id end,
      case when p_subject_kind='resource' then p_subject_id end,
      p_timezone_name,p_default_state,p_profile_state,p_metadata,p_provenance
    ) returning * into v_profile;
  else
    update reality.availability_profiles
    set timezone_name=p_timezone_name,
        default_state=p_default_state,
        profile_state=p_profile_state,
        metadata=reality.availability_profiles.metadata||p_metadata,
        provenance=reality.availability_profiles.provenance||p_provenance,
        updated_at=now()
    where id=v_profile.id
    returning * into v_profile;
  end if;

  return jsonb_build_object(
    'contractVersion','reality_availability_profile_v1',
    'profileId',v_profile.id,'subjectKind',p_subject_kind,'subjectId',p_subject_id,
    'timezoneName',v_profile.timezone_name,'defaultState',v_profile.default_state,'profileState',v_profile.profile_state
  );
end;
$$;

create or replace function reality.upsert_availability_rule_service_v1(
  p_profile_id uuid,
  p_stable_key text,
  p_rule_effect text,
  p_effective_start_date date,
  p_effective_end_date date default null,
  p_weekdays smallint[] default array[0,1,2,3,4,5,6]::smallint[],
  p_all_day boolean default false,
  p_local_start_time time default null,
  p_local_end_time time default null,
  p_priority integer default 0,
  p_rule_state text default 'active',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_rule reality.availability_rules%rowtype;
begin
  insert into reality.availability_rules(
    profile_id,stable_key,rule_effect,effective_start_date,effective_end_date,weekdays,
    all_day,local_start_time,local_end_time,priority,rule_state,metadata,provenance
  ) values(
    p_profile_id,btrim(p_stable_key),p_rule_effect,p_effective_start_date,p_effective_end_date,
    p_weekdays,p_all_day,p_local_start_time,p_local_end_time,p_priority,p_rule_state,
    coalesce(p_metadata,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb)
  )
  on conflict(profile_id,stable_key) do update
  set rule_effect=excluded.rule_effect,
      effective_start_date=excluded.effective_start_date,
      effective_end_date=excluded.effective_end_date,
      weekdays=excluded.weekdays,
      all_day=excluded.all_day,
      local_start_time=excluded.local_start_time,
      local_end_time=excluded.local_end_time,
      priority=excluded.priority,
      rule_state=excluded.rule_state,
      metadata=reality.availability_rules.metadata||excluded.metadata,
      provenance=reality.availability_rules.provenance||excluded.provenance,
      updated_at=now()
  returning * into v_rule;

  return jsonb_build_object(
    'contractVersion','reality_availability_rule_v1',
    'ruleId',v_rule.id,'profileId',v_rule.profile_id,'stableKey',v_rule.stable_key,
    'ruleEffect',v_rule.rule_effect,'ruleState',v_rule.rule_state
  );
end;
$$;

create or replace function reality.upsert_availability_exception_service_v1(
  p_profile_id uuid,
  p_stable_key text,
  p_local_date date,
  p_exception_effect text,
  p_all_day boolean default true,
  p_local_start_time time default null,
  p_local_end_time time default null,
  p_priority integer default 100,
  p_exception_state text default 'active',
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_exception reality.availability_exceptions%rowtype;
begin
  insert into reality.availability_exceptions(
    profile_id,stable_key,local_date,exception_effect,all_day,local_start_time,local_end_time,
    priority,exception_state,reason,metadata,provenance
  ) values(
    p_profile_id,btrim(p_stable_key),p_local_date,p_exception_effect,p_all_day,
    p_local_start_time,p_local_end_time,p_priority,p_exception_state,p_reason,
    coalesce(p_metadata,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb)
  )
  on conflict(profile_id,stable_key) do update
  set local_date=excluded.local_date,
      exception_effect=excluded.exception_effect,
      all_day=excluded.all_day,
      local_start_time=excluded.local_start_time,
      local_end_time=excluded.local_end_time,
      priority=excluded.priority,
      exception_state=excluded.exception_state,
      reason=excluded.reason,
      metadata=reality.availability_exceptions.metadata||excluded.metadata,
      provenance=reality.availability_exceptions.provenance||excluded.provenance,
      updated_at=now()
  returning * into v_exception;

  return jsonb_build_object(
    'contractVersion','reality_availability_exception_v1',
    'exceptionId',v_exception.id,'profileId',v_exception.profile_id,'stableKey',v_exception.stable_key,
    'localDate',v_exception.local_date,'exceptionEffect',v_exception.exception_effect
  );
end;
$$;

create or replace function reality.subject_schedule_availability_v1(
  p_subject_kind text,
  p_subject_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_profile reality.availability_profiles%rowtype;
  v_local_start timestamp;
  v_local_end timestamp;
  v_date date;
  v_seg_start timestamptz;
  v_seg_end timestamptz;
  v_source_date date;
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_exception reality.availability_exceptions%rowtype;
  v_rule_id uuid;
  v_rule_key text;
  v_blockers jsonb:='[]'::jsonb;
  v_day_open boolean;
begin
  if p_subject_kind not in ('entity','resource') then
    raise exception 'Availability subject kind must be entity or resource.' using errcode='22023';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Availability window must have starts_at < ends_at.' using errcode='22023';
  end if;

  if p_subject_kind='entity' then
    select * into v_profile
    from reality.availability_profiles
    where subject_entity_id=p_subject_id and profile_state='active';
  else
    select * into v_profile
    from reality.availability_profiles
    where subject_resource_id=p_subject_id and profile_state='active';
  end if;

  if v_profile.id is null then
    return jsonb_build_object(
      'contractVersion','reality_subject_schedule_availability_v1',
      'subjectKind',p_subject_kind,'subjectId',p_subject_id,
      'available',true,'mode','no_profile_default_open','blockingRules','[]'::jsonb
    );
  end if;

  v_local_start:=p_starts_at at time zone v_profile.timezone_name;
  v_local_end:=p_ends_at at time zone v_profile.timezone_name;

  for v_date in
    select gs::date
    from generate_series(v_local_start::date,v_local_end::date,interval '1 day') gs
  loop
    v_seg_start:=greatest(p_starts_at,(v_date::timestamp) at time zone v_profile.timezone_name);
    v_seg_end:=least(p_ends_at,((v_date+1)::timestamp) at time zone v_profile.timezone_name);
    if v_seg_end<=v_seg_start then continue; end if;

    select e.*
      into v_exception
    from reality.availability_exceptions e
    where e.profile_id=v_profile.id
      and e.exception_state='active'
      and e.local_date in (v_date,v_date-1)
      and (
        case when e.all_day
          then (e.local_date::timestamp at time zone v_profile.timezone_name)
          else ((e.local_date + e.local_start_time) at time zone v_profile.timezone_name)
        end
      ) < v_seg_end
      and (
        case when e.all_day
          then ((e.local_date+1)::timestamp at time zone v_profile.timezone_name)
          when e.local_end_time > e.local_start_time
            then ((e.local_date + e.local_end_time) at time zone v_profile.timezone_name)
          else (((e.local_date+1) + e.local_end_time) at time zone v_profile.timezone_name)
        end
      ) > v_seg_start
    order by e.priority desc,
             case when e.exception_effect='unavailable' then 0 else 1 end,
             e.updated_at desc,e.id
    limit 1;

    if v_exception.id is not null then
      v_window_start:=case when v_exception.all_day
        then (v_exception.local_date::timestamp at time zone v_profile.timezone_name)
        else ((v_exception.local_date + v_exception.local_start_time) at time zone v_profile.timezone_name)
      end;
      v_window_end:=case when v_exception.all_day
        then ((v_exception.local_date+1)::timestamp at time zone v_profile.timezone_name)
        when v_exception.local_end_time > v_exception.local_start_time
          then ((v_exception.local_date + v_exception.local_end_time) at time zone v_profile.timezone_name)
        else (((v_exception.local_date+1) + v_exception.local_end_time) at time zone v_profile.timezone_name)
      end;

      if v_exception.exception_effect='unavailable' then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'kind','exception','id',v_exception.id,'stableKey',v_exception.stable_key,
          'effect','unavailable','reason',v_exception.reason,
          'windowStart',v_window_start,'windowEnd',v_window_end
        ));
        continue;
      elsif v_window_start<=v_seg_start and v_window_end>=v_seg_end then
        continue;
      end if;
    end if;

    select r.id,r.stable_key,sd.source_date,
      case when r.all_day
        then (sd.source_date::timestamp at time zone v_profile.timezone_name)
        else ((sd.source_date+r.local_start_time) at time zone v_profile.timezone_name)
      end,
      case when r.all_day
        then ((sd.source_date+1)::timestamp at time zone v_profile.timezone_name)
        when r.local_end_time > r.local_start_time
          then ((sd.source_date+r.local_end_time) at time zone v_profile.timezone_name)
        else (((sd.source_date+1)+r.local_end_time) at time zone v_profile.timezone_name)
      end
    into v_rule_id,v_rule_key,v_source_date,v_window_start,v_window_end
    from reality.availability_rules r
    cross join lateral (
      select d::date as source_date from (values(v_date),(v_date-1)) x(d)
    ) sd
    where r.profile_id=v_profile.id
      and r.rule_state='active'
      and r.rule_effect='unavailable'
      and sd.source_date between r.effective_start_date and coalesce(r.effective_end_date,sd.source_date)
      and extract(dow from sd.source_date)::smallint=any(r.weekdays)
      and (
        case when r.all_day
          then (sd.source_date::timestamp at time zone v_profile.timezone_name)
          else ((sd.source_date + r.local_start_time) at time zone v_profile.timezone_name)
        end
      ) < v_seg_end
      and (
        case when r.all_day
          then ((sd.source_date+1)::timestamp at time zone v_profile.timezone_name)
          when r.local_end_time > r.local_start_time
            then ((sd.source_date + r.local_end_time) at time zone v_profile.timezone_name)
          else (((sd.source_date+1) + r.local_end_time) at time zone v_profile.timezone_name)
        end
      ) > v_seg_start
    order by r.priority desc,r.updated_at desc,r.id
    limit 1;

    if v_rule_id is not null then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'kind','rule','id',v_rule_id,'stableKey',v_rule_key,
        'effect','unavailable','sourceLocalDate',v_source_date,
        'windowStart',v_window_start,'windowEnd',v_window_end
      ));
      v_rule_id:=null; v_rule_key:=null;
      continue;
    end if;

    if v_profile.default_state='unavailable' then
      v_day_open:=exists(
        select 1
        from reality.availability_rules r
        cross join lateral (
          select d::date as source_date from (values(v_date),(v_date-1)) x(d)
        ) sd
        where r.profile_id=v_profile.id
          and r.rule_state='active'
          and r.rule_effect='available'
          and sd.source_date between r.effective_start_date and coalesce(r.effective_end_date,sd.source_date)
          and extract(dow from sd.source_date)::smallint=any(r.weekdays)
          and (
            case when r.all_day
              then (sd.source_date::timestamp at time zone v_profile.timezone_name)
              else ((sd.source_date+r.local_start_time) at time zone v_profile.timezone_name)
            end
          ) <= v_seg_start
          and (
            case when r.all_day
              then ((sd.source_date+1)::timestamp at time zone v_profile.timezone_name)
              when r.local_end_time > r.local_start_time
                then ((sd.source_date+r.local_end_time) at time zone v_profile.timezone_name)
              else (((sd.source_date+1)+r.local_end_time) at time zone v_profile.timezone_name)
            end
          ) >= v_seg_end
      );

      if not v_day_open then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'kind','profile_default','effect','unavailable',
          'localDate',v_date,'reason','outside_available_windows'
        ));
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','reality_subject_schedule_availability_v1',
    'profileId',v_profile.id,
    'subjectKind',p_subject_kind,'subjectId',p_subject_id,
    'timezoneName',v_profile.timezone_name,
    'defaultState',v_profile.default_state,
    'available',jsonb_array_length(v_blockers)=0,
    'blockingRules',v_blockers
  );
end;
$$;

create or replace function ledger.upsert_booking_policy_service_v1(
  p_ledger_id uuid,
  p_stable_key text,
  p_policy_kind text,
  p_config jsonb,
  p_resource_id uuid default null,
  p_booking_kind text default null,
  p_priority integer default 0,
  p_policy_state text default 'active',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_policy ledger.booking_policies%rowtype;
begin
  insert into ledger.booking_policies(
    ledger_id,resource_id,stable_key,booking_kind,policy_kind,policy_state,priority,
    config,metadata,provenance
  ) values(
    p_ledger_id,p_resource_id,btrim(p_stable_key),nullif(btrim(p_booking_kind),''),
    p_policy_kind,p_policy_state,p_priority,coalesce(p_config,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb)
  )
  on conflict(ledger_id,stable_key) do update
  set resource_id=excluded.resource_id,
      booking_kind=excluded.booking_kind,
      policy_kind=excluded.policy_kind,
      policy_state=excluded.policy_state,
      priority=excluded.priority,
      config=excluded.config,
      metadata=ledger.booking_policies.metadata||excluded.metadata,
      provenance=ledger.booking_policies.provenance||excluded.provenance,
      updated_at=now()
  returning * into v_policy;

  return jsonb_build_object(
    'contractVersion','ledger_booking_policy_v1',
    'policyId',v_policy.id,'ledgerId',v_policy.ledger_id,'stableKey',v_policy.stable_key,
    'policyKind',v_policy.policy_kind,'policyState',v_policy.policy_state
  );
end;
$$;

create or replace function ledger.evaluate_booking_policies_v1(
  p_ledger_id uuid,
  p_resource_ids uuid[],
  p_booking_kind text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_is_recurring boolean default false,
  p_as_of timestamptz default now()
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_policy ledger.booking_policies%rowtype;
  v_duration numeric;
  v_blockers jsonb:='[]'::jsonb;
  v_applied jsonb:='[]'::jsonb;
  v_setup integer:=0;
  v_teardown integer:=0;
  v_approval boolean:=false;
  v_tz text:='UTC';
  v_local_start timestamp;
  v_increment integer;
  v_minute_of_day integer;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Booking policy window must have starts_at < ends_at.' using errcode='22023';
  end if;

  v_duration:=extract(epoch from (p_ends_at-p_starts_at))/60.0;

  if p_resource_ids is not null and cardinality(p_resource_ids)>0 then
    select coalesce(r.timezone_name,'UTC') into v_tz
    from reality.resources r where r.id=p_resource_ids[1];
  end if;

  for v_policy in
    select p.*
    from ledger.booking_policies p
    where p.ledger_id=p_ledger_id
      and p.policy_state='active'
      and (p.booking_kind is null or p.booking_kind=p_booking_kind)
      and (p.resource_id is null or p.resource_id=any(coalesce(p_resource_ids,'{}'::uuid[])))
    order by p.priority desc,p.stable_key,p.id
  loop
    v_applied:=v_applied||jsonb_build_array(jsonb_build_object(
      'policyId',v_policy.id,'stableKey',v_policy.stable_key,'policyKind',v_policy.policy_kind
    ));

    if v_policy.policy_kind='duration' then
      if v_policy.config ? 'minMinutes'
         and v_duration < (v_policy.config->>'minMinutes')::numeric then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','duration_too_short','policyId',v_policy.id,'minimumMinutes',(v_policy.config->>'minMinutes')::numeric
        ));
      end if;
      if v_policy.config ? 'maxMinutes'
         and v_duration > (v_policy.config->>'maxMinutes')::numeric then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','duration_too_long','policyId',v_policy.id,'maximumMinutes',(v_policy.config->>'maxMinutes')::numeric
        ));
      end if;

    elsif v_policy.policy_kind='booking_window' then
      if v_policy.config ? 'minNoticeMinutes'
         and p_starts_at < p_as_of + make_interval(mins=>(v_policy.config->>'minNoticeMinutes')::integer) then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','minimum_notice_not_met','policyId',v_policy.id,'minimumNoticeMinutes',(v_policy.config->>'minNoticeMinutes')::integer
        ));
      end if;
      if v_policy.config ? 'maxAdvanceMinutes'
         and p_starts_at > p_as_of + make_interval(mins=>(v_policy.config->>'maxAdvanceMinutes')::integer) then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','maximum_advance_exceeded','policyId',v_policy.id,'maximumAdvanceMinutes',(v_policy.config->>'maxAdvanceMinutes')::integer
        ));
      end if;

    elsif v_policy.policy_kind='start_increment' then
      v_increment:=(v_policy.config->>'minutes')::integer;
      v_local_start:=p_starts_at at time zone coalesce(nullif(v_policy.config->>'timezoneName',''),v_tz);
      v_minute_of_day:=extract(hour from v_local_start)::integer*60+extract(minute from v_local_start)::integer;
      if mod(v_minute_of_day-coalesce((v_policy.config->>'offsetMinutes')::integer,0),v_increment)<>0
         or extract(second from v_local_start)<>0 then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','start_increment_mismatch','policyId',v_policy.id,'incrementMinutes',v_increment
        ));
      end if;

    elsif v_policy.policy_kind='buffer' then
      v_setup:=greatest(v_setup,coalesce((v_policy.config->>'setupMinutes')::integer,0));
      v_teardown:=greatest(v_teardown,coalesce((v_policy.config->>'teardownMinutes')::integer,0));

    elsif v_policy.policy_kind='approval' then
      if coalesce((v_policy.config->>'required')::boolean,false) then
        v_approval:=true;
      end if;

    elsif v_policy.policy_kind='recurrence' then
      if p_is_recurring and not coalesce((v_policy.config->>'allowed')::boolean,true) then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','recurrence_not_allowed','policyId',v_policy.id
        ));
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','ledger_booking_policy_evaluation_v1',
    'ledgerId',p_ledger_id,
    'bookingKind',p_booking_kind,
    'allowed',jsonb_array_length(v_blockers)=0,
    'blockingReasons',v_blockers,
    'appliedPolicies',v_applied,
    'requirements',jsonb_build_object(
      'setupBufferMinutes',v_setup,
      'teardownBufferMinutes',v_teardown,
      'approvalRequired',v_approval
    )
  );
end;
$$;

create or replace function ledger.resource_claim_availability_v1(
  p_ledger_id uuid,
  p_resource_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_requested_claim_kind text default 'exclusive',
  p_requested_quantity numeric default null,
  p_exclude_claim_id uuid default null,
  p_exclude_occurrence_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_subject uuid;
  v_resource reality.resources%rowtype;
  v_blockers jsonb;
  v_capacity_used numeric:=0;
  v_capacity_exceeded boolean:=false;
  v_schedule_checks jsonb:='[]'::jsonb;
  v_schedule_available boolean:=true;
  v_schedule_result jsonb;
  v_related_resource record;
  v_available boolean:=false;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Availability window must have starts_at < ends_at.' using errcode='22023';
  end if;
  if p_requested_claim_kind not in ('exclusive','shared','capacity') then
    raise exception 'Unknown requested claim kind: %',p_requested_claim_kind using errcode='22023';
  end if;

  select l.subject_entity_id into v_subject
  from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active';
  if v_subject is null then raise exception 'Active Ledger required.' using errcode='23514'; end if;

  select * into v_resource from reality.resources r where r.id=p_resource_id;
  if v_resource.id is null or v_resource.owner_entity_id<>v_subject then
    raise exception 'Resource is outside this Ledger subject.' using errcode='23514';
  end if;

  if v_resource.capacity_mode='quantity'
     and p_requested_claim_kind='capacity'
     and (p_requested_quantity is null or p_requested_quantity<=0) then
    raise exception 'Quantity-governed capacity request requires requested_quantity > 0.'
      using errcode='22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,'occurrenceId',c.occurrence_id,'bookingId',c.booking_id,'resourceId',c.resource_id,
    'resourceLabel',rr.label,'claimKind',c.claim_kind,'claimState',c.claim_state,'startsAt',c.starts_at,'endsAt',c.ends_at
  ) order by c.starts_at,c.id),'[]'::jsonb)
  into v_blockers
  from ledger.occurrence_resource_claims c
  join reality.resources rr on rr.id=c.resource_id
  where c.ledger_id=p_ledger_id
    and c.claim_state in ('tentative','confirmed')
    and c.starts_at<p_ends_at
    and c.ends_at>p_starts_at
    and (p_exclude_claim_id is null or c.id<>p_exclude_claim_id)
    and (p_exclude_occurrence_id is null or c.occurrence_id<>p_exclude_occurrence_id)
    and c.resource_id in (select d.resource_id from ledger.resource_conflict_domain_v1(p_resource_id) d)
    and (p_requested_claim_kind='exclusive' or c.claim_kind='exclusive');

  if v_resource.capacity_mode='quantity' and p_requested_claim_kind='capacity' then
    select coalesce(sum(c.quantity),0) into v_capacity_used
    from ledger.occurrence_resource_claims c
    where c.ledger_id=p_ledger_id and c.resource_id=p_resource_id
      and c.claim_state in ('tentative','confirmed') and c.claim_kind='capacity'
      and c.starts_at<p_ends_at and c.ends_at>p_starts_at
      and (p_exclude_claim_id is null or c.id<>p_exclude_claim_id)
      and (p_exclude_occurrence_id is null or c.occurrence_id<>p_exclude_occurrence_id);
    v_capacity_exceeded:=v_capacity_used+p_requested_quantity>v_resource.capacity_quantity;
  end if;

  for v_related_resource in
    select r.id,r.label
    from ledger.resource_conflict_domain_v1(p_resource_id) d
    join reality.resources r on r.id=d.resource_id
    order by r.id
  loop
    v_schedule_result:=reality.subject_schedule_availability_v1(
      'resource',v_related_resource.id,p_starts_at,p_ends_at
    );
    v_schedule_checks:=v_schedule_checks||jsonb_build_array(jsonb_build_object(
      'resourceId',v_related_resource.id,
      'resourceLabel',v_related_resource.label,
      'availability',v_schedule_result
    ));
    if not coalesce((v_schedule_result->>'available')::boolean,true) then
      v_schedule_available:=false;
    end if;
  end loop;

  v_available:=v_resource.resource_state='active'
    and v_resource.reservable
    and jsonb_array_length(v_blockers)=0
    and not v_capacity_exceeded
    and v_schedule_available;

  return jsonb_build_object(
    'contractVersion','ledger_resource_availability_v2',
    'ledgerId',p_ledger_id,'resourceId',v_resource.id,'resourceLabel',v_resource.label,
    'windowStart',p_starts_at,'windowEnd',p_ends_at,
    'requestedClaimKind',p_requested_claim_kind,'requestedQuantity',p_requested_quantity,
    'available',v_available,'resourceState',v_resource.resource_state,'reservable',v_resource.reservable,
    'capacityMode',v_resource.capacity_mode,'capacityQuantity',v_resource.capacity_quantity,
    'capacityUnit',v_resource.capacity_unit,'capacityUsed',v_capacity_used,'capacityExceeded',v_capacity_exceeded,
    'scheduleAvailable',v_schedule_available,'scheduleChecks',v_schedule_checks,'blockingClaims',v_blockers
  );
end;
$$;

create or replace function ledger.establish_booking_bundle_service_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_booking_kind text,
  p_claims jsonb,
  p_customer_entity_id uuid default null,
  p_business_model_key text default null,
  p_booking_label text default null,
  p_booking_state text default 'hold',
  p_created_by_seat_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_booking_json jsonb;
  v_booking_id uuid;
  v_resource_ids uuid[];
  v_claim jsonb;
  v_claim_result jsonb;
  v_claim_results jsonb:='[]'::jsonb;
  v_idx integer:=0;
  v_claim_idem text;
  v_occ_start timestamptz;
  v_occ_end timestamptz;
  v_policy jsonb;
  v_setup integer:=0;
  v_teardown integer:=0;
  v_claim_start timestamptz;
  v_claim_end timestamptz;
  v_apply_buffers boolean;
begin
  if p_claims is null or jsonb_typeof(p_claims)<>'array' or jsonb_array_length(p_claims)=0 then
    raise exception 'Booking bundle requires a non-empty JSON array of resource claims.'
      using errcode='22023';
  end if;

  if exists(
    select 1 from jsonb_array_elements(p_claims) x
    where jsonb_typeof(x)<>'object'
       or nullif(x->>'resourceId','') is null
       or nullif(x->>'claimKind','') is null
       or nullif(x->>'startsAt','') is null
       or nullif(x->>'endsAt','') is null
  ) then
    raise exception 'Every booking bundle claim requires resourceId, claimKind, startsAt, and endsAt.'
      using errcode='22023';
  end if;

  select array_agg(distinct (x->>'resourceId')::uuid order by (x->>'resourceId')::uuid)
    into v_resource_ids
  from jsonb_array_elements(p_claims) x;

  select o.start_at,o.end_at into v_occ_start,v_occ_end
  from local_intel.occurrences o where o.id=p_occurrence_id;

  if v_occ_start is null then raise exception 'Booking occurrence not found.' using errcode='P0002'; end if;

  if v_occ_end is null then
    select min((x->>'startsAt')::timestamptz),max((x->>'endsAt')::timestamptz)
      into v_occ_start,v_occ_end
    from jsonb_array_elements(p_claims) x;
  end if;

  v_policy:=ledger.evaluate_booking_policies_v1(
    p_ledger_id,v_resource_ids,p_booking_kind,v_occ_start,v_occ_end,false,now()
  );

  if not coalesce((v_policy->>'allowed')::boolean,false) then
    raise exception 'Booking violates policy: %',v_policy using errcode='23514';
  end if;

  if p_booking_state='confirmed'
     and coalesce((v_policy->'requirements'->>'approvalRequired')::boolean,false) then
    raise exception 'Booking requires approval before confirmation: %',v_policy using errcode='23514';
  end if;

  v_setup:=coalesce((v_policy->'requirements'->>'setupBufferMinutes')::integer,0);
  v_teardown:=coalesce((v_policy->'requirements'->>'teardownBufferMinutes')::integer,0);

  perform ledger.lock_resource_conflict_domains_v1(v_resource_ids);

  v_booking_json:=ledger.establish_booking_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_customer_entity_id,
    p_business_model_key,p_booking_label,p_booking_state,p_created_by_seat_id,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('policyEvaluation',v_policy),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('atomicResourceBundle',true),
    p_idempotency_key
  );
  v_booking_id:=(v_booking_json->>'bookingId')::uuid;

  for v_claim in select value from jsonb_array_elements(p_claims)
  loop
    v_idx:=v_idx+1;
    v_claim_idem:=coalesce(
      nullif(v_claim->>'idempotencyKey',''),
      case when nullif(p_idempotency_key,'') is null then null else p_idempotency_key||':claim:'||v_idx::text end
    );
    v_apply_buffers:=coalesce((v_claim->>'applyPolicyBuffers')::boolean,true);
    v_claim_start:=(v_claim->>'startsAt')::timestamptz
      - case when v_apply_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_claim_end:=(v_claim->>'endsAt')::timestamptz
      + case when v_apply_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;

    v_claim_result:=ledger.establish_occurrence_resource_claim_service_v1(
      p_ledger_id,p_occurrence_id,(v_claim->>'resourceId')::uuid,v_claim->>'claimKind',
      v_claim_start,v_claim_end,v_booking_id,
      coalesce(nullif(v_claim->>'claimState',''),case when p_booking_state='confirmed' then 'confirmed' else 'tentative' end),
      case when nullif(v_claim->>'quantity','') is null then null else (v_claim->>'quantity')::numeric end,
      nullif(v_claim->>'quantityUnit',''),
      coalesce(v_claim->'metadata','{}'::jsonb)||jsonb_build_object(
        'policyBuffersApplied',v_apply_buffers,'setupBufferMinutes',case when v_apply_buffers then v_setup else 0 end,
        'teardownBufferMinutes',case when v_apply_buffers then v_teardown else 0 end
      ),
      coalesce(v_claim->'provenance','{}'::jsonb)||jsonb_build_object('atomicBookingBundleId',v_booking_id),
      v_claim_idem,false
    );
    v_claim_results:=v_claim_results||jsonb_build_array(v_claim_result);
  end loop;

  return jsonb_build_object(
    'contractVersion','ledger_booking_bundle_v2','booking',v_booking_json,
    'resourceClaims',v_claim_results,'policyEvaluation',v_policy,'atomic',true
  );
end;
$$;

create or replace function atlas.upsert_ledger_availability_profile_self_api_v1(
  p_ledger_id uuid,
  p_subject_kind text,
  p_subject_id uuid,
  p_timezone_name text,
  p_default_state text default 'available',
  p_profile_state text default 'active',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid; v_subject uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'availability.manage');
  v_person:=atlas.current_person_id_v1();
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active';

  if p_subject_kind='entity' then
    if p_subject_id<>v_subject then raise exception 'Availability Entity is outside Ledger subject.' using errcode='42501'; end if;
  elsif p_subject_kind='resource' then
    if not exists(select 1 from reality.resources r where r.id=p_subject_id and r.owner_entity_id=v_subject) then
      raise exception 'Availability resource is outside Ledger subject.' using errcode='42501';
    end if;
  else
    raise exception 'Availability subject kind must be entity or resource.' using errcode='22023';
  end if;

  return reality.upsert_availability_profile_service_v1(
    p_subject_kind,p_subject_id,p_timezone_name,p_default_state,p_profile_state,
    coalesce(p_metadata,'{}'::jsonb),
    jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation,'ledgerId',p_ledger_id)
  );
end;
$$;

create or replace function atlas.upsert_ledger_availability_rule_self_api_v1(
  p_ledger_id uuid,
  p_profile_id uuid,
  p_stable_key text,
  p_rule_effect text,
  p_effective_start_date date,
  p_effective_end_date date default null,
  p_weekdays smallint[] default array[0,1,2,3,4,5,6]::smallint[],
  p_all_day boolean default false,
  p_local_start_time time default null,
  p_local_end_time time default null,
  p_priority integer default 0,
  p_rule_state text default 'active',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid; v_subject uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'availability.manage');
  v_person:=atlas.current_person_id_v1();
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active';

  if not exists(
    select 1 from reality.availability_profiles ap
    left join reality.resources r on r.id=ap.subject_resource_id
    where ap.id=p_profile_id
      and (ap.subject_entity_id=v_subject or r.owner_entity_id=v_subject)
  ) then
    raise exception 'Availability profile is outside Ledger subject.' using errcode='42501';
  end if;

  return reality.upsert_availability_rule_service_v1(
    p_profile_id,p_stable_key,p_rule_effect,p_effective_start_date,p_effective_end_date,p_weekdays,
    p_all_day,p_local_start_time,p_local_end_time,p_priority,p_rule_state,
    coalesce(p_metadata,'{}'::jsonb),
    jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation,'ledgerId',p_ledger_id)
  );
end;
$$;

create or replace function atlas.upsert_ledger_availability_exception_self_api_v1(
  p_ledger_id uuid,
  p_profile_id uuid,
  p_stable_key text,
  p_local_date date,
  p_exception_effect text,
  p_all_day boolean default true,
  p_local_start_time time default null,
  p_local_end_time time default null,
  p_priority integer default 100,
  p_exception_state text default 'active',
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid; v_subject uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'availability.manage');
  v_person:=atlas.current_person_id_v1();
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active';

  if not exists(
    select 1 from reality.availability_profiles ap
    left join reality.resources r on r.id=ap.subject_resource_id
    where ap.id=p_profile_id
      and (ap.subject_entity_id=v_subject or r.owner_entity_id=v_subject)
  ) then
    raise exception 'Availability profile is outside Ledger subject.' using errcode='42501';
  end if;

  return reality.upsert_availability_exception_service_v1(
    p_profile_id,p_stable_key,p_local_date,p_exception_effect,p_all_day,
    p_local_start_time,p_local_end_time,p_priority,p_exception_state,p_reason,
    coalesce(p_metadata,'{}'::jsonb),
    jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation,'ledgerId',p_ledger_id)
  );
end;
$$;

create or replace function atlas.upsert_ledger_booking_policy_self_api_v1(
  p_ledger_id uuid,
  p_stable_key text,
  p_policy_kind text,
  p_config jsonb,
  p_resource_id uuid default null,
  p_booking_kind text default null,
  p_priority integer default 0,
  p_policy_state text default 'active',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'policy.manage');
  v_person:=atlas.current_person_id_v1();

  return ledger.upsert_booking_policy_service_v1(
    p_ledger_id,p_stable_key,p_policy_kind,p_config,p_resource_id,p_booking_kind,p_priority,p_policy_state,
    coalesce(p_metadata,'{}'::jsonb),
    jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation)
  );
end;
$$;

revoke all on reality.availability_profiles,reality.availability_rules,reality.availability_exceptions,ledger.booking_policies
  from public,anon,authenticated;
revoke execute on function reality.upsert_availability_profile_service_v1(text,uuid,text,text,text,jsonb,jsonb)
  from public,anon,authenticated;
revoke execute on function reality.upsert_availability_rule_service_v1(uuid,text,text,date,date,smallint[],boolean,time,time,integer,text,jsonb,jsonb)
  from public,anon,authenticated;
revoke execute on function reality.upsert_availability_exception_service_v1(uuid,text,date,text,boolean,time,time,integer,text,text,jsonb,jsonb)
  from public,anon,authenticated;
revoke execute on function reality.subject_schedule_availability_v1(text,uuid,timestamptz,timestamptz)
  from public,anon,authenticated;
revoke execute on function ledger.upsert_booking_policy_service_v1(uuid,text,text,jsonb,uuid,text,integer,text,jsonb,jsonb)
  from public,anon,authenticated;
revoke execute on function ledger.evaluate_booking_policies_v1(uuid,uuid[],text,timestamptz,timestamptz,boolean,timestamptz)
  from public,anon,authenticated;
revoke execute on function atlas.upsert_ledger_availability_profile_self_api_v1(uuid,text,uuid,text,text,text,jsonb)
  from public,anon;
revoke execute on function atlas.upsert_ledger_availability_rule_self_api_v1(uuid,uuid,text,text,date,date,smallint[],boolean,time,time,integer,text,jsonb)
  from public,anon;
revoke execute on function atlas.upsert_ledger_availability_exception_self_api_v1(uuid,uuid,text,date,text,boolean,time,time,integer,text,text,jsonb)
  from public,anon;
revoke execute on function atlas.upsert_ledger_booking_policy_self_api_v1(uuid,text,text,jsonb,uuid,text,integer,text,jsonb)
  from public,anon;
grant execute on function atlas.upsert_ledger_availability_profile_self_api_v1(uuid,text,uuid,text,text,text,jsonb)
  to authenticated;
grant execute on function atlas.upsert_ledger_availability_rule_self_api_v1(uuid,uuid,text,text,date,date,smallint[],boolean,time,time,integer,text,jsonb)
  to authenticated;
grant execute on function atlas.upsert_ledger_availability_exception_self_api_v1(uuid,uuid,text,date,text,boolean,time,time,integer,text,text,jsonb)
  to authenticated;
grant execute on function atlas.upsert_ledger_booking_policy_self_api_v1(uuid,text,text,jsonb,uuid,text,integer,text,jsonb)
  to authenticated;

comment on table reality.availability_profiles is
'Universal availability profile for a canonical Reality Entity or Reality resource, with one timezone and explicit default-open/default-closed semantics.';
comment on table reality.availability_rules is
'Recurring weekly availability/unavailability windows in the profile timezone, supporting overnight windows and effective date ranges.';
comment on table reality.availability_exceptions is
'One-off local-date availability exceptions such as closures, special openings, maintenance, or holidays.';
comment on table ledger.booking_policies is
'Ledger-scoped declarative booking rules for duration, booking windows, start increments, buffers, approval, and recurrence permission.';
