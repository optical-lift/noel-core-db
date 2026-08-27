drop trigger if exists sync_setup_unit_checklist_v1 on atlas.tasks;

update atlas.task_execution_checklist_items canonical
set checked = canonical.checked or duplicate.checked,
    checked_at = case
      when duplicate.checked and (canonical.checked_at is null or duplicate.checked_at > canonical.checked_at) then duplicate.checked_at
      else canonical.checked_at
    end,
    checked_by_membership_id = case
      when duplicate.checked and (canonical.checked_at is null or duplicate.checked_at > canonical.checked_at) then duplicate.checked_by_membership_id
      else canonical.checked_by_membership_id
    end,
    updated_at = now()
from atlas.task_execution_checklist_items duplicate
where duplicate.task_id = canonical.task_id
  and coalesce(duplicate.metadata->>'setup_unit_component','false') = 'true'
  and canonical.item_key = duplicate.metadata->>'growing_object_stable_key'
  and canonical.metadata->>'setupUnitContract' = 'known_growing_objects_v1';

delete from atlas.task_execution_checklist_items item
where coalesce(item.metadata->>'setup_unit_component','false') = 'true'
  and item.metadata->>'setup_unit_contract' = 'known_growing_objects_v1'
  and item.metadata->>'source' = 'atlas.growing_objects';

update atlas.tasks
set metadata = metadata - 'setup_unit_object_type' - 'setup_unit_scope_semantics',
    updated_at = now()
where metadata->>'setup_unit_scope_semantics' = 'snapshot_on_task_scope_change_v1';

drop function if exists atlas.sync_setup_unit_checklist_v1();
drop function if exists atlas.ensure_setup_unit_checklist_v1(uuid);
