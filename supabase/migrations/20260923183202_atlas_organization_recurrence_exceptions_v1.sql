-- Atlas Organization recurrence + exception kernel v1
-- Recurrence describes Organization-private schedule expectation.
-- It never manufactures canonical local_intel occurrence identity.

create table if not exists atlas.organization_recurrence_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  stable_key text not null,
  title text not null,
  frequency text not null,
  interval_count integer not null default 1,
  timezone_name text not null,
  effective_start_date date not null,
  effective_end_date date,
  weekdays smallint[] not null default '{}'::smallint[],
  month_ordinals smallint[] not null default '{}'::smallint[],
  local_start_time time not null,
  local_end_time time,
  rule_state text not null default 'active',
  payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,stable_key),
  unique (organization_id,id),
  constraint organization_recurrence_rules_stable_key_nonblank_v1
    check (btrim(stable_key) <> ''),
  constraint organization_recurrence_rules_title_nonblank_v1
    check (btrim(title) <> ''),
  constraint organization_recurrence_rules_frequency_v1
    check (frequency in ('weekly','monthly_nth_weekday')),
  constraint organization_recurrence_rules_interval_v1
    check (interval_count >= 1),
  constraint organization_recurrence_rules_date_order_v1
    check (effective_end_date is null or effective_end_date >= effective_start_date),
  constraint organization_recurrence_rules_weekdays_v1
    check (weekdays <@ array[0,1,2,3,4,5,6]::smallint[] and cardinality(weekdays) > 0),
  constraint organization_recurrence_rules_month_ordinals_v1
    check (
      month_ordinals <@ array[-1,1,2,3,4,5]::smallint[]
      and (
        (frequency='weekly' and cardinality(month_ordinals)=0)
        or
        (frequency='monthly_nth_weekday' and cardinality(month_ordinals)>0)
      )
    ),
  constraint organization_recurrence_rules_state_v1
    check (rule_state in ('active','paused','retired')),
  constraint organization_recurrence_rules_payload_v1
    check (jsonb_typeof(payload)='object'),
  constraint organization_recurrence_rules_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table atlas.organization_recurrence_rules is
  'Organization-private recurrence law. A rule predicts schedule dates/times but is not canonical event identity and never creates local_intel.occurrences by itself.';

create table if not exists atlas.organization_recurrence_exceptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  recurrence_rule_id uuid not null,
  source_local_date date not null,
  exception_action text not null,
  replacement_date date,
  override_start_time time,
  override_end_time time,
  temporal_binding_id uuid,
  reason text,
  payload jsonb not null default '{}'::jsonb,
  exception_state text not null default 'active',
  created_by_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,recurrence_rule_id,source_local_date),
  constraint organization_recurrence_exceptions_rule_org_fk_v1
    foreign key (organization_id,recurrence_rule_id)
    references atlas.organization_recurrence_rules(organization_id,id)
    on delete cascade,
  constraint organization_recurrence_exceptions_temporal_org_fk_v1
    foreign key (organization_id,temporal_binding_id)
    references atlas.organization_temporal_bindings(organization_id,id)
    on delete restrict,
  constraint organization_recurrence_exceptions_action_v1
    check (exception_action in ('skip','override','move')),
  constraint organization_recurrence_exceptions_move_shape_v1
    check (
      (exception_action='move' and replacement_date is not null)
      or
      (exception_action<>'move' and replacement_date is null)
    ),
  constraint organization_recurrence_exceptions_state_v1
    check (exception_state in ('active','retired')),
  constraint organization_recurrence_exceptions_payload_v1
    check (jsonb_typeof(payload)='object')
);

comment on table atlas.organization_recurrence_exceptions is
  'One Organization-private exception to one nominal recurrence date. May link to canonical temporal meaning such as a holiday.';

create table if not exists atlas.organization_recurrence_instances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  recurrence_rule_id uuid not null,
  source_local_date date not null,
  local_date date not null,
  expected_start_at timestamptz not null,
  expected_end_at timestamptz,
  schedule_state text not null default 'expected',
  exception_id uuid,
  occurrence_binding_id uuid,
  realization_state text not null default 'unmaterialized',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,recurrence_rule_id,source_local_date),
  constraint organization_recurrence_instances_rule_org_fk_v1
    foreign key (organization_id,recurrence_rule_id)
    references atlas.organization_recurrence_rules(organization_id,id)
    on delete cascade,
  constraint organization_recurrence_instances_exception_fk_v1
    foreign key (exception_id)
    references atlas.organization_recurrence_exceptions(id)
    on delete set null,
  constraint organization_recurrence_instances_occurrence_org_fk_v1
    foreign key (organization_id,occurrence_binding_id)
    references atlas.organization_occurrence_bindings(organization_id,id)
    on delete restrict,
  constraint organization_recurrence_instances_schedule_state_v1
    check (schedule_state in ('expected','skipped','overridden','moved','retired')),
  constraint organization_recurrence_instances_realization_state_v1
    check (realization_state in ('unmaterialized','materialized','cancelled')),
  constraint organization_recurrence_instances_payload_v1
    check (jsonb_typeof(payload)='object')
);

comment on table atlas.organization_recurrence_instances is
  'Resolved Organization schedule expectation. source_local_date is the nominal rule date; local_date is effective after exceptions. Optional occurrence_binding_id links the expectation to real canonical occurrence identity.';

create index if not exists organization_recurrence_instances_date_idx_v1
  on atlas.organization_recurrence_instances(organization_id,local_date,schedule_state);

create index if not exists organization_recurrence_exceptions_temporal_idx_v1
  on atlas.organization_recurrence_exceptions(organization_id,temporal_binding_id)
  where temporal_binding_id is not null;

alter table atlas.organization_recurrence_rules enable row level security;
alter table atlas.organization_recurrence_exceptions enable row level security;
alter table atlas.organization_recurrence_instances enable row level security;

revoke all on table atlas.organization_recurrence_rules from public,anon,authenticated;
revoke all on table atlas.organization_recurrence_exceptions from public,anon,authenticated;
revoke all on table atlas.organization_recurrence_instances from public,anon,authenticated;

grant select,insert,update,delete on table atlas.organization_recurrence_rules to service_role;
grant select,insert,update,delete on table atlas.organization_recurrence_exceptions to service_role;
grant select,insert,update,delete on table atlas.organization_recurrence_instances to service_role;

create or replace function atlas.set_recurrence_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','atlas'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists organization_recurrence_rules_updated_at_v1
  on atlas.organization_recurrence_rules;
create trigger organization_recurrence_rules_updated_at_v1
before update on atlas.organization_recurrence_rules
for each row execute function atlas.set_recurrence_updated_at_v1();

drop trigger if exists organization_recurrence_exceptions_updated_at_v1
  on atlas.organization_recurrence_exceptions;
create trigger organization_recurrence_exceptions_updated_at_v1
before update on atlas.organization_recurrence_exceptions
for each row execute function atlas.set_recurrence_updated_at_v1();

drop trigger if exists organization_recurrence_instances_updated_at_v1
  on atlas.organization_recurrence_instances;
create trigger organization_recurrence_instances_updated_at_v1
before update on atlas.organization_recurrence_instances
for each row execute function atlas.set_recurrence_updated_at_v1();

create or replace function atlas.refresh_organization_recurrence_instances_service_v1(
  p_organization_id uuid,
  p_recurrence_rule_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_rule atlas.organization_recurrence_rules%rowtype;
  v_date date;
  v_match boolean;
  v_day_ordinal integer;
  v_months_since integer;
  v_weeks_since integer;
  v_exception atlas.organization_recurrence_exceptions%rowtype;
  v_local_date date;
  v_start_time time;
  v_end_time time;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_schedule_state text;
  v_count integer := 0;
  v_effective_start date;
  v_effective_end date;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid recurrence refresh date range is required.' using errcode='22023';
  end if;

  if p_end_date - p_start_date > 3660 then
    raise exception 'Recurrence refresh range may not exceed 3660 days.' using errcode='22023';
  end if;

  select *
  into v_rule
  from atlas.organization_recurrence_rules r
  where r.id=p_recurrence_rule_id
    and r.organization_id=p_organization_id;

  if v_rule.id is null then
    raise exception 'Recurrence rule is outside organization or missing.' using errcode='42501';
  end if;

  v_effective_start:=greatest(p_start_date,v_rule.effective_start_date);
  v_effective_end:=least(
    p_end_date,
    coalesce(v_rule.effective_end_date,p_end_date)
  );

  if v_effective_end < v_effective_start then
    return jsonb_build_object(
      'contractVersion','recurrence_refresh_v1',
      'ruleId',v_rule.id,
      'generatedCount',0
    );
  end if;

  update atlas.organization_recurrence_instances i
  set schedule_state='retired',
      updated_at=now()
  where i.organization_id=p_organization_id
    and i.recurrence_rule_id=v_rule.id
    and i.source_local_date between v_effective_start and v_effective_end;

  for v_date in
    select gs::date
    from generate_series(v_effective_start,v_effective_end,interval '1 day') gs
  loop
    v_match:=false;

    if v_rule.frequency='weekly' then
      v_weeks_since:=floor((v_date-v_rule.effective_start_date)::numeric/7)::integer;
      v_match :=
        extract(dow from v_date)::smallint = any(v_rule.weekdays)
        and v_weeks_since >= 0
        and mod(v_weeks_since,v_rule.interval_count)=0;

    elsif v_rule.frequency='monthly_nth_weekday' then
      v_months_since :=
        (extract(year from v_date)::integer-extract(year from v_rule.effective_start_date)::integer)*12
        + extract(month from v_date)::integer
        - extract(month from v_rule.effective_start_date)::integer;

      v_day_ordinal:=((extract(day from v_date)::integer-1)/7)+1;

      v_match :=
        extract(dow from v_date)::smallint = any(v_rule.weekdays)
        and v_months_since >= 0
        and mod(v_months_since,v_rule.interval_count)=0
        and (
          v_day_ordinal::smallint = any(v_rule.month_ordinals)
          or (
            (-1)::smallint = any(v_rule.month_ordinals)
            and extract(month from (v_date+7)) <> extract(month from v_date)
          )
        );
    end if;

    if not v_match then
      continue;
    end if;

    select *
    into v_exception
    from atlas.organization_recurrence_exceptions e
    where e.organization_id=p_organization_id
      and e.recurrence_rule_id=v_rule.id
      and e.source_local_date=v_date
      and e.exception_state='active';

    v_local_date:=case
      when v_exception.id is not null and v_exception.exception_action='move'
        then v_exception.replacement_date
      else v_date
    end;

    v_start_time:=coalesce(v_exception.override_start_time,v_rule.local_start_time);
    v_end_time:=coalesce(v_exception.override_end_time,v_rule.local_end_time);

    v_start_at := (v_local_date + v_start_time) at time zone v_rule.timezone_name;

    if v_end_time is null then
      v_end_at:=null;
    elsif v_end_time >= v_start_time then
      v_end_at := (v_local_date + v_end_time) at time zone v_rule.timezone_name;
    else
      v_end_at := ((v_local_date+1) + v_end_time) at time zone v_rule.timezone_name;
    end if;

    v_schedule_state:=case
      when v_exception.id is null then 'expected'
      when v_exception.exception_action='skip' then 'skipped'
      when v_exception.exception_action='override' then 'overridden'
      when v_exception.exception_action='move' then 'moved'
      else 'expected'
    end;

    insert into atlas.organization_recurrence_instances(
      organization_id,
      recurrence_rule_id,
      source_local_date,
      local_date,
      expected_start_at,
      expected_end_at,
      schedule_state,
      exception_id,
      payload
    )
    values(
      p_organization_id,
      v_rule.id,
      v_date,
      v_local_date,
      v_start_at,
      v_end_at,
      v_schedule_state,
      v_exception.id,
      jsonb_strip_nulls(jsonb_build_object(
        'ruleStableKey',v_rule.stable_key,
        'exceptionAction',v_exception.exception_action,
        'exceptionReason',v_exception.reason
      ))
    )
    on conflict (organization_id,recurrence_rule_id,source_local_date)
    do update set
      local_date=excluded.local_date,
      expected_start_at=excluded.expected_start_at,
      expected_end_at=excluded.expected_end_at,
      schedule_state=excluded.schedule_state,
      exception_id=excluded.exception_id,
      payload=atlas.organization_recurrence_instances.payload || excluded.payload,
      updated_at=now();

    v_count:=v_count+1;
  end loop;

  return jsonb_build_object(
    'contractVersion','recurrence_refresh_v1',
    'ruleId',v_rule.id,
    'generatedCount',v_count,
    'rangeStart',v_effective_start,
    'rangeEnd',v_effective_end
  );
end
$function$;

create or replace function atlas.set_organization_recurrence_exception_service_v1(
  p_organization_id uuid,
  p_recurrence_rule_id uuid,
  p_source_local_date date,
  p_exception_action text,
  p_replacement_date date default null,
  p_override_start_time time default null,
  p_override_end_time time default null,
  p_temporal_binding_id uuid default null,
  p_reason text default null,
  p_payload jsonb default '{}'::jsonb,
  p_created_by_membership_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_exception atlas.organization_recurrence_exceptions%rowtype;
begin
  if not exists(
    select 1
    from atlas.organization_recurrence_rules r
    where r.id=p_recurrence_rule_id
      and r.organization_id=p_organization_id
  ) then
    raise exception 'Recurrence rule is outside organization or missing.' using errcode='42501';
  end if;

  if p_exception_action not in ('skip','override','move') then
    raise exception 'Invalid recurrence exception action.' using errcode='22023';
  end if;

  if p_exception_action='move' and p_replacement_date is null then
    raise exception 'Move exception requires replacement date.' using errcode='22023';
  end if;

  if p_exception_action<>'move' and p_replacement_date is not null then
    raise exception 'Replacement date is only valid for move exceptions.' using errcode='22023';
  end if;

  if p_temporal_binding_id is not null and not exists(
    select 1
    from atlas.organization_temporal_bindings b
    where b.id=p_temporal_binding_id
      and b.organization_id=p_organization_id
      and b.binding_state='active'
  ) then
    raise exception 'Temporal binding is outside organization or inactive.' using errcode='42501';
  end if;

  if jsonb_typeof(coalesce(p_payload,'{}'::jsonb)) <> 'object' then
    raise exception 'Exception payload must be a JSON object.' using errcode='22023';
  end if;

  if p_created_by_membership_id is not null and not exists(
    select 1
    from atlas.organization_memberships om
    where om.id=p_created_by_membership_id
      and om.organization_id=p_organization_id
  ) then
    raise exception 'Creator membership is outside organization.' using errcode='42501';
  end if;

  insert into atlas.organization_recurrence_exceptions(
    organization_id,
    recurrence_rule_id,
    source_local_date,
    exception_action,
    replacement_date,
    override_start_time,
    override_end_time,
    temporal_binding_id,
    reason,
    payload,
    exception_state,
    created_by_membership_id
  )
  values(
    p_organization_id,
    p_recurrence_rule_id,
    p_source_local_date,
    p_exception_action,
    p_replacement_date,
    p_override_start_time,
    p_override_end_time,
    p_temporal_binding_id,
    p_reason,
    coalesce(p_payload,'{}'::jsonb),
    'active',
    p_created_by_membership_id
  )
  on conflict (organization_id,recurrence_rule_id,source_local_date)
  do update set
    exception_action=excluded.exception_action,
    replacement_date=excluded.replacement_date,
    override_start_time=excluded.override_start_time,
    override_end_time=excluded.override_end_time,
    temporal_binding_id=excluded.temporal_binding_id,
    reason=excluded.reason,
    payload=excluded.payload,
    exception_state='active',
    created_by_membership_id=coalesce(
      excluded.created_by_membership_id,
      atlas.organization_recurrence_exceptions.created_by_membership_id
    ),
    updated_at=now()
  returning * into v_exception;

  return jsonb_build_object(
    'contractVersion','recurrence_exception_v1',
    'exceptionId',v_exception.id,
    'ruleId',v_exception.recurrence_rule_id,
    'sourceLocalDate',v_exception.source_local_date,
    'exceptionAction',v_exception.exception_action,
    'temporalBindingId',v_exception.temporal_binding_id
  );
end
$function$;

create or replace function atlas.attach_occurrence_to_recurrence_instance_service_v1(
  p_organization_id uuid,
  p_recurrence_instance_id uuid,
  p_occurrence_binding_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_instance atlas.organization_recurrence_instances%rowtype;
  v_occurrence_status text;
begin
  select *
  into v_instance
  from atlas.organization_recurrence_instances i
  where i.id=p_recurrence_instance_id
    and i.organization_id=p_organization_id;

  if v_instance.id is null then
    raise exception 'Recurrence instance is outside organization or missing.' using errcode='42501';
  end if;

  select o.status
  into v_occurrence_status
  from atlas.organization_occurrence_bindings b
  join local_intel.occurrences o on o.id=b.occurrence_id
  where b.id=p_occurrence_binding_id
    and b.organization_id=p_organization_id
    and b.binding_state='active';

  if v_occurrence_status is null then
    raise exception 'Occurrence binding is outside organization or inactive.' using errcode='42501';
  end if;

  update atlas.organization_recurrence_instances
  set occurrence_binding_id=p_occurrence_binding_id,
      realization_state=case
        when v_occurrence_status='cancelled' then 'cancelled'
        else 'materialized'
      end,
      updated_at=now()
  where id=v_instance.id
  returning * into v_instance;

  return jsonb_build_object(
    'contractVersion','recurrence_instance_realization_v1',
    'recurrenceInstanceId',v_instance.id,
    'occurrenceBindingId',v_instance.occurrence_binding_id,
    'scheduleState',v_instance.schedule_state,
    'realizationState',v_instance.realization_state
  );
end
$function$;

create or replace function atlas.organization_recurrence_schedule_service_v1(
  p_organization_id uuid,
  p_start_date date,
  p_end_date date
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
  select jsonb_build_object(
    'contractVersion','organization_recurrence_schedule_v1',
    'organizationId',p_organization_id,
    'rangeStart',p_start_date,
    'rangeEnd',p_end_date,
    'instances',coalesce(jsonb_agg(
      jsonb_build_object(
        'recurrenceInstanceId',i.id,
        'ruleId',r.id,
        'ruleStableKey',r.stable_key,
        'ruleTitle',r.title,
        'sourceLocalDate',i.source_local_date,
        'localDate',i.local_date,
        'expectedStartAt',i.expected_start_at,
        'expectedEndAt',i.expected_end_at,
        'scheduleState',i.schedule_state,
        'realizationState',i.realization_state,
        'occurrenceBindingId',i.occurrence_binding_id,
        'exception',case when e.id is null then null else jsonb_build_object(
          'exceptionId',e.id,
          'action',e.exception_action,
          'reason',e.reason,
          'temporalBindingId',e.temporal_binding_id,
          'temporalMarker',case when t.id is null then null else jsonb_build_object(
            'temporalMarkerId',t.id,
            'title',t.title,
            'markerKind',t.marker_kind,
            'startDate',t.start_date,
            'endDate',t.end_date
          ) end
        ) end,
        'canonicalOccurrence',case when o.id is null then null else jsonb_build_object(
          'occurrenceId',o.id,
          'title',o.title,
          'status',o.status,
          'startAt',o.start_at,
          'endAt',o.end_at
        ) end
      )
      order by i.local_date,i.expected_start_at,r.stable_key
    ) filter (where i.id is not null),'[]'::jsonb)
  )
  from atlas.organization_recurrence_instances i
  join atlas.organization_recurrence_rules r
    on r.id=i.recurrence_rule_id
   and r.organization_id=i.organization_id
  left join atlas.organization_recurrence_exceptions e
    on e.id=i.exception_id
  left join atlas.organization_temporal_bindings tb
    on tb.id=e.temporal_binding_id
   and tb.organization_id=e.organization_id
  left join local_intel.temporal_markers t
    on t.id=tb.temporal_marker_id
  left join atlas.organization_occurrence_bindings ob
    on ob.id=i.occurrence_binding_id
   and ob.organization_id=i.organization_id
  left join local_intel.occurrences o
    on o.id=ob.occurrence_id
  where i.organization_id=p_organization_id
    and i.local_date between p_start_date and p_end_date
    and i.schedule_state<>'retired';
$function$;

revoke all on function atlas.refresh_organization_recurrence_instances_service_v1(uuid,uuid,date,date)
  from public,anon,authenticated;
grant execute on function atlas.refresh_organization_recurrence_instances_service_v1(uuid,uuid,date,date)
  to service_role;

revoke all on function atlas.set_organization_recurrence_exception_service_v1(uuid,uuid,date,text,date,time,time,uuid,text,jsonb,uuid)
  from public,anon,authenticated;
grant execute on function atlas.set_organization_recurrence_exception_service_v1(uuid,uuid,date,text,date,time,time,uuid,text,jsonb,uuid)
  to service_role;

revoke all on function atlas.attach_occurrence_to_recurrence_instance_service_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.attach_occurrence_to_recurrence_instance_service_v1(uuid,uuid,uuid)
  to service_role;

revoke all on function atlas.organization_recurrence_schedule_service_v1(uuid,date,date)
  from public,anon,authenticated;
grant execute on function atlas.organization_recurrence_schedule_service_v1(uuid,date,date)
  to service_role;

-- Initial Elm recurrence authority.
do $$
declare
  v_org constant uuid := 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2';
  v_program constant uuid := '76959888-070f-4f04-834e-f4ad273f5f09';
  v_morning_rule uuid;
  v_evening_rule uuid;
  v_thanksgiving_binding uuid;
  v_event record;
  v_instance uuid;
begin
  insert into atlas.organization_recurrence_rules(
    organization_id,stable_key,title,frequency,interval_count,timezone_name,
    effective_start_date,weekdays,month_ordinals,
    local_start_time,local_end_time,rule_state,payload,metadata
  )
  values(
    v_org,
    'thursdays_community_mornings',
    'Thursdays at Elm — Community Mornings',
    'monthly_nth_weekday',
    1,
    'America/Chicago',
    date '2026-10-01',
    array[4]::smallint[],
    array[1,3]::smallint[],
    time '09:30',
    time '11:30',
    'active',
    jsonb_build_object(
      'programKey','thursdays_at_elm',
      'access','free community flower-farming morning'
    ),
    jsonb_build_object(
      'basis','operator_calendar_spec_2026_09_23',
      'recurrenceAuthority','atlas.organization_recurrence_rules'
    )
  )
  on conflict (organization_id,stable_key) do update
  set title=excluded.title,
      frequency=excluded.frequency,
      interval_count=excluded.interval_count,
      timezone_name=excluded.timezone_name,
      effective_start_date=excluded.effective_start_date,
      weekdays=excluded.weekdays,
      month_ordinals=excluded.month_ordinals,
      local_start_time=excluded.local_start_time,
      local_end_time=excluded.local_end_time,
      rule_state='active',
      payload=excluded.payload,
      metadata=atlas.organization_recurrence_rules.metadata || excluded.metadata,
      updated_at=now()
  returning id into v_morning_rule;

  insert into atlas.organization_recurrence_rules(
    organization_id,stable_key,title,frequency,interval_count,timezone_name,
    effective_start_date,weekdays,month_ordinals,
    local_start_time,local_end_time,rule_state,payload,metadata
  )
  values(
    v_org,
    'thursdays_seasonal_evenings',
    'Thursdays at Elm — Seasonal Evenings',
    'monthly_nth_weekday',
    1,
    'America/Chicago',
    date '2026-10-01',
    array[4]::smallint[],
    array[2,4]::smallint[],
    time '18:30',
    time '20:30',
    'active',
    jsonb_build_object(
      'programKey','thursdays_at_elm',
      'access','ticketed seasonal gathering'
    ),
    jsonb_build_object(
      'basis','operator_calendar_spec_2026_09_23',
      'recurrenceAuthority','atlas.organization_recurrence_rules'
    )
  )
  on conflict (organization_id,stable_key) do update
  set title=excluded.title,
      frequency=excluded.frequency,
      interval_count=excluded.interval_count,
      timezone_name=excluded.timezone_name,
      effective_start_date=excluded.effective_start_date,
      weekdays=excluded.weekdays,
      month_ordinals=excluded.month_ordinals,
      local_start_time=excluded.local_start_time,
      local_end_time=excluded.local_end_time,
      rule_state='active',
      payload=excluded.payload,
      metadata=atlas.organization_recurrence_rules.metadata || excluded.metadata,
      updated_at=now()
  returning id into v_evening_rule;

  select b.id
  into v_thanksgiving_binding
  from atlas.organization_temporal_bindings b
  join local_intel.temporal_markers t on t.id=b.temporal_marker_id
  where b.organization_id=v_org
    and t.stable_key='us-thanksgiving-2026'
    and b.binding_state='active';

  perform atlas.set_organization_recurrence_exception_service_v1(
    v_org,
    v_evening_rule,
    date '2026-11-26',
    'skip',
    null,
    null,
    null,
    v_thanksgiving_binding,
    'Thanksgiving — No Thursday at Elm',
    jsonb_build_object(
      'calendarDisposition','programming_closure',
      'basis','operator_calendar_spec_2026_09_23'
    ),
    null
  );

  perform atlas.refresh_organization_recurrence_instances_service_v1(
    v_org,v_morning_rule,date '2026-10-01',date '2026-11-30'
  );

  perform atlas.refresh_organization_recurrence_instances_service_v1(
    v_org,v_evening_rule,date '2026-10-01',date '2026-11-30'
  );

  -- Attach already-existing canonical Thursdays-at-Elm occurrences.
  for v_event in
    select
      ce.event_date,
      ce.event_kind,
      ce.occurrence_binding_id,
      o.status as occurrence_status
    from atlas.community_events ce
    join atlas.organization_occurrence_bindings b
      on b.id=ce.occurrence_binding_id
     and b.organization_id=v_org
    join local_intel.occurrences o on o.id=b.occurrence_id
    where ce.program_id=v_program
      and ce.event_date between date '2026-10-01' and date '2026-11-30'
      and ce.event_kind in ('free_community_morning','ticketed_seasonal_evening')
  loop
    select i.id
    into v_instance
    from atlas.organization_recurrence_instances i
    where i.organization_id=v_org
      and i.recurrence_rule_id=case
        when v_event.event_kind='free_community_morning' then v_morning_rule
        else v_evening_rule
      end
      and i.source_local_date=v_event.event_date;

    if v_instance is not null then
      perform atlas.attach_occurrence_to_recurrence_instance_service_v1(
        v_org,v_instance,v_event.occurrence_binding_id
      );
    end if;
  end loop;

  -- Existing program cadence remains a compatibility description, not authority.
  update atlas.community_programs
  set cadence=jsonb_set(
        cadence,
        '{free_mornings,end_local_time}',
        '"11:30"'::jsonb,
        true
      ),
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'recurrenceAuthority','atlas.organization_recurrence_rules',
        'recurrenceRuleKeys',jsonb_build_array(
          'thursdays_community_mornings',
          'thursdays_seasonal_evenings'
        ),
        'cadenceState','compatibility_description'
      ),
      updated_at=now()
  where id=v_program;
end
$$;
