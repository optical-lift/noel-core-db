create or replace function atlas.weed_selected_crop_turnover_focus_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_role text;
  v_membership_id uuid;
  v_beds jsonb;
  v_surfaces jsonb;
  v_zone_label text;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Task not found.' using errcode='P0002'; end if;

  v_role:=atlas.current_farm_role(v_task.farm_id);
  v_membership_id:=atlas.current_membership_id(v_task.farm_id);
  if not atlas.is_farm_owner(v_task.farm_id)
     and not (v_role in ('farm_hand','manager') and v_membership_id is not null and v_task.assigned_membership_id=v_membership_id)
  then
    raise exception 'This Weed turnover card is not available to the signed-in farm member.' using errcode='42501';
  end if;

  if coalesce(v_task.metadata->>'weed_management_mode','')<>'clear_selected_crop' then
    return null;
  end if;

  select cc.* into v_cycle
  from atlas.task_crop_cycles tc join atlas.crop_cycles cc on cc.id=tc.crop_cycle_id
  where tc.task_id=v_task.id and tc.role='clears'
  order by tc.created_at limit 1;
  if v_cycle.id is null then raise exception 'Selected crop turnover has no crop body.' using errcode='P0002'; end if;

  select z.label into v_zone_label
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join atlas.zones z on z.id=go.zone_id
  where x.task_id=v_task.id and x.role='work_carrier'
  order by go.sort_order,go.label limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId',go.id,
    'objectKey',go.stable_key,
    'objectLabel',go.label,
    'cardId',wc.id,
    'occupancyState',coalesce(q.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((q.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(q.occ->'groups','[]'::jsonb)
  ) order by go.sort_order,go.label),'[]'::jsonb) into v_beds
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join atlas.weed_cards wc on wc.object_id=go.id
  left join lateral (select atlas.object_crop_occupancy_v1(go.id) as occ) q on true
  where x.task_id=v_task.id and x.role='work_carrier';

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId',go.id,
    'objectKey',go.stable_key,
    'objectLabel',go.label,
    'occupancyState',coalesce(q.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((q.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(q.occ->'groups','[]'::jsonb)
  ) order by go.sort_order,go.label),'[]'::jsonb) into v_surfaces
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join lateral (select atlas.object_crop_occupancy_v1(go.id) as occ) q on true
  where x.task_id=v_task.id and x.role='capacity_surface';

  return jsonb_build_object(
    'contractVersion','weed_selected_crop_turnover_focus_v1',
    'taskId',v_task.id,
    'taskStatus',v_task.status,
    'taskDueDate',v_task.due_date,
    'mode','clear_selected_crop',
    'zoneLabel',coalesce(v_zone_label,'Elm Farm'),
    'collectionLabel',coalesce(nullif(v_task.metadata->>'turnover_collection_label',''),v_task.metadata->>'display_location','Bed turnover'),
    'selectedCrop',jsonb_build_object(
      'cropCycleId',v_cycle.id,
      'cropLabel',v_cycle.crop_label,
      'variety',v_cycle.variety,
      'cycleState',v_cycle.cycle_state,
      'biomassDestination',v_task.metadata->>'biomass_destination'
    ),
    'wholeBedTurnover',false,
    'rootBedPositionKnown',coalesce((v_task.metadata->>'selected_crop_root_bed_position_known')::boolean,false),
    'beds',v_beds,
    'capacitySurfaces',v_surfaces
  );
end;
$function$;