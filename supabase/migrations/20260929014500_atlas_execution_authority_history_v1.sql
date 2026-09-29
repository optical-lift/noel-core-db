-- Atlas Canonical Execution Authority History v1
--
-- Canonical history/read membrane for execution authority. Authority is addressed
-- only by canonical Reality coordinates: Person + Institution + Responsibility +
-- target + exact operation. Operational carriers (including Worker Day Execution
-- Leases) may be preserved in provenance, but their farm/membership/service-date
-- vocabulary is not canonical identity.
--
-- This migration does not allocate Work, create a task, establish a Principal
-- claim, admit Clock/Today state, or establish that the underlying work occurred.

create table if not exists atlas.execution_authority_history (
  event_id uuid primary key default gen_random_uuid(),
  authority_id uuid not null,
  person_entity_id uuid not null references reality.entities(id) on delete restrict,
  institution_entity_id uuid not null references reality.entities(id) on delete restrict,
  responsibility_entity_id uuid not null references reality.entities(id) on delete restrict,
  target_entity_id uuid not null references reality.entities(id) on delete restrict,
  operation_key text not null,
  authority_state text not null,
  authority_valid_from timestamptz not null,
  authority_valid_until timestamptz,
  effective_at timestamptz not null,
  carrier_kind text not null,
  carrier_id text not null,
  carrier_event_id text,
  evidence jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default statement_timestamp(),
  constraint execution_authority_operation_nonblank_v1
    check (btrim(operation_key)<>''),
  constraint execution_authority_state_v1
    check (authority_state in ('leased','started','interrupted','completed','withdrawn','expired')),
  constraint execution_authority_window_v1
    check (authority_valid_until is null or authority_valid_until>authority_valid_from),
  constraint execution_authority_carrier_kind_nonblank_v1
    check (btrim(carrier_kind)<>''),
  constraint execution_authority_carrier_id_nonblank_v1
    check (btrim(carrier_id)<>'')
);

create index if not exists execution_authority_history_exact_lookup_v1
  on atlas.execution_authority_history(
    person_entity_id,
    institution_entity_id,
    responsibility_entity_id,
    target_entity_id,
    operation_key,
    effective_at,
    event_id
  );

create index if not exists execution_authority_history_chain_v1
  on atlas.execution_authority_history(authority_id,effective_at,event_id);

comment on table atlas.execution_authority_history is
  'Append-history carrier for canonical execution authority coordinates. Legacy Worker Day identifiers may appear only in carrier provenance; they do not determine canonical Person, Institution, Responsibility, target, or operation identity.';

revoke all on table atlas.execution_authority_history
  from public,anon,authenticated,service_role;


-- One authority_id is one exact authority coordinate for its whole history. A
-- later event may change state, not subject, jurisdiction, operation, or window.
create or replace function atlas.enforce_execution_authority_chain_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if exists(
    select 1
    from atlas.execution_authority_history h
    where h.authority_id=new.authority_id
      and h.event_id<>new.event_id
      and (
        h.person_entity_id<>new.person_entity_id
        or h.institution_entity_id<>new.institution_entity_id
        or h.responsibility_entity_id<>new.responsibility_entity_id
        or h.target_entity_id<>new.target_entity_id
        or h.operation_key<>new.operation_key
        or h.authority_valid_from<>new.authority_valid_from
        or h.authority_valid_until is distinct from new.authority_valid_until
        or h.carrier_kind<>new.carrier_kind
        or h.carrier_id<>new.carrier_id
      )
  ) then
    raise exception 'Execution authority history cannot change canonical coordinates, authority window, or carrier identity within one authority_id.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

revoke all on function atlas.enforce_execution_authority_chain_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists enforce_execution_authority_chain_v1
  on atlas.execution_authority_history;

create trigger enforce_execution_authority_chain_v1
before insert or update on atlas.execution_authority_history
for each row execute function atlas.enforce_execution_authority_chain_v1();


create or replace function atlas.execution_authority_history_api_v1(
  p_person_entity_id uuid,
  p_institution_entity_id uuid,
  p_responsibility_entity_id uuid,
  p_target_entity_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person jsonb;
  v_institution jsonb;
  v_responsibility jsonb;
  v_target jsonb;
  v_history jsonb:='[]'::jsonb;
  v_captured_at timestamptz:=statement_timestamp();
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_person_entity_id is null then
    raise exception 'Canonical Person Entity is required.' using errcode='22023';
  end if;
  if p_institution_entity_id is null then
    raise exception 'Canonical Institution Entity is required.' using errcode='22023';
  end if;
  if p_responsibility_entity_id is null then
    raise exception 'Canonical Responsibility Entity is required.' using errcode='22023';
  end if;
  if p_target_entity_id is null then
    raise exception 'Canonical target Reality Entity is required.' using errcode='22023';
  end if;
  if p_operation_key is null or btrim(p_operation_key)='' then
    raise exception 'Exact operation key is required.' using errcode='22023';
  end if;

  perform reality.assert_canonical_entity_kind_v1(p_person_entity_id,'person');
  perform reality.assert_canonical_entity_kind_v1(p_responsibility_entity_id,'responsibility');

  select jsonb_build_object(
    'id',e.id,'stableKey',e.stable_key,'kind',e.entity_kind,
    'displayName',e.display_name,'identityState',e.identity_state
  ) into v_person
  from reality.entities e
  where e.id=p_person_entity_id and e.identity_state='canonical';

  select jsonb_build_object(
    'id',e.id,'stableKey',e.stable_key,'kind',e.entity_kind,
    'displayName',e.display_name,'identityState',e.identity_state
  ) into v_institution
  from reality.entities e
  where e.id=p_institution_entity_id and e.identity_state='canonical';

  select jsonb_build_object(
    'id',e.id,'stableKey',e.stable_key,'kind',e.entity_kind,
    'displayName',e.display_name,'identityState',e.identity_state
  ) into v_responsibility
  from reality.entities e
  where e.id=p_responsibility_entity_id and e.identity_state='canonical';

  select jsonb_build_object(
    'id',e.id,'stableKey',e.stable_key,'kind',e.entity_kind,
    'displayName',e.display_name,'identityState',e.identity_state
  ) into v_target
  from reality.entities e
  where e.id=p_target_entity_id and e.identity_state='canonical';

  if v_person is null then
    raise exception 'Canonical Person Reality Entity not found.' using errcode='P0002';
  end if;
  if v_institution is null then
    raise exception 'Canonical Institution Reality Entity not found.' using errcode='P0002';
  end if;
  if v_responsibility is null then
    raise exception 'Canonical Responsibility Reality Entity not found.' using errcode='P0002';
  end if;
  if v_target is null then
    raise exception 'Canonical target Reality Entity not found.' using errcode='P0002';
  end if;

  -- Return complete matching history rather than a current-state snapshot. Atlas
  -- resolves the latest event at or before its explicit as_of, so a later revoke,
  -- interruption, completion, or expiry cannot erase an earlier lawful state.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'eventId',h.event_id,
        'authorityId',h.authority_id,
        'personEntityId',h.person_entity_id,
        'institutionEntityId',h.institution_entity_id,
        'responsibilityEntityId',h.responsibility_entity_id,
        'targetEntityId',h.target_entity_id,
        'operationKey',h.operation_key,
        'authorityState',h.authority_state,
        'authorityValidFrom',h.authority_valid_from,
        'authorityValidUntil',h.authority_valid_until,
        'effectiveAt',h.effective_at,
        'carrierKind',h.carrier_kind,
        'carrierId',h.carrier_id,
        'carrierEventId',h.carrier_event_id,
        'evidence',h.evidence,
        'provenance',h.provenance,
        'createdAt',h.created_at
      )
      order by h.effective_at,h.event_id
    ),
    '[]'::jsonb
  ) into v_history
  from atlas.execution_authority_history h
  where h.person_entity_id=p_person_entity_id
    and h.institution_entity_id=p_institution_entity_id
    and h.responsibility_entity_id=p_responsibility_entity_id
    and h.target_entity_id=p_target_entity_id
    and h.operation_key=p_operation_key;

  return jsonb_build_object(
    'contractVersion','execution_authority_history_v1',
    'state','ready',
    'capturedAt',v_captured_at,
    'person',v_person,
    'institution',v_institution,
    'responsibility',v_responsibility,
    'target',v_target,
    'operationKey',p_operation_key,
    'history',v_history,
    'completeness',jsonb_build_object(
      'complete',true,
      'exactPersonEntityId',p_person_entity_id,
      'exactInstitutionEntityId',p_institution_entity_id,
      'exactResponsibilityEntityId',p_responsibility_entity_id,
      'exactTargetEntityId',p_target_entity_id,
      'exactOperationKey',p_operation_key,
      'includesAllAuthorityStates',true,
      'includesAllMatchingAuthorityChains',true,
      'historicalEventsPreserved',true,
      'laterEventsDoNotReplaceEarlierEvents',true
    ),
    'truthBoundary',jsonb_build_object(
      'readDoesNotCreateReality',true,
      'workerDayIdentifiersAcceptedAsCanonicalIdentity',false,
      'executionAuthorityWarrantCreated',false,
      'workAllocationCreated',false,
      'taskCreated',false,
      'principalClaimCreated',false,
      'clockOrTodayStateCreated',false,
      'workPerformedEstablished',false,
      'terminalAuthorityStateEstablishesUnderlyingSubjectOutcome',false
    )
  );
end
$function$;

revoke all on function atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text)
  from public,anon,authenticated,service_role;

grant execute on function atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text)
  to authenticated;

comment on function atlas.execution_authority_history_api_v1(uuid,uuid,uuid,uuid,text) is
  'Complete canonical Execution Authority history for one exact Person + Institution + Responsibility + target + operation coordinate. The read preserves revocation/interruption history and does not create a warrant, allocate Work, admit Clock/Today state, or establish work performance.';
