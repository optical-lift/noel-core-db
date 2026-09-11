-- Atlas Current Company Work Canonicalization v1 verification
-- Run after the read-authority and current-work canonicalization migrations.

-- 1. No current company-work identity remains to create or repair.
select work_identity_position,count(*) as rows
from atlas.legacy_company_work_canonicalization_audit_v1
where legacy_status in ('open','blocked')
  and company_scope_position='current_company_work'
group by work_identity_position
order by work_identity_position;
-- Expected cutover shape at the audited fixture:
-- already_mapped = 101
-- execution_only = 9
-- create_work_item = 0
-- map_existing_work_item = 0

-- 2. The execution-only rows are checklist/result components, not Ledger rows.
select legacy_task_id,legacy_title,effective_parent_task_id,task_type
from atlas.legacy_company_work_canonicalization_audit_v1
where legacy_status in ('open','blocked')
  and company_scope_position='current_company_work'
  and work_identity_position='execution_only';
-- Expected: 9 rows; each task_type=checklist_step and each has a parent.

-- 3. Canonical Company Work population grew by work identity, not by every old row.
select count(*) as canonical_work_items from atlas.work_items;
-- Audited rollback projection: 157 total after current cutover.

-- 4. Current named responsibility remains truthful when membership is inactive.
select responsibility_display_name,responsibility_position,count(*) as open_work
from atlas.company_work_ledger_v1
where is_open and responsibility_user_id is not null
group by responsibility_display_name,responsibility_position
order by responsibility_display_name,responsibility_position;
-- Expected: inactive named people appear as unresolved_named, not allocated or unassigned.

-- 5. No unlawful active responsibility allocations.
select wa.id,wa.work_item_id,wa.assignee_membership_id
from atlas.work_allocations wa
left join atlas.organization_memberships om
  on om.organization_id=wa.organization_id
 and om.id=wa.assignee_membership_id
where wa.state='active'
  and wa.allocation_role='responsible'
  and coalesce(om.active,false)=false;
-- Expected: zero rows.

-- 6. Named-but-inactive responsibility is backed by canonical conflict truth.
select up.display_name,count(distinct pc.work_item_id) as work_items
from atlas.work_planning_conflicts pc
join atlas.user_profiles up
  on up.user_id=(pc.metadata->>'assignedUserId')::uuid
where pc.state='open'
  and pc.conflict_kind='no_eligible_assignee'
  and pc.metadata->>'assignedUserId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
group by up.display_name
order by up.display_name;
-- Audited rollback projection before any membership repair: Anna 45, Marshall 3
-- from current legacy responsibility evidence, plus any independently-existing
-- canonical no_eligible_assignee conflicts that remain valid.

-- 7. Independently actionable legacy children became Company Work relations.
select count(*) as adopted_part_of_relations
from atlas.work_item_relations
where active
  and relation_kind='part_of'
  and metadata->>'source'='current_company_work_canonicalization_v1';
-- Audited rollback projection: 15.

-- 8. Legacy due dates adopted by this cutover are preferred targets only.
select wi.id,wi.title,tc.preferred_end_at,tc.latest_lawful_at,tc.hard_finish_at,tc.metadata
from atlas.work_items wi
join atlas.work_time_contracts tc
  on tc.work_item_id=wi.id and tc.contract_state='active'
where wi.metadata->>'currentCompanyWorkCanonicalization'='v1'
  and tc.source_kind='legacy_task';
-- Expected for these adoption-owned contracts: preferred_end_at may be set;
-- latest_lawful_at and hard_finish_at remain null; metadata marks target-not-hard-law.

-- 9. Scope-review rows remain explicit rather than silently included/excluded.
select legacy_task_id,legacy_title,organization_id,farm_id,task_scope,origin_kind
from atlas.legacy_company_work_canonicalization_audit_v1
where legacy_status in ('open','blocked')
  and company_scope_position='scope_review';
-- Audit point: one row. Must be explicitly adjudicated before claiming that
-- every nonterminal legacy row has been semantically retired.

-- 10. Governed retrieval sees the same canonical population.
select count(*) as open_company_work
from atlas.get_company_work_v1(
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  p_work_states=>array['open']
);

-- 11. Anna lens includes both lawful and unresolved named responsibility.
select responsibility_position,count(*)
from atlas.get_company_work_v1(
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  p_responsibility_user_id=>'21436a28-40fd-4914-8015-a248d0dca14e'::uuid,
  p_work_states=>array['open']
)
group by responsibility_position
order by responsibility_position;

-- 12. Unassigned means genuinely unnamed responsibility only.
select count(*) as truly_unassigned_open
from atlas.get_company_work_v1(
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  p_responsibility_positions=>array['unassigned'],
  p_work_states=>array['open']
);
