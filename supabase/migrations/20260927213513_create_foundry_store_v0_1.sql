create schema if not exists foundry;

create table if not exists foundry.events (
  workspace_id text not null,
  sequence bigint not null check (sequence >= 1),
  event_id text not null unique,
  event_type text not null,
  envelope jsonb not null check (jsonb_typeof(envelope) = 'object'),
  inserted_at timestamptz not null default now(),
  primary key (workspace_id, sequence)
);

create table if not exists foundry.snapshots (
  workspace_id text primary key,
  through_sequence bigint not null check (through_sequence >= 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  inserted_at timestamptz not null default now()
);

create or replace function foundry.prevent_event_mutation()
returns trigger
language plpgsql
set search_path = foundry, pg_temp
as $$
begin
  raise exception 'foundry events are append-only';
end;
$$;

drop trigger if exists foundry_events_append_only on foundry.events;
create trigger foundry_events_append_only
before update or delete on foundry.events
for each row execute function foundry.prevent_event_mutation();

create or replace function foundry.append_event(p_event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = foundry, pg_temp
as $$
declare
  v_event_id text;
  v_workspace_id text;
  v_event_type text;
  v_sequence bigint;
  v_expected bigint;
  v_existing jsonb;
begin
  if p_event is null or jsonb_typeof(p_event) <> 'object' then
    raise exception 'event must be a JSON object';
  end if;

  v_event_id := nullif(p_event->>'event_id', '');
  v_workspace_id := nullif(p_event->>'workspace_id', '');
  v_event_type := nullif(p_event->>'event_type', '');

  if v_event_id is null then raise exception 'missing event_id'; end if;
  if v_workspace_id is null then raise exception 'missing workspace_id'; end if;
  if v_event_type is null then raise exception 'missing event_type'; end if;
  if not (p_event ? 'sequence') then raise exception 'missing sequence'; end if;
  if not (p_event ? 'payload') or jsonb_typeof(p_event->'payload') <> 'object' then raise exception 'payload must be an object'; end if;
  if not (p_event ? 'basis_refs') or jsonb_typeof(p_event->'basis_refs') <> 'array' then raise exception 'basis_refs must be an array'; end if;
  if nullif(p_event->>'authority','') is null then raise exception 'missing authority'; end if;
  if nullif(p_event->>'actor_kind','') is null then raise exception 'missing actor_kind'; end if;
  if nullif(p_event->>'recorded_at','') is null then raise exception 'missing recorded_at'; end if;
  if nullif(p_event->>'protocol_version','') is null then raise exception 'missing protocol_version'; end if;

  begin
    v_sequence := (p_event->>'sequence')::bigint;
  exception when others then
    raise exception 'sequence must be a positive integer';
  end;
  if v_sequence < 1 then raise exception 'sequence must be a positive integer'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_workspace_id, 0));

  select envelope into v_existing from foundry.events where event_id = v_event_id;
  if found then
    if v_existing = p_event then
      return jsonb_build_object('status','REPLAYED','event',v_existing);
    end if;
    raise exception 'event_id % already exists with different content', v_event_id;
  end if;

  select coalesce(max(sequence), 0) + 1 into v_expected
  from foundry.events
  where workspace_id = v_workspace_id;

  if v_sequence <> v_expected then
    raise exception 'workspace % expected sequence %, received %', v_workspace_id, v_expected, v_sequence;
  end if;

  insert into foundry.events(workspace_id, sequence, event_id, event_type, envelope)
  values (v_workspace_id, v_sequence, v_event_id, v_event_type, p_event);

  return jsonb_build_object('status','APPENDED','event',p_event);
end;
$$;

create or replace function foundry.read_events(
  p_workspace_id text,
  p_after_sequence bigint default 0,
  p_through_sequence bigint default null,
  p_limit integer default null
)
returns setof jsonb
language sql
stable
security definer
set search_path = foundry, pg_temp
as $$
  select e.envelope
  from foundry.events e
  where e.workspace_id = p_workspace_id
    and e.sequence > greatest(coalesce(p_after_sequence,0),0)
    and (p_through_sequence is null or e.sequence <= p_through_sequence)
  order by e.sequence
  limit case when p_limit is not null and p_limit > 0 then p_limit else null end;
$$;

create or replace function foundry.has_event(p_event_id text)
returns boolean
language sql
stable
security definer
set search_path = foundry, pg_temp
as $$
  select exists(select 1 from foundry.events where event_id = p_event_id);
$$;

create or replace function foundry.write_snapshot(p_snapshot jsonb)
returns jsonb
language plpgsql
security definer
set search_path = foundry, pg_temp
as $$
declare
  v_workspace_id text;
  v_through bigint;
  v_latest bigint;
  v_prior bigint;
begin
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then raise exception 'snapshot must be a JSON object'; end if;
  v_workspace_id := nullif(p_snapshot->>'workspace_id','');
  if v_workspace_id is null then raise exception 'missing workspace_id'; end if;
  if not (p_snapshot ? 'workspace') or jsonb_typeof(p_snapshot->'workspace') <> 'object' then raise exception 'workspace must be an object'; end if;
  if nullif(p_snapshot->>'created_at','') is null then raise exception 'missing created_at'; end if;
  if nullif(p_snapshot->>'protocol_version','') is null then raise exception 'missing protocol_version'; end if;
  begin
    v_through := (p_snapshot->>'through_sequence')::bigint;
  exception when others then
    raise exception 'through_sequence must be a non-negative integer';
  end;
  if v_through < 0 then raise exception 'through_sequence must be a non-negative integer'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_workspace_id, 0));
  select coalesce(max(sequence),0) into v_latest from foundry.events where workspace_id = v_workspace_id;
  if v_through > v_latest then raise exception 'snapshot through_sequence % exceeds stored event sequence %', v_through, v_latest; end if;

  select through_sequence into v_prior from foundry.snapshots where workspace_id = v_workspace_id;
  if found and v_through < v_prior then raise exception 'snapshot regression for %: % < %', v_workspace_id, v_through, v_prior; end if;

  insert into foundry.snapshots(workspace_id, through_sequence, snapshot)
  values (v_workspace_id, v_through, p_snapshot)
  on conflict (workspace_id) do update
    set through_sequence = excluded.through_sequence,
        snapshot = excluded.snapshot,
        inserted_at = now();

  return p_snapshot;
end;
$$;

create or replace function foundry.read_latest_snapshot(p_workspace_id text)
returns jsonb
language sql
stable
security definer
set search_path = foundry, pg_temp
as $$
  select snapshot from foundry.snapshots where workspace_id = p_workspace_id;
$$;

revoke all on schema foundry from public, anon, authenticated;
revoke all on all tables in schema foundry from public, anon, authenticated;
revoke all on all functions in schema foundry from public, anon, authenticated;
grant usage on schema foundry to service_role;
grant execute on function foundry.append_event(jsonb) to service_role;
grant execute on function foundry.read_events(text,bigint,bigint,integer) to service_role;
grant execute on function foundry.has_event(text) to service_role;
grant execute on function foundry.write_snapshot(jsonb) to service_role;
grant execute on function foundry.read_latest_snapshot(text) to service_role;