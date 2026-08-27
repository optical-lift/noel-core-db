create or replace function atlas.task_execution_checklist_v1(
  p_task_id uuid,
  p_effective_membership_id uuid default null::uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_context jsonb;
  v_task atlas.tasks%rowtype;
  v_items jsonb;
  v_total integer;
  v_complete integer;
begin
  v_context := atlas.task_execution_checklist_context_v1(p_task_id, p_effective_membership_id);
  select * into v_task from atlas.tasks where id = p_task_id;

  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'itemId', item.id,
        'itemKey', item.item_key,
        'sectionKey', item.section_key,
        'sectionLabel', item.section_label,
        'label', item.item_label,
        'sortOrder', item.sort_order,
        'required', item.required,
        'checked', item.checked,
        'checkedAt', item.checked_at,
        'crossedOut', coalesce((item.metadata ->> 'crossedOut')::boolean,false),
        'interaction', nullif(item.metadata->>'interaction',''),
        'stationKey', nullif(item.metadata->>'stationKey',''),
        'stationLocation', nullif(item.metadata->>'stationLocation',''),
        'restockLabel', nullif(item.metadata->>'restockLabel','')
      ) order by item.sort_order, item.item_key
    ), '[]'::jsonb),
    count(*) filter (where coalesce(item.metadata ->> 'crossedOut','false') <> 'true')::integer,
    count(*) filter (where item.checked and coalesce(item.metadata ->> 'crossedOut','false') <> 'true')::integer
  into v_items, v_total, v_complete
  from atlas.task_execution_checklist_items item
  where item.task_id = p_task_id
    and coalesce(item.metadata ->> 'retired', 'false') <> 'true';

  return jsonb_build_object(
    'taskId', v_task.id,
    'title', coalesce(nullif(v_task.metadata ->> 'execution_checklist_title',''), v_task.title),
    'completionLabel', coalesce(nullif(v_task.metadata ->> 'execution_checklist_completion_label',''), 'Finish task'),
    'items', v_items,
    'totalCount', coalesce(v_total,0),
    'completeCount', coalesce(v_complete,0),
    'ready', not exists (
      select 1
      from atlas.task_execution_checklist_items required_item
      where required_item.task_id = p_task_id
        and required_item.required
        and not required_item.checked
        and coalesce(required_item.metadata ->> 'retired', 'false') <> 'true'
    ) and coalesce(v_total,0) > 0
  );
end;
$function$;

create or replace function atlas.normalize_ticketed_venue_prep_checklist_item_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_paid boolean := false;
  v_template text := '';
  v_hide boolean := false;
begin
  select
    coalesce((t.metadata->>'paid_event_scope')::boolean, false),
    coalesce(t.metadata->>'execution_checklist_template_key', '')
  into v_paid, v_template
  from atlas.tasks t
  where t.id = new.task_id;

  if v_template <> 'community_thursday_venue_prep_v1' then
    return new;
  end if;

  v_hide := new.item_key = 'blooms_unscheduled'
    or new.section_key = 'ticketed_event_theme'
    or new.item_key like 'theme_%'
    or (
      v_paid
      and new.item_key in (
        'coffee_keuring',
        'coffee_grounds',
        'coffee_milk',
        'coffee_syrup',
        'coffee_mug_hutch',
        'water_cups',
        'coffee_paper_disposable_cups'
      )
    );

  if v_hide then
    if tg_op = 'INSERT' then
      return null;
    end if;
    new.required := false;
    new.metadata := coalesce(new.metadata, '{}'::jsonb)
      || jsonb_build_object('retired', true, 'retiredBy', 'ticketed_venue_prep_hospitality_tree_v1');
    return new;
  end if;

  if v_paid and new.item_key = 'water_dispenser' then
    new.section_key := 'hospitality';
    new.section_label := 'Hospitality';
    new.item_label := 'Water station · Confirm the water dispenser is full';
    new.sort_order := 65;
    new.metadata := coalesce(new.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'source', 'venue_prep_required_action',
        'stationKey', 'water_station',
        'stationLocation', 'Dining room',
        'interaction', 'action',
        'paidEventVariant', true
      );
  end if;

  return new;
end;
$function$;

drop trigger if exists normalize_ticketed_venue_prep_checklist_item_v1
  on atlas.task_execution_checklist_items;

create trigger normalize_ticketed_venue_prep_checklist_item_v1
before insert or update on atlas.task_execution_checklist_items
for each row
execute function atlas.normalize_ticketed_venue_prep_checklist_item_v1();

update atlas.community_events
set metadata = coalesce(metadata, '{}'::jsonb)
    || jsonb_build_object('eventSubtitle', 'Flowers + Seeds'),
    updated_at = now()
where stable_key = 'thursdays_at_elm_2026_08_27_evening'
  and event_kind = 'ticketed_seasonal_evening'
  and event_date = date '2026-08-27';

update atlas.tasks
set metadata = coalesce(metadata, '{}'::jsonb)
    || jsonb_build_object('community_event_subtitle', 'Flowers + Seeds'),
    updated_at = now()
where metadata->>'community_event_key' = 'thursdays_at_elm_2026_08_27_evening'
  and metadata->>'execution_checklist_template_key' = 'community_thursday_venue_prep_v1';

delete from atlas.task_execution_checklist_items item
using atlas.tasks task
where item.task_id = task.id
  and task.metadata->>'execution_checklist_template_key' = 'community_thursday_venue_prep_v1'
  and (
    item.item_key = 'blooms_unscheduled'
    or item.section_key = 'ticketed_event_theme'
    or item.item_key like 'theme_%'
    or (
      coalesce((task.metadata->>'paid_event_scope')::boolean, false)
      and item.item_key in (
        'coffee_keuring',
        'coffee_grounds',
        'coffee_milk',
        'coffee_syrup',
        'coffee_mug_hutch',
        'water_cups',
        'coffee_paper_disposable_cups'
      )
    )
  );

update atlas.task_execution_checklist_items item
set section_key = 'hospitality',
    section_label = 'Hospitality',
    item_label = 'Water station · Confirm the water dispenser is full',
    sort_order = 65,
    metadata = coalesce(item.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'source', 'venue_prep_required_action',
        'stationKey', 'water_station',
        'stationLocation', 'Dining room',
        'interaction', 'action',
        'paidEventVariant', true
      ),
    updated_at = now()
from atlas.tasks task
where item.task_id = task.id
  and item.item_key = 'water_dispenser'
  and task.metadata->>'execution_checklist_template_key' = 'community_thursday_venue_prep_v1'
  and coalesce((task.metadata->>'paid_event_scope')::boolean, false);