-- Atlas Current Company Work Canonicalization v1
-- One-time transitional ingestion from current non-terminal legacy task evidence
-- into the canonical Company Work Kernel.
--
-- Preconditions:
--   * atlas.legacy_company_work_canonicalization_audit_v1 exists
--   * Company Work Kernel v1 exists
--
-- This script does not reactivate memberships, widen authority, alter Worker Day,
-- or turn checklist/result components into duplicate Company Work identities.

begin;

-- 1. Materialize one requirement for each current company-work identity that
-- still lacks canonical work. Legacy due dates are deliberately NOT written as
-- latest_satisfactory_at; timing is handled separately as a preferred target.
insert into atlas.work_requirements (
  organization_id,
  organization_unit_id,
  stable_key,
  requirement_kind,
  summary,
  source_object_type,
  source_object_id,
  state,
  established_at,
  requirement_began_at,
  earliest_relevant_at,
  latest_satisfactory_at,
  consequence_of_delay,
  jurisdiction_key,
  metadata
)
select
  a.organization_id,
  a.farm_organization_unit_id,
  'legacy_task_adoption:' || a.legacy_task_id::text,
  'operational',
  a.legacy_title,
  'legacy_task',
  a.legacy_task_id,
  'active',
  coalesce(t.released_at,t.created_at,now()),
  coalesce(t.released_at,t.created_at,now()),
  null,
  null,
  '{}'::jsonb,
  coalesce(nullif(t.task_scope,''),'operations'),
  jsonb_build_object(
    'adoptedFromLegacyTask',true,
    'legacyTaskId',a.legacy_task_id,
    'currentCompanyWorkCanonicalization','v1',
    'legacyDueDateNotRequirementDeadline',true,
    'readinessMayNotSuppressRequirement',true
  )
from atlas.legacy_company_work_canonicalization_audit_v1 a
join atlas.tasks t on t.id=a.legacy_task_id
where a.legacy_status in ('open','blocked')
  and a.company_scope_position='current_company_work'
  and a.work_identity_position='create_work_item'
on conflict (organization_id,stable_key) where stable_key is not null
do update set
  organization_unit_id=excluded.organization_unit_id,
  summary=excluded.summary,
  metadata=atlas.work_requirements.metadata || excluded.metadata,
  updated_at=now();

-- 2. Materialize canonical work identity. Blocked is not a work lifecycle state;
-- blocked legacy work remains open Company Work with blockers/readiness handled
-- by their own authorities.
insert into atlas.work_items (
  organization_id,
  organization_unit_id,
  stable_key,
  title,
  instructions,
  work_state,
  operation_class,
  jurisdiction_key,
  source_object_type,
  source_object_id,
  result_contract_key,
  metadata
)
select
  a.organization_id,
  a.farm_organization_unit_id,
  'legacy_task_adoption:' || a.legacy_task_id::text,
  a.legacy_title,
  coalesce(nullif(btrim(t.note),''),nullif(btrim(t.unlock_text),'')),
  'open',
  coalesce(nullif(t.operation_class,''),nullif(t.task_type,''),'task'),
  coalesce(nullif(t.task_scope,''),'operations'),
  'legacy_task',
  a.legacy_task_id,
  nullif(t.metadata->>'result_contract_key',''),
  jsonb_build_object(
    'adoptedFromLegacyTask',true,
    'legacyTaskId',a.legacy_task_id,
    'currentCompanyWorkCanonicalization','v1',
    'legacyCarrierIsAuthority',false,
    'companyWorkIsResponsibilityAuthority',true,
    'executionStructure',a.execution_structure_position
  )
from atlas.legacy_company_work_canonicalization_audit_v1 a
join atlas.tasks t on t.id=a.legacy_task_id
where a.legacy_status in ('open','blocked')
  and a.company_scope_position='current_company_work'
  and a.work_identity_position='create_work_item'
on conflict (organization_id,stable_key) where stable_key is not null
do update set
  organization_unit_id=excluded.organization_unit_id,
  title=excluded.title,
  instructions=excluded.instructions,
  operation_class=excluded.operation_class,
  jurisdiction_key=excluded.jurisdiction_key,
  metadata=atlas.work_items.metadata || excluded.metadata,
  updated_at=now();

-- 3. Link adoption-owned requirements to their work identities.
insert into atlas.work_requirement_links (
  organization_id,requirement_id,work_item_id,link_role,active,metadata
)
select
  t.organization_id,
  wr.id,
  wi.id,
  'resolves',
  true,
  jsonb_build_object('source','current_company_work_canonicalization_v1')
from atlas.tasks t
join atlas.farms f on f.id=t.farm_id and f.organization_id=t.organization_id
join atlas.work_requirements wr
  on wr.organization_id=t.organization_id
 and wr.stable_key='legacy_task_adoption:' || t.id::text
join atlas.work_items wi
  on wi.organization_id=t.organization_id
 and wi.stable_key='legacy_task_adoption:' || t.id::text
where t.status in ('open','blocked')
on conflict (requirement_id,work_item_id,link_role)
do update set active=true,
  metadata=atlas.work_requirement_links.metadata || excluded.metadata;

-- 4. Establish/repair the execution-carrier adapter for every current company
-- work row that owns a Company Work identity. Execution-only checklist/result
-- rows remain beneath their parent and do not receive their own work identity.
insert into atlas.work_execution_adapters (
  organization_id,organization_unit_id,work_item_id,adapter_kind,task_id,state,metadata
)
select
  a.organization_id,
  wi.organization_unit_id,
  wi.id,
  'legacy_task',
  a.legacy_task_id,
  'active',
  jsonb_build_object(
    'transitional',true,
    'currentCompanyWorkCanonicalization','v1',
    'responsibilityAuthority','company_work',
    'executionCarrierAuthorityOnly',true
  )
from atlas.legacy_company_work_canonicalization_audit_v1 a
join atlas.work_items wi
  on wi.organization_id=a.organization_id
 and wi.source_object_type='legacy_task'
 and wi.source_object_id=a.legacy_task_id
where a.legacy_status in ('open','blocked')
  and a.company_scope_position='current_company_work'
  and a.execution_structure_position<>'execution_component'
on conflict (task_id) where task_id is not null
do update set
  organization_id=excluded.organization_id,
  organization_unit_id=excluded.organization_unit_id,
  work_item_id=excluded.work_item_id,
  adapter_kind=excluded.adapter_kind,
  state='active',
  retired_at=null,
  completed_at=null,
  metadata=atlas.work_execution_adapters.metadata || excluded.metadata,
  updated_at=now();

-- 5. Preserve a plain legacy due date only as an adoption-owned movable
-- preferred target. It is not latest-lawful or hard-finish truth.
insert into atlas.work_time_contracts (
  organization_id,work_item_id,contract_state,preferred_end_at,movement_policy,
  source_kind,source_id,source_confidence,metadata
)
select
  wi.organization_id,
  wi.id,
  'active',
  ((t.due_date+1)::timestamp at time zone
    case
      when exists (
        select 1 from pg_catalog.pg_timezone_names z
        where z.name=coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
      ) then coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
      else 'America/Chicago'
    end),
  'movable',
  'legacy_task',
  t.id,
  1,
  jsonb_build_object(
    'dueDate',t.due_date,
    'dueDateIsTargetNotHardLaw',true,
    'currentCompanyWorkCanonicalization','v1'
  )
from atlas.tasks t
join atlas.farms f on f.id=t.farm_id and f.organization_id=t.organization_id
join atlas.work_items wi
  on wi.organization_id=t.organization_id
 and wi.source_object_type='legacy_task'
 and wi.source_object_id=t.id
where t.status in ('open','blocked')
  and t.due_date is not null
  and coalesce((wi.metadata->>'adoptedFromLegacyTask')::boolean,false)
  and not exists (
    select 1 from atlas.work_time_contracts tc
    where tc.work_item_id=wi.id and tc.contract_state='active'
  );

-- 6. Create lawful active responsibility only where the legacy person resolves
-- to exactly one active Organization Membership. Never reactivate membership.
insert into atlas.work_allocations (
  organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
  allocation_role,state,allocated_at,metadata
)
select
  wi.organization_id,
  wi.id,
  om.id,
  null,
  'responsible',
  'active',
  coalesce(t.released_at,t.created_at,now()),
  jsonb_build_object(
    'source','current_company_work_canonicalization_v1',
    'legacyTaskId',t.id,
    'assignerNotInferred',true
  )
from atlas.tasks t
join atlas.farms f on f.id=t.farm_id and f.organization_id=t.organization_id
join atlas.work_execution_adapters a on a.task_id=t.id and a.state<>'retired'
join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
left join atlas.farm_memberships fm on fm.id=t.assigned_membership_id
join lateral (
  select candidate.id
  from atlas.organization_memberships candidate
  where candidate.organization_id=t.organization_id
    and candidate.user_id=coalesce(t.assigned_user_id,fm.user_id)
    and candidate.active
  order by candidate.created_at,candidate.id
  limit 1
) om on true
where t.status in ('open','blocked')
  and t.task_type<>'checklist_step'
  and not (
    t.assigned_user_id is not null
    and fm.user_id is not null
    and t.assigned_user_id<>fm.user_id
  )
  and not exists (
    select 1 from atlas.work_allocations existing
    where existing.work_item_id=wi.id
      and existing.state='active'
      and existing.allocation_role='responsible'
  );

-- 7. Resolve stale assignment conflicts when lawful allocation now exists.
update atlas.work_planning_conflicts pc
set state='resolved',
    resolution_kind='assignment_identity_resolved',
    resolution_note='Current Company Work canonicalization resolved the responsibility candidate to an active Organization Membership.',
    resolved_at=now(),
    updated_at=now()
where pc.state='open'
  and pc.conflict_kind='no_eligible_assignee'
  and exists (
    select 1 from atlas.work_allocations wa
    where wa.work_item_id=pc.work_item_id
      and wa.state='active'
      and wa.allocation_role='responsible'
  );

-- 8. Preserve named-but-unallocatable responsibility as canonical conflict
-- truth. This is what permits a management Anna/Fred lens without pretending a
-- lawful allocation exists.
insert into atlas.work_planning_conflicts (
  organization_id,work_item_id,allocation_id,conflict_kind,detected_at,
  required_by,capacity_snapshot,reason,state,metadata
)
select
  wi.organization_id,
  wi.id,
  null,
  'no_eligible_assignee',
  now(),
  case when t.due_date is null then null
       else ((t.due_date+1)::timestamp at time zone
         case
           when exists (
             select 1 from pg_catalog.pg_timezone_names z
             where z.name=coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
           ) then coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
           else 'America/Chicago'
         end)
  end,
  jsonb_build_object('missingActiveOrganizationMembership',true),
  'The named responsibility candidate does not resolve to an active Organization Membership. Company Work is preserved; management resolution is required.',
  'open',
  jsonb_build_object(
    'source','current_company_work_canonicalization_v1',
    'sourceTaskId',t.id,
    'assignedUserId',coalesce(t.assigned_user_id,fm.user_id),
    'assignedFarmMembershipId',t.assigned_membership_id
  )
from atlas.tasks t
join atlas.farms f on f.id=t.farm_id and f.organization_id=t.organization_id
join atlas.work_execution_adapters a on a.task_id=t.id and a.state<>'retired'
join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
left join atlas.farm_memberships fm on fm.id=t.assigned_membership_id
where t.status in ('open','blocked')
  and t.task_type<>'checklist_step'
  and coalesce(t.assigned_user_id,fm.user_id) is not null
  and not (
    t.assigned_user_id is not null
    and fm.user_id is not null
    and t.assigned_user_id<>fm.user_id
  )
  and not exists (
    select 1 from atlas.organization_memberships om
    where om.organization_id=t.organization_id
      and om.user_id=coalesce(t.assigned_user_id,fm.user_id)
      and om.active
  )
  and not exists (
    select 1 from atlas.work_allocations wa
    where wa.work_item_id=wi.id
      and wa.state='active'
      and wa.allocation_role='responsible'
  )
  and not exists (
    select 1 from atlas.work_planning_conflicts existing
    where existing.organization_id=wi.organization_id
      and existing.work_item_id=wi.id
      and existing.state='open'
      and existing.conflict_kind='no_eligible_assignee'
      and existing.metadata->>'assignedUserId'=coalesce(t.assigned_user_id,fm.user_id)::text
  );

-- 9. Preserve contradictory legacy assignee identifiers without choosing a
-- person. There are zero current conflicts of this shape at the audit point,
-- but the migration remains safe if one appears before release.
insert into atlas.work_planning_conflicts (
  organization_id,work_item_id,allocation_id,conflict_kind,detected_at,
  required_by,capacity_snapshot,reason,state,metadata
)
select
  wi.organization_id,
  wi.id,
  null,
  'no_eligible_assignee',
  now(),
  null,
  jsonb_build_object('assignmentIdentityConflict',true),
  'Legacy assignee identifiers disagree. Company Work is preserved and Atlas will not choose a person.',
  'open',
  jsonb_build_object(
    'source','current_company_work_assignment_identity_conflict_v1',
    'sourceTaskId',t.id,
    'assignedUserIdEvidence',t.assigned_user_id,
    'assignedFarmMembershipId',t.assigned_membership_id,
    'farmMembershipUserId',fm.user_id
  )
from atlas.tasks t
join atlas.farms f on f.id=t.farm_id and f.organization_id=t.organization_id
join atlas.work_execution_adapters a on a.task_id=t.id and a.state<>'retired'
join atlas.work_items wi on wi.organization_id=a.organization_id and wi.id=a.work_item_id
join atlas.farm_memberships fm on fm.id=t.assigned_membership_id
where t.status in ('open','blocked')
  and t.task_type<>'checklist_step'
  and t.assigned_user_id is not null
  and fm.user_id<>t.assigned_user_id
  and not exists (
    select 1 from atlas.work_planning_conflicts existing
    where existing.organization_id=wi.organization_id
      and existing.work_item_id=wi.id
      and existing.state='open'
      and existing.conflict_kind='no_eligible_assignee'
      and existing.metadata->>'sourceTaskId'=t.id::text
  );

-- 10. Convert independently actionable legacy parent/child structure into an
-- explicit Company Work `part_of` relation. Checklist components never enter
-- this statement because they never receive a work adapter.
insert into atlas.work_item_relations (
  organization_id,from_work_item_id,to_work_item_id,relation_kind,active,metadata
)
select
  child.organization_id,
  child_adapter.work_item_id,
  parent_adapter.work_item_id,
  'part_of',
  true,
  jsonb_build_object(
    'source','current_company_work_canonicalization_v1',
    'legacyChildTaskId',child.id,
    'legacyParentTaskId',parent.id
  )
from atlas.tasks child
join atlas.tasks parent
  on parent.id=coalesce(
    child.parent_task_id,
    case
      when child.metadata->>'parent_task_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then (child.metadata->>'parent_task_id')::uuid
      else null::uuid
    end
  )
join atlas.work_execution_adapters child_adapter
  on child_adapter.task_id=child.id and child_adapter.state<>'retired'
join atlas.work_execution_adapters parent_adapter
  on parent_adapter.task_id=parent.id and parent_adapter.state<>'retired'
where child.status in ('open','blocked')
  and child.task_type<>'checklist_step'
  and child_adapter.work_item_id<>parent_adapter.work_item_id
on conflict (from_work_item_id,to_work_item_id,relation_kind)
do update set active=true,
  metadata=atlas.work_item_relations.metadata || excluded.metadata,
  updated_at=now();

commit;
