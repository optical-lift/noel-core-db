-- Reality / Ledger scheduling custody acceptance v1
-- Read-only structural assertions for the recovered live scheduling kernel.

do $$
declare
  v_missing text[];
  v_rls_missing text[];
  v_function_missing text[];
begin
  select array_agg(required_name order by required_name)
    into v_missing
  from (
    values
      ('reality.resources'),
      ('reality.availability_profiles'),
      ('reality.availability_rules'),
      ('reality.availability_exceptions'),
      ('ledger.bookings'),
      ('ledger.booking_events'),
      ('ledger.booking_references'),
      ('ledger.occurrence_calendar_bindings'),
      ('ledger.occurrence_resource_claims'),
      ('ledger.booking_policies'),
      ('ledger.recurrence_series'),
      ('ledger.recurrence_exceptions'),
      ('ledger.recurrence_instances')
  ) required(required_name)
  where to_regclass(required_name) is null;

  if v_missing is not null then
    raise exception 'Missing scheduling tables: %', array_to_string(v_missing, ', ');
  end if;

  select array_agg(n.nspname || '.' || c.relname order by n.nspname,c.relname)
    into v_rls_missing
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where (n.nspname,c.relname) in (
      ('reality','resources'),
      ('reality','availability_profiles'),
      ('reality','availability_rules'),
      ('reality','availability_exceptions'),
      ('ledger','bookings'),
      ('ledger','booking_events'),
      ('ledger','booking_references'),
      ('ledger','occurrence_calendar_bindings'),
      ('ledger','occurrence_resource_claims'),
      ('ledger','booking_policies'),
      ('ledger','recurrence_series'),
      ('ledger','recurrence_exceptions'),
      ('ledger','recurrence_instances')
    )
    and not c.relrowsecurity;

  if v_rls_missing is not null then
    raise exception 'Scheduling tables without RLS: %', array_to_string(v_rls_missing, ', ');
  end if;

  select array_agg(required_name order by required_name)
    into v_function_missing
  from (
    values
      ('reality.upsert_resource_service_v1'),
      ('reality.subject_schedule_availability_v1'),
      ('reality.upsert_availability_profile_service_v1'),
      ('reality.upsert_availability_rule_service_v1'),
      ('reality.upsert_availability_exception_service_v1'),
      ('ledger.bind_occurrence_to_calendar_service_v1'),
      ('ledger.establish_booking_service_v1'),
      ('ledger.transition_booking_state_service_v1'),
      ('ledger.add_booking_reference_service_v1'),
      ('ledger.establish_occurrence_resource_claim_service_v1'),
      ('ledger.resource_claim_availability_v1'),
      ('ledger.resource_conflict_domain_v1'),
      ('ledger.lock_resource_conflict_domains_v1'),
      ('ledger.establish_booking_bundle_service_v1'),
      ('ledger.upsert_booking_policy_service_v1'),
      ('ledger.evaluate_booking_policies_v1'),
      ('ledger.upsert_recurrence_series_service_v1'),
      ('ledger.set_recurrence_exception_service_v1'),
      ('ledger.refresh_recurrence_instances_service_v1'),
      ('ledger.materialize_recurrence_instance_service_v1'),
      ('ledger.materialize_recurrence_range_service_v1'),
      ('ledger.recurrence_schedule_service_v1'),
      ('atlas.ledger_resources_self_api_v1'),
      ('atlas.ledger_resource_calendar_self_api_v1'),
      ('atlas.ledger_resource_availability_self_api_v1'),
      ('atlas.establish_ledger_booking_self_api_v1'),
      ('atlas.establish_ledger_booking_bundle_self_api_v1'),
      ('atlas.transition_ledger_booking_self_api_v1'),
      ('atlas.upsert_ledger_resource_self_api_v1'),
      ('atlas.ledger_recurrence_schedule_self_api_v1')
  ) required(required_name)
  where to_regprocedure(required_name || case
    when required_name='reality.upsert_resource_service_v1' then '(uuid,uuid,text,text,text,text,boolean,text,numeric,text,text,jsonb)'
    else ''
  end) is null
    and not exists (
      select 1
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname=split_part(required_name,'.',1)
        and p.proname=split_part(required_name,'.',2)
    );

  if v_function_missing is not null then
    raise exception 'Missing scheduling functions: %', array_to_string(v_function_missing, ', ');
  end if;
end
$$;

-- Canonical identity / occurrence dependency checks.
do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid=c.conrelid
    join pg_catalog.pg_namespace tn on tn.oid=t.relnamespace
    join pg_catalog.pg_class rt on rt.oid=c.confrelid
    join pg_catalog.pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='reality'
      and t.relname='resources'
      and rn.nspname='reality'
      and rt.relname='entities'
  ) then
    raise exception 'reality.resources must depend on canonical reality.entities.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid=c.conrelid
    join pg_catalog.pg_namespace tn on tn.oid=t.relnamespace
    join pg_catalog.pg_class rt on rt.oid=c.confrelid
    join pg_catalog.pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='ledger'
      and t.relname='bookings'
      and rn.nspname='local_intel'
      and rt.relname='occurrences'
  ) then
    raise exception 'ledger.bookings must reference canonical local_intel.occurrences.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid=c.conrelid
    join pg_catalog.pg_namespace tn on tn.oid=t.relnamespace
    join pg_catalog.pg_class rt on rt.oid=c.confrelid
    join pg_catalog.pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='ledger'
      and t.relname='occurrence_calendar_bindings'
      and rn.nspname='local_intel'
      and rt.relname='occurrences'
  ) then
    raise exception 'ledger.occurrence_calendar_bindings must reference canonical local_intel.occurrences.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid=c.conrelid
    join pg_catalog.pg_namespace tn on tn.oid=t.relnamespace
    join pg_catalog.pg_class rt on rt.oid=c.confrelid
    join pg_catalog.pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='ledger'
      and t.relname='occurrence_resource_claims'
      and rn.nspname='reality'
      and rt.relname='resources'
  ) then
    raise exception 'ledger.occurrence_resource_claims must reference reality.resources.';
  end if;
end
$$;

-- Non-collapse shape checks.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema='ledger'
      and table_name='bookings'
      and column_name in (
        'payment_state','payment_status','amount_paid','stripe_payment_intent_id',
        'venue_id','farm_id','organization_id'
      )
  ) then
    raise exception 'ledger.bookings contains forbidden collapsed authority columns.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='ledger'
      and table_name='occurrence_calendar_bindings'
      and column_name in ('starts_at','ends_at','resource_id','payment_state')
  ) then
    raise exception 'Calendar binding has absorbed occurrence, occupancy, or payment authority.';
  end if;
end
$$;

select jsonb_build_object(
  'contractVersion','reality_ledger_scheduling_custody_acceptance_v1',
  'status','pass',
  'requiredTables',13,
  'canonicalOccurrenceAuthority','local_intel.occurrences',
  'resourceAuthority','reality.resources',
  'bookingAuthority','ledger.bookings',
  'occupancyAuthority','ledger.occurrence_resource_claims',
  'calendarMembershipAuthority','ledger.occurrence_calendar_bindings'
) as acceptance;
