-- Important Dates is a capture/routing membrane, not a generic household_events writer.
--
-- A date can be durable testimony before Atlas knows the final owning domain. The intake preserves:
--   * what the Principal said the date is about;
--   * the exact calendar date supplied;
--   * whether it is one-time, yearly, or not yet resolved;
--   * optional local clock testimony;
--   * the user-confirmed reality kind.
--
-- V1 delegates only a one-time, timed, explicitly household/family commitment to household_events.
-- Personal appointments, personal dates/milestones, relationship dates such as birthdays/anniversaries,
-- deadlines, yearly recurrence, and unclear dates remain visible captured truth until their owning
-- person/relationship/deadline recurrence authorities are mapped.
--
-- Missing time never becomes midnight or a default appointment window. Browser timezone is not authority;
-- household-local time is interpreted through the established household timezone.

create table if not exists atlas.principal_important_date_intakes (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  household_id uuid references atlas.households(id) on delete set null,
  source_key text not null,
  testimony text not null,
  reality_kind text not null check (reality_kind in (
    'household_commitment',
    'personal_commitment',
    'relationship_date',
    'personal_date',
    'deadline',
    'unresolved'
  )),
  calendar_date date not null,
  recurrence_kind text not null default 'none' check (recurrence_kind in ('none','yearly','unknown')),
  start_local time without time zone,
  end_local time without time zone,
  affects_principal_time boolean,
  timezone_snapshot text,
  routing_state text not null default 'captured' check (routing_state in ('captured','routed','unresolved','retired')),
  routing_reason text,
  routed_domain text,
  routed_kind text,
  routed_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_key),
  check ((start_local is null and end_local is null) or (start_local is not null and end_local is not null)),
  check (start_local is null or end_local > start_local)
);

create index if not exists principal_important_date_intakes_owner_date_idx
  on atlas.principal_important_date_intakes(owner_user_id,calendar_date,routing_state);

alter table atlas.principal_important_date_intakes enable row level security;
revoke all on atlas.principal_important_date_intakes from public,anon,authenticated;

create or replace function atlas.capture_personal_important_date_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_source_key text;
  v_testimony text;
  v_kind text;
  v_calendar_date date;
  v_recurrence text;
  v_start_local time without time zone;
  v_end_local time without time zone;
  v_affects boolean;
  v_intake atlas.principal_important_date_intakes%rowtype;
  v_existing atlas.principal_important_date_intakes%rowtype;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_event jsonb;
  v_event_id text;
  v_routed boolean := false;
  v_routing_state text;
  v_routing_reason text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Important date input must be an object.' using errcode='22023';
  end if;

  select * into v_principal
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal.id is null or v_principal.active_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select * into v_household
  from atlas.households h
  where h.id=v_principal.active_household_id and h.status='active';
  if v_household.id is null then raise exception 'Active household required.' using errcode='42501'; end if;

  v_source_key:=nullif(trim(p_input->>'sourceKey'),'');
  v_testimony:=nullif(trim(p_input->>'testimony'),'');
  v_kind:=nullif(trim(p_input->>'realityKind'),'');
  v_calendar_date:=nullif(trim(p_input->>'calendarDate'),'')::date;
  v_recurrence:=coalesce(nullif(trim(p_input->>'recurrenceKind'),''),'none');
  v_start_local:=nullif(trim(p_input->>'startLocal'),'')::time;
  v_end_local:=nullif(trim(p_input->>'endLocal'),'')::time;

  if p_input ? 'affectsPrincipalTime' and jsonb_typeof(p_input->'affectsPrincipalTime')='boolean' then
    v_affects:=(p_input->>'affectsPrincipalTime')::boolean;
  end if;

  if v_source_key is null or v_testimony is null or v_calendar_date is null then
    raise exception 'sourceKey, testimony, and calendarDate are required.' using errcode='22023';
  end if;
  if v_kind not in ('household_commitment','personal_commitment','relationship_date','personal_date','deadline','unresolved') then
    raise exception 'Unsupported important date reality kind.' using errcode='22023';
  end if;
  if v_recurrence not in ('none','yearly','unknown') then
    raise exception 'recurrenceKind must be none, yearly, or unknown.' using errcode='22023';
  end if;
  if (v_start_local is null) <> (v_end_local is null) then
    raise exception 'Important date clock time must include both start and end, or neither.' using errcode='22023';
  end if;
  if v_start_local is not null and v_end_local<=v_start_local then
    raise exception 'Important date end time must be after start time on the same day.' using errcode='22023';
  end if;
  if v_kind='household_commitment' and v_affects is null then
    raise exception 'Household commitment requires an explicit affectsPrincipalTime answer.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.principal_important_date_intakes i
  where i.owner_user_id=v_user_id and i.source_key=v_source_key;

  if v_existing.id is not null then
    if v_existing.testimony is distinct from v_testimony
      or v_existing.reality_kind is distinct from v_kind
      or v_existing.calendar_date is distinct from v_calendar_date
      or v_existing.recurrence_kind is distinct from v_recurrence
      or v_existing.start_local is distinct from v_start_local
      or v_existing.end_local is distinct from v_end_local
      or v_existing.affects_principal_time is distinct from v_affects then
      raise exception 'sourceKey retry does not match existing important date intake.' using errcode='23505';
    end if;
    v_intake:=v_existing;
  else
    insert into atlas.principal_important_date_intakes(
      principal_id,owner_user_id,household_id,source_key,testimony,reality_kind,
      calendar_date,recurrence_kind,start_local,end_local,affects_principal_time,
      timezone_snapshot,routing_state,routing_reason,metadata
    ) values(
      v_principal.id,v_user_id,v_household.id,v_source_key,v_testimony,v_kind,
      v_calendar_date,v_recurrence,v_start_local,v_end_local,v_affects,
      v_household.timezone,'captured',null,
      jsonb_build_object(
        'source','personal_important_date_intake_v1',
        'userConfirmedRealityKind',true,
        'dateWasExplicitlySupplied',true,
        'clockTimeWasExplicitlySupplied',(v_start_local is not null)
      )
    ) returning * into v_intake;
  end if;

  if v_kind='household_commitment'
    and v_recurrence='none'
    and v_start_local is not null
    and v_end_local is not null then

    v_starts_at:=(v_calendar_date+v_start_local) at time zone v_household.timezone;
    v_ends_at:=(v_calendar_date+v_end_local) at time zone v_household.timezone;

    v_event:=atlas.principal_upsert_household_event_api_v1(jsonb_build_object(
      'stableKey','important-date:'||v_intake.id::text,
      'title',v_testimony,
      'eventKind','family_commitment',
      'startsAt',v_starts_at,
      'endsAt',v_ends_at,
      'fixed',true,
      'blocksCapacity',v_affects,
      'expectedMinutes',extract(epoch from (v_ends_at-v_starts_at))::integer/60,
      'protectionLevel','critical',
      'floorClass',1,
      'interruptibility','should_not_interrupt',
      'principalRequired',v_affects,
      'reasonForFloor','User-confirmed one-time household/family commitment captured through Important Dates.',
      'source','personal_important_date_intake_v1',
      'metadata',jsonb_build_object(
        'importantDateIntakeId',v_intake.id,
        'calendarDate',v_calendar_date,
        'startLocal',v_start_local::text,
        'endLocal',v_end_local::text,
        'authoringTimezone',v_household.timezone,
        'realityKind',v_kind,
        'recurrenceKind',v_recurrence,
        'affectsPrincipalTime',v_affects
      )
    ));

    v_event_id:=v_event#>>'{event,id}';
    v_routed:=true;
    v_routing_state:='routed';
    v_routing_reason:='one_time_timed_household_commitment';
  else
    v_routing_state:='unresolved';
    v_routing_reason:=case
      when v_kind='household_commitment' and v_recurrence='yearly' then 'annual_recurrence_authority_not_mapped'
      when v_kind='household_commitment' and v_recurrence='unknown' then 'recurrence_not_resolved'
      when v_kind='household_commitment' and v_start_local is null then 'household_commitment_clock_time_not_established'
      when v_kind='personal_commitment' then 'personal_calendar_commitment_authority_not_mapped'
      when v_kind='relationship_date' then 'relationship_date_authority_not_mapped'
      when v_kind='personal_date' then 'personal_date_authority_not_mapped'
      when v_kind='deadline' then 'deadline_authority_not_mapped'
      else 'owning_domain_not_resolved'
    end;
  end if;

  update atlas.principal_important_date_intakes
  set routing_state=v_routing_state,
      routing_reason=v_routing_reason,
      routed_domain=case when v_routed then 'household' else null end,
      routed_kind=case when v_routed then 'household_event' else null end,
      routed_id=case when v_routed then v_event_id else null end,
      updated_at=now()
  where id=v_intake.id
  returning * into v_intake;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_important_date_intake_v1',
    'intake',jsonb_build_object(
      'id',v_intake.id,
      'testimony',v_intake.testimony,
      'realityKind',v_intake.reality_kind,
      'calendarDate',v_intake.calendar_date,
      'recurrenceKind',v_intake.recurrence_kind,
      'startLocal',v_intake.start_local,
      'endLocal',v_intake.end_local,
      'affectsPrincipalTime',v_intake.affects_principal_time,
      'timezone',v_intake.timezone_snapshot,
      'routingState',v_intake.routing_state,
      'routingReason',v_intake.routing_reason,
      'routedDomain',v_intake.routed_domain,
      'routedKind',v_intake.routed_kind,
      'routedId',v_intake.routed_id
    ),
    'routed',v_routed,
    'householdEvent',case when v_routed then v_event else null end,
    'message',case
      when v_routed then 'This date now belongs to household event authority.'
      else 'Captured. The owning date authority is still being mapped.'
    end,
    'truthBoundary',jsonb_build_object(
      'intakePreservesUserTestimony',true,
      'calendarDateIsDurableTestimony',true,
      'missingTimeDoesNotBecomeMidnight',true,
      'missingTimeDoesNotBecomeDefaultWindow',true,
      'browserTimezoneIsNotAuthority',true,
      'householdEventOnlyForExplicitHouseholdCommitment',true,
      'yearlyDateDoesNotBecomeOneTimeEvent',true,
      'personalAppointmentNotRelabeledAsHousehold',true,
      'relationshipDateNotRelabeledAsHousehold',true,
      'deadlineNotRelabeledAsHousehold',true
    )
  );
end;
$function$;

create or replace function atlas.personal_important_dates_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_timezone text;
  v_items jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select p.id,p.active_household_id,h.timezone
  into v_principal_id,v_household_id,v_timezone
  from atlas.principals p
  left join atlas.households h on h.id=p.active_household_id and h.status='active'
  where p.user_id=v_user_id and p.status='active'
  limit 1;

  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',i.id,
    'testimony',i.testimony,
    'realityKind',i.reality_kind,
    'calendarDate',i.calendar_date,
    'recurrenceKind',i.recurrence_kind,
    'startLocal',i.start_local,
    'endLocal',i.end_local,
    'affectsPrincipalTime',i.affects_principal_time,
    'timezone',i.timezone_snapshot,
    'routingState',i.routing_state,
    'routingReason',i.routing_reason,
    'routedDomain',i.routed_domain,
    'routedKind',i.routed_kind,
    'routedId',i.routed_id,
    'createdAt',i.created_at
  ) order by i.calendar_date,i.start_local nulls last,i.created_at,i.id),'[]'::jsonb)
  into v_items
  from atlas.principal_important_date_intakes i
  where i.owner_user_id=v_user_id
    and i.principal_id=v_principal_id
    and i.routing_state<>'retired';

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_important_dates_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'timezone',v_timezone,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'intakeIsCaptureAndRoutingEvidence',true,
      'intakeDoesNotReplaceOwningDomain',true,
      'unroutedDatesRemainVisible',true,
      'dateOnlyTruthIsAllowed',true
    )
  );
end;
$function$;

revoke all on function atlas.capture_personal_important_date_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.personal_important_dates_self_api_v1() from public,anon;
grant execute on function atlas.capture_personal_important_date_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.personal_important_dates_self_api_v1() to authenticated,service_role;

create or replace function public.capture_personal_important_date_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.capture_personal_important_date_self_api_v1(p_input); $function$;

create or replace function public.personal_important_dates_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_important_dates_self_api_v1(); $function$;

revoke all on function public.capture_personal_important_date_self_api_v1(jsonb) from public,anon;
revoke all on function public.personal_important_dates_self_api_v1() from public,anon;
grant execute on function public.capture_personal_important_date_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.personal_important_dates_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  (
    'atlas.capture_personal_important_date_self_api_v1(p_input jsonb)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object(
      'purpose','Capture an important calendar date without guessing its final domain; delegate only one-time timed user-confirmed household/family commitments to household event authority.',
      'dateOnlyAllowed',true,
      'browserTimezoneAuthority',false
    ),now()
  ),
  (
    'atlas.personal_important_dates_self_api_v1()',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Read Important Date capture/routing evidence for the authenticated Principal without replacing owning-domain reads.'),now()
  )
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();
