
create table ledger.recurrence_series (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  stable_key text not null,
  title text not null,
  occurrence_type text not null,
  frequency text not null check (frequency in ('daily','weekly','monthly_nth_weekday')),
  interval_count integer not null default 1 check (interval_count>=1),
  timezone_name text not null,
  effective_start_date date not null,
  effective_end_date date null,
  weekdays smallint[] not null default '{}'::smallint[],
  month_ordinals smallint[] not null default '{}'::smallint[],
  all_day boolean not null default false,
  local_start_time time null,
  local_end_time time null,
  series_state text not null default 'active' check (series_state in ('active','paused','retired')),
  external_uid text null,
  sequence integer not null default 0 check (sequence>=0),
  rrule_text text null,
  template_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(template_payload)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_by_seat_id uuid null references ledger.seats(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(stable_key)<>''),
  check (btrim(title)<>''),
  check (btrim(occurrence_type)<>''),
  check (effective_end_date is null or effective_end_date>=effective_start_date),
  check (weekdays <@ array[0,1,2,3,4,5,6]::smallint[]),
  check (month_ordinals <@ array[-1,1,2,3,4,5]::smallint[]),
  check (
    (frequency='daily' and cardinality(weekdays)=0 and cardinality(month_ordinals)=0)
    or
    (frequency='weekly' and cardinality(weekdays)>0 and cardinality(month_ordinals)=0)
    or
    (frequency='monthly_nth_weekday' and cardinality(weekdays)>0 and cardinality(month_ordinals)>0)
  ),
  check (
    (all_day and local_start_time is null and local_end_time is null)
    or
    (not all_day and local_start_time is not null)
  ),
  unique(ledger_id,stable_key)
);
create index recurrence_series_ledger_state_idx on ledger.recurrence_series(ledger_id,series_state,effective_start_date,effective_end_date);
alter table ledger.recurrence_series enable row level security;
create trigger recurrence_series_set_updated_at before update on ledger.recurrence_series
for each row execute function atlas.set_updated_at();

create table ledger.recurrence_exceptions (
  id uuid primary key default gen_random_uuid(),
  recurrence_series_id uuid not null references ledger.recurrence_series(id) on delete cascade,
  source_local_date date not null,
  exception_action text not null check (exception_action in ('skip','override','move')),
  replacement_date date null,
  override_start_time time null,
  override_end_time time null,
  reason text null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  exception_state text not null default 'active' check (exception_state in ('active','retired')),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_by_seat_id uuid null references ledger.seats(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (exception_action='move' and replacement_date is not null)
    or (exception_action<>'move' and replacement_date is null)
  ),
  unique(recurrence_series_id,source_local_date)
);
create index recurrence_exceptions_series_state_idx on ledger.recurrence_exceptions(recurrence_series_id,exception_state,source_local_date);
alter table ledger.recurrence_exceptions enable row level security;
create trigger recurrence_exceptions_set_updated_at before update on ledger.recurrence_exceptions
for each row execute function atlas.set_updated_at();

create table ledger.recurrence_instances (
  id uuid primary key default gen_random_uuid(),
  recurrence_series_id uuid not null references ledger.recurrence_series(id) on delete cascade,
  source_local_date date not null,
  local_date date not null,
  expected_start_at timestamptz not null,
  expected_end_at timestamptz null,
  schedule_state text not null default 'expected'
    check (schedule_state in ('expected','skipped','overridden','moved','retired')),
  exception_id uuid null references ledger.recurrence_exceptions(id) on delete set null,
  occurrence_id uuid null references local_intel.occurrences(id) on delete restrict,
  realization_state text not null default 'unmaterialized'
    check (realization_state in ('unmaterialized','materialized','cancelled','conflict')),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(recurrence_series_id,source_local_date)
);
create index recurrence_instances_series_date_idx on ledger.recurrence_instances(recurrence_series_id,local_date,schedule_state);
create index recurrence_instances_occurrence_idx on ledger.recurrence_instances(occurrence_id) where occurrence_id is not null;
alter table ledger.recurrence_instances enable row level security;
create trigger recurrence_instances_set_updated_at before update on ledger.recurrence_instances
for each row execute function atlas.set_updated_at();

create or replace function ledger.guard_recurrence_series_v1()
returns trigger language plpgsql set search_path='' as $$
declare v_seat_ledger uuid; v_seat_state text;
begin
  if not exists(select 1 from ledger.ledgers l where l.id=new.ledger_id and l.ledger_state='active') then
    raise exception 'Recurrence series requires an active Ledger.' using errcode='23514';
  end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=new.timezone_name) then
    raise exception 'Unknown recurrence timezone: %',new.timezone_name using errcode='22023';
  end if;
  if new.created_by_seat_id is not null then
    select s.ledger_id,s.seat_state into v_seat_ledger,v_seat_state
    from ledger.seats s where s.id=new.created_by_seat_id;
    if v_seat_ledger is null or v_seat_ledger<>new.ledger_id or v_seat_state<>'active' then
      raise exception 'Recurrence author Seat must be active in the same Ledger.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger recurrence_series_guard before insert or update on ledger.recurrence_series
for each row execute function ledger.guard_recurrence_series_v1();

create or replace function ledger.guard_recurrence_exception_v1()
returns trigger language plpgsql set search_path='' as $$
declare v_ledger uuid; v_seat_ledger uuid; v_seat_state text;
begin
  select s.ledger_id into v_ledger from ledger.recurrence_series s where s.id=new.recurrence_series_id;
  if v_ledger is null then raise exception 'Recurrence series not found.' using errcode='P0002'; end if;
  if new.created_by_seat_id is not null then
    select s.ledger_id,s.seat_state into v_seat_ledger,v_seat_state
    from ledger.seats s where s.id=new.created_by_seat_id;
    if v_seat_ledger is null or v_seat_ledger<>v_ledger or v_seat_state<>'active' then
      raise exception 'Recurrence exception author Seat must be active in the same Ledger.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger recurrence_exceptions_guard before insert or update on ledger.recurrence_exceptions
for each row execute function ledger.guard_recurrence_exception_v1();

create or replace function ledger.upsert_recurrence_series_service_v1(
  p_ledger_id uuid,p_stable_key text,p_title text,p_occurrence_type text,p_frequency text,
  p_interval_count integer,p_timezone_name text,p_effective_start_date date,p_effective_end_date date default null,
  p_weekdays smallint[] default '{}'::smallint[],p_month_ordinals smallint[] default '{}'::smallint[],
  p_all_day boolean default false,p_local_start_time time default null,p_local_end_time time default null,
  p_series_state text default 'active',p_external_uid text default null,p_rrule_text text default null,
  p_template_payload jsonb default '{}'::jsonb,p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,p_created_by_seat_id uuid default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_series ledger.recurrence_series%rowtype; v_existing uuid;
begin
  select id into v_existing from ledger.recurrence_series
  where ledger_id=p_ledger_id and stable_key=btrim(p_stable_key);

  insert into ledger.recurrence_series(
    ledger_id,stable_key,title,occurrence_type,frequency,interval_count,timezone_name,
    effective_start_date,effective_end_date,weekdays,month_ordinals,all_day,
    local_start_time,local_end_time,series_state,external_uid,rrule_text,template_payload,
    metadata,provenance,created_by_seat_id
  ) values(
    p_ledger_id,btrim(p_stable_key),btrim(p_title),btrim(p_occurrence_type),p_frequency,p_interval_count,
    p_timezone_name,p_effective_start_date,p_effective_end_date,coalesce(p_weekdays,'{}'::smallint[]),
    coalesce(p_month_ordinals,'{}'::smallint[]),p_all_day,p_local_start_time,p_local_end_time,
    p_series_state,nullif(btrim(p_external_uid),''),nullif(btrim(p_rrule_text),''),
    coalesce(p_template_payload,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb),p_created_by_seat_id
  )
  on conflict(ledger_id,stable_key) do update
  set title=excluded.title,occurrence_type=excluded.occurrence_type,frequency=excluded.frequency,
      interval_count=excluded.interval_count,timezone_name=excluded.timezone_name,
      effective_start_date=excluded.effective_start_date,effective_end_date=excluded.effective_end_date,
      weekdays=excluded.weekdays,month_ordinals=excluded.month_ordinals,all_day=excluded.all_day,
      local_start_time=excluded.local_start_time,local_end_time=excluded.local_end_time,
      series_state=excluded.series_state,
      external_uid=coalesce(excluded.external_uid,ledger.recurrence_series.external_uid),
      sequence=ledger.recurrence_series.sequence+1,rrule_text=excluded.rrule_text,
      template_payload=excluded.template_payload,metadata=ledger.recurrence_series.metadata||excluded.metadata,
      provenance=ledger.recurrence_series.provenance||excluded.provenance,
      created_by_seat_id=coalesce(excluded.created_by_seat_id,ledger.recurrence_series.created_by_seat_id),
      updated_at=now()
  returning * into v_series;

  return jsonb_build_object(
    'contractVersion','ledger_recurrence_series_v1','seriesId',v_series.id,'ledgerId',v_series.ledger_id,
    'stableKey',v_series.stable_key,'frequency',v_series.frequency,'timezoneName',v_series.timezone_name,
    'seriesState',v_series.series_state,'sequence',v_series.sequence,'created',v_existing is null
  );
end;
$$;

create or replace function ledger.set_recurrence_exception_service_v1(
  p_recurrence_series_id uuid,p_source_local_date date,p_exception_action text,p_replacement_date date default null,
  p_override_start_time time default null,p_override_end_time time default null,p_reason text default null,
  p_payload jsonb default '{}'::jsonb,p_exception_state text default 'active',
  p_provenance jsonb default '{}'::jsonb,p_created_by_seat_id uuid default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_exception ledger.recurrence_exceptions%rowtype;
begin
  if p_exception_action not in ('skip','override','move') then
    raise exception 'Invalid recurrence exception action.' using errcode='22023';
  end if;
  if p_exception_action='move' and p_replacement_date is null then
    raise exception 'Move exception requires replacement date.' using errcode='22023';
  end if;
  if p_exception_action<>'move' and p_replacement_date is not null then
    raise exception 'Replacement date is only valid for move exceptions.' using errcode='22023';
  end if;

  insert into ledger.recurrence_exceptions(
    recurrence_series_id,source_local_date,exception_action,replacement_date,
    override_start_time,override_end_time,reason,payload,exception_state,provenance,created_by_seat_id
  ) values(
    p_recurrence_series_id,p_source_local_date,p_exception_action,p_replacement_date,
    p_override_start_time,p_override_end_time,p_reason,coalesce(p_payload,'{}'::jsonb),
    p_exception_state,coalesce(p_provenance,'{}'::jsonb),p_created_by_seat_id
  )
  on conflict(recurrence_series_id,source_local_date) do update
  set exception_action=excluded.exception_action,replacement_date=excluded.replacement_date,
      override_start_time=excluded.override_start_time,override_end_time=excluded.override_end_time,
      reason=excluded.reason,payload=excluded.payload,exception_state=excluded.exception_state,
      provenance=ledger.recurrence_exceptions.provenance||excluded.provenance,
      created_by_seat_id=coalesce(excluded.created_by_seat_id,ledger.recurrence_exceptions.created_by_seat_id),
      updated_at=now()
  returning * into v_exception;

  return jsonb_build_object(
    'contractVersion','ledger_recurrence_exception_v1','exceptionId',v_exception.id,
    'seriesId',v_exception.recurrence_series_id,'sourceLocalDate',v_exception.source_local_date,
    'exceptionAction',v_exception.exception_action,'exceptionState',v_exception.exception_state
  );
end;
$$;

create or replace function ledger.refresh_recurrence_instances_service_v1(
  p_recurrence_series_id uuid,p_start_date date,p_end_date date
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_series ledger.recurrence_series%rowtype; v_date date; v_match boolean;
  v_day_ordinal integer; v_months_since integer; v_weeks_since integer; v_days_since integer;
  v_exception ledger.recurrence_exceptions%rowtype; v_local_date date; v_start_time time; v_end_time time;
  v_start_at timestamptz; v_end_at timestamptz; v_schedule_state text; v_count integer:=0;
  v_effective_start date; v_effective_end date;
begin
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'Valid recurrence refresh date range is required.' using errcode='22023';
  end if;
  if p_end_date-p_start_date>3660 then
    raise exception 'Recurrence refresh range may not exceed 3660 days.' using errcode='22023';
  end if;

  select * into v_series from ledger.recurrence_series s where s.id=p_recurrence_series_id;
  if v_series.id is null then raise exception 'Recurrence series not found.' using errcode='P0002'; end if;

  v_effective_start:=greatest(p_start_date,v_series.effective_start_date);
  v_effective_end:=least(p_end_date,coalesce(v_series.effective_end_date,p_end_date));
  if v_effective_end<v_effective_start then
    return jsonb_build_object('contractVersion','ledger_recurrence_refresh_v1','seriesId',v_series.id,'generatedCount',0);
  end if;

  update ledger.recurrence_instances i
  set schedule_state='retired',updated_at=now()
  where i.recurrence_series_id=v_series.id
    and i.source_local_date between v_effective_start and v_effective_end
    and i.realization_state<>'materialized';

  for v_date in select gs::date from generate_series(v_effective_start,v_effective_end,interval '1 day') gs
  loop
    v_match:=false;
    if v_series.frequency='daily' then
      v_days_since:=v_date-v_series.effective_start_date;
      v_match:=v_days_since>=0 and mod(v_days_since,v_series.interval_count)=0;
    elsif v_series.frequency='weekly' then
      v_weeks_since:=floor((v_date-v_series.effective_start_date)::numeric/7)::integer;
      v_match:=extract(dow from v_date)::smallint=any(v_series.weekdays)
        and v_weeks_since>=0 and mod(v_weeks_since,v_series.interval_count)=0;
    elsif v_series.frequency='monthly_nth_weekday' then
      v_months_since:=(extract(year from v_date)::integer-extract(year from v_series.effective_start_date)::integer)*12
        + extract(month from v_date)::integer-extract(month from v_series.effective_start_date)::integer;
      v_day_ordinal:=((extract(day from v_date)::integer-1)/7)+1;
      v_match:=extract(dow from v_date)::smallint=any(v_series.weekdays)
        and v_months_since>=0 and mod(v_months_since,v_series.interval_count)=0
        and (v_day_ordinal::smallint=any(v_series.month_ordinals)
          or ((-1)::smallint=any(v_series.month_ordinals)
              and extract(month from (v_date+7))<>extract(month from v_date)));
    end if;
    if not v_match then continue; end if;

    select * into v_exception from ledger.recurrence_exceptions e
    where e.recurrence_series_id=v_series.id and e.source_local_date=v_date and e.exception_state='active';

    v_local_date:=case when v_exception.id is not null and v_exception.exception_action='move'
      then v_exception.replacement_date else v_date end;

    if v_series.all_day then
      v_start_at:=(v_local_date::timestamp) at time zone v_series.timezone_name;
      v_end_at:=((v_local_date+1)::timestamp) at time zone v_series.timezone_name;
    else
      v_start_time:=coalesce(v_exception.override_start_time,v_series.local_start_time);
      v_end_time:=coalesce(v_exception.override_end_time,v_series.local_end_time);
      v_start_at:=(v_local_date+v_start_time) at time zone v_series.timezone_name;
      if v_end_time is null then v_end_at:=null;
      elsif v_end_time>v_start_time then v_end_at:=(v_local_date+v_end_time) at time zone v_series.timezone_name;
      else v_end_at:=((v_local_date+1)+v_end_time) at time zone v_series.timezone_name;
      end if;
    end if;

    v_schedule_state:=case
      when v_exception.id is null then 'expected'
      when v_exception.exception_action='skip' then 'skipped'
      when v_exception.exception_action='override' then 'overridden'
      when v_exception.exception_action='move' then 'moved'
      else 'expected' end;

    insert into ledger.recurrence_instances(
      recurrence_series_id,source_local_date,local_date,expected_start_at,expected_end_at,
      schedule_state,exception_id,payload
    ) values(
      v_series.id,v_date,v_local_date,v_start_at,v_end_at,v_schedule_state,v_exception.id,
      jsonb_strip_nulls(jsonb_build_object(
        'seriesStableKey',v_series.stable_key,'exceptionAction',v_exception.exception_action,
        'exceptionReason',v_exception.reason,'timezoneName',v_series.timezone_name,'sequence',v_series.sequence
      ))
    )
    on conflict(recurrence_series_id,source_local_date) do update
    set local_date=excluded.local_date,expected_start_at=excluded.expected_start_at,
        expected_end_at=excluded.expected_end_at,
        schedule_state=case when ledger.recurrence_instances.realization_state='materialized'
          then ledger.recurrence_instances.schedule_state else excluded.schedule_state end,
        exception_id=excluded.exception_id,payload=ledger.recurrence_instances.payload||excluded.payload,updated_at=now();
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'contractVersion','ledger_recurrence_refresh_v1','seriesId',v_series.id,'generatedCount',v_count,
    'rangeStart',v_effective_start,'rangeEnd',v_effective_end
  );
end;
$$;

create or replace function ledger.materialize_recurrence_instance_service_v1(
  p_recurrence_instance_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_instance ledger.recurrence_instances%rowtype; v_series ledger.recurrence_series%rowtype;
  v_subject uuid; v_occurrence local_intel.occurrences%rowtype; v_stable_key text;
begin
  select * into v_instance from ledger.recurrence_instances i where i.id=p_recurrence_instance_id for update;
  if v_instance.id is null then raise exception 'Recurrence instance not found.' using errcode='P0002'; end if;
  if v_instance.schedule_state in ('skipped','retired') then
    raise exception 'Skipped or retired recurrence instance cannot be materialized.' using errcode='23514';
  end if;

  select * into v_series from ledger.recurrence_series s where s.id=v_instance.recurrence_series_id;
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=v_series.ledger_id and l.ledger_state='active';

  if v_instance.occurrence_id is not null then
    select * into v_occurrence from local_intel.occurrences o where o.id=v_instance.occurrence_id;
  else
    v_stable_key:='ledger-recurrence:'||v_series.id::text||':'||v_instance.source_local_date::text;
    insert into local_intel.occurrences(
      stable_key,entity_id,title,occurrence_type,start_at,end_at,status,metadata,last_verified_at
    ) values(
      v_stable_key,v_subject,v_series.title,v_series.occurrence_type,
      v_instance.expected_start_at,v_instance.expected_end_at,'scheduled',
      v_series.template_payload||jsonb_build_object(
        'recurrenceSeriesId',v_series.id,'recurrenceInstanceId',v_instance.id,
        'sourceLocalDate',v_instance.source_local_date,'localDate',v_instance.local_date,
        'scheduleState',v_instance.schedule_state,'timezoneName',v_series.timezone_name,
        'externalUid',v_series.external_uid,'sequence',v_series.sequence
      ),now()
    )
    on conflict(stable_key) do update
    set title=excluded.title,occurrence_type=excluded.occurrence_type,start_at=excluded.start_at,
        end_at=excluded.end_at,status=excluded.status,
        metadata=local_intel.occurrences.metadata||excluded.metadata,last_verified_at=now(),updated_at=now()
    returning * into v_occurrence;

    update ledger.recurrence_instances
    set occurrence_id=v_occurrence.id,realization_state='materialized',updated_at=now()
    where id=v_instance.id;

    perform ledger.bind_occurrence_to_calendar_service_v1(
      v_series.ledger_id,v_occurrence.id,array['recurrence_instance']::text[],
      jsonb_build_object('recurrenceSeriesId',v_series.id,'recurrenceInstanceId',v_instance.id),
      jsonb_build_object('source','ledger_recurrence_materialization_v1')
    );
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_recurrence_materialization_v1','seriesId',v_series.id,
    'instanceId',v_instance.id,'occurrenceId',v_occurrence.id,
    'startAt',v_occurrence.start_at,'endAt',v_occurrence.end_at
  );
end;
$$;

create or replace function ledger.materialize_recurrence_range_service_v1(
  p_recurrence_series_id uuid,p_start_date date,p_end_date date
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_instance record; v_results jsonb:='[]'::jsonb; v_refresh jsonb;
begin
  v_refresh:=ledger.refresh_recurrence_instances_service_v1(p_recurrence_series_id,p_start_date,p_end_date);
  for v_instance in
    select i.id from ledger.recurrence_instances i
    where i.recurrence_series_id=p_recurrence_series_id
      and i.local_date between p_start_date and p_end_date
      and i.schedule_state in ('expected','overridden','moved')
    order by i.local_date,i.expected_start_at,i.id
  loop
    v_results:=v_results||jsonb_build_array(ledger.materialize_recurrence_instance_service_v1(v_instance.id));
  end loop;
  return jsonb_build_object(
    'contractVersion','ledger_recurrence_range_materialization_v1','refresh',v_refresh,'materialized',v_results
  );
end;
$$;

create or replace function ledger.recurrence_schedule_service_v1(
  p_ledger_id uuid,p_start_date date,p_end_date date
) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'contractVersion','ledger_recurrence_schedule_v1','ledgerId',p_ledger_id,
    'rangeStart',p_start_date,'rangeEnd',p_end_date,
    'instances',coalesce(jsonb_agg(
      jsonb_build_object(
        'recurrenceInstanceId',i.id,'seriesId',s.id,'seriesStableKey',s.stable_key,'seriesTitle',s.title,
        'sourceLocalDate',i.source_local_date,'localDate',i.local_date,
        'expectedStartAt',i.expected_start_at,'expectedEndAt',i.expected_end_at,
        'scheduleState',i.schedule_state,'realizationState',i.realization_state,'occurrenceId',i.occurrence_id,
        'exception',case when e.id is null then null else jsonb_build_object(
          'exceptionId',e.id,'action',e.exception_action,'reason',e.reason,'replacementDate',e.replacement_date
        ) end,
        'canonicalOccurrence',case when o.id is null then null else jsonb_build_object(
          'occurrenceId',o.id,'title',o.title,'status',o.status,'startAt',o.start_at,'endAt',o.end_at
        ) end
      ) order by i.local_date,i.expected_start_at,s.stable_key
    ) filter(where i.id is not null),'[]'::jsonb)
  )
  from ledger.recurrence_instances i
  join ledger.recurrence_series s on s.id=i.recurrence_series_id
  left join ledger.recurrence_exceptions e on e.id=i.exception_id
  left join local_intel.occurrences o on o.id=i.occurrence_id
  where s.ledger_id=p_ledger_id
    and i.local_date between p_start_date and p_end_date
    and i.schedule_state<>'retired';
$$;

create or replace function atlas.upsert_ledger_recurrence_series_self_api_v1(
  p_ledger_id uuid,p_stable_key text,p_title text,p_occurrence_type text,p_frequency text,
  p_interval_count integer,p_timezone_name text,p_effective_start_date date,p_effective_end_date date default null,
  p_weekdays smallint[] default '{}'::smallint[],p_month_ordinals smallint[] default '{}'::smallint[],
  p_all_day boolean default false,p_local_start_time time default null,p_local_end_time time default null,
  p_series_state text default 'active',p_external_uid text default null,p_rrule_text text default null,
  p_template_payload jsonb default '{}'::jsonb,p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid; v_seat uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'recurrence.write');
  v_person:=atlas.current_person_id_v1();
  select s.id into v_seat from ledger.seats s
  where s.ledger_id=p_ledger_id and s.person_entity_id=v_person and s.seat_state='active'
  order by s.began_at desc,s.id limit 1;
  if v_seat is null then raise exception 'Active Ledger Seat required.' using errcode='42501'; end if;

  return ledger.upsert_recurrence_series_service_v1(
    p_ledger_id,p_stable_key,p_title,p_occurrence_type,p_frequency,p_interval_count,p_timezone_name,
    p_effective_start_date,p_effective_end_date,p_weekdays,p_month_ordinals,p_all_day,
    p_local_start_time,p_local_end_time,p_series_state,p_external_uid,p_rrule_text,
    p_template_payload,p_metadata,
    jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),
    v_seat
  );
end;
$$;

create or replace function atlas.set_ledger_recurrence_exception_self_api_v1(
  p_ledger_id uuid,p_recurrence_series_id uuid,p_source_local_date date,p_exception_action text,
  p_replacement_date date default null,p_override_start_time time default null,p_override_end_time time default null,
  p_reason text default null,p_payload jsonb default '{}'::jsonb,p_exception_state text default 'active'
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_relation uuid; v_seat uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'recurrence.write');
  v_person:=atlas.current_person_id_v1();
  if not exists(select 1 from ledger.recurrence_series s where s.id=p_recurrence_series_id and s.ledger_id=p_ledger_id) then
    raise exception 'Recurrence series is outside Ledger.' using errcode='42501';
  end if;
  select s.id into v_seat from ledger.seats s
  where s.ledger_id=p_ledger_id and s.person_entity_id=v_person and s.seat_state='active'
  order by s.began_at desc,s.id limit 1;
  if v_seat is null then raise exception 'Active Ledger Seat required.' using errcode='42501'; end if;

  return ledger.set_recurrence_exception_service_v1(
    p_recurrence_series_id,p_source_local_date,p_exception_action,p_replacement_date,
    p_override_start_time,p_override_end_time,p_reason,p_payload,p_exception_state,
    jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),v_seat
  );
end;
$$;

create or replace function atlas.refresh_ledger_recurrence_self_api_v1(
  p_ledger_id uuid,p_recurrence_series_id uuid,p_start_date date,p_end_date date
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'recurrence.write');
  if not exists(select 1 from ledger.recurrence_series s where s.id=p_recurrence_series_id and s.ledger_id=p_ledger_id) then
    raise exception 'Recurrence series is outside Ledger.' using errcode='42501';
  end if;
  return ledger.refresh_recurrence_instances_service_v1(p_recurrence_series_id,p_start_date,p_end_date);
end;
$$;

create or replace function atlas.materialize_ledger_recurrence_range_self_api_v1(
  p_ledger_id uuid,p_recurrence_series_id uuid,p_start_date date,p_end_date date
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'recurrence.write');
  if not exists(select 1 from ledger.recurrence_series s where s.id=p_recurrence_series_id and s.ledger_id=p_ledger_id) then
    raise exception 'Recurrence series is outside Ledger.' using errcode='42501';
  end if;
  return ledger.materialize_recurrence_range_service_v1(p_recurrence_series_id,p_start_date,p_end_date);
end;
$$;

create or replace function atlas.ledger_recurrence_schedule_self_api_v1(
  p_ledger_id uuid,p_start_date date,p_end_date date
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'recurrence.read');
  return ledger.recurrence_schedule_service_v1(p_ledger_id,p_start_date,p_end_date);
end;
$$;

revoke all on ledger.recurrence_series,ledger.recurrence_exceptions,ledger.recurrence_instances
  from public,anon,authenticated;
revoke execute on function ledger.upsert_recurrence_series_service_v1(uuid,text,text,text,text,integer,text,date,date,smallint[],smallint[],boolean,time,time,text,text,text,jsonb,jsonb,jsonb,uuid)
  from public,anon,authenticated;
revoke execute on function ledger.set_recurrence_exception_service_v1(uuid,date,text,date,time,time,text,jsonb,text,jsonb,uuid)
  from public,anon,authenticated;
revoke execute on function ledger.refresh_recurrence_instances_service_v1(uuid,date,date)
  from public,anon,authenticated;
revoke execute on function ledger.materialize_recurrence_instance_service_v1(uuid)
  from public,anon,authenticated;
revoke execute on function ledger.materialize_recurrence_range_service_v1(uuid,date,date)
  from public,anon,authenticated;
revoke execute on function ledger.recurrence_schedule_service_v1(uuid,date,date)
  from public,anon,authenticated;

revoke execute on function atlas.upsert_ledger_recurrence_series_self_api_v1(uuid,text,text,text,text,integer,text,date,date,smallint[],smallint[],boolean,time,time,text,text,text,jsonb,jsonb)
  from public,anon;
revoke execute on function atlas.set_ledger_recurrence_exception_self_api_v1(uuid,uuid,date,text,date,time,time,text,jsonb,text)
  from public,anon;
revoke execute on function atlas.refresh_ledger_recurrence_self_api_v1(uuid,uuid,date,date)
  from public,anon;
revoke execute on function atlas.materialize_ledger_recurrence_range_self_api_v1(uuid,uuid,date,date)
  from public,anon;
revoke execute on function atlas.ledger_recurrence_schedule_self_api_v1(uuid,date,date)
  from public,anon;

grant execute on function atlas.upsert_ledger_recurrence_series_self_api_v1(uuid,text,text,text,text,integer,text,date,date,smallint[],smallint[],boolean,time,time,text,text,text,jsonb,jsonb)
  to authenticated;
grant execute on function atlas.set_ledger_recurrence_exception_self_api_v1(uuid,uuid,date,text,date,time,time,text,jsonb,text)
  to authenticated;
grant execute on function atlas.refresh_ledger_recurrence_self_api_v1(uuid,uuid,date,date)
  to authenticated;
grant execute on function atlas.materialize_ledger_recurrence_range_self_api_v1(uuid,uuid,date,date)
  to authenticated;
grant execute on function atlas.ledger_recurrence_schedule_self_api_v1(uuid,date,date)
  to authenticated;

comment on table ledger.recurrence_series is
'Ledger-native recurrence definition using local wall-clock time and timezone. Promotes recurrence semantics out of legacy Organization/membership architecture.';
comment on table ledger.recurrence_exceptions is
'Series instance exceptions preserving source local date with skip, override, and move semantics.';
comment on table ledger.recurrence_instances is
'Expected or materialized recurrence instances, each anchored to a source local date and optionally realized as one canonical occurrence.';
