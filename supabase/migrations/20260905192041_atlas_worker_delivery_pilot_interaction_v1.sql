begin;

create table if not exists atlas.worker_delivery_pilot_capabilities (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  scope text not null default 'anna_worker_day_pilot',
  bootstrap_token_hash text not null unique,
  redeemed_at timestamptz,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  constraint worker_delivery_pilot_capabilities_scope_check
    check (scope = 'anna_worker_day_pilot')
);

create table if not exists atlas.worker_delivery_pilot_sessions (
  id uuid primary key default gen_random_uuid(),
  capability_id uuid not null references atlas.worker_delivery_pilot_capabilities(id) on delete restrict,
  session_token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists atlas.worker_delivery_pilot_events (
  id uuid primary key default gen_random_uuid(),
  event_seq bigint generated always as identity unique,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  projection_id uuid references atlas.worker_week_projection(id) on delete restrict,
  session_id uuid not null references atlas.worker_delivery_pilot_sessions(id) on delete restrict,
  event_kind text not null,
  effective_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  reported_title text,
  metadata jsonb not null default '{}'::jsonb,
  constraint worker_delivery_pilot_events_kind_check
    check (event_kind = any (array[
      'start'::text,
      'stop'::text,
      'done_reported'::text,
      'completion_reopened'::text,
      'unscheduled_work_reported'::text
    ])),
  constraint worker_delivery_pilot_events_subject_check
    check (
      (event_kind = 'unscheduled_work_reported' and projection_id is null and nullif(btrim(reported_title), '') is not null)
      or
      (event_kind <> 'unscheduled_work_reported' and projection_id is not null and reported_title is null)
    )
);

create table if not exists atlas.worker_delivery_pilot_active_attention (
  membership_id uuid primary key references atlas.organization_memberships(id) on delete restrict,
  projection_id uuid not null references atlas.worker_week_projection(id) on delete restrict,
  start_event_id uuid not null references atlas.worker_delivery_pilot_events(id) on delete restrict,
  started_effective_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create index if not exists worker_delivery_pilot_events_membership_seq_idx
  on atlas.worker_delivery_pilot_events (membership_id, event_seq desc);

create index if not exists worker_delivery_pilot_events_projection_seq_idx
  on atlas.worker_delivery_pilot_events (projection_id, event_seq desc)
  where projection_id is not null;

alter table atlas.worker_delivery_pilot_capabilities enable row level security;
alter table atlas.worker_delivery_pilot_sessions enable row level security;
alter table atlas.worker_delivery_pilot_events enable row level security;
alter table atlas.worker_delivery_pilot_active_attention enable row level security;

create or replace function atlas.prevent_worker_delivery_pilot_event_mutation_v1()
returns trigger
language plpgsql
set search_path = atlas, public
as $$
begin
  raise exception 'worker_delivery_pilot_events are append-only';
end;
$$;

drop trigger if exists worker_delivery_pilot_events_append_only
  on atlas.worker_delivery_pilot_events;

create trigger worker_delivery_pilot_events_append_only
before update or delete on atlas.worker_delivery_pilot_events
for each row execute function atlas.prevent_worker_delivery_pilot_event_mutation_v1();

create or replace function atlas.redeem_worker_delivery_pilot_capability_v1(
  p_bootstrap_token_hash text,
  p_session_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, public
as $$
declare
  v_cap atlas.worker_delivery_pilot_capabilities%rowtype;
  v_session_id uuid;
  v_session_expires timestamptz;
begin
  select *
  into v_cap
  from atlas.worker_delivery_pilot_capabilities
  where bootstrap_token_hash = p_bootstrap_token_hash
  for update;

  if not found
     or v_cap.revoked_at is not null
     or v_cap.redeemed_at is not null
     or v_cap.expires_at <= clock_timestamp() then
    return jsonb_build_object('ok', false, 'code', 'invalid_or_expired_capability');
  end if;

  v_session_expires := least(v_cap.expires_at, clock_timestamp() + interval '14 days');

  update atlas.worker_delivery_pilot_capabilities
  set redeemed_at = clock_timestamp()
  where id = v_cap.id;

  insert into atlas.worker_delivery_pilot_sessions (
    capability_id,
    session_token_hash,
    expires_at
  )
  values (
    v_cap.id,
    p_session_token_hash,
    v_session_expires
  )
  returning id into v_session_id;

  return jsonb_build_object(
    'ok', true,
    'sessionId', v_session_id,
    'membershipId', v_cap.membership_id,
    'expiresAt', v_session_expires
  );
end;
$$;

create or replace function atlas.worker_delivery_pilot_session_status_v1(
  p_session_token_hash text
)
returns jsonb
language sql
security definer
stable
set search_path = atlas, public
as $$
  select coalesce(
    (
      select jsonb_build_object(
        'ok', true,
        'sessionId', s.id,
        'membershipId', c.membership_id,
        'expiresAt', s.expires_at
      )
      from atlas.worker_delivery_pilot_sessions s
      join atlas.worker_delivery_pilot_capabilities c
        on c.id = s.capability_id
      where s.session_token_hash = p_session_token_hash
        and s.revoked_at is null
        and s.expires_at > clock_timestamp()
        and c.revoked_at is null
        and c.expires_at > clock_timestamp()
        and c.scope = 'anna_worker_day_pilot'
      limit 1
    ),
    jsonb_build_object('ok', false, 'code', 'invalid_or_expired_session')
  );
$$;

create or replace function atlas.worker_delivery_pilot_transition_v1(
  p_session_token_hash text,
  p_action text,
  p_projection_id uuid default null,
  p_effective_at timestamptz default null,
  p_reported_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = atlas, public
as $$
declare
  v_session_id uuid;
  v_membership_id uuid;
  v_organization_id uuid;
  v_title text;
  v_active atlas.worker_delivery_pilot_active_attention%rowtype;
  v_active_title text;
  v_now timestamptz := clock_timestamp();
  v_effective timestamptz := coalesce(p_effective_at, clock_timestamp());
  v_event_id uuid;
  v_latest_completion text;
begin
  select s.id, c.membership_id
  into v_session_id, v_membership_id
  from atlas.worker_delivery_pilot_sessions s
  join atlas.worker_delivery_pilot_capabilities c
    on c.id = s.capability_id
  where s.session_token_hash = p_session_token_hash
    and s.revoked_at is null
    and s.expires_at > v_now
    and c.revoked_at is null
    and c.expires_at > v_now
    and c.scope = 'anna_worker_day_pilot'
  limit 1;

  if v_session_id is null then
    return jsonb_build_object('ok', false, 'code', 'unauthorized');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_membership_id::text, 0));

  if p_action = 'report_unscheduled' then
    if nullif(btrim(p_reported_title), '') is null then
      return jsonb_build_object('ok', false, 'code', 'title_required');
    end if;

    select om.organization_id
    into v_organization_id
    from atlas.organization_memberships om
    where om.id = v_membership_id;

    if v_organization_id is null then
      return jsonb_build_object('ok', false, 'code', 'membership_not_found');
    end if;

    insert into atlas.worker_delivery_pilot_events (
      organization_id,
      membership_id,
      projection_id,
      session_id,
      event_kind,
      effective_at,
      reported_title
    )
    values (
      v_organization_id,
      v_membership_id,
      null,
      v_session_id,
      'unscheduled_work_reported',
      v_effective,
      btrim(p_reported_title)
    )
    returning id into v_event_id;

    return jsonb_build_object('ok', true, 'status', 'unscheduled_recorded', 'eventId', v_event_id);
  end if;

  if p_projection_id is null then
    return jsonb_build_object('ok', false, 'code', 'projection_required');
  end if;

  select p.organization_id, p.title
  into v_organization_id, v_title
  from atlas.worker_week_projection p
  where p.id = p_projection_id
    and p.membership_id = v_membership_id;

  if v_organization_id is null then
    return jsonb_build_object('ok', false, 'code', 'projection_not_found');
  end if;

  select e.event_kind
  into v_latest_completion
  from atlas.worker_delivery_pilot_events e
  where e.projection_id = p_projection_id
    and e.event_kind in ('done_reported', 'completion_reopened')
  order by e.event_seq desc
  limit 1;

  select *
  into v_active
  from atlas.worker_delivery_pilot_active_attention
  where membership_id = v_membership_id
  for update;

  if p_action = 'start' then
    if v_latest_completion = 'done_reported' then
      return jsonb_build_object('ok', false, 'code', 'already_completed');
    end if;

    if v_active.membership_id is not null then
      if v_active.projection_id = p_projection_id then
        return jsonb_build_object('ok', true, 'status', 'already_active');
      end if;

      select title into v_active_title
      from atlas.worker_week_projection
      where id = v_active.projection_id;

      return jsonb_build_object(
        'ok', false,
        'code', 'attention_conflict',
        'activeProjectionId', v_active.projection_id,
        'activeTitle', coalesce(v_active_title, 'Previous task')
      );
    end if;

    insert into atlas.worker_delivery_pilot_events (
      organization_id, membership_id, projection_id, session_id, event_kind, effective_at
    )
    values (
      v_organization_id, v_membership_id, p_projection_id, v_session_id, 'start', v_effective
    )
    returning id into v_event_id;

    insert into atlas.worker_delivery_pilot_active_attention (
      membership_id, projection_id, start_event_id, started_effective_at, updated_at
    )
    values (
      v_membership_id, p_projection_id, v_event_id, v_effective, v_now
    );

    return jsonb_build_object('ok', true, 'status', 'started');
  end if;

  if p_action = 'stop' then
    if v_active.membership_id is null or v_active.projection_id <> p_projection_id then
      return jsonb_build_object('ok', true, 'status', 'not_active');
    end if;

    if v_effective > v_now + interval '1 minute'
       or v_effective < v_active.started_effective_at then
      return jsonb_build_object('ok', false, 'code', 'invalid_stop_time');
    end if;

    insert into atlas.worker_delivery_pilot_events (
      organization_id, membership_id, projection_id, session_id, event_kind, effective_at
    )
    values (
      v_organization_id, v_membership_id, p_projection_id, v_session_id, 'stop', v_effective
    );

    delete from atlas.worker_delivery_pilot_active_attention
    where membership_id = v_membership_id;

    return jsonb_build_object('ok', true, 'status', 'stopped');
  end if;

  if p_action = 'done' then
    if v_latest_completion = 'done_reported' then
      return jsonb_build_object('ok', true, 'status', 'already_completed');
    end if;

    if v_active.membership_id is not null and v_active.projection_id = p_projection_id then
      insert into atlas.worker_delivery_pilot_events (
        organization_id, membership_id, projection_id, session_id, event_kind, effective_at
      )
      values (
        v_organization_id, v_membership_id, p_projection_id, v_session_id, 'stop', v_effective
      );

      delete from atlas.worker_delivery_pilot_active_attention
      where membership_id = v_membership_id;
    end if;

    insert into atlas.worker_delivery_pilot_events (
      organization_id, membership_id, projection_id, session_id, event_kind, effective_at
    )
    values (
      v_organization_id, v_membership_id, p_projection_id, v_session_id, 'done_reported', v_effective
    );

    return jsonb_build_object('ok', true, 'status', 'done_reported');
  end if;

  if p_action = 'reopen' then
    if v_latest_completion <> 'done_reported' then
      return jsonb_build_object('ok', true, 'status', 'already_open');
    end if;

    insert into atlas.worker_delivery_pilot_events (
      organization_id, membership_id, projection_id, session_id, event_kind, effective_at
    )
    values (
      v_organization_id, v_membership_id, p_projection_id, v_session_id, 'completion_reopened', v_effective
    );

    return jsonb_build_object('ok', true, 'status', 'reopened');
  end if;

  if p_action in ('switch_finish', 'switch_stop') then
    if v_latest_completion = 'done_reported' then
      return jsonb_build_object('ok', false, 'code', 'already_completed');
    end if;

    if v_active.membership_id is null then
      insert into atlas.worker_delivery_pilot_events (
        organization_id, membership_id, projection_id, session_id, event_kind, effective_at
      )
      values (
        v_organization_id, v_membership_id, p_projection_id, v_session_id, 'start', v_now
      )
      returning id into v_event_id;

      insert into atlas.worker_delivery_pilot_active_attention (
        membership_id, projection_id, start_event_id, started_effective_at, updated_at
      )
      values (
        v_membership_id, p_projection_id, v_event_id, v_now, v_now
      );

      return jsonb_build_object('ok', true, 'status', 'started');
    end if;

    if v_active.projection_id = p_projection_id then
      return jsonb_build_object('ok', true, 'status', 'already_active');
    end if;

    if p_action = 'switch_stop'
       and (
         v_effective > v_now + interval '1 minute'
         or v_effective < v_active.started_effective_at
       ) then
      return jsonb_build_object('ok', false, 'code', 'invalid_stop_time');
    end if;

    select p.organization_id, p.title
    into v_organization_id, v_active_title
    from atlas.worker_week_projection p
    where p.id = v_active.projection_id;

    insert into atlas.worker_delivery_pilot_events (
      organization_id, membership_id, projection_id, session_id, event_kind, effective_at
    )
    values (
      v_organization_id,
      v_membership_id,
      v_active.projection_id,
      v_session_id,
      'stop',
      case when p_action = 'switch_stop' then v_effective else v_now end
    );

    if p_action = 'switch_finish' then
      insert into atlas.worker_delivery_pilot_events (
        organization_id, membership_id, projection_id, session_id, event_kind, effective_at
      )
      values (
        v_organization_id,
        v_membership_id,
        v_active.projection_id,
        v_session_id,
        'done_reported',
        v_now
      );
    end if;

    select p.organization_id, p.title
    into v_organization_id, v_title
    from atlas.worker_week_projection p
    where p.id = p_projection_id
      and p.membership_id = v_membership_id;

    insert into atlas.worker_delivery_pilot_events (
      organization_id, membership_id, projection_id, session_id, event_kind, effective_at
    )
    values (
      v_organization_id, v_membership_id, p_projection_id, v_session_id, 'start', v_now
    )
    returning id into v_event_id;

    update atlas.worker_delivery_pilot_active_attention
    set projection_id = p_projection_id,
        start_event_id = v_event_id,
        started_effective_at = v_now,
        updated_at = v_now
    where membership_id = v_membership_id;

    return jsonb_build_object('ok', true, 'status', 'switched');
  end if;

  return jsonb_build_object('ok', false, 'code', 'unsupported_action');
end;
$$;

revoke all on function atlas.redeem_worker_delivery_pilot_capability_v1(text, text) from public;
revoke all on function atlas.worker_delivery_pilot_session_status_v1(text) from public;
revoke all on function atlas.worker_delivery_pilot_transition_v1(text, text, uuid, timestamptz, text) from public;

grant execute on function atlas.redeem_worker_delivery_pilot_capability_v1(text, text) to service_role;
grant execute on function atlas.worker_delivery_pilot_session_status_v1(text) to service_role;
grant execute on function atlas.worker_delivery_pilot_transition_v1(text, text, uuid, timestamptz, text) to service_role;

comment on table atlas.worker_delivery_pilot_events is
  'Append-only Sept 2026 Worker Day pilot interaction ledger. These events report worker-facing interaction and do not directly mutate or replace canonical institutional work truth.';

comment on table atlas.worker_delivery_pilot_active_attention is
  'Mutable coordination projection for the Worker Day pilot one-active-attention invariant. History remains authoritative in worker_delivery_pilot_events.';

commit;