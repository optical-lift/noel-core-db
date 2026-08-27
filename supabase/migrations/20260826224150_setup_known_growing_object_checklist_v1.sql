create or replace function atlas.ensure_setup_unit_checklist_v1(p_task_id uuid)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_task atlas.tasks%rowtype;
  v_object_type text;
  v_section_label text;
  v_item_key text;
  v_index integer := 0;
  v_object record;
begin
  select * into v_task
  from atlas.tasks
  where id = p_task_id;

  if v_task.id is null
     or coalesce(v_task.metadata->>'setup_unit_checklist','false') <> 'true'
     or coalesce(v_task.metadata->>'setup_unit_contract','') <> 'known_growing_objects_v1' then
    return 0;
  end if;

  v_object_type := nullif(btrim(v_task.metadata->>'setup_unit_object_type'),'');
  v_section_label := coalesce(nullif(btrim(v_task.metadata->>'execution_checklist_title'),''),'Checklist');

  update atlas.task_execution_checklist_items
  set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object('retired','true'),
      updated_at = now()
  where task_id = p_task_id
    and coalesce(metadata->>'setup_unit_component','false') = 'true';

  if v_task.zone_id is null or v_object_type is null then
    return 0;
  end if;

  for v_object in
    select go.id, go.stable_key, go.label, go.sort_order
    from atlas.growing_objects go
    where go.farm_id = v_task.farm_id
      and go.zone_id = v_task.zone_id
      and go.object_type = v_object_type
      and coalesce(go.metadata->>'retired','false') <> 'true'
    order by go.sort_order, go.stable_key
  loop
    v_index := v_index + 1;
    v_item_key := 'setup_unit:' || v_object.stable_key;

    insert into atlas.task_execution_checklist_items (
      farm_id,
      task_id,
      item_key,
      section_key,
      section_label,
      item_label,
      sort_order,
      required,
      checked,
      metadata
    ) values (
      v_task.farm_id,
      p_task_id,
      v_item_key,
      'setup_units',
      v_section_label,
      v_object.label,
      v_index * 10,
      true,
      false,
      jsonb_build_object(
        'setup_unit_component', true,
        'setup_unit_contract', 'known_growing_objects_v1',
        'setup_unit_object_type', v_object_type,
        'source', 'atlas.growing_objects',
        'growing_object_id', v_object.id,
        'growing_object_stable_key', v_object.stable_key,
        'retired', 'false'
      )
    )
    on conflict (task_id,item_key) do update
    set section_key = excluded.section_key,
        section_label = excluded.section_label,
        item_label = excluded.item_label,
        sort_order = excluded.sort_order,
        required = excluded.required,
        metadata = coalesce(atlas.task_execution_checklist_items.metadata,'{}'::jsonb) || excluded.metadata,
        updated_at = now();
  end loop;

  return v_index;
end;
$$;

create or replace function atlas.sync_setup_unit_checklist_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  perform atlas.ensure_setup_unit_checklist_v1(new.id);
  return new;
end;
$$;

drop trigger if exists sync_setup_unit_checklist_v1 on atlas.tasks;
create trigger sync_setup_unit_checklist_v1
after insert or update of metadata, zone_id on atlas.tasks
for each row
when ((new.metadata->>'setup_unit_contract') = 'known_growing_objects_v1')
execute function atlas.sync_setup_unit_checklist_v1();

revoke all on function atlas.ensure_setup_unit_checklist_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.sync_setup_unit_checklist_v1() from public, anon, authenticated;

update atlas.tasks t
set metadata = coalesce(t.metadata,'{}'::jsonb) || jsonb_build_object(
      'setup_unit_object_type', 'bed',
      'setup_unit_scope_semantics', 'snapshot_on_task_scope_change_v1'
    ),
    updated_at = now()
from atlas.zones z
where z.id = t.zone_id
  and t.task_type = 'site_layout'
  and t.action_key = 'measure_stake_string'
  and z.stable_key = 'u_pick'
  and t.metadata->>'setup_unit_contract' = 'known_growing_objects_v1'
  and coalesce(t.metadata->>'setup_unit_checklist','false') = 'true';

select atlas.ensure_setup_unit_checklist_v1(t.id)
from atlas.tasks t
where t.metadata->>'setup_unit_contract' = 'known_growing_objects_v1'
  and coalesce(t.metadata->>'setup_unit_checklist','false') = 'true';
