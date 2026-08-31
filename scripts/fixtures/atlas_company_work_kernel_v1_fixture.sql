-- Atlas Company Work Kernel v1 disposable fixture
-- Proves requirement -> work -> allocation -> dependency -> time -> conflict -> reassignment.
-- This script MUST roll back; it leaves no synthetic company work behind.

begin;

do $$
declare
  v_org uuid := '52afd94a-25e8-4532-a3c6-6aeeb2654297'::uuid;
  v_member_a uuid;
  v_member_b uuid;
  v_req_ops uuid;
  v_req_delivery uuid;
  v_work_a uuid;
  v_work_b uuid;
  v_work_c uuid;
  v_work_d uuid;
  v_alloc_a_old uuid;
  v_alloc_d uuid;
  v_total bigint;
  v_unassigned bigint;
  v_allocated bigint;
  v_waiting bigint;
  v_conflict bigint;
  v_history_count bigint;
  v_active_count bigint;
begin
  select min(id), max(id)
    into v_member_a, v_member_b
  from atlas.organization_memberships
  where organization_id = v_org
    and active;

  if v_member_a is null or v_member_b is null or v_member_a = v_member_b then
    raise exception 'Fixture requires at least two active memberships in organization %', v_org;
  end if;

  insert into atlas.work_requirements (
    organization_id,
    requirement_kind,
    summary,
    latest_satisfactory_at,
    jurisdiction_key,
    metadata
  ) values (
    v_org,
    'fixture_operational',
    'Prepare fixture operating area before protected boundary',
    now() + interval '7 days',
    'fixture.operations',
    jsonb_build_object('fixture', 'atlas_company_work_kernel_v1')
  ) returning id into v_req_ops;

  insert into atlas.work_requirements (
    organization_id,
    requirement_kind,
    summary,
    latest_satisfactory_at,
    jurisdiction_key,
    metadata
  ) values (
    v_org,
    'fixture_delivery',
    'Fulfill fixture delivery before customer boundary',
    now() + interval '5 days',
    'fixture.distribution',
    jsonb_build_object('fixture', 'atlas_company_work_kernel_v1')
  ) returning id into v_req_delivery;

  insert into atlas.work_items (organization_id, title, work_state, jurisdiction_key, metadata)
  values (v_org, 'Fixture: cut replacement material', 'open', 'fixture.operations', jsonb_build_object('fixture', true))
  returning id into v_work_a;

  insert into atlas.work_items (organization_id, title, work_state, jurisdiction_key, metadata)
  values (v_org, 'Fixture: repair operating area', 'open', 'fixture.operations', jsonb_build_object('fixture', true))
  returning id into v_work_b;

  insert into atlas.work_items (organization_id, title, work_state, jurisdiction_key, metadata)
  values (v_org, 'Fixture: prepare destination', 'open', 'fixture.operations', jsonb_build_object('fixture', true))
  returning id into v_work_c;

  insert into atlas.work_items (organization_id, title, work_state, jurisdiction_key, metadata)
  values (v_org, 'Fixture: deliver customer order', 'open', 'fixture.distribution', jsonb_build_object('fixture', true))
  returning id into v_work_d;

  insert into atlas.work_requirement_links (organization_id, requirement_id, work_item_id, link_role)
  values
    (v_org, v_req_ops, v_work_a, 'advances'),
    (v_org, v_req_ops, v_work_b, 'advances'),
    (v_org, v_req_ops, v_work_c, 'resolves'),
    (v_org, v_req_delivery, v_work_d, 'resolves');

  insert into atlas.work_allocations (
    organization_id,
    work_item_id,
    assignee_membership_id,
    assigned_by_membership_id,
    allocation_role
  ) values (
    v_org,
    v_work_a,
    v_member_a,
    v_member_a,
    'responsible'
  ) returning id into v_alloc_a_old;

  insert into atlas.work_allocations (
    organization_id,
    work_item_id,
    assignee_membership_id,
    assigned_by_membership_id,
    allocation_role
  ) values (
    v_org,
    v_work_b,
    v_member_b,
    v_member_a,
    'responsible'
  );

  insert into atlas.work_allocations (
    organization_id,
    work_item_id,
    assignee_membership_id,
    assigned_by_membership_id,
    allocation_role
  ) values (
    v_org,
    v_work_d,
    v_member_a,
    v_member_a,
    'responsible'
  ) returning id into v_alloc_d;

  -- Work B remains open and visible while waiting on Work A.
  insert into atlas.work_item_relations (
    organization_id,
    from_work_item_id,
    to_work_item_id,
    relation_kind
  ) values (
    v_org,
    v_work_b,
    v_work_a,
    'depends_on'
  );

  insert into atlas.work_time_contracts (
    organization_id,
    work_item_id,
    earliest_lawful_at,
    latest_lawful_at,
    hard_finish_at,
    expected_duration_minutes,
    movement_policy,
    consequence_of_delay,
    source_kind
  ) values (
    v_org,
    v_work_d,
    now(),
    now() + interval '5 days',
    now() + interval '5 days',
    240,
    'bounded',
    jsonb_build_object('kind', 'customer_promise_missed'),
    'fixture'
  );

  insert into atlas.work_planning_conflicts (
    organization_id,
    work_item_id,
    allocation_id,
    conflict_kind,
    horizon_start,
    horizon_end,
    required_by,
    capacity_snapshot,
    reason
  ) values (
    v_org,
    v_work_d,
    v_alloc_d,
    'hard_boundary_unfit',
    now(),
    now() + interval '5 days',
    now() + interval '5 days',
    jsonb_build_object('available_minutes', 180, 'required_minutes', 240),
    'Fixture proves that work that cannot fit becomes an explicit planning conflict.'
  );

  select total_open, unassigned, allocated, waiting_dependency, planning_conflict
    into v_total, v_unassigned, v_allocated, v_waiting, v_conflict
  from atlas.company_open_work_accounting_v1(v_org);

  if (v_total, v_unassigned, v_allocated, v_waiting, v_conflict) <> (4::bigint, 1::bigint, 1::bigint, 1::bigint, 1::bigint) then
    raise exception 'Unexpected company work accounting: total %, unassigned %, allocated %, waiting %, conflict %',
      v_total, v_unassigned, v_allocated, v_waiting, v_conflict;
  end if;

  -- Reassign Work A without creating a new Work Item or losing custody history.
  update atlas.work_allocations
  set state = 'released', released_at = now(), release_reason = 'fixture_reassignment', updated_at = now()
  where id = v_alloc_a_old;

  insert into atlas.work_allocations (
    organization_id,
    work_item_id,
    assignee_membership_id,
    assigned_by_membership_id,
    allocation_role
  ) values (
    v_org,
    v_work_a,
    v_member_b,
    v_member_a,
    'responsible'
  );

  select count(*), count(*) filter (where state = 'active')
    into v_history_count, v_active_count
  from atlas.work_allocations
  where organization_id = v_org
    and work_item_id = v_work_a
    and allocation_role = 'responsible';

  if v_history_count <> 2 or v_active_count <> 1 then
    raise exception 'Reassignment custody history failed: history %, active %', v_history_count, v_active_count;
  end if;

  if not exists (
    select 1
    from atlas.work_items
    where organization_id = v_org
      and id = v_work_a
      and work_state = 'open'
  ) then
    raise exception 'Reassignment changed or erased Work Item identity';
  end if;

  raise notice 'PASS atlas_company_work_kernel_v1: 4/4 accounted; dependency visible; planning conflict explicit; reassignment preserved identity';
end
$$;

rollback;
