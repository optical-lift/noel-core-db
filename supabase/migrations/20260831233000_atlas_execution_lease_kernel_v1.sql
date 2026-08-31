BEGIN;

-- Atlas Execution Lease kernel v1.
--
-- Operational trust boundary:
--   planners are advisory;
--   a lease is the explicit handoff of executable work to a human;
--   planner recomputation cannot silently add, remove, or rewrite a lease.
--
-- The kernel is domain-neutral. Domain adapters must translate their own
-- readiness / identity contracts into one explicit admissionWarrant.authorized
-- boolean before a lease can be granted.

create table atlas.execution_leases (
  id uuid primary key default gen_random_uuid(),
  lease_key text not null check (btrim(lease_key) <> ''),
  lease_kind text not null check (btrim(lease_kind) <> ''),
  custody_kind text not null check (custody_kind in ('organization','principal')),
  organization_id uuid references atlas.organizations(id) on delete restrict,
  principal_id uuid references atlas.principals(id) on delete restrict,
  recipient_kind text not null check (btrim(recipient_kind) <> ''),
  recipient_id uuid not null,
  obligation_kind text,
  obligation_id uuid,
  execution_kind text not null check (btrim(execution_kind) <> ''),
  execution_id uuid not null,
  title_snapshot text not null check (btrim(title_snapshot) <> ''),
  lease_start timestamptz not null,
  lease_end timestamptz not null check (lease_end > lease_start),
  warrant_contract text not null check (btrim(warrant_contract) <> ''),
  admission_warrant jsonb not null,
  admitted_reason text not null check (btrim(admitted_reason) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id uuid,
  actor_user_id uuid,
  shadow_only boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (
    (custody_kind='organization' and organization_id is not null and principal_id is null)
    or
    (custody_kind='principal' and principal_id is not null and organization_id is null)
  ),
  check (obligation_id is null or nullif(btrim(coalesce(obligation_kind,'')),'') is not null),
  check (jsonb_typeof(admission_warrant)='object'),
  check (coalesce((admission_warrant->>'authorized')::boolean,false)=true)
);

create unique index execution_leases_organization_key_uq
  on atlas.execution_leases(organization_id, lease_key)
  where custody_kind='organization';
create unique index execution_leases_principal_key_uq
  on atlas.execution_leases(principal_id, lease_key)
  where custody_kind='principal';
create index execution_leases_recipient_window_idx
  on atlas.execution_leases(recipient_kind, recipient_id, lease_start, lease_end, id);
create index execution_leases_execution_idx
  on atlas.execution_leases(execution_kind, execution_id, lease_start, lease_end, id);

comment on table atlas.execution_leases is
  'Immutable item-level execution handoffs. A planner recommendation is not a lease; granting a lease is the operational authority boundary.';

create table atlas.execution_lease_events (
  id uuid primary key default gen_random_uuid(),
  lease_id uuid not null references atlas.execution_leases(id) on delete restrict,
  event_key text not null check (btrim(event_key) <> ''),
  event_kind text not null check (event_kind in (
    'granted','started','interrupted','resumed','completed','withdrawn','expired'
  )),
  previous_state text check (previous_state is null or previous_state in (
    'leased','started','interrupted','completed','withdrawn','expired'
  )),
  resulting_state text not null check (resulting_state in (
    'leased','started','interrupted','completed','withdrawn','expired'
  )),
  reason text not null check (btrim(reason) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id uuid,
  actor_user_id uuid,
  evidence jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(lease_id,event_key)
);

create index execution_lease_events_state_idx
  on atlas.execution_lease_events(lease_id, occurred_at desc, id desc);

comment on table atlas.execution_lease_events is
  'Append-only execution lease state transitions. Existing leases never disappear because a planner recomputed; a transition event is required.';

create or replace function atlas.reject_execution_lease_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
begin
  raise exception 'Atlas execution lease history is append-only.' using errcode='55000';
end;
$$;

create trigger execution_leases_append_only
before update or delete on atlas.execution_leases
for each row execute function atlas.reject_execution_lease_history_mutation_v1();

create trigger execution_lease_events_append_only
before update or delete on atlas.execution_lease_events
for each row execute function atlas.reject_execution_lease_history_mutation_v1();

create or replace function atlas.guard_execution_lease_event_transition_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_previous_state text;
  v_expected_state text;
begin
  -- Serialize all transitions for one lease, including direct service-role
  -- inserts, so two concurrent events cannot both claim the same predecessor.
  perform 1 from atlas.execution_leases l where l.id=new.lease_id for update;
  if not found then
    raise exception 'Execution lease not found.' using errcode='23503';
  end if;

  select e.resulting_state
    into v_previous_state
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

create trigger execution_lease_events_transition_guard
before insert on atlas.execution_lease_events
for each row execute function atlas.guard_execution_lease_event_transition_v1();

alter table atlas.execution_leases enable row level security;
alter table atlas.execution_lease_events enable row level security;

revoke all on atlas.execution_leases from public, anon, authenticated;
revoke all on atlas.execution_lease_events from public, anon, authenticated;
grant select,insert on atlas.execution_leases to service_role;
grant select,insert on atlas.execution_lease_events to service_role;

create or replace function atlas.execution_lease_current_state_v1(p_lease_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
  select case when l.id is null then null else jsonb_build_object(
    'contractVersion','execution_lease_current_state_v1',
    'leaseId',l.id,
    'leaseKey',l.lease_key,
    'leaseKind',l.lease_kind,
    'recipient',jsonb_build_object('kind',l.recipient_kind,'id',l.recipient_id),
    'execution',jsonb_build_object('kind',l.execution_kind,'id',l.execution_id),
    'title',l.title_snapshot,
    'leaseStart',l.lease_start,
    'leaseEnd',l.lease_end,
    'state',e.resulting_state,
    'actionable',coalesce(e.resulting_state in ('leased','started'),false),
    'interrupted',coalesce(e.resulting_state='interrupted',false),
    'terminal',coalesce(e.resulting_state in ('completed','withdrawn','expired'),false),
    'lastEvent',case when e.id is null then null else jsonb_build_object(
      'eventId',e.id,'eventKind',e.event_kind,'eventKey',e.event_key,
      'reason',e.reason,'sourceKind',e.source_kind,'sourceId',e.source_id,
      'occurredAt',e.occurred_at
    ) end,
    'shadowOnly',l.shadow_only,
    'metadata',l.metadata
  ) end
  from atlas.execution_leases l
  left join lateral (
    select x.*
    from atlas.execution_lease_events x
    where x.lease_id=l.id
    order by x.occurred_at desc,x.id desc
    limit 1
  ) e on true
  where l.id=p_lease_id;
$$;

revoke all on function atlas.execution_lease_current_state_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.execution_lease_current_state_v1(uuid) to service_role;

create or replace function atlas.grant_execution_lease_v1(
  p_lease_key text,
  p_lease_kind text,
  p_custody_kind text,
  p_organization_id uuid,
  p_principal_id uuid,
  p_recipient_kind text,
  p_recipient_id uuid,
  p_obligation_kind text,
  p_obligation_id uuid,
  p_execution_kind text,
  p_execution_id uuid,
  p_title text,
  p_lease_start timestamptz,
  p_lease_end timestamptz,
  p_warrant_contract text,
  p_admission_warrant jsonb,
  p_reason text,
  p_source_kind text,
  p_source_id uuid default null,
  p_actor_user_id uuid default null,
  p_shadow_only boolean default true,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_lease atlas.execution_leases%rowtype;
  v_event_id uuid;
  v_state jsonb;
begin
  if nullif(btrim(p_lease_key),'') is null
     or nullif(btrim(p_lease_kind),'') is null
     or nullif(btrim(p_recipient_kind),'') is null
     or p_recipient_id is null
     or nullif(btrim(p_execution_kind),'') is null
     or p_execution_id is null
     or nullif(btrim(p_title),'') is null
     or p_lease_start is null
     or p_lease_end is null
     or p_lease_end<=p_lease_start
     or nullif(btrim(p_warrant_contract),'') is null
     or nullif(btrim(p_reason),'') is null
     or nullif(btrim(p_source_kind),'') is null then
    raise exception 'Execution lease identity, recipient, execution, window, warrant, reason, and source are required.' using errcode='22023';
  end if;
  if p_custody_kind not in ('organization','principal') then
    raise exception 'Unsupported execution lease custody kind.' using errcode='22023';
  end if;
  if (p_custody_kind='organization' and (p_organization_id is null or p_principal_id is not null))
     or (p_custody_kind='principal' and (p_principal_id is null or p_organization_id is not null)) then
    raise exception 'Execution lease custody reference does not match custody kind.' using errcode='22023';
  end if;
  if p_admission_warrant is null
     or jsonb_typeof(p_admission_warrant)<>'object'
     or coalesce((p_admission_warrant->>'authorized')::boolean,false)<>true then
    raise exception 'Execution lease requires admissionWarrant.authorized=true.' using errcode='23514';
  end if;
  if p_obligation_id is not null and nullif(btrim(coalesce(p_obligation_kind,'')),'') is null then
    raise exception 'obligationKind is required when obligationId is supplied.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_custody_kind||':'||coalesce(p_organization_id::text,p_principal_id::text)||':'||btrim(p_lease_key),0
  ));

  if p_custody_kind='organization' then
    select * into v_lease
    from atlas.execution_leases l
    where l.organization_id=p_organization_id and l.lease_key=btrim(p_lease_key)
    limit 1;
  else
    select * into v_lease
    from atlas.execution_leases l
    where l.principal_id=p_principal_id and l.lease_key=btrim(p_lease_key)
    limit 1;
  end if;

  if v_lease.id is not null then
    if v_lease.lease_kind is distinct from btrim(p_lease_kind)
       or v_lease.custody_kind is distinct from p_custody_kind
       or v_lease.organization_id is distinct from p_organization_id
       or v_lease.principal_id is distinct from p_principal_id
       or v_lease.recipient_kind is distinct from btrim(p_recipient_kind)
       or v_lease.recipient_id is distinct from p_recipient_id
       or v_lease.obligation_kind is distinct from nullif(btrim(coalesce(p_obligation_kind,'')),'')
       or v_lease.obligation_id is distinct from p_obligation_id
       or v_lease.execution_kind is distinct from btrim(p_execution_kind)
       or v_lease.execution_id is distinct from p_execution_id
       or v_lease.title_snapshot is distinct from btrim(p_title)
       or v_lease.lease_start is distinct from p_lease_start
       or v_lease.lease_end is distinct from p_lease_end
       or v_lease.warrant_contract is distinct from btrim(p_warrant_contract)
       or v_lease.admission_warrant is distinct from p_admission_warrant
       or v_lease.shadow_only is distinct from coalesce(p_shadow_only,true) then
      raise exception 'Existing execution lease identity cannot be silently rewritten; mint a new lease key or transition the existing lease.' using errcode='55000';
    end if;
    v_state:=atlas.execution_lease_current_state_v1(v_lease.id);
    return jsonb_build_object(
      'contractVersion','grant_execution_lease_v1',
      'state','unchanged',
      'leaseId',v_lease.id,
      'currentState',v_state->>'state',
      'trustBoundary',jsonb_build_object(
        'plannerIsAdvisory',true,
        'leaseIdentityImmutable',true,
        'sameGrantIsIdempotent',true,
        'leaseRemovalRequiresTransition',true
      )
    );
  end if;

  insert into atlas.execution_leases(
    lease_key,lease_kind,custody_kind,organization_id,principal_id,
    recipient_kind,recipient_id,obligation_kind,obligation_id,
    execution_kind,execution_id,title_snapshot,lease_start,lease_end,
    warrant_contract,admission_warrant,admitted_reason,source_kind,source_id,
    actor_user_id,shadow_only,metadata
  ) values (
    btrim(p_lease_key),btrim(p_lease_kind),p_custody_kind,p_organization_id,p_principal_id,
    btrim(p_recipient_kind),p_recipient_id,nullif(btrim(coalesce(p_obligation_kind,'')),''),p_obligation_id,
    btrim(p_execution_kind),p_execution_id,btrim(p_title),p_lease_start,p_lease_end,
    btrim(p_warrant_contract),p_admission_warrant,btrim(p_reason),btrim(p_source_kind),p_source_id,
    p_actor_user_id,coalesce(p_shadow_only,true),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_lease;

  insert into atlas.execution_lease_events(
    lease_id,event_key,event_kind,previous_state,resulting_state,reason,
    source_kind,source_id,actor_user_id,evidence,metadata,occurred_at
  ) values (
    v_lease.id,'grant','granted',null,'leased',btrim(p_reason),
    btrim(p_source_kind),p_source_id,p_actor_user_id,
    jsonb_build_object('warrantContract',p_warrant_contract,'admissionWarrant',p_admission_warrant),
    '{}'::jsonb,now()
  ) returning id into v_event_id;

  return jsonb_build_object(
    'contractVersion','grant_execution_lease_v1',
    'state','granted',
    'leaseId',v_lease.id,
    'grantEventId',v_event_id,
    'currentState','leased',
    'trustBoundary',jsonb_build_object(
      'plannerIsAdvisory',true,
      'leaseIdentityImmutable',true,
      'sameGrantIsIdempotent',true,
      'leaseRemovalRequiresTransition',true
    )
  );
end;
$$;

revoke all on function atlas.grant_execution_lease_v1(text,text,text,uuid,uuid,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,jsonb,text,text,uuid,uuid,boolean,jsonb) from public, anon, authenticated;
grant execute on function atlas.grant_execution_lease_v1(text,text,text,uuid,uuid,text,uuid,text,uuid,text,uuid,text,timestamptz,timestamptz,text,jsonb,text,text,uuid,uuid,boolean,jsonb) to service_role;

create or replace function atlas.transition_execution_lease_v1(
  p_lease_id uuid,
  p_event_key text,
  p_event_kind text,
  p_reason text,
  p_source_kind text,
  p_source_id uuid default null,
  p_actor_user_id uuid default null,
  p_evidence jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_lease atlas.execution_leases%rowtype;
  v_existing atlas.execution_lease_events%rowtype;
  v_previous_state text;
  v_resulting_state text;
  v_event_id uuid;
begin
  if p_lease_id is null
     or nullif(btrim(p_event_key),'') is null
     or p_event_kind not in ('started','interrupted','resumed','completed','withdrawn','expired')
     or nullif(btrim(p_reason),'') is null
     or nullif(btrim(p_source_kind),'') is null
     or p_occurred_at is null then
    raise exception 'Execution lease transition requires lease, event key/kind, reason, source, and occurredAt.' using errcode='22023';
  end if;

  select * into v_lease
  from atlas.execution_leases l
  where l.id=p_lease_id
  for update;
  if v_lease.id is null then
    raise exception 'Execution lease not found.' using errcode='23503';
  end if;

  select * into v_existing
  from atlas.execution_lease_events e
  where e.lease_id=p_lease_id and e.event_key=btrim(p_event_key)
  limit 1;
  if v_existing.id is not null then
    if v_existing.event_kind is distinct from p_event_kind
       or v_existing.reason is distinct from btrim(p_reason)
       or v_existing.source_kind is distinct from btrim(p_source_kind)
       or v_existing.source_id is distinct from p_source_id
       or v_existing.evidence is distinct from coalesce(p_evidence,'{}'::jsonb)
       or v_existing.metadata is distinct from coalesce(p_metadata,'{}'::jsonb) then
      raise exception 'Execution lease event key already exists with different evidence.' using errcode='55000';
    end if;
    return jsonb_build_object(
      'contractVersion','transition_execution_lease_v1',
      'state','unchanged',
      'leaseId',p_lease_id,
      'eventId',v_existing.id,
      'currentState',v_existing.resulting_state
    );
  end if;

  select e.resulting_state into v_previous_state
  from atlas.execution_lease_events e
  where e.lease_id=p_lease_id
  order by e.occurred_at desc,e.id desc
  limit 1;

  v_resulting_state:=case p_event_kind
    when 'started' then 'started'
    when 'interrupted' then 'interrupted'
    when 'resumed' then 'started'
    when 'completed' then 'completed'
    when 'withdrawn' then 'withdrawn'
    when 'expired' then 'expired'
  end;

  insert into atlas.execution_lease_events(
    lease_id,event_key,event_kind,previous_state,resulting_state,reason,
    source_kind,source_id,actor_user_id,evidence,metadata,occurred_at
  ) values (
    p_lease_id,btrim(p_event_key),p_event_kind,v_previous_state,v_resulting_state,btrim(p_reason),
    btrim(p_source_kind),p_source_id,p_actor_user_id,coalesce(p_evidence,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb),p_occurred_at
  ) returning id into v_event_id;

  return jsonb_build_object(
    'contractVersion','transition_execution_lease_v1',
    'state','transitioned',
    'leaseId',p_lease_id,
    'eventId',v_event_id,
    'previousState',v_previous_state,
    'currentState',v_resulting_state
  );
end;
$$;

revoke all on function atlas.transition_execution_lease_v1(uuid,text,text,text,text,uuid,uuid,jsonb,jsonb,timestamptz) from public, anon, authenticated;
grant execute on function atlas.transition_execution_lease_v1(uuid,text,text,text,text,uuid,uuid,jsonb,jsonb,timestamptz) to service_role;

create or replace function atlas.execution_lease_reconciliation_proposal_v1(
  p_custody_kind text,
  p_organization_id uuid,
  p_principal_id uuid,
  p_recipient_kind text,
  p_recipient_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_candidates jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_candidate jsonb;
  v_key text;
  v_seen text[]:=array[]::text[];
  v_add jsonb;
  v_retain jsonb;
  v_withdraw jsonb;
begin
  if p_custody_kind not in ('organization','principal')
     or nullif(btrim(p_recipient_kind),'') is null
     or p_recipient_id is null
     or p_window_start is null
     or p_window_end is null
     or p_window_end<=p_window_start
     or p_candidates is null
     or jsonb_typeof(p_candidates)<>'array' then
    raise exception 'Lease reconciliation requires custody, recipient, window, and candidate array.' using errcode='22023';
  end if;
  if (p_custody_kind='organization' and (p_organization_id is null or p_principal_id is not null))
     or (p_custody_kind='principal' and (p_principal_id is null or p_organization_id is not null)) then
    raise exception 'Lease reconciliation custody reference does not match custody kind.' using errcode='22023';
  end if;

  for v_candidate in select value from jsonb_array_elements(p_candidates)
  loop
    if jsonb_typeof(v_candidate)<>'object'
       or nullif(btrim(v_candidate->>'executionKind'),'') is null
       or coalesce(v_candidate->>'executionId','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or nullif(btrim(v_candidate->>'title'),'') is null then
      raise exception 'Every lease candidate requires executionKind, UUID executionId, and title.' using errcode='22023';
    end if;
    v_key:=btrim(v_candidate->>'executionKind')||':'||lower(v_candidate->>'executionId');
    if v_key=any(v_seen) then
      raise exception 'Duplicate execution candidate: %',v_key using errcode='23505';
    end if;
    v_seen:=array_append(v_seen,v_key);
  end loop;

  with current_leases as (
    select l.*,e.resulting_state
    from atlas.execution_leases l
    join lateral (
      select x.resulting_state
      from atlas.execution_lease_events x
      where x.lease_id=l.id
      order by x.occurred_at desc,x.id desc
      limit 1
    ) e on true
    where l.custody_kind=p_custody_kind
      and l.organization_id is not distinct from p_organization_id
      and l.principal_id is not distinct from p_principal_id
      and l.recipient_kind=btrim(p_recipient_kind)
      and l.recipient_id=p_recipient_id
      and l.lease_start<p_window_end
      and l.lease_end>p_window_start
      and e.resulting_state not in ('completed','withdrawn','expired')
  ), candidates as (
    select c.value,c.ord
    from jsonb_array_elements(p_candidates) with ordinality c(value,ord)
  )
  select
    coalesce((select jsonb_agg(c.value order by c.ord)
      from candidates c
      where not exists (
        select 1 from current_leases l
        where l.execution_kind=btrim(c.value->>'executionKind')
          and l.execution_id=(c.value->>'executionId')::uuid
      )),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'leaseId',l.id,'leaseKey',l.lease_key,'currentState',l.resulting_state,
        'executionKind',l.execution_kind,'executionId',l.execution_id,'title',l.title_snapshot
      ) order by c.ord)
      from candidates c
      join current_leases l
        on l.execution_kind=btrim(c.value->>'executionKind')
       and l.execution_id=(c.value->>'executionId')::uuid),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object(
        'leaseId',l.id,'leaseKey',l.lease_key,'currentState',l.resulting_state,
        'executionKind',l.execution_kind,'executionId',l.execution_id,'title',l.title_snapshot,
        'proposedAction','withdraw'
      ) order by l.lease_start,l.id)
      from current_leases l
      where not exists (
        select 1 from candidates c
        where l.execution_kind=btrim(c.value->>'executionKind')
          and l.execution_id=(c.value->>'executionId')::uuid
      )),'[]'::jsonb)
  into v_add,v_retain,v_withdraw;

  return jsonb_build_object(
    'contractVersion','execution_lease_reconciliation_proposal_v1',
    'mutationAuthority',false,
    'proposalOnly',true,
    'add',v_add,
    'retain',v_retain,
    'withdraw',v_withdraw,
    'trustBoundary',jsonb_build_object(
      'plannerMayPropose',true,
      'proposalDoesNotAlterLease',true,
      'leaseChangeRequiresExplicitTransition',true
    )
  );
end;
$$;

revoke all on function atlas.execution_lease_reconciliation_proposal_v1(text,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb) from public, anon, authenticated;
grant execute on function atlas.execution_lease_reconciliation_proposal_v1(text,uuid,uuid,text,uuid,timestamptz,timestamptz,jsonb) to service_role;

COMMIT;
