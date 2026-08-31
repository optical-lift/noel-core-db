BEGIN;

-- Worker Day projection must not call worker_task_presentability_v1 once per
-- candidate. That warrant calls worker_task_routing_warrant_v1, which consults
-- the canonical live selector; doing so from inside the projection rebuilds the
-- entire selection graph for every candidate and can hit the API statement
-- timeout. Compute routing evidence once, then evaluate only the remaining
-- per-task readiness and operation-fit warrants.

create or replace function atlas.worker_day_work_projection_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  visibility_state text,
  visibility_reason text,
  presentation_state text,
  presentation_reason text,
  selection_rank bigint,
  work_lane text,
  commitment_kind text,
  effort_units numeric,
  budget_units numeric,
  notification_planned boolean,
  overload boolean
)
language sql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with member as materialized (
    select fm.user_id,nullif(lower(btrim(fm.worker_key)),'') as worker_key
    from atlas.farm_memberships fm
    where fm.id=p_membership_id
      and fm.farm_id=p_farm_id
      and fm.active
  ), selected as materialized (
    select *
    from atlas.presented_work_selection_rows_live_v1(p_farm_id,p_membership_id,p_day)
  ), placed as materialized (
    select distinct p.task_id
    from atlas.worker_day_task_placements p
    where p.farm_id=p_farm_id
      and p.membership_id=p_membership_id
      and p.service_date=p_day
      and p.state='placed'
  ), ids as (
    select s.task_id from selected s
    union
    select p.task_id from placed p
  ), candidates as materialized (
    select
      i.task_id,
      t.status,
      case when p.task_id is not null then 'explicit_placement_today' else 'presentation_selected' end as visibility_reason,
      coalesce(s.presentation_state,'presented') as presentation_state,
      coalesce(s.presentation_reason,'explicit_placement') as presentation_reason,
      coalesce(s.selection_rank,9223372036854775807::bigint) as selection_rank,
      coalesce(s.work_lane,t.work_lane,'required') as work_lane,
      coalesce(s.commitment_kind,t.commitment_kind,'none') as commitment_kind,
      coalesce(s.effort_units,t.effort_units,0::numeric) as effort_units,
      coalesce(s.budget_units,0::numeric) as budget_units,
      coalesce(s.notification_planned,false) as notification_planned,
      coalesce(s.overload,false) as overload,
      (
        t.assigned_membership_id=p_membership_id
        or t.assigned_user_id=m.user_id
        or t.metadata->>'executor_membership_id'=p_membership_id::text
        or (
          m.worker_key is not null
          and lower(coalesce(
            nullif(t.metadata->>'executor_worker_key',''),
            nullif(t.metadata->>'assignee_key',''),
            nullif(t.metadata->>'assigned_to',''),
            nullif(t.metadata->>'work_route','')
          ))=m.worker_key
        )
      ) as assignment_match,
      atlas.task_execution_readiness_v1(i.task_id) as readiness,
      atlas.task_operation_fit_warrant_v1(i.task_id) as fit
    from ids i
    join atlas.tasks t on t.id=i.task_id
    cross join member m
    left join selected s on s.task_id=i.task_id
    left join placed p on p.task_id=i.task_id
  )
  select
    c.task_id,
    'visible'::text,
    c.visibility_reason,
    c.presentation_state,
    c.presentation_reason,
    c.selection_rank,
    c.work_lane,
    c.commitment_kind,
    c.effort_units,
    c.budget_units,
    c.notification_planned,
    c.overload
  from candidates c
  where c.status='open'
    and c.assignment_match
    and coalesce((c.readiness->>'executionReady')::boolean,false)
    and coalesce((c.fit->>'exactIdentitySupported')::boolean,false)
  order by c.selection_rank,c.task_id;
$function$;

-- Coverage auditing has the same no-recursion rule. It may inspect obligations
-- that are not routed, but it must not call the presentability warrant for every
-- row because that warrant re-enters the live selector.
create or replace function atlas.worker_day_obligation_coverage_audit_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns table(
  task_id uuid,
  task_status text,
  due_date date,
  execution_ready boolean,
  routed_for_day boolean,
  presentable boolean,
  hold_reason text,
  coverage_reason text
)
language sql
stable security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with member as materialized (
    select fm.user_id,nullif(lower(btrim(fm.worker_key)),'') as worker_key
    from atlas.farm_memberships fm
    where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active
  ), selected as materialized (
    select s.task_id
    from atlas.presented_work_selection_rows_live_v1(p_farm_id,p_membership_id,p_day) s
    where s.presentation_state='presented'
  ), placed as materialized (
    select distinct p.task_id
    from atlas.worker_day_task_placements p
    where p.farm_id=p_farm_id
      and p.membership_id=p_membership_id
      and p.service_date=p_day
      and p.state='placed'
  ), candidates as materialized (
    select
      t.id,
      t.status,
      t.due_date,
      case
        when t.due_date is not null and t.due_date<p_day then 'assigned_overdue'
        when t.due_date=p_day then 'assigned_due_today'
        when coalesce(t.metadata->>'execution_date','') ~ '^\d{4}-\d{2}-\d{2}$'
          and (t.metadata->>'execution_date')::date<p_day then 'assigned_execution_overdue'
        else 'assigned_active_obligation'
      end as coverage_reason,
      (s.task_id is not null or p.task_id is not null) as routed,
      atlas.task_execution_readiness_v1(t.id) as readiness,
      atlas.task_operation_fit_warrant_v1(t.id) as fit
    from atlas.tasks t
    cross join member m
    left join selected s on s.task_id=t.id
    left join placed p on p.task_id=t.id
    where t.farm_id=p_farm_id
      and t.task_scope='farm_operation'
      and t.status in ('open','blocked')
      and t.parent_task_id is null
      and coalesce(t.visibility_scope,'assigned_worker')<>'system_internal'
      and (
        t.assigned_membership_id=p_membership_id
        or t.assigned_user_id=m.user_id
        or t.metadata->>'executor_membership_id'=p_membership_id::text
        or (
          m.worker_key is not null
          and lower(coalesce(
            nullif(t.metadata->>'executor_worker_key',''),
            nullif(t.metadata->>'assignee_key',''),
            nullif(t.metadata->>'assigned_to',''),
            nullif(t.metadata->>'work_route','')
          ))=m.worker_key
        )
      )
  ), resolved as (
    select
      c.*,
      coalesce((c.readiness->>'executionReady')::boolean,false) as ready,
      coalesce((c.fit->>'exactIdentitySupported')::boolean,false) as fit_ready
    from candidates c
  )
  select
    r.id,
    r.status,
    r.due_date,
    r.ready,
    r.routed,
    (r.status='open' and r.ready and r.routed and r.fit_ready),
    case
      when r.status<>'open' then 'task_status_'||r.status
      when not r.ready then 'execution_not_ready'
      when not r.fit_ready then 'operation_identity_unresolved'
      when not r.routed then 'not_routed_for_day'
      else null
    end,
    r.coverage_reason
  from resolved r
  order by r.due_date nulls last,r.id;
$function$;

comment on function atlas.worker_day_work_projection_v1(uuid,uuid,date) is
  'Active Worker Day projection. Computes canonical live selection and explicit placement routing once, then applies assignment, execution readiness, and operation fit without re-entering the selector per candidate.';

comment on function atlas.worker_day_obligation_coverage_audit_v1(uuid,uuid,date) is
  'Internal obligation coverage audit using set-based routing evidence. It never forces audit-only obligations onto Worker Day and never recursively re-enters the selector through worker_task_presentability_v1.';

COMMIT;
