-- Universal Temporal Field Constitution v1
-- Read-only structural acceptance against the currently live source authorities.
-- This file creates no schema and performs no writes.

do $$
declare
  v_missing text[];
begin
  select array_agg(required_name order by required_name)
    into v_missing
  from (
    values
      ('local_intel.occurrences'),
      ('local_intel.temporal_markers'),
      ('atlas.organization_occurrence_bindings'),
      ('atlas.organization_temporal_bindings'),
      ('atlas.organization_purpose_contexts'),
      ('atlas.organization_purpose_context_memberships'),
      ('ledger.occurrence_calendar_bindings'),
      ('ledger.bookings'),
      ('ledger.occurrence_resource_claims'),
      ('ledger.booking_offerings'),
      ('atlas.work_items'),
      ('atlas.work_time_contracts'),
      ('atlas.work_planning_conflicts'),
      ('atlas.person_life_consequence_instances'),
      ('atlas.communication_conversations')
  ) required(required_name)
  where to_regclass(required_name) is null;

  if v_missing is not null then
    raise exception 'Temporal Field source authorities missing: %', array_to_string(v_missing, ', ');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace tn on tn.oid=t.relnamespace
    join pg_class rt on rt.oid=c.confrelid
    join pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='atlas' and t.relname='organization_occurrence_bindings'
      and rn.nspname='local_intel' and rt.relname='occurrences'
  ) then
    raise exception 'Organization occurrence binding must preserve canonical occurrence identity.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace tn on tn.oid=t.relnamespace
    join pg_class rt on rt.oid=c.confrelid
    join pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='atlas' and t.relname='organization_temporal_bindings'
      and rn.nspname='local_intel' and rt.relname='temporal_markers'
  ) then
    raise exception 'Organization temporal binding must preserve canonical temporal-marker identity.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.organization_purpose_context_memberships'::regclass
      and c.contype='c'
      and pg_get_constraintdef(c.oid) like '%occurrence_binding%'
      and pg_get_constraintdef(c.oid) like '%temporal_binding%'
  ) then
    raise exception 'Purpose-context membership must support occurrence and temporal bindings.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace tn on tn.oid=t.relnamespace
    join pg_class rt on rt.oid=c.confrelid
    join pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='ledger' and t.relname='bookings'
      and rn.nspname='local_intel' and rt.relname='occurrences'
  ) then
    raise exception 'Ledger bookings must preserve canonical occurrence identity.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace tn on tn.oid=t.relnamespace
    join pg_class rt on rt.oid=c.confrelid
    join pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='ledger' and t.relname='occurrence_resource_claims'
      and rn.nspname='reality' and rt.relname='resources'
  ) then
    raise exception 'Resource occupancy must remain attached to canonical Reality resources.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace tn on tn.oid=t.relnamespace
    join pg_class rt on rt.oid=c.confrelid
    join pg_namespace rn on rn.oid=rt.relnamespace
    where c.contype='f'
      and tn.nspname='atlas' and t.relname='work_time_contracts'
      and rn.nspname='atlas' and rt.relname='work_items'
  ) then
    raise exception 'Company Work time truth must remain attached to Work identity.';
  end if;
end
$$;

do $$
declare
  v_required text[] := array[
    'carrier_state',
    'placement_state',
    'execution_readiness'
  ];
  v_missing text[];
begin
  select array_agg(x order by x)
    into v_missing
  from unnest(v_required) x
  where not exists (
    select 1
    from information_schema.columns c
    where c.table_schema='atlas'
      and c.table_name='person_life_consequence_instances'
      and c.column_name=x
  );

  if v_missing is not null then
    raise exception 'Person Life consequence separation missing columns: %', array_to_string(v_missing, ', ');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas' and p.proname='principal_clock_arbitration_v1'
  ) then
    raise exception 'Principal Clock arbitration authority missing.';
  end if;

  if not exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas' and p.proname='principal_clock_api_v1'
  ) then
    raise exception 'Principal Clock read authority missing.';
  end if;

  if to_regclass('atlas.calendar_events') is not null
     or to_regclass('ledger.calendar_events') is not null
     or to_regclass('reality.calendar_events') is not null
     or to_regclass('local_intel.calendar_events') is not null then
    raise exception 'Canonical catch-all calendar_events authority is prohibited.';
  end if;
end
$$;

select jsonb_build_object(
  'contractVersion','universal_temporal_field_constitution_v1',
  'status','pass',
  'sourceFamilies',jsonb_build_array(
    'canonical_occurrence',
    'canonical_temporal_marker',
    'organization_private_context',
    'reality_ledger_scheduling',
    'company_work_time',
    'person_life_consequence',
    'principal_clock',
    'communication_consequence'
  ),
  'persistedTemporalField',false,
  'canonicalCalendarEventTable',false,
  'firstExecutableAdapters',jsonb_build_array(
    'canonical_occurrence',
    'canonical_temporal_marker',
    'organization_private_context'
  )
) as acceptance;
