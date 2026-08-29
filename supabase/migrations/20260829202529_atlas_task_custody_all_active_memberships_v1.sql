create or replace function atlas.roll_expired_farm_worker_tasks_v1()
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  r record;
  v_results jsonb := '[]'::jsonb;
begin
  for r in
    select fm.farm_id,fm.id as membership_id
    from atlas.farm_memberships fm
    where fm.active=true
      and (
        exists(
          select 1
          from atlas.tasks t
          where t.farm_id=fm.farm_id
            and t.assigned_membership_id=fm.id
            and t.task_scope='farm_operation'
            and t.status in ('open','blocked')
        )
        or exists(
          select 1
          from atlas.worker_day_task_placements p
          join atlas.tasks t on t.id=p.task_id
          where p.farm_id=fm.farm_id
            and p.membership_id=fm.id
            and p.state='placed'
            and t.status in ('open','blocked')
        )
      )
    order by fm.farm_id,fm.id
  loop
    v_results := v_results || jsonb_build_array(
      atlas.roll_expired_worker_tasks_v1(r.farm_id,r.membership_id,null)
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','worker_calendar_rollover_v2',
    'ranAt',now(),
    'workers',v_results,
    'truthBoundary',jsonb_build_object(
      'custodyIsRoleIndependent',true,
      'activeMembershipWithOperationalWorkIsReconciled',true
    )
  );
end;
$function$;