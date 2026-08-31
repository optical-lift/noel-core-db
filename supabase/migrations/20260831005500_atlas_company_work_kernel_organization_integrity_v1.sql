-- Atlas Company Work Kernel organization-integrity v1
-- Prevent cross-organization linkage or allocation even if a future API supplies mismatched UUIDs.

begin;

-- Composite uniqueness lets foreign keys carry organization identity alongside object identity.
create unique index if not exists organization_memberships_org_id_identity_idx
  on atlas.organization_memberships (organization_id, id);

create unique index if not exists work_requirements_org_id_identity_idx
  on atlas.work_requirements (organization_id, id);

create unique index if not exists work_items_org_id_identity_idx
  on atlas.work_items (organization_id, id);

create unique index if not exists work_allocations_org_id_identity_idx
  on atlas.work_allocations (organization_id, id);

-- Requirement links may only join requirement/work belonging to the same organization.
alter table atlas.work_requirement_links
  drop constraint if exists work_requirement_links_requirement_org_fk,
  add constraint work_requirement_links_requirement_org_fk
    foreign key (organization_id, requirement_id)
    references atlas.work_requirements (organization_id, id)
    on delete cascade;

alter table atlas.work_requirement_links
  drop constraint if exists work_requirement_links_work_org_fk,
  add constraint work_requirement_links_work_org_fk
    foreign key (organization_id, work_item_id)
    references atlas.work_items (organization_id, id)
    on delete cascade;

-- Allocation may only attach work to memberships inside the work's organization.
alter table atlas.work_allocations
  drop constraint if exists work_allocations_work_org_fk,
  add constraint work_allocations_work_org_fk
    foreign key (organization_id, work_item_id)
    references atlas.work_items (organization_id, id)
    on delete cascade;

alter table atlas.work_allocations
  drop constraint if exists work_allocations_assignee_org_fk,
  add constraint work_allocations_assignee_org_fk
    foreign key (organization_id, assignee_membership_id)
    references atlas.organization_memberships (organization_id, id);

alter table atlas.work_allocations
  drop constraint if exists work_allocations_assigner_org_fk,
  add constraint work_allocations_assigner_org_fk
    foreign key (organization_id, assigned_by_membership_id)
    references atlas.organization_memberships (organization_id, id);

-- Work relations cannot cross company boundaries.
alter table atlas.work_item_relations
  drop constraint if exists work_item_relations_from_org_fk,
  add constraint work_item_relations_from_org_fk
    foreign key (organization_id, from_work_item_id)
    references atlas.work_items (organization_id, id)
    on delete cascade;

alter table atlas.work_item_relations
  drop constraint if exists work_item_relations_to_org_fk,
  add constraint work_item_relations_to_org_fk
    foreign key (organization_id, to_work_item_id)
    references atlas.work_items (organization_id, id)
    on delete cascade;

-- Time truth belongs to the same organization as the work it governs.
alter table atlas.work_time_contracts
  drop constraint if exists work_time_contracts_work_org_fk,
  add constraint work_time_contracts_work_org_fk
    foreign key (organization_id, work_item_id)
    references atlas.work_items (organization_id, id)
    on delete cascade;

-- Planning conflicts cannot point across organizational boundaries.
alter table atlas.work_planning_conflicts
  drop constraint if exists work_planning_conflicts_work_org_fk,
  add constraint work_planning_conflicts_work_org_fk
    foreign key (organization_id, work_item_id)
    references atlas.work_items (organization_id, id)
    on delete cascade;

alter table atlas.work_planning_conflicts
  drop constraint if exists work_planning_conflicts_allocation_org_fk,
  add constraint work_planning_conflicts_allocation_org_fk
    foreign key (organization_id, allocation_id)
    references atlas.work_allocations (organization_id, id)
    on delete set null;

alter table atlas.work_planning_conflicts
  drop constraint if exists work_planning_conflicts_resolver_org_fk,
  add constraint work_planning_conflicts_resolver_org_fk
    foreign key (organization_id, resolved_by_membership_id)
    references atlas.organization_memberships (organization_id, id);

comment on index atlas.organization_memberships_org_id_identity_idx is
  'Supports organization-scoped custody FKs so Atlas work cannot be assigned across company boundaries.';

commit;
