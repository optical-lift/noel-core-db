BEGIN;

create or replace function atlas.guard_execution_lease_event_transition_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_previous_state text;
  v_previous_at timestamptz;
  v_expected_state text;
begin
  perform 1 from atlas.execution_leases l where l.id=new.lease_id for update;
  if not found then
    raise exception 'Execution lease not found.' using errcode='23503';
  end if;

  select e.resulting_state,e.occurred_at
    into v_previous_state,v_previous_at
  from atlas.execution_lease_events e
  where e.lease_id=new.lease_id
  order by e.occurred_at desc,e.id desc
  limit 1;

  v_expected_state := case new.event_kind
    when 'granted' then 'leased'
    when 'started' then 'started'
    when 'interrupted' then 'interrupted'
    when 'resumed' then 'started'
    when 'completed' then 'completed'
    when 'withdrawn' then 'withdrawn'
    when 'expired' then 'expired'
  end;

  if new.resulting_state is distinct from v_expected_state then
    raise exception 'Execution lease event resulting state does not match event kind.' using errcode='23514';
  end if;

  if v_previous_state is null then
    if new.event_kind <> 'granted'
       or new.previous_state is not null
       or new.resulting_state <> 'leased' then
      raise exception 'First execution lease event must be granted -> leased.' using errcode='23514';
    end if;
    return new;
  end if;

  if new.occurred_at < v_previous_at then
    raise exception 'Execution lease events cannot be backdated before the current lease state.' using errcode='23514';
  end if;

  if new.previous_state is distinct from v_previous_state then
    raise exception 'Execution lease transition predecessor is stale or incorrect.' using errcode='40001';
  end if;

  if v_previous_state in ('completed','withdrawn','expired') then
    raise exception 'Terminal execution lease state cannot transition.' using errcode='23514';
  end if;

  if new.event_kind='granted' then
    raise exception 'An execution lease can only be granted once.' using errcode='23514';
  end if;

  if not (
    (v_previous_state='leased' and new.event_kind in ('started','interrupted','completed','withdrawn','expired'))
    or
    (v_previous_state='started' and new.event_kind in ('interrupted','completed','withdrawn','expired'))
    or
    (v_previous_state='interrupted' and new.event_kind in ('resumed','completed','withdrawn','expired'))
  ) then
    raise exception 'Invalid execution lease transition from % using %.',v_previous_state,new.event_kind using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_execution_lease_event_transition_v1() is
  'Serializes and validates append-only execution lease transitions, including monotonic event chronology and terminal-state custody.';

COMMIT;
