do $migration$
declare
  v_farm_id uuid;
  v_arch1 uuid;
  v_arch2 uuid;
  v_a1_left uuid;
  v_a1_right uuid;
  v_a2_left uuid;
  v_a2_right uuid;
begin
  select id into v_farm_id from atlas.farms where stable_key='elm_farm' limit 1;
  if v_farm_id is null then raise exception 'Elm Farm not found'; end if;

  select id into v_arch1 from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01';
  select id into v_arch2 from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02';
  select id into v_a1_left from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01_left_bed';
  select id into v_a1_right from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_01_right_bed';
  select id into v_a2_left from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02_left_bed';
  select id into v_a2_right from atlas.growing_objects where farm_id=v_farm_id and stable_key='curve_arch_02_right_bed';

  if v_arch1 is null or v_arch2 is null or v_a1_left is null or v_a1_right is null or v_a2_left is null or v_a2_right is null then
    raise exception 'Curve Garden arch geometry is incomplete';
  end if;

  alter table atlas.growing_objects drop constraint if exists growing_objects_object_type_check;
  alter table atlas.growing_objects add constraint growing_objects_object_type_check
    check (object_type = any(array['bed','path','arch_bed','component','area','corridor','seed_room','zone_summary','room']::text[]));

  update atlas.growing_objects
  set object_type='component',
      object_mode='component',
      metadata=(coalesce(metadata,'{}'::jsonb)
        - 'occupancy_independent_of_foot_beds')
        || jsonb_build_object(
          'component_kind','arch',
          'component_scope','shared_between_left_and_right_raised_beds',
          'independent_task_surface',false,
          'can_carry_crop_occupancy',true,
          'occupancy_independent_of_ground_bed',true,
          'owner_confirmed_component_model',true,
          'component_model_source','owner_report_20260826'
        ),
      updated_at=now()
  where id in (v_arch1,v_arch2);

  update atlas.growing_objects
  set metadata=(coalesce(metadata,'{}'::jsonb)
        - 'arch_foot_bed'
        - 'occupancy_independent_of_arch_surface')
      || jsonb_build_object(
        'contains_arch_component',true,
        'ground_crop_occupancy_independent_of_component_occupancy',true,
        'component_model_source','owner_report_20260826'
      ),
      updated_at=now()
  where id in (v_a1_left,v_a1_right,v_a2_left,v_a2_right);

  insert into atlas.growing_object_relationships(farm_id,parent_object_id,child_object_id,relationship_type,position_label,sort_order,metadata)
  values
    (v_farm_id,v_a1_left,v_arch1,'contains','shared arch component · left side',10,jsonb_build_object('childRole','bed_component','componentKind','arch','bedSide','left','sharedWithSiblingBed',true,'source','owner_report_20260826')),
    (v_farm_id,v_a1_right,v_arch1,'contains','shared arch component · right side',10,jsonb_build_object('childRole','bed_component','componentKind','arch','bedSide','right','sharedWithSiblingBed',true,'source','owner_report_20260826')),
    (v_farm_id,v_a2_left,v_arch2,'contains','shared arch component · left side',10,jsonb_build_object('childRole','bed_component','componentKind','arch','bedSide','left','sharedWithSiblingBed',true,'source','owner_report_20260826')),
    (v_farm_id,v_a2_right,v_arch2,'contains','shared arch component · right side',10,jsonb_build_object('childRole','bed_component','componentKind','arch','bedSide','right','sharedWithSiblingBed',true,'source','owner_report_20260826'))
  on conflict(parent_object_id,child_object_id,relationship_type) do update
    set position_label=excluded.position_label,
        sort_order=excluded.sort_order,
        metadata=excluded.metadata,
        updated_at=now();

  delete from atlas.task_objects x
  using atlas.tasks t
  where x.task_id=t.id
    and t.farm_id=v_farm_id
    and x.role='capacity_surface'
    and x.object_id in (v_arch1,v_arch2)
    and coalesce(t.metadata->>'weed_management_mode','')='clear_selected_crop'
    and coalesce(t.metadata->>'selected_crop_label','')='Muncher Cucumber';

  update atlas.tasks t
  set metadata=(coalesce(t.metadata,'{}'::jsonb)-'arch_surface_stable_key'-'arch_surface_side')
      || jsonb_build_object(
        'bed_component_kind','arch',
        'bed_component_side','left',
        'component_is_not_task_surface',true,
        'component_model_source','owner_report_20260826'
      ),
      updated_at=now()
  where t.farm_id=v_farm_id
    and t.status in ('open','blocked')
    and coalesce(t.metadata->>'weed_management_mode','')='clear_selected_crop'
    and coalesce(t.metadata->>'selected_crop_label','')='Muncher Cucumber'
    and coalesce(t.metadata->>'root_bed_stable_key','') in ('curve_arch_01_left_bed','curve_arch_02_left_bed');
end
$migration$;

create or replace function atlas.bed_components_state_v1(p_bed_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_bed atlas.growing_objects%rowtype;
  v_role text;
  v_result jsonb;
begin
  select * into v_bed from atlas.growing_objects where id=p_bed_id;
  if v_bed.id is null then raise exception 'Growing object not found.' using errcode='P0002'; end if;

  v_role:=atlas.current_farm_role(v_bed.farm_id);
  if not atlas.is_farm_owner(v_bed.farm_id) and coalesce(v_role,'') not in ('farm_hand','manager') then
    raise exception 'Bed components are not available to the signed-in farm member.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'componentId',c.id,
    'componentKey',c.stable_key,
    'componentLabel',c.label,
    'componentKind',coalesce(c.metadata->>'component_kind','component'),
    'positionLabel',r.position_label,
    'relationshipMetadata',r.metadata,
    'occupancyState',coalesce(o.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((o.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(o.occ->'groups','[]'::jsonb)
  ) order by r.sort_order,c.label),'[]'::jsonb)
  into v_result
  from atlas.growing_object_relationships r
  join atlas.growing_objects c on c.id=r.child_object_id
  left join lateral (select atlas.object_crop_occupancy_v1(c.id) as occ) o on true
  where r.parent_object_id=v_bed.id
    and r.relationship_type='contains'
    and c.object_type='component';

  return jsonb_build_object(
    'bedId',v_bed.id,
    'bedKey',v_bed.stable_key,
    'bedLabel',v_bed.label,
    'components',coalesce(v_result,'[]'::jsonb)
  );
end;
$function$;

grant execute on function atlas.bed_components_state_v1(uuid) to authenticated, service_role;
