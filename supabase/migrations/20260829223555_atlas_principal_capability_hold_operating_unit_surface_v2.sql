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
    'contractVersion','principal_capability_holds_v2',
    'state',case when v_count>0 then 'waiting' else 'clear' end,
    'count',v_count,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'surfaceUsesOperatingUnitNotFarmIdentity',true,
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