begin;

drop policy if exists tasks_read_authorized on atlas.tasks;

create policy tasks_read_authorized
on atlas.tasks
for select
to authenticated
using (
  atlas.is_farm_owner(farm_id)
  or (
    atlas.current_farm_role(farm_id) = 'manager'
    and visibility_scope = any (array['management'::text, 'assigned_worker'::text, 'farm_shared'::text])
  )
  or assigned_user_id = auth.uid()
  or assigned_membership_id = atlas.current_membership_id(farm_id)
  or exists (
    select 1
    from atlas.project_task_links ptl
    where ptl.task_id = tasks.id
      and atlas.can_read_project(ptl.project_id)
  )
);

commit;