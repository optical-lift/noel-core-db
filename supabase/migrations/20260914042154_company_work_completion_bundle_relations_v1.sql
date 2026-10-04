create or replace function atlas.complete_company_work_bundle_members_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_now timestamptz := coalesce(new.completed_at, clock_timestamp());
begin
  if old.work_state is distinct from new.work_state and new.work_state='completed' then
    update atlas.work_items child
    set work_state='completed',
        completed_at=coalesce(child.completed_at,v_now),
        metadata=coalesce(child.metadata,'{}'::jsonb)||jsonb_build_object(
          'completedViaBundleWorkItemId',new.id,
          'completedViaBundleAt',v_now
        ),
        updated_at=v_now
    where child.id in (
      select r.to_work_item_id
      from atlas.work_item_relations r
      where r.organization_id=new.organization_id
        and r.from_work_item_id=new.id
        and r.relation_kind='completion_bundle_member'
        and r.active
        and r.to_work_item_id<>new.id
    )
      and child.organization_id=new.organization_id
      and child.work_state='open';

    update atlas.work_allocations a
    set state='completed',
        completed_at=coalesce(a.completed_at,v_now),
        updated_at=v_now
    where a.work_item_id in (
      select r.to_work_item_id
      from atlas.work_item_relations r
      where r.organization_id=new.organization_id
        and r.from_work_item_id=new.id
        and r.relation_kind='completion_bundle_member'
        and r.active
    ) and a.state='active';

    update atlas.work_item_relations r
    set satisfied_at=coalesce(r.satisfied_at,v_now),updated_at=v_now
    where r.organization_id=new.organization_id
      and r.from_work_item_id=new.id
      and r.relation_kind='completion_bundle_member'
      and r.active;
  end if;
  return new;
end;
$function$;

drop trigger if exists work_items_complete_bundle_members_v1 on atlas.work_items;
create trigger work_items_complete_bundle_members_v1
after update of work_state on atlas.work_items
for each row execute function atlas.complete_company_work_bundle_members_v1();