create or replace function atlas.normalize_task_execution_resource_issue_semantics_v1()
returns trigger
language plpgsql
set search_path = atlas, public
as $$
declare
  v_metadata jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  if new.item_key = 'hospitality_pastry_box'
     or coalesce(v_metadata ->> 'entity', '') = 'pastry_box'
     or coalesce(v_metadata ->> 'stationKey', '') = 'pastry_box'
  then
    v_metadata := v_metadata || jsonb_build_object('supplyMode', 'event_supplied');
  end if;

  if coalesce(v_metadata ->> 'supplyMode', '') = 'event_supplied' then
    v_metadata := v_metadata - 'restockLabel';
  end if;

  new.metadata := v_metadata;
  return new;
end;
$$;

comment on function atlas.normalize_task_execution_resource_issue_semantics_v1() is
  'Normalizes checklist resource issue affordances: event-supplied resources never carry continuous-restock metadata; pastry boxes are canonical event-supplied resources.';

drop trigger if exists trg_task_execution_resource_issue_semantics_v1
  on atlas.task_execution_checklist_items;

create trigger trg_task_execution_resource_issue_semantics_v1
before insert or update of item_key, metadata
on atlas.task_execution_checklist_items
for each row
execute function atlas.normalize_task_execution_resource_issue_semantics_v1();

update atlas.task_execution_checklist_items
set metadata = (
      coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object('supplyMode', 'event_supplied')
    ) - 'restockLabel',
    updated_at = now()
where item_key = 'hospitality_pastry_box'
   or coalesce(metadata ->> 'entity', '') = 'pastry_box'
   or coalesce(metadata ->> 'stationKey', '') = 'pastry_box';