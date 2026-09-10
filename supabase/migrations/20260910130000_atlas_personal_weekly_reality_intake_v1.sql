-- Weekly setup is a routing membrane, not a generic household_rhythms writer.
-- The intake preserves exactly what the Principal said, the user-confirmed scope/kind, and any timing testimony.
-- Only weekly realities that are explicitly household-level are delegated to household_rhythms in v1.
-- Personal and relationship rhythms remain captured but unresolved until their owning domain surfaces are mapped.

create table if not exists atlas.principal_weekly_reality_intakes (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  household_id uuid references atlas.households(id) on delete set null,
  source_key text not null,
  testimony text not null,
  reality_kind text not null check (reality_kind in (
    'household_operation','household_commitment','personal_rhythm','relationship_rhythm','unresolved'
  )),
  weekday_iso smallint check (weekday_iso between 1 and 7),
  start_local time without time zone,
  expected_minutes integer check (expected_minutes is null or expected_minutes > 0),
  affects_principal_time boolean,
  timezone_snapshot text,
  routing_state text not null default 'captured' check (routing_state in ('captured','routed','unresolved','retired')),
  routed_domain text,
  routed_kind text,
  routed_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_key)
);

alter table atlas.principal_weekly_reality_intakes enable row level security;
revoke all on atlas.principal_weekly_reality_intakes from public,anon,authenticated;

create or replace function atlas.next_weekly_local_occurrence_v1(
  p_timezone text,
  p_weekday_iso integer,
  p_start_local time without time zone,
  p_as_of timestamptz default now()
)
returns timestamptz
language plpgsql
stable
set search_path=pg_catalog
as $function$
declare
  v_local_now timestamp without time zone;
  v_local_date date;
  v_candidate timestamp without time zone;
  v_days_ahead integer;
begin
  if nullif(trim(p_timezone),'') is null then raise exception 'timezone required.' using errcode='22023'; end if;
  if p_weekday_iso not between 1 and 7 then raise exception 'weekday must be ISO 1 through 7.' using errcode='22023'; end if;
  if p_start_local is null then raise exception 'local start time required.' using errcode='22023'; end if;

  v_local_now:=coalesce(p_as_of,now()) at time zone p_timezone;
  v_local_date:=v_local_now::date;
  v_days_ahead:=(p_weekday_iso-extract(isodow from v_local_date)::integer+7)%7;
  v_candidate:=(v_local_date+v_days_ahead)+p_start_local;
  if v_candidate<=v_local_now then v_candidate:=v_candidate+interval '7 days'; end if;
  return v_candidate at time zone p_timezone;
end;
$function$;

create or replace function atlas.capture_personal_weekly_reality_self_api_v1(p_input jsonb)
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
  v_weekday integer;
  v_start_local time without time zone;
  v_expected integer;
  v_affects boolean;
  v_intake atlas.principal_weekly_reality_intakes%rowtype;
  v_existing atlas.principal_weekly_reality_intakes%rowtype;
  v_next_start timestamptz;
  v_next_end timestamptz;
  v_rhythm jsonb;
  v_rhythm_id text;
  v_routed boolean := false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Weekly reality input must be an object.' using errcode='22023'; end if;

  select * into v_principal from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal.id is null or v_principal.active_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  select * into v_household from atlas.households h where h.id=v_principal.active_household_id and h.status='active';
  if v_household.id is null then raise exception 'Active household required.' using errcode='42501'; end if;

  v_source_key:=nullif(trim(p_input->>'sourceKey'),'');
  v_testimony:=nullif(trim(p_input->>'testimony'),'');
  v_kind:=nullif(trim(p_input->>'realityKind'),'');
  v_weekday:=nullif(trim(p_input->>'weekdayIso'),'')::integer;
  v_start_local:=nullif(trim(p_input->>'startLocal'),'')::time;
  v_expected:=nullif(trim(p_input->>'expectedMinutes'),'')::integer;
  if p_input ? 'affectsPrincipalTime' and jsonb_typeof(p_input->'affectsPrincipalTime')='boolean' then
    v_affects:=(p_input->>'affectsPrincipalTime')::boolean;
  end if;

  if v_source_key is null or v_testimony is null then raise exception 'sourceKey and testimony are required.' using errcode='22023'; end if;
  if v_kind not in ('household_operation','household_commitment','personal_rhythm','relationship_rhythm','unresolved') then
    raise exception 'Unsupported weekly reality kind.' using errcode='22023';
  end if;
  if v_weekday is not null and v_weekday not between 1 and 7 then raise exception 'weekdayIso must be 1 through 7.' using errcode='22023'; end if;
  if v_start_local is not null and v_weekday is null then raise exception 'A local time requires a weekday.' using errcode='22023'; end if;
  if v_expected is not null and v_expected<=0 then raise exception 'expectedMinutes must be positive.' using errcode='22023'; end if;

  if v_kind in ('household_operation','household_commitment') then
    if v_expected is null then raise exception 'Household weekly reality requires expectedMinutes.' using errcode='22023'; end if;
    if v_affects is null then raise exception 'Household weekly reality requires an explicit affectsPrincipalTime answer.' using errcode='22023'; end if;
  end if;

  select * into v_existing
  from atlas.principal_weekly_reality_intakes i
  where i.owner_user_id=v_user_id and i.source_key=v_source_key;

  if v_existing.id is not null then
    if v_existing.testimony is distinct from v_testimony
      or v_existing.reality_kind is distinct from v_kind
      or v_existing.weekday_iso is distinct from v_weekday
      or v_existing.start_local is distinct from v_start_local
      or v_existing.expected_minutes is distinct from v_expected
      or v_existing.affects_principal_time is distinct from v_affects then
      raise exception 'sourceKey retry does not match existing weekly reality intake.' using errcode='23505';
    end if;
    v_intake:=v_existing;
  else
    insert into atlas.principal_weekly_reality_intakes(
      principal_id,owner_user_id,household_id,source_key,testimony,reality_kind,
      weekday_iso,start_local,expected_minutes,affects_principal_time,timezone_snapshot,
      routing_state,metadata
    ) values(
      v_principal.id,v_user_id,v_household.id,v_source_key,v_testimony,v_kind,
      v_weekday,v_start_local,v_expected,v_affects,v_household.timezone,
      case when v_kind in ('household_operation','household_commitment') then 'captured' else 'unresolved' end,
      jsonb_build_object('source','personal_weekly_reality_intake_v1','userConfirmedRealityKind',true)
    ) returning * into v_intake;
  end if;

  if v_kind in ('household_operation','household_commitment') then
    if v_weekday is not null and v_start_local is not null then
      v_next_start:=atlas.next_weekly_local_occurrence_v1(v_household.timezone,v_weekday,v_start_local,now());
      v_next_end:=v_next_start+make_interval(mins=>v_expected);
    end if;

    v_rhythm:=atlas.principal_upsert_household_rhythm_api_v1(jsonb_strip_nulls(jsonb_build_object(
      'stableKey','weekly-reality:'||v_intake.id::text,
      'area',v_kind,
      'title',v_testimony,
      'cadenceRule','weekly',
      'nextWindowStart',v_next_start,
      'nextWindowEnd',v_next_end,
      'expectedMinutes',v_expected,
      'protectionLevel',case when v_kind='household_commitment' then 'protected' else 'flexible' end,
      'floorClass',case when v_kind='household_commitment' then 2 else 3 end,
      'interruptibility',case when v_kind='household_commitment' then 'should_not_interrupt' else 'interruptible' end,
      'principalRequired',v_affects,
      'blocksCapacity',v_affects,
      'reasonForFloor',case when v_kind='household_commitment' then 'User-confirmed recurring household commitment.' else 'User-confirmed recurring household operation.' end,
      'metadata',jsonb_strip_nulls(jsonb_build_object(
        'source','personal_weekly_reality_intake_v1',
        'weeklyRealityIntakeId',v_intake.id,
        'realityKind',v_kind,
        'semanticCadence',true,
        'weekdayIso',v_weekday,
        'startLocal',case when v_start_local is null then null else v_start_local::text end,
        'authoringTimezone',v_household.timezone,
        'clockWindowEstablished',(v_next_start is not null),
        'affectsPrincipalTime',v_affects
      ))
    )));
    v_rhythm_id:=coalesce(v_rhythm#>>'{rhythm,id}',v_rhythm->>'id');
    v_routed:=true;

    update atlas.principal_weekly_reality_intakes
    set routing_state='routed',routed_domain='household',routed_kind='household_rhythm',routed_id=v_rhythm_id,updated_at=now()
    where id=v_intake.id
    returning * into v_intake;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_weekly_reality_intake_v1',
    'intake',jsonb_build_object(
      'id',v_intake.id,
      'testimony',v_intake.testimony,
      'realityKind',v_intake.reality_kind,
      'weekdayIso',v_intake.weekday_iso,
      'startLocal',v_intake.start_local,
      'expectedMinutes',v_intake.expected_minutes,
      'affectsPrincipalTime',v_intake.affects_principal_time,
      'routingState',v_intake.routing_state,
      'routedDomain',v_intake.routed_domain,
      'routedKind',v_intake.routed_kind,
      'routedId',v_intake.routed_id
    ),
    'routed',v_routed,
    'householdRhythm',case when v_routed then v_rhythm else null end,
    'message',case
      when v_routed then 'This weekly reality now belongs to household rhythm authority.'
      else 'Captured. The owning domain for this weekly reality is still being mapped.'
    end,
    'truthBoundary',jsonb_build_object(
      'intakePreservesUserTestimony',true,
      'userConfirmsRealityKind',true,
      'householdRhythmOnlyForHouseholdReality',true,
      'personalAndRelationshipRealityNotRelabeledAsHousehold',true,
      'missingWeekdayDoesNotInventADay',true,
      'missingTimeDoesNotInventAClockWindow',true
    )
  );
end;
$function$;

create or replace function atlas.personal_weekly_reality_self_api_v1()
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
  v_items jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id,p.active_household_id into v_principal_id,v_household_id
  from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',i.id,
    'testimony',i.testimony,
    'realityKind',i.reality_kind,
    'weekdayIso',i.weekday_iso,
    'startLocal',i.start_local,
    'expectedMinutes',i.expected_minutes,
    'affectsPrincipalTime',i.affects_principal_time,
    'routingState',i.routing_state,
    'routedDomain',i.routed_domain,
    'routedKind',i.routed_kind,
    'routedId',i.routed_id,
    'createdAt',i.created_at
  ) order by i.created_at,i.id),'[]'::jsonb)
  into v_items
  from atlas.principal_weekly_reality_intakes i
  where i.owner_user_id=v_user_id and i.principal_id=v_principal_id and i.routing_state<>'retired';

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_weekly_reality_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'count',jsonb_array_length(v_items),
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'intakeIsCaptureAndRoutingEvidence',true,
      'intakeDoesNotReplaceOwningDomain',true,
      'unroutedItemsRemainVisible',true
    )
  );
end;
$function$;

revoke all on function atlas.capture_personal_weekly_reality_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.personal_weekly_reality_self_api_v1() from public,anon;
grant execute on function atlas.capture_personal_weekly_reality_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.personal_weekly_reality_self_api_v1() to authenticated,service_role;

create or replace function public.capture_personal_weekly_reality_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.capture_personal_weekly_reality_self_api_v1(p_input); $function$;

create or replace function public.personal_weekly_reality_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_weekly_reality_self_api_v1(); $function$;

revoke all on function public.capture_personal_weekly_reality_self_api_v1(jsonb) from public,anon;
revoke all on function public.personal_weekly_reality_self_api_v1() from public,anon;
grant execute on function public.capture_personal_weekly_reality_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.personal_weekly_reality_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.capture_personal_weekly_reality_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,
   jsonb_build_object('purpose','Capture weekly testimony, preserve user-confirmed scope/kind, and delegate only explicit household-level recurrence to household rhythm authority.'),now()),
  ('atlas.personal_weekly_reality_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,
   jsonb_build_object('purpose','Read weekly reality intake/routing evidence for the authenticated Principal without replacing owning-domain reads.'),now())
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
