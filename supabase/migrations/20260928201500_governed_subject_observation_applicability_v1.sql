-- Governed physical/resource observation and Responsibility→subject applicability sources.
--
-- Architectural boundary:
--   * resource observations are append-only source evidence about reality.resources;
--   * institutional Responsibility remains owned by atlas organization structure;
--   * applicability is a separate governed relation between an exact Responsibility scope,
--     an exact resource subject, and an exact operation;
--   * neither membrane creates Task/Work state or execution authority.

create table if not exists reality.resource_observations (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references reality.resources(id) on delete restrict,
  observation_type text not null,
  observation_payload jsonb not null,
  observer_ref text not null,
  observer_entity_id uuid null references reality.entities(id) on delete restrict,
  observed_at timestamptz not null,
  recorded_at timestamptz not null default clock_timestamp(),
  provenance jsonb not null default '{}'::jsonb,
  idempotency_scope text not null default 'reality.resource_observation.v1',
  idempotency_key text not null,
  payload_fingerprint text not null,
  constraint resource_observations_type_nonblank check (btrim(observation_type) <> ''),
  constraint resource_observations_observer_ref_nonblank check (btrim(observer_ref) <> ''),
  constraint resource_observations_payload_object check (jsonb_typeof(observation_payload) = 'object'),
  constraint resource_observations_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint resource_observations_idempotency_scope_nonblank check (btrim(idempotency_scope) <> ''),
  constraint resource_observations_idempotency_key_nonblank check (btrim(idempotency_key) <> ''),
  constraint resource_observations_fingerprint_nonblank check (btrim(payload_fingerprint) <> ''),
  constraint resource_observations_idempotency_uq unique (idempotency_scope, idempotency_key)
);

create index if not exists resource_observations_subject_type_observed_idx
  on reality.resource_observations (resource_id, observation_type, observed_at desc, recorded_at desc);

alter table reality.resource_observations enable row level security;
revoke all on table reality.resource_observations from public, anon, authenticated;
grant select, insert on table reality.resource_observations to service_role;

comment on table reality.resource_observations is
  'Append-only canonical source evidence about a reality.resources subject. This table is not Task state, readiness state, or a generic completion carrier.';
comment on column reality.resource_observations.observed_at is
  'When the observation applies in the observed world; distinct from recorded_at.';
comment on column reality.resource_observations.recorded_at is
  'When this source accepted the observation into canonical storage.';

create or replace function reality.record_resource_observation_service_v1(
  p_resource_id uuid,
  p_observation_type text,
  p_observation_payload jsonb,
  p_observer_ref text,
  p_observed_at timestamptz,
  p_idempotency_key text,
  p_observer_entity_id uuid default null,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, reality
as $$
declare
  v_observation_type text := btrim(coalesce(p_observation_type, ''));
  v_observer_ref text := btrim(coalesce(p_observer_ref, ''));
  v_idempotency_key text := btrim(coalesce(p_idempotency_key, ''));
  v_scope constant text := 'reality.resource_observation.v1';
  v_fingerprint text;
  v_existing reality.resource_observations%rowtype;
  v_inserted reality.resource_observations%rowtype;
  v_resource_state text;
begin
  if p_resource_id is null then
    raise exception using errcode = '22023', message = 'resource_id is required';
  end if;
  if v_observation_type = '' then
    raise exception using errcode = '22023', message = 'observation_type is required';
  end if;
  if p_observation_payload is null or jsonb_typeof(p_observation_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'observation_payload must be a JSON object';
  end if;
  if v_observer_ref = '' then
    raise exception using errcode = '22023', message = 'observer_ref is required';
  end if;
  if p_observed_at is null then
    raise exception using errcode = '22023', message = 'observed_at is required';
  end if;
  if v_idempotency_key = '' then
    raise exception using errcode = '22023', message = 'idempotency_key is required';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance) <> 'object' then
    raise exception using errcode = '22023', message = 'provenance must be a JSON object';
  end if;

  select r.resource_state
    into v_resource_state
    from reality.resources r
   where r.id = p_resource_id;

  if not found then
    raise exception using errcode = '23503', message = 'resource does not exist';
  end if;
  if v_resource_state <> 'active' then
    raise exception using errcode = '23514', message = 'resource must be active to accept a new observation';
  end if;

  if p_observer_entity_id is not null
     and not exists (select 1 from reality.entities e where e.id = p_observer_entity_id) then
    raise exception using errcode = '23503', message = 'observer_entity_id does not exist';
  end if;

  v_fingerprint := md5(jsonb_build_object(
    'resource_id', p_resource_id,
    'observation_type', v_observation_type,
    'observation_payload', p_observation_payload,
    'observer_ref', v_observer_ref,
    'observer_entity_id', p_observer_entity_id,
    'observed_at', p_observed_at,
    'provenance', p_provenance
  )::text);

  select *
    into v_existing
    from reality.resource_observations o
   where o.idempotency_scope = v_scope
     and o.idempotency_key = v_idempotency_key;

  if found then
    if v_existing.payload_fingerprint <> v_fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key already admitted with different observation content';
    end if;

    return jsonb_build_object(
      'state', 'replayed',
      'observationId', v_existing.id,
      'resourceId', v_existing.resource_id,
      'observationType', v_existing.observation_type,
      'observedAt', v_existing.observed_at,
      'recordedAt', v_existing.recorded_at,
      'payloadFingerprint', v_existing.payload_fingerprint
    );
  end if;

  insert into reality.resource_observations (
    resource_id,
    observation_type,
    observation_payload,
    observer_ref,
    observer_entity_id,
    observed_at,
    provenance,
    idempotency_scope,
    idempotency_key,
    payload_fingerprint
  ) values (
    p_resource_id,
    v_observation_type,
    p_observation_payload,
    v_observer_ref,
    p_observer_entity_id,
    p_observed_at,
    p_provenance,
    v_scope,
    v_idempotency_key,
    v_fingerprint
  )
  on conflict (idempotency_scope, idempotency_key) do nothing
  returning * into v_inserted;

  if v_inserted.id is null then
    select *
      into v_existing
      from reality.resource_observations o
     where o.idempotency_scope = v_scope
       and o.idempotency_key = v_idempotency_key;

    if not found or v_existing.payload_fingerprint <> v_fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key conflict';
    end if;

    return jsonb_build_object(
      'state', 'replayed',
      'observationId', v_existing.id,
      'resourceId', v_existing.resource_id,
      'observationType', v_existing.observation_type,
      'observedAt', v_existing.observed_at,
      'recordedAt', v_existing.recorded_at,
      'payloadFingerprint', v_existing.payload_fingerprint
    );
  end if;

  -- Canonical readback is part of admission. If the inserted source fact cannot be
  -- re-read here, the transaction fails instead of returning a false receipt.
  select *
    into v_existing
    from reality.resource_observations o
   where o.id = v_inserted.id
     and o.resource_id = p_resource_id
     and o.observation_type = v_observation_type
     and o.payload_fingerprint = v_fingerprint;

  if not found then
    raise exception using errcode = 'P0001', message = 'canonical observation readback failed';
  end if;

  return jsonb_build_object(
    'state', 'admitted',
    'observationId', v_existing.id,
    'resourceId', v_existing.resource_id,
    'observationType', v_existing.observation_type,
    'observedAt', v_existing.observed_at,
    'recordedAt', v_existing.recorded_at,
    'payloadFingerprint', v_existing.payload_fingerprint
  );
end;
$$;

revoke all on function reality.record_resource_observation_service_v1(uuid, text, jsonb, text, timestamptz, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function reality.record_resource_observation_service_v1(uuid, text, jsonb, text, timestamptz, text, uuid, jsonb) to service_role;

create or replace function reality.resolve_resource_observation_latest_v1(
  p_resource_id uuid,
  p_observation_type text,
  p_observed_as_of timestamptz default clock_timestamp(),
  p_recorded_as_of timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, reality
as $$
declare
  v_type text := btrim(coalesce(p_observation_type, ''));
  v_item reality.resource_observations%rowtype;
begin
  if p_resource_id is null or v_type = '' then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'invalid_observation_query',
      'resourceId', p_resource_id,
      'observationType', nullif(v_type, '')
    );
  end if;

  if not exists (select 1 from reality.resources r where r.id = p_resource_id) then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'resource_not_found',
      'resourceId', p_resource_id,
      'observationType', v_type
    );
  end if;

  select *
    into v_item
    from reality.resource_observations o
   where o.resource_id = p_resource_id
     and o.observation_type = v_type
     and o.observed_at <= p_observed_as_of
     and o.recorded_at <= p_recorded_as_of
   order by o.observed_at desc, o.recorded_at desc, o.id desc
   limit 1;

  if not found then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'no_admitted_observation',
      'resourceId', p_resource_id,
      'observationType', v_type,
      'observedAsOf', p_observed_as_of,
      'recordedAsOf', p_recorded_as_of
    );
  end if;

  return jsonb_build_object(
    'state', 'established_latest',
    'reason', 'latest_admitted_observation_found',
    'resourceId', v_item.resource_id,
    'observationId', v_item.id,
    'observationType', v_item.observation_type,
    'observationPayload', v_item.observation_payload,
    'observerRef', v_item.observer_ref,
    'observerEntityId', v_item.observer_entity_id,
    'observedAt', v_item.observed_at,
    'recordedAt', v_item.recorded_at,
    'provenance', v_item.provenance,
    'payloadFingerprint', v_item.payload_fingerprint
  );
end;
$$;

revoke all on function reality.resolve_resource_observation_latest_v1(uuid, text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function reality.resolve_resource_observation_latest_v1(uuid, text, timestamptz, timestamptz) to service_role;


create table if not exists atlas.organization_responsibility_resource_applicability (
  id uuid primary key default gen_random_uuid(),
  responsibility_scope_id uuid not null references atlas.organization_responsibility_scopes(id) on delete restrict,
  resource_id uuid not null references reality.resources(id) on delete restrict,
  operation_key text not null,
  effective_from timestamptz not null,
  effective_until timestamptz null,
  provenance jsonb not null default '{}'::jsonb,
  admitted_at timestamptz not null default clock_timestamp(),
  idempotency_scope text not null default 'atlas.responsibility_resource_applicability.v1',
  idempotency_key text not null,
  payload_fingerprint text not null,
  constraint responsibility_resource_applicability_operation_nonblank check (btrim(operation_key) <> ''),
  constraint responsibility_resource_applicability_window_check check (effective_until is null or effective_until > effective_from),
  constraint responsibility_resource_applicability_provenance_object check (jsonb_typeof(provenance) = 'object'),
  constraint responsibility_resource_applicability_idempotency_scope_nonblank check (btrim(idempotency_scope) <> ''),
  constraint responsibility_resource_applicability_idempotency_key_nonblank check (btrim(idempotency_key) <> ''),
  constraint responsibility_resource_applicability_fingerprint_nonblank check (btrim(payload_fingerprint) <> ''),
  constraint responsibility_resource_applicability_idempotency_uq unique (idempotency_scope, idempotency_key)
);

create index if not exists responsibility_resource_applicability_lookup_idx
  on atlas.organization_responsibility_resource_applicability
  (responsibility_scope_id, resource_id, operation_key, effective_from desc);

alter table atlas.organization_responsibility_resource_applicability enable row level security;
revoke all on table atlas.organization_responsibility_resource_applicability from public, anon, authenticated;
grant select, insert on table atlas.organization_responsibility_resource_applicability to service_role;

comment on table atlas.organization_responsibility_resource_applicability is
  'Governed applicability of one exact institutional Responsibility scope to one exact resource subject for one exact operation. This relation does not grant execution authority, create Work, or assign a Task.';

create or replace function atlas.admit_organization_responsibility_resource_applicability_service_v1(
  p_responsibility_scope_id uuid,
  p_resource_id uuid,
  p_operation_key text,
  p_effective_from timestamptz,
  p_effective_until timestamptz,
  p_idempotency_key text,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, atlas, reality
as $$
declare
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_idempotency_key text := btrim(coalesce(p_idempotency_key, ''));
  v_scope constant text := 'atlas.responsibility_resource_applicability.v1';
  v_fingerprint text;
  v_existing atlas.organization_responsibility_resource_applicability%rowtype;
  v_inserted atlas.organization_responsibility_resource_applicability%rowtype;
  v_org_id uuid;
  v_responsibility_id uuid;
  v_responsibility_status text;
  v_org_status text;
  v_resource_state text;
begin
  if p_responsibility_scope_id is null or p_resource_id is null then
    raise exception using errcode = '22023', message = 'responsibility_scope_id and resource_id are required';
  end if;
  if v_operation_key = '' then
    raise exception using errcode = '22023', message = 'operation_key is required';
  end if;
  if p_effective_from is null then
    raise exception using errcode = '22023', message = 'effective_from is required';
  end if;
  if p_effective_until is not null and p_effective_until <= p_effective_from then
    raise exception using errcode = '22023', message = 'effective_until must be later than effective_from';
  end if;
  if v_idempotency_key = '' then
    raise exception using errcode = '22023', message = 'idempotency_key is required';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance) <> 'object' then
    raise exception using errcode = '22023', message = 'provenance must be a JSON object';
  end if;

  select s.organization_id, s.responsibility_id, r.status, o.status
    into v_org_id, v_responsibility_id, v_responsibility_status, v_org_status
    from atlas.organization_responsibility_scopes s
    join atlas.organization_responsibilities r
      on r.id = s.responsibility_id
     and r.organization_id = s.organization_id
    join atlas.organizations o on o.id = s.organization_id
   where s.id = p_responsibility_scope_id;

  if not found then
    raise exception using errcode = '23503', message = 'responsibility scope does not exist or is structurally invalid';
  end if;
  if v_org_status <> 'active' or v_responsibility_status <> 'active' then
    raise exception using errcode = '23514', message = 'organization and Responsibility must be active when applicability is admitted';
  end if;

  select r.resource_state
    into v_resource_state
    from reality.resources r
   where r.id = p_resource_id;

  if not found then
    raise exception using errcode = '23503', message = 'resource does not exist';
  end if;
  if v_resource_state <> 'active' then
    raise exception using errcode = '23514', message = 'resource must be active when applicability is admitted';
  end if;

  v_fingerprint := md5(jsonb_build_object(
    'responsibility_scope_id', p_responsibility_scope_id,
    'resource_id', p_resource_id,
    'operation_key', v_operation_key,
    'effective_from', p_effective_from,
    'effective_until', p_effective_until,
    'provenance', p_provenance
  )::text);

  select *
    into v_existing
    from atlas.organization_responsibility_resource_applicability a
   where a.idempotency_scope = v_scope
     and a.idempotency_key = v_idempotency_key;

  if found then
    if v_existing.payload_fingerprint <> v_fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key already admitted with different applicability content';
    end if;

    return jsonb_build_object(
      'state', 'replayed',
      'applicabilityId', v_existing.id,
      'responsibilityScopeId', v_existing.responsibility_scope_id,
      'resourceId', v_existing.resource_id,
      'operationKey', v_existing.operation_key,
      'effectiveFrom', v_existing.effective_from,
      'effectiveUntil', v_existing.effective_until,
      'payloadFingerprint', v_existing.payload_fingerprint
    );
  end if;

  -- Serialize admissions for the same semantic relation so overlap checks remain
  -- correct under concurrent service calls without requiring a new extension.
  perform pg_advisory_xact_lock(hashtextextended(
    p_responsibility_scope_id::text || ':' || p_resource_id::text || ':' || v_operation_key,
    0
  ));

  if exists (
    select 1
      from atlas.organization_responsibility_resource_applicability a
     where a.responsibility_scope_id = p_responsibility_scope_id
       and a.resource_id = p_resource_id
       and a.operation_key = v_operation_key
       and tstzrange(a.effective_from, a.effective_until, '[)')
           && tstzrange(p_effective_from, p_effective_until, '[)')
  ) then
    raise exception using errcode = '23P01', message = 'applicability effective window overlaps an existing governed relation';
  end if;

  insert into atlas.organization_responsibility_resource_applicability (
    responsibility_scope_id,
    resource_id,
    operation_key,
    effective_from,
    effective_until,
    provenance,
    idempotency_scope,
    idempotency_key,
    payload_fingerprint
  ) values (
    p_responsibility_scope_id,
    p_resource_id,
    v_operation_key,
    p_effective_from,
    p_effective_until,
    p_provenance,
    v_scope,
    v_idempotency_key,
    v_fingerprint
  )
  on conflict (idempotency_scope, idempotency_key) do nothing
  returning * into v_inserted;

  if v_inserted.id is null then
    select *
      into v_existing
      from atlas.organization_responsibility_resource_applicability a
     where a.idempotency_scope = v_scope
       and a.idempotency_key = v_idempotency_key;

    if not found or v_existing.payload_fingerprint <> v_fingerprint then
      raise exception using errcode = '23505', message = 'idempotency key conflict';
    end if;

    return jsonb_build_object(
      'state', 'replayed',
      'applicabilityId', v_existing.id,
      'responsibilityScopeId', v_existing.responsibility_scope_id,
      'resourceId', v_existing.resource_id,
      'operationKey', v_existing.operation_key,
      'effectiveFrom', v_existing.effective_from,
      'effectiveUntil', v_existing.effective_until,
      'payloadFingerprint', v_existing.payload_fingerprint
    );
  end if;

  select *
    into v_existing
    from atlas.organization_responsibility_resource_applicability a
   where a.id = v_inserted.id
     and a.payload_fingerprint = v_fingerprint;

  if not found then
    raise exception using errcode = 'P0001', message = 'canonical applicability readback failed';
  end if;

  return jsonb_build_object(
    'state', 'admitted',
    'applicabilityId', v_existing.id,
    'responsibilityScopeId', v_existing.responsibility_scope_id,
    'resourceId', v_existing.resource_id,
    'operationKey', v_existing.operation_key,
    'effectiveFrom', v_existing.effective_from,
    'effectiveUntil', v_existing.effective_until,
    'payloadFingerprint', v_existing.payload_fingerprint
  );
end;
$$;

revoke all on function atlas.admit_organization_responsibility_resource_applicability_service_v1(uuid, uuid, text, timestamptz, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function atlas.admit_organization_responsibility_resource_applicability_service_v1(uuid, uuid, text, timestamptz, timestamptz, text, jsonb) to service_role;

create or replace function atlas.resolve_organization_responsibility_resource_applicability_current_v1(
  p_responsibility_scope_id uuid,
  p_resource_id uuid,
  p_operation_key text,
  p_as_of timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, atlas, reality
as $$
declare
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_scope atlas.organization_responsibility_scopes%rowtype;
  v_responsibility atlas.organization_responsibilities%rowtype;
  v_current_count integer;
  v_any_count integer;
  v_item atlas.organization_responsibility_resource_applicability%rowtype;
begin
  if p_responsibility_scope_id is null or p_resource_id is null or v_operation_key = '' then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'invalid_applicability_query'
    );
  end if;

  select * into v_scope
    from atlas.organization_responsibility_scopes s
   where s.id = p_responsibility_scope_id;
  if not found then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'responsibility_scope_not_found',
      'responsibilityScopeId', p_responsibility_scope_id,
      'resourceId', p_resource_id,
      'operationKey', v_operation_key
    );
  end if;

  select * into v_responsibility
    from atlas.organization_responsibilities r
   where r.id = v_scope.responsibility_id
     and r.organization_id = v_scope.organization_id;
  if not found then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'responsibility_scope_source_invalid',
      'responsibilityScopeId', p_responsibility_scope_id,
      'resourceId', p_resource_id,
      'operationKey', v_operation_key
    );
  end if;

  if not exists (select 1 from reality.resources r where r.id = p_resource_id) then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'resource_not_found',
      'responsibilityScopeId', p_responsibility_scope_id,
      'resourceId', p_resource_id,
      'operationKey', v_operation_key
    );
  end if;

  select count(*)::integer,
         count(*) filter (
           where a.effective_from <= p_as_of
             and (a.effective_until is null or p_as_of < a.effective_until)
         )::integer
    into v_any_count, v_current_count
    from atlas.organization_responsibility_resource_applicability a
   where a.responsibility_scope_id = p_responsibility_scope_id
     and a.resource_id = p_resource_id
     and a.operation_key = v_operation_key;

  if v_current_count > 1 then
    return jsonb_build_object(
      'state', 'indeterminate',
      'reason', 'multiple_current_applicability_rows',
      'responsibilityScopeId', p_responsibility_scope_id,
      'resourceId', p_resource_id,
      'operationKey', v_operation_key,
      'asOf', p_as_of
    );
  end if;

  if v_current_count = 0 then
    if v_any_count = 0 then
      return jsonb_build_object(
        'state', 'indeterminate',
        'reason', 'applicability_not_recorded',
        'responsibilityScopeId', p_responsibility_scope_id,
        'resourceId', p_resource_id,
        'operationKey', v_operation_key,
        'asOf', p_as_of
      );
    end if;

    return jsonb_build_object(
      'state', 'established_not_current',
      'reason', 'applicability_exists_but_not_current',
      'responsibilityScopeId', p_responsibility_scope_id,
      'resourceId', p_resource_id,
      'operationKey', v_operation_key,
      'asOf', p_as_of
    );
  end if;

  select *
    into v_item
    from atlas.organization_responsibility_resource_applicability a
   where a.responsibility_scope_id = p_responsibility_scope_id
     and a.resource_id = p_resource_id
     and a.operation_key = v_operation_key
     and a.effective_from <= p_as_of
     and (a.effective_until is null or p_as_of < a.effective_until)
   order by a.effective_from desc, a.admitted_at desc, a.id desc
   limit 1;

  return jsonb_build_object(
    'state', 'established_current',
    'reason', 'current_responsibility_resource_applicability_established',
    'currentOnly', true,
    'asOf', p_as_of,
    'item', jsonb_build_object(
      'applicabilityId', v_item.id,
      'organizationId', v_scope.organization_id,
      'responsibilityId', v_scope.responsibility_id,
      'responsibilityKey', v_responsibility.stable_key,
      'responsibilityKind', v_responsibility.responsibility_kind,
      'responsibilityScopeId', v_scope.id,
      'scopeKind', v_scope.scope_kind,
      'scopeId', v_scope.scope_id,
      'scopeRelationKind', v_scope.relation_kind,
      'resourceId', v_item.resource_id,
      'operationKey', v_item.operation_key,
      'effectiveFrom', v_item.effective_from,
      'effectiveUntil', v_item.effective_until,
      'provenance', v_item.provenance,
      'admittedAt', v_item.admitted_at
    )
  );
end;
$$;

revoke all on function atlas.resolve_organization_responsibility_resource_applicability_current_v1(uuid, uuid, text, timestamptz) from public, anon, authenticated;
grant execute on function atlas.resolve_organization_responsibility_resource_applicability_current_v1(uuid, uuid, text, timestamptz) to service_role;
