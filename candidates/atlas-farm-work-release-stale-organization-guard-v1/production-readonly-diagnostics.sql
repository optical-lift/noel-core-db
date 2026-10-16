-- Production-safe work-release diagnostic: SELECT only.
-- No DDL, no DML, no release functions, no triggers, no side effects.
-- Run against production to characterize current candidates before and after
-- a separately approved deployment. Counts can change with real farm work.
with candidate as (
  select
    o.farm_id,
    o.state,
    case
      when nullif(o.task_payload->>'organization_id','') is null then 'unspecified'
      when org.id is null then 'invalid'
      when org.id = f.organization_id then 'valid_current_farm'
      else 'existing_but_foreign_org'
    end as source_org_state
  from atlas.planned_work_occurrences o
  join atlas.farms f on f.id=o.farm_id
  join atlas.work_release_policies p on p.id=o.release_policy_id and p.active
  join atlas.farm_task_release_settings settings
    on settings.farm_id=o.farm_id and settings.active
  left join atlas.organizations org
    on org.id::text=o.task_payload->>'organization_id'
  where o.state in ('planned','eligible','failed')
    and o.not_before_date <= (now() at time zone settings.timezone_name)::date
    and o.planned_due_date <=
      (now() at time zone settings.timezone_name)::date
      + least(p.horizon_days,settings.maximum_task_horizon_days)
    and (
      o.parent_occurrence_id is null
      or exists (
        select 1 from atlas.planned_work_occurrences parent
        where parent.id=o.parent_occurrence_id
          and parent.state in ('released','completed')
      )
    )
    and atlas.work_occurrence_gate_satisfied_v1(
      o.id,(now() at time zone settings.timezone_name)::date
    )
)
select source_org_state, state, count(*) as candidates
from candidate
group by source_org_state,state
order by source_org_state,state;

-- Optional related integrity check (read-only):
select
  count(*) filter (
    where org.id is not null and org.id<>f.organization_id
  ) as existing_but_different_farm_organization,
  count(*) filter (
    where org.id=f.organization_id
  ) as matches_farm_organization,
  count(*) filter (
    where nullif(o.task_payload->>'organization_id','') is null
  ) as organization_unspecified
from atlas.planned_work_occurrences o
join atlas.farms f on f.id=o.farm_id
left join atlas.organizations org
  on org.id::text=o.task_payload->>'organization_id'
where o.state in ('planned','eligible','failed');
