create or replace function atlas.principal_capability_holds_v1(p_principal_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_items jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  if p_principal_id is null then
    return jsonb_build_object('state','principal_required','count',0,'items','[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'taskId',t.id,
      'title',t.title,
      'taskType',t.task_type,
      'actionKey',t.action_key,
      'status',t.status,
      'dueDate',t.due_date,
      'farmId',t.farm_id,
      'portfolioUnitId',u.id,
      'portfolioUnitName',u.name,
      'portfolioHorizon',u.horizon,
      'assignedMembershipId',t.assigned_membership_id,
      'assignedWorkerKey',fm.worker_key,
      'assignedRole',fm.role,
      'readinessKey',g.readiness_key,
      'readinessLabel',g.readiness_label,
      'blocker',g.blocker_text,
      'holdDimensions',coalesce(g.metadata->'hold_dimensions',t.metadata->'capability_hold_dimensions','[]'::jsonb),
      'heldSince',g.created_at,
      'lastChangedAt',g.updated_at,
      'originalDueDate',coalesce(g.restore_due_date,t.due_date)
    ) order by case u.horizon when 'H1' then 1 when 'H2' then 2 when 'H3' then 3 else 4 end,g.created_at,t.title),'[]'::jsonb),count(*)::integer
  into v_items,v_count
  from atlas.task_external_readiness_gates g
  join atlas.tasks t on t.id=g.task_id
  join lateral (
    select pu.id,pu.name,pu.horizon
    from atlas.portfolio_units pu
    where pu.owner_id=p_principal_id
      and pu.archived_at is null
      and pu.linked_farm_id=t.farm_id
    order by case pu.horizon when 'H1' then 1 when 'H2' then 2 when 'H3' then 3 else 4 end,pu.created_at,pu.id
    limit 1
  ) u on true
  left join atlas.farm_memberships fm on fm.id=t.assigned_membership_id
  where g.gate_state='waiting'
    and coalesce((g.metadata->>'capability_hold')::boolean,(t.metadata->>'capability_hold')::boolean,false)=true
    and t.status not in ('done','skipped','archived');

  return jsonb_build_object(
    'contractVersion','principal_capability_holds_v1',
    'state',case when v_count>0 then 'waiting' else 'clear' end,
    'count',v_count,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'notPrincipalClockClaims',true,
      'notWorkerDayPlacement',true,
      'obligationRetained',true,
      'dueTruthRetained',true,
      'releaseRequiresCapabilityReadiness',true
    )
  );
end;
$function$;

revoke all on function atlas.principal_capability_holds_v1(uuid) from public,anon,authenticated;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_household jsonb;
  v_portfolio jsonb;
  v_candidates jsonb;
  v_day date;
  v_clock jsonb;
  v_office jsonb;
  v_readiness jsonb;
  v_capability_holds jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals p
  where p.user_id=auth.uid() and p.status='active'
  limit 1;

  if v_principal.id is null then
    return jsonb_build_object('contractVersion','principal_self_context_v2','state','principal_required');
  end if;

  v_day := (now() at time zone coalesce(nullif(v_principal.home_timezone,''),'America/Chicago'))::date;

  select to_jsonb(h) into v_household
  from atlas.households h where h.id=v_principal.active_household_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',u.id,'stableKey',u.stable_key,'name',u.name,'unitKind',u.unit_kind,
    'linkedFarmId',u.linked_farm_id,'lifecycleState',u.lifecycle_state,
    'portfolioRole',u.portfolio_role,'horizon',u.horizon,'archivedAt',u.archived_at
  ) order by case u.horizon when 'H1' then 1 when 'H2' then 2 else 3 end,u.name),'[]'::jsonb)
  into v_portfolio
  from atlas.portfolio_units u
  where u.owner_id=v_principal.id and u.archived_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'domain',c.domain,'sourceType',c.source_type,'sourceId',c.source_id,'title',c.title,
    'floorClass',c.floor_class,'windowStart',c.window_start,'windowEnd',c.window_end,
    'fixedStart',c.fixed_start,'mustBeginBy',c.must_begin_by,'mustFinishBy',c.must_finish_by,
    'expectedMinutes',c.expected_minutes,'protectionLevel',c.protection_level,
    'ownerRequired',c.owner_required,'consequence',c.consequence,'reasonForFloor',c.reason_for_floor,
    'portfolioUnitId',c.portfolio_unit_id,'horizon',c.horizon
  ) order by c.floor_class,c.window_end nulls last,c.title),'[]'::jsonb)
  into v_candidates
  from atlas.principal_clock_candidates_v1 c
  where c.principal_id=v_principal.id;

  v_clock:=atlas.principal_clock_api_v1(v_day,now());
  v_office:=atlas.principal_office_context_api_v1();
  v_readiness:=atlas.principal_reality_readiness_v3(v_principal.id,v_day);
  v_capability_holds:=atlas.principal_capability_holds_v1(v_principal.id);

  return jsonb_build_object(
    'contractVersion','principal_self_context_v2','state','ready',
    'principal',jsonb_build_object(
      'id',v_principal.id,'stableKey',v_principal.stable_key,'name',v_principal.name,
      'organizationId',v_principal.organization_id,'homeTimezone',v_principal.home_timezone,
      'activeHouseholdId',v_principal.active_household_id
    ),
    'household',v_household,'portfolioUnits',v_portfolio,
    'clockCandidatesMode','raw_inventory_not_arbitration','clockCandidates',v_candidates,
    'principalClock',v_clock,'principalOffice',v_office,
    'capacityToday',atlas.principal_capacity_day_state_v1(v_principal.id,v_day),
    'capabilityHolds',v_capability_holds,
    'realityReadiness',v_readiness
  );
end;
$function$;