-- Reality / Ledger booking offering, requirements, and routing acceptance v1
-- Read-only structural assertions against the live kernel.

do $$
declare
  v_missing text[];
  v_rls_missing text[];
  v_internal_exposed text[];
  v_wrapper_missing text[];
begin
  select array_agg(required_name order by required_name)
  into v_missing
  from (values
    ('ledger.booking_offerings'),
    ('ledger.booking_offering_requirement_groups'),
    ('ledger.booking_offering_requirements'),
    ('ledger.booking_offering_routing_policies'),
    ('ledger.booking_offering_routing_candidates')
  ) required(required_name)
  where to_regclass(required_name) is null;

  if v_missing is not null then
    raise exception 'Missing booking offering tables: %',array_to_string(v_missing,', ');
  end if;

  select array_agg(n.nspname||'.'||c.relname order by n.nspname,c.relname)
  into v_rls_missing
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where (n.nspname,c.relname) in (
    ('ledger','booking_offerings'),
    ('ledger','booking_offering_requirement_groups'),
    ('ledger','booking_offering_requirements'),
    ('ledger','booking_offering_routing_policies'),
    ('ledger','booking_offering_routing_candidates')
  ) and not c.relrowsecurity;

  if v_rls_missing is not null then
    raise exception 'Booking offering tables without RLS: %',array_to_string(v_rls_missing,', ');
  end if;

  select array_agg(n.nspname||'.'||p.proname order by n.nspname,p.proname)
  into v_internal_exposed
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='ledger'
    and p.proname in (
      'booking_offering_detail_v1',
      'booking_offerings_service_v1',
      'upsert_booking_offering_service_v1',
      'replace_booking_offering_requirement_graph_service_v1',
      'booking_offering_requirement_candidates_v1',
      'booking_offering_group_evaluation_v1',
      'evaluate_booking_offering_v1'
    )
    and (
      has_function_privilege('anon',p.oid,'EXECUTE')
      or has_function_privilege('authenticated',p.oid,'EXECUTE')
      or has_function_privilege('public',p.oid,'EXECUTE')
    );

  if v_internal_exposed is not null then
    raise exception 'Internal booking offering services exposed to API roles: %',array_to_string(v_internal_exposed,', ');
  end if;

  select array_agg(required_name order by required_name)
  into v_wrapper_missing
  from (values
    ('ledger_booking_offerings_self_api_v1'),
    ('ledger_booking_offering_self_api_v1'),
    ('evaluate_ledger_booking_offering_self_api_v1'),
    ('upsert_ledger_booking_offering_self_api_v1'),
    ('replace_ledger_booking_offering_requirement_graph_self_api_v1')
  ) required(required_name)
  where not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname=required_name
      and p.prosecdef
      and coalesce(p.proconfig,'{}'::text[]) @> array['search_path=']::text[]
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and not has_function_privilege('anon',p.oid,'EXECUTE')
      and not has_function_privilege('public',p.oid,'EXECUTE')
  );

  if v_wrapper_missing is not null then
    raise exception 'Missing or incorrectly secured booking offering self APIs: %',array_to_string(v_wrapper_missing,', ');
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1 from reality.responsibility_relations rr
    where rr.responsibility_key='institutional_schedule_operations'
      and rr.relation_state='active'
      and 'offering.read'=any(rr.permitted_operations)
      and 'offering.manage'=any(rr.permitted_operations)
  ) then
    raise exception 'Institutional scheduling responsibility lacks offering.read/offering.manage.';
  end if;

  if not exists (
    select 1 from pg_constraint c
    where c.conrelid='ledger.booking_offering_requirements'::regclass
      and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%resource%'
      and pg_get_constraintdef(c.oid) ilike '%seat_responsibility%'
  ) then
    raise exception 'Booking offering requirement-kind shape constraint missing.';
  end if;

  if not exists (
    select 1 from pg_constraint c
    where c.conrelid='ledger.booking_offering_routing_policies'::regclass
      and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%manual%'
      and pg_get_constraintdef(c.oid) ilike '%requester_choice%'
      and pg_get_constraintdef(c.oid) ilike '%first_eligible%'
      and pg_get_constraintdef(c.oid) ilike '%ordered_priority%'
  ) then
    raise exception 'Booking offering routing-mode constraint missing.';
  end if;

  if exists (
    select 1 from pg_constraint c
    where c.conrelid='ledger.booking_offering_routing_policies'::regclass
      and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%balanced%'
  ) then
    raise exception 'Unsupported workload-balancing routing semantics leaked into V1.';
  end if;
end
$$;

select jsonb_build_object(
  'contractVersion','reality_ledger_booking_offering_requirements_routing_acceptance_v1',
  'status','pass',
  'offeringAuthority','ledger.booking_offerings',
  'requirementAuthority','ledger.booking_offering_requirements',
  'routingAuthority','ledger.booking_offering_routing_policies',
  'resourceAvailabilityAuthority','ledger.resource_claim_availability_v1',
  'personFreeBusyBoundary','not_yet_canonical'
) as acceptance;
