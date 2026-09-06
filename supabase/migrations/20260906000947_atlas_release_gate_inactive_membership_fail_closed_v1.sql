create or replace function atlas.work_occurrence_gate_satisfied_v1(
  p_occurrence_id uuid,
  p_as_of_date date
)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
  select case
    when occurrence.id is null then false
    -- An explicit execution-membership pointer is a delivery constraint, not a
    -- suggestion. If that historical membership is missing, foreign to this
    -- farm, or inactive, fail this occurrence closed instead of letting task
    -- insertion abort the entire farm release sweep. Atlas does not guess a
    -- replacement worker here.
    when nullif(occurrence.task_payload->>'assigned_membership_id','') is not null
      and not exists(
        select 1
        from atlas.farm_memberships explicit_member
        where explicit_member.id::text=occurrence.task_payload->>'assigned_membership_id'
          and explicit_member.farm_id=occurrence.farm_id
          and explicit_member.active
      )
    then false
    when exists(
      select 1
      from atlas.work_execution_adapters adapter
      join atlas.work_items work_item
        on work_item.organization_id=adapter.organization_id
       and work_item.id=adapter.work_item_id
      where adapter.planned_occurrence_id=occurrence.id
        and adapter.state='active'
        and work_item.work_state='open'
        and coalesce(adapter.metadata->>'responsibilityAuthority','')='work_allocations'
    ) and not exists(
      select 1
      from atlas.work_execution_adapters adapter
      join atlas.work_items work_item
        on work_item.organization_id=adapter.organization_id
       and work_item.id=adapter.work_item_id
      join atlas.work_allocations allocation
        on allocation.organization_id=work_item.organization_id
       and allocation.work_item_id=work_item.id
       and allocation.state='active'
       and allocation.allocation_role='responsible'
      join atlas.organization_memberships org_member
        on org_member.organization_id=allocation.organization_id
       and org_member.id=allocation.assignee_membership_id
       and org_member.active
      join atlas.farm_memberships farm_member
        on farm_member.farm_id=occurrence.farm_id
       and farm_member.user_id=org_member.user_id
       and farm_member.active
      where adapter.planned_occurrence_id=occurrence.id
        and adapter.state='active'
        and work_item.work_state='open'
        and coalesce(adapter.metadata->>'responsibilityAuthority','')='work_allocations'
        and nullif(occurrence.task_payload->>'assigned_membership_id','')::uuid=farm_member.id
        and nullif(occurrence.task_payload->>'assigned_user_id','')::uuid=org_member.user_id
    ) then false
    when exists(
      select 1
      from atlas.task_external_readiness_gates external_gate
      join atlas.tasks external_task on external_task.id=external_gate.task_id
      where external_task.planned_occurrence_id=occurrence.id
        and external_gate.gate_state='waiting'
    ) then false
    when exists(
      select 1
      from atlas.task_release_queue_items qi
      where qi.planned_occurrence_id=occurrence.id and qi.state='queued'
    ) then exists(
      select 1
      from atlas.task_release_queue_items qi
      where qi.planned_occurrence_id=occurrence.id and qi.state='queued'
        and not exists(
          select 1
          from atlas.task_release_queue_items active_item
          where active_item.farm_id=qi.farm_id
            and active_item.queue_key=qi.queue_key
            and active_item.state='active'
        )
        and qi.position=(
          select min(head.position)
          from atlas.task_release_queue_items head
          where head.farm_id=qi.farm_id
            and head.queue_key=qi.queue_key
            and head.state='queued'
        )
        and (occurrence.not_before_date is null or occurrence.not_before_date<=p_as_of_date)
    )
    when coalesce(occurrence.task_payload->>'action_key','')='weed'
      and exists(
        select 1
        from atlas.farm_memberships anna
        where anna.id=nullif(occurrence.task_payload->>'assigned_membership_id','')::uuid
          and anna.farm_id=occurrence.farm_id
          and anna.worker_key='anna'
          and anna.active=true
      )
      and exists(
        select 1
        from atlas.task_release_queue_items qi
        where qi.farm_id=occurrence.farm_id
          and qi.queue_key='anna_weeding_rotation'
          and qi.state in ('active','queued')
      )
      and not exists(
        select 1
        from atlas.task_release_queue_items qi
        where qi.planned_occurrence_id=occurrence.id
          and qi.queue_key='anna_weeding_rotation'
          and qi.state='active'
      )
    then false
    when occurrence.state='eligible' then true
    when policy.gate_type in ('immediate','time_window','serial_queue')
      then occurrence.not_before_date is null or occurrence.not_before_date<=p_as_of_date
    when policy.gate_type='predecessor'
      then occurrence.gate_satisfied_at is not null
        or (
          occurrence.parent_occurrence_id is not null
          and exists(
            select 1
            from atlas.planned_work_occurrences parent
            where parent.id=occurrence.parent_occurrence_id
              and parent.state in ('released','completed')
          )
        )
    else occurrence.gate_satisfied_at is not null
  end
  from atlas.planned_work_occurrences occurrence
  join atlas.work_release_policies policy on policy.id=occurrence.release_policy_id
  where occurrence.id=p_occurrence_id
$function$;

comment on function atlas.work_occurrence_gate_satisfied_v1(uuid,date) is
'Canonical release gate. An occurrence with an explicit assigned Farm Membership cannot release unless that membership is active on the same farm. Stale assignment pointers fail only that occurrence closed; they do not authorize reassignment and must not abort unrelated farm releases.';