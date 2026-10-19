begin;

-- Build 5 continuation, Slice D0. Correct the known seat -> unrestricted
-- native action-history escalation BEFORE authorizing any new worker seat.
-- Preserve the released root-owner workspace behavior behind a private,
-- explicitly non-executable function for API roles.
alter function atlas.ledger_workspace_self_api_v1(uuid)
  rename to ledger_workspace_unfiltered_internal_v1;
revoke all on function atlas.ledger_workspace_unfiltered_internal_v1(uuid)
  from public,anon,authenticated,service_role;

-- Seat participation conveys the shared Ledger identity. It does not by
-- itself convey finance, customer, action history or legacy source records.
-- Explicit per-action worker permits are a later separately tested contract.
create function atlas.ledger_workspace_self_api_v1(p_ledger_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_access jsonb;
  v_ledger ledger.ledgers%rowtype;
  v_subject_name text;
  v_is_root boolean:=false;
  v_full jsonb;
begin
  v_access:=atlas.reality_access_self_api_v1();
  if auth.uid() is null or p_ledger_id is null
    or v_access->>'state' is distinct from 'ready'
    or v_access->>'authenticated' is distinct from 'true'
    or not exists (
      select 1 from jsonb_array_elements(
        coalesce(v_access->'ledgerSeats','[]'::jsonb)) seat
      where seat->>'ledgerId'=p_ledger_id::text
        and seat->>'seatState'='active'
        and seat->>'ledgerState'='active'
    ) then
    raise exception 'No current authorized Ledger seat' using errcode='42501';
  end if;

  select l.* into v_ledger
  from ledger.ledgers l
  join reality.entities e on e.id=l.subject_entity_id
    and e.identity_state='canonical'
  where l.id=p_ledger_id and l.ledger_state='active'
    and l.retired_at is null;
  if v_ledger.id is null then
    raise exception 'Ledger unavailable' using errcode='42501';
  end if;
  select e.display_name into v_subject_name
  from reality.entities e where e.id=v_ledger.subject_entity_id
    and e.identity_state='canonical';

  begin
    perform 1 from atlas.capability_root_authority_context_self_v1(
      p_ledger_id);
    v_is_root:=true;
  exception when insufficient_privilege then
    v_is_root:=false;
  end;

  if v_is_root then
    -- Old full reader can only execute inside the proven exact root lane.
    v_full:=atlas.ledger_workspace_unfiltered_internal_v1(p_ledger_id);
    return v_full||jsonb_build_object(
      'truthBoundary',coalesce(v_full->'truthBoundary','{}'::jsonb)
        ||jsonb_build_object(
          'nativeFullHistoryRequiresExactRootAuthority',true,
          'seatAloneNeverGrantsSensitiveActionHistory',true));
  end if;

  -- Deliberately do not execute the old full reader for a seat-only actor.
  -- An authorized worker view of canonical Work must use separate exact
  -- assignment/permission projections, NEVER generic Ledger action history.
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_workspace_self_v1',
    'ledger',jsonb_build_object(
      'id',v_ledger.id,'name',v_ledger.name,
      'stableKey',v_ledger.stable_key,'subject',v_subject_name),
    'actions','[]'::jsonb,'operationalScope','seat_only',
    'farm',null,'tasks','[]'::jsonb,'sales','[]'::jsonb,
    'demand','[]'::jsonb,'events','[]'::jsonb,
    'registrations','[]'::jsonb,
    'truthBoundary',jsonb_build_object(
      'ledgerSeatGrantsWorkspaceReadOnly',true,
      'nativeFullHistoryRequiresExactRootAuthority',true,
      'seatAloneNeverGrantsSensitiveActionHistory',true,
      'workerWorkRequiresIndependentExactPermissionProjection',true,
      'noOperationalSourceRecordsReleasedBySeatAlone',true));
end
$fn$;
revoke all on function atlas.ledger_workspace_self_api_v1(uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.ledger_workspace_self_api_v1(uuid)
  to authenticated;

-- Replace the existing public SECURITY DEFINER wrapper with a thin
-- invoker. The actual privilege boundary lives in the atlas function.
create or replace function public.ledger_workspace_self_api_v1(
  p_ledger_id uuid)
returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.ledger_workspace_self_api_v1(p_ledger_id) $fn$;
revoke all on function public.ledger_workspace_self_api_v1(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.ledger_workspace_self_api_v1(uuid)
  to authenticated;

comment on function public.ledger_workspace_self_api_v1(uuid) is
  'An active native seat grants Ledger identity only. Full native action history and sensitive source facts require current root governing authority. Nonroot seat returns only safe Ledger identity, no financial/customer/owner history. Not a worker-Work permission grant.';

-- The entity-context API has the same seat-only flaw: it returns the
-- contact routes, context metadata, and last ledger.actions payload for
-- every entity. Unlike the safe Ledger shell above, these records have no
-- useful generic worker-safe projection. Deny them to nonroot callers.
alter function atlas.ledger_entity_contexts_self_api_v1(uuid,text)
  rename to ledger_entity_contexts_unfiltered_internal_v1;
revoke all on function atlas.ledger_entity_contexts_unfiltered_internal_v1(uuid,text)
  from public,anon,authenticated,service_role;

create function atlas.ledger_entity_contexts_self_api_v1(
  p_ledger_id uuid,p_context_kind text default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
begin
  if auth.uid() is null or p_ledger_id is null then
    raise exception 'Canonical signed-in Ledger required' using errcode='42501';
  end if;
  -- Full entity/contact/action-payload scope requires current root authority.
  -- The original internal reader independently checks the native seat.
  perform 1 from atlas.capability_root_authority_context_self_v1(p_ledger_id);
  return atlas.ledger_entity_contexts_unfiltered_internal_v1(
    p_ledger_id,p_context_kind);
end
$fn$;
revoke all on function atlas.ledger_entity_contexts_self_api_v1(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function atlas.ledger_entity_contexts_self_api_v1(uuid,text)
  to authenticated;

-- The temporal composer independently accepted a seat as authority for the
-- *entire* Ledger scheduling calendar, occurrence details, linked bookings,
-- prices and resource-claim snapshots. A worker's own assigned Work/Clock
-- projection must never borrow this unrestricted aggregate.
alter function atlas.ledger_temporal_composer_self_api_v1(uuid,date,date,text,integer)
  rename to ledger_temporal_composer_unfiltered_internal_v1;
revoke all on function atlas.ledger_temporal_composer_unfiltered_internal_v1(
  uuid,date,date,text,integer)
  from public,anon,authenticated,service_role;

create function atlas.ledger_temporal_composer_self_api_v1(
  p_ledger_id uuid,p_start_date date,p_end_date date,
  p_timezone_name text,p_limit integer default 5000)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
begin
  if auth.uid() is null or p_ledger_id is null then
    raise exception 'Signed-in exact Ledger required' using errcode='42501';
  end if;
  -- Root proof first: do not execute the broad temporal reader for a seat.
  -- The private original still requires an active native Ledger seat.
  perform 1 from atlas.capability_root_authority_context_self_v1(p_ledger_id);
  return atlas.ledger_temporal_composer_unfiltered_internal_v1(
    p_ledger_id,p_start_date,p_end_date,p_timezone_name,p_limit);
end
$fn$;
revoke all on function atlas.ledger_temporal_composer_self_api_v1(
  uuid,date,date,text,integer)
  from public,anon,authenticated,service_role;
grant execute on function atlas.ledger_temporal_composer_self_api_v1(
  uuid,date,date,text,integer)
  to authenticated;

commit;
