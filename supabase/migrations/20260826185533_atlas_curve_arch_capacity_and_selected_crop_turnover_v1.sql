-- Atlas Curve Garden arch capacity + selected-crop Weed turnover v1
--
-- Separates the vertical arch planting surface from the beds at its feet, makes
-- crop placements authoritative spatial occupancy evidence, and carries the
-- Muncher cucumber cleanup as a bed-maintenance / Weed-card turnover operation
-- that clears one crop body without clearing the whole bed.

alter table atlas.growing_object_relationships
  drop constraint if exists growing_object_relationships_relationship_type_check;
alter table atlas.growing_object_relationships
  add constraint growing_object_relationships_relationship_type_check
  check (relationship_type = any (array[
    'contains'::text,'adjacent'::text,'destination'::text,'travels_with'::text,'side_bed_of'::text
  ]));

create or replace function atlas.object_crop_occupancy_v1(p_object_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $$
declare
  v_object atlas.growing_objects%rowtype;
  v_role text;
  v_result jsonb;
begin
  select go.* into v_object from atlas.growing_objects go where go.id=p_object_id;
  if v_object.id is null then
    raise exception 'Growing object not found.' using errcode='P0002';
  end if;

  v_role := atlas.current_farm_role(v_object.farm_id);
  if not atlas.is_farm_owner(v_object.farm_id) and coalesce(v_role,'') not in ('farm_hand','manager') then
    raise exception 'Crop occupancy is not available to the signed-in farm member.' using errcode='42501';
  end if;

  with cycle_enriched as (
    select
      cc.id as crop_cycle_id,
      cc.crop_label,
      cc.variety,
      cc.cycle_state,
      cc.sown_date,
      cc.planted_date,
      pc.planted_date as claim_planted_date,
      cp.life_cycle,
      coalesce(cc.planted_date,cc.sown_date,pc.planted_date) as establishment_date,
      case
        when cc.planted_date is not null then 'planted'
        when cc.sown_date is not null then 'sown'
        when pc.planted_date is not null then 'planting_claim'
        else 'unknown'
      end as date_source,
      (
        lower(coalesce(cp.life_cycle,''))='perennial'
        or exists(
          select 1
          from atlas.crop_occupancy_evidence e
          join atlas.object_contents oc on oc.id=e.object_content_id
          where e.crop_cycle_id=cc.id and lower(coalesce(oc.content_type,'')) like '%perennial%'
        )
      ) as is_perennial,
      case
        when lower(cc.crop_label)='sunflower' and nullif(btrim(coalesce(cc.variety,'')),'') is not null
          then btrim(cc.variety)||' sunflower'
        when lower(cc.crop_label) in ('bearded iris','iris') then 'Iris'
        else cc.crop_label
      end as display_label,
      p.id as placement_id,
      p.placement_mode,
      p.placement_label,
      p.row_count,
      p.row_length_ft,
      p.area_sqft,
      p.explicit_plant_count,
      p.clump_count,
      p.spacing_in,
      p.plants_per_sqft,
      p.expected_quantity,
      p.expected_quantity_kind,
      p.expected_quantity_unit,
      p.expected_quantity_basis,
      p.confidence as placement_confidence,
      coalesce(cell_counts.cell_count,0) as cell_count,
      latest_observation.id as latest_observation_id,
      latest_observation.observed_date as latest_observed_date,
      latest_observation.stage as observed_stage,
      latest_observation.observed_quantity,
      latest_observation.quantity_unit as observed_quantity_unit,
      latest_observation.quantity_kind as observed_quantity_kind,
      latest_observation.stand_percent,
      latest_observation.condition,
      latest_observation.confidence as observation_confidence,
      first_observation.first_observed_date
    from atlas.crop_cycles cc
    left join atlas.planting_claims pc on pc.id=cc.planting_claim_id
    left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
    left join lateral (
      select p0.*
      from atlas.crop_placements p0
      where p0.crop_cycle_id=cc.id and p0.object_id=p_object_id
      order by
        (p0.expected_quantity_kind='recorded') desc,
        (p0.expected_quantity is not null) desc,
        p0.created_at
      limit 1
    ) p on true
    left join lateral (
      select count(*)::integer as cell_count
      from atlas.crop_placement_cells c where c.placement_id=p.id
    ) cell_counts on true
    left join lateral (
      select o.*
      from atlas.crop_observations o
      where o.crop_cycle_id=cc.id
      order by o.observed_date desc nulls last,o.created_at desc
      limit 1
    ) latest_observation on true
    left join lateral (
      select min(o.observed_date) as first_observed_date
      from atlas.crop_observations o
      where o.crop_cycle_id=cc.id and o.observed_date is not null
    ) first_observation on true
    where cc.lifecycle_status='active'
      and (
        cc.object_id=p_object_id
        or exists(
          select 1 from atlas.crop_placements px
          where px.crop_cycle_id=cc.id and px.object_id=p_object_id
        )
      )
  ), active_cycles as (
    select
      ce.*,
      coalesce(ce.observed_stage,atlas.crop_stage_from_state_v1(ce.cycle_state,ce.life_cycle)) as stage,
      atlas.crop_stage_label_v1(coalesce(ce.observed_stage,atlas.crop_stage_from_state_v1(ce.cycle_state,ce.life_cycle))) as stage_label,
      atlas.crop_placement_summary_v1(
        ce.placement_mode,ce.row_count,ce.row_length_ft,ce.area_sqft,
        ce.explicit_plant_count,ce.clump_count,ce.placement_label
      ) as placement_summary,
      case
        when ce.is_perennial then 'perennial'
        when ce.establishment_date is not null then 'dated'
        when ce.first_observed_date is not null then 'observed'
        else 'unknown'
      end as group_kind,
      case
        when ce.is_perennial then null
        when ce.establishment_date is not null then ce.establishment_date
        else ce.first_observed_date
      end as group_date
    from cycle_enriched ce
  ), visible_cycles as (
    select * from active_cycles
    where coalesce(stage,'unknown') not in ('cleared','failed','dead','absent','abandoned','archived','removed','inactive')
  ), cohort_rows as (
    select
      vc.*,
      case vc.group_kind
        when 'dated' then to_char(vc.group_date,'Mon FMDD')
        when 'observed' then 'Observed '||to_char(vc.group_date,'Mon FMDD')
        when 'perennial' then 'Perennial'
        else 'Date unknown'
      end as group_label,
      case vc.group_kind when 'dated' then 1 when 'observed' then 2 when 'perennial' then 3 else 4 end as group_rank
    from visible_cycles vc
  ), distinct_groups as (
    select distinct group_kind,group_date,group_label,group_rank
    from cohort_rows
  )
  select jsonb_build_object(
    'objectId',v_object.id,
    'objectKey',v_object.stable_key,
    'objectLabel',v_object.label,
    'lengthFt',v_object.length_ft,
    'widthFt',v_object.width_ft,
    'areaSqft',v_object.area_sqft,
    'occupancyState',case when exists(select 1 from visible_cycles) then 'occupied' else 'empty' end,
    'availableForPlanting',not exists(select 1 from visible_cycles),
    'groups',coalesce(jsonb_agg(
      jsonb_build_object(
        'groupKind',g.group_kind,
        'groupDate',g.group_date,
        'groupLabel',g.group_label,
        'cohorts',(
          select coalesce(jsonb_agg(
            jsonb_strip_nulls(jsonb_build_object(
              'cropCycleId',c.crop_cycle_id,
              'cropLabel',c.crop_label,
              'displayLabel',c.display_label,
              'variety',c.variety,
              'lifeCycle',case when c.is_perennial then 'perennial' else coalesce(c.life_cycle,'annual') end,
              'establishmentDate',c.establishment_date,
              'dateSource',c.date_source,
              'stage',c.stage,
              'stageLabel',c.stage_label,
              'placementId',c.placement_id,
              'placementMode',c.placement_mode,
              'placementLabel',c.placement_label,
              'placementSummary',c.placement_summary,
              'rowCount',c.row_count,
              'rowLengthFt',c.row_length_ft,
              'areaSqft',c.area_sqft,
              'cellCount',c.cell_count,
              'spacingIn',c.spacing_in,
              'plantsPerSqft',c.plants_per_sqft,
              'expectedQuantity',c.expected_quantity,
              'expectedQuantityKind',c.expected_quantity_kind,
              'expectedQuantityUnit',c.expected_quantity_unit,
              'expectedQuantityBasis',c.expected_quantity_basis,
              'observedQuantity',c.observed_quantity,
              'observedQuantityUnit',c.observed_quantity_unit,
              'observedQuantityKind',c.observed_quantity_kind,
              'observedQuantityDate',c.latest_observed_date,
              'standPercent',c.stand_percent,
              'condition',c.condition,
              'confidence',coalesce(c.observation_confidence,c.placement_confidence,'medium')
            )) order by c.display_label,c.crop_cycle_id
          ),'[]'::jsonb)
          from cohort_rows c
          where c.group_kind=g.group_kind and c.group_date is not distinct from g.group_date
        )
      ) order by g.group_rank,g.group_date nulls last
    ),'[]'::jsonb)
  ) into v_result
  from distinct_groups g;

  return coalesce(v_result,jsonb_build_object(
    'objectId',v_object.id,'objectKey',v_object.stable_key,'objectLabel',v_object.label,
    'lengthFt',v_object.length_ft,'widthFt',v_object.width_ft,'areaSqft',v_object.area_sqft,
    'occupancyState','empty','availableForPlanting',true,'groups','[]'::jsonb
  ));
end;
$$;

create or replace function atlas.weed_selected_crop_turnover_focus_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $$
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
    'occupancyState',coalesce(occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(occ->'groups','[]'::jsonb)
  ) order by go.sort_order,go.label),'[]'::jsonb) into v_beds
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join atlas.weed_cards wc on wc.object_id=go.id
  left join lateral (select atlas.object_crop_occupancy_v1(go.id) as occ) q on true
  cross join lateral (select q.occ) o(occ)
  where x.task_id=v_task.id and x.role='work_carrier';

  select coalesce(jsonb_agg(jsonb_build_object(
    'objectId',go.id,
    'objectKey',go.stable_key,
    'objectLabel',go.label,
    'occupancyState',coalesce(occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(occ->'groups','[]'::jsonb)
  ) order by go.sort_order,go.label),'[]'::jsonb) into v_surfaces
  from atlas.task_objects x
  join atlas.growing_objects go on go.id=x.object_id
  left join lateral (select atlas.object_crop_occupancy_v1(go.id) as occ) q on true
  cross join lateral (select q.occ) o(occ)
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
$$;

revoke all on function atlas.weed_selected_crop_turnover_focus_v1(uuid) from public,anon;
grant execute on function atlas.weed_selected_crop_turnover_focus_v1(uuid) to authenticated,service_role;

create or replace function atlas.sync_completed_crop_cycle_clear_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_cycle record;
  v_clear_date date;
  v_destination text;
  v_selected_turnover boolean;
begin
  v_selected_turnover := new.task_type='maintenance'
    and new.action_key='weed'
    and coalesce(new.metadata->>'weed_management_mode','')='clear_selected_crop';

  if new.status<>'done' or old.status='done'
     or not (new.task_type='crop_clear' or v_selected_turnover)
  then
    return new;
  end if;

  v_clear_date:=coalesce((new.completed_at at time zone 'America/Chicago')::date,(now() at time zone 'America/Chicago')::date);
  v_destination:=coalesce(nullif(new.metadata->>'biomass_destination',''),'compost');

  for v_cycle in
    select cc.* from atlas.task_crop_cycles tc join atlas.crop_cycles cc on cc.id=tc.crop_cycle_id
    where tc.task_id=new.id and tc.role='clears'
  loop
    update atlas.crop_cycles
    set cycle_state='cleared',lifecycle_status='complete',cleared_date=v_clear_date,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'clear_task_id',new.id,
          'biomass_destination',v_destination,
          'postproduction_completed_at',v_clear_date,
          'object_vacancy_not_inferred',true,
          'spatial_capacity_recomputed_from_active_crop_bodies',true
        ),updated_at=now()
    where id=v_cycle.id;

    update atlas.object_contents
    set status='cleared',clear_bed_date=v_clear_date,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'clear_task_id',new.id,'biomass_destination',v_destination
        ),updated_at=now()
    where id=v_cycle.object_content_id;

    insert into atlas.crop_observations(
      farm_id,object_id,crop_cycle_id,object_content_id,observed_date,stage,condition,
      confidence,source_kind,source_id,note,idempotency_key,metadata
    ) values(
      v_cycle.farm_id,v_cycle.object_id,v_cycle.id,v_cycle.object_content_id,v_clear_date,'cleared','removed',
      'high','task_result',new.id::text,
      v_cycle.crop_label||' crop body was physically cleared; removed biomass was taken to '||v_destination||'.',
      'crop-clear:'||new.id::text||':'||v_cycle.id::text,
      jsonb_build_object('biomassDestination',v_destination,'cropCompletionDoesNotImplyObjectVacancy',true)
    ) on conflict(farm_id,idempotency_key) do nothing;

    insert into atlas.crop_cycle_management_events(
      farm_id,crop_cycle_id,event_date,management_purpose,disposition,biomass_destination,
      confidence,source_kind,source_id,note,idempotency_key,metadata
    ) values(
      v_cycle.farm_id,v_cycle.id,v_clear_date,null,'clearance_completed',v_destination,
      'high','task_result',new.id::text,'Physical crop clearance completed.',
      'crop-clear-management:'||new.id::text||':'||v_cycle.id::text,
      jsonb_build_object('taskId',new.id,'turnoverScope',case when v_selected_turnover then 'selected_crop' else 'crop_clear' end)
    ) on conflict(farm_id,idempotency_key) do nothing;

    insert into atlas.object_activity_events(
      farm_id,object_id,event_type,event_date,note,created_by,source,metadata,crop_cycle_id,idempotency_key
    )
    select new.farm_id,link.object_id,'maintained',v_clear_date,
      v_cycle.crop_label||' was removed from this bed-maintenance scope; other crop occupancy remains independent.',
      'task_result','crop_terminal_lifecycle_v1',
      jsonb_build_object('task_id',new.id,'biomass_destination',v_destination,'crop_cycle_id',v_cycle.id,'turnover_scope','selected_crop'),
      v_cycle.id,'crop-clear-object:'||new.id::text||':'||link.object_id::text
    from atlas.task_objects link
    where link.task_id=new.id and link.role='work_carrier'
      and not exists(
        select 1 from atlas.object_activity_events e
        where e.farm_id=new.farm_id and e.idempotency_key='crop-clear-object:'||new.id::text||':'||link.object_id::text
      );
  end loop;

  return new;
end;
$$;

revoke all on function atlas.sync_completed_crop_cycle_clear_v1() from public,anon,authenticated;
grant execute on function atlas.sync_completed_crop_cycle_clear_v1() to service_role;

do $$
declare
  v_farm uuid;
  v_zone uuid;
  v_arch1 uuid;
  v_arch2 uuid;
  v_cycle uuid;
  v_task uuid;
  v_bed record;
begin
  select id into strict v_farm from atlas.farms where stable_key='elm_farm';
  select id into strict v_zone from atlas.zones where farm_id=v_farm and id='983dc5d7-d964-49df-952f-be99bae8a905';

  insert into atlas.growing_objects(
    farm_id,zone_id,stable_key,label,object_type,object_mode,guest_visible,sort_order,metadata
  ) values
    (v_farm,v_zone,'curve_arch_01','Curve Arch 1','arch_bed','row_based',true,101,
      jsonb_build_object('capacity_kind','vertical_arch','planting_surface','arch','arch_set',1,'owner_confirmed',true,'occupancy_independent_of_foot_beds',true)),
    (v_farm,v_zone,'curve_arch_02','Curve Arch 2','arch_bed','row_based',true,102,
      jsonb_build_object('capacity_kind','vertical_arch','planting_surface','arch','arch_set',2,'owner_confirmed',true,'occupancy_independent_of_foot_beds',true))
  on conflict(farm_id,stable_key) do update set
    label=excluded.label,object_type=excluded.object_type,object_mode=excluded.object_mode,
    zone_id=excluded.zone_id,metadata=atlas.growing_objects.metadata||excluded.metadata,updated_at=now();

  select id into strict v_arch1 from atlas.growing_objects where farm_id=v_farm and stable_key='curve_arch_01';
  select id into strict v_arch2 from atlas.growing_objects where farm_id=v_farm and stable_key='curve_arch_02';

  update atlas.growing_objects
  set object_type='bed',metadata=metadata||jsonb_build_object(
    'capacity_kind','ground_bed','planting_surface','bed','arch_foot_bed',true,
    'occupancy_independent_of_arch_surface',true
  ),updated_at=now()
  where farm_id=v_farm and stable_key in (
    'curve_arch_01_left_bed','curve_arch_01_right_bed','curve_arch_02_left_bed','curve_arch_02_right_bed'
  );

  for v_bed in
    select id,stable_key,label,
      case when stable_key like 'curve_arch_01_%' then v_arch1 else v_arch2 end as arch_id,
      case when stable_key like '%left_bed' then 'left' else 'right' end as side
    from atlas.growing_objects
    where farm_id=v_farm and stable_key in (
      'curve_arch_01_left_bed','curve_arch_01_right_bed','curve_arch_02_left_bed','curve_arch_02_right_bed'
    )
  loop
    insert into atlas.growing_object_relationships(
      farm_id,parent_object_id,child_object_id,relationship_type,position_label,metadata
    ) values(
      v_farm,v_bed.arch_id,v_bed.id,'side_bed_of',v_bed.side,
      jsonb_build_object('capacityIndependent',true,'relationshipRole','arch_foot_bed')
    ) on conflict(parent_object_id,child_object_id,relationship_type) do update set
      position_label=excluded.position_label,metadata=atlas.growing_object_relationships.metadata||excluded.metadata,updated_at=now();
  end loop;

  select cc.id into strict v_cycle
  from atlas.crop_cycles cc join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
  where cc.farm_id=v_farm and cc.lifecycle_status='active' and cp.stable_key='muncher_cucumber';

  insert into atlas.crop_placements(
    farm_id,object_id,crop_cycle_id,placement_key,placement_mode,placement_label,
    confidence,position_confidence,metadata
  ) values
    (v_farm,v_arch1,v_cycle,'curve_arch_01_vine_surface','unknown','Curve Arch 1 vine surface','owner_confirmed','unknown',
      jsonb_build_object('source','owner_report_20260826','capacitySurface','vertical_arch','rootBedPositionKnown',false)),
    (v_farm,v_arch2,v_cycle,'curve_arch_02_vine_surface','unknown','Curve Arch 2 vine surface','owner_confirmed','unknown',
      jsonb_build_object('source','owner_report_20260826','capacitySurface','vertical_arch','rootBedPositionKnown',false))
  on conflict(crop_cycle_id,placement_key) do update set
    object_id=excluded.object_id,placement_label=excluded.placement_label,confidence=excluded.confidence,
    position_confidence=excluded.position_confidence,metadata=atlas.crop_placements.metadata||excluded.metadata,updated_at=now();

  select t.id into strict v_task
  from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle and tc.role='clears' and t.status in ('open','blocked')
  order by t.created_at desc limit 1;

  update atlas.tasks
  set title='Turn over Muncher cucumber — Curve Garden Arches 1 + 2',
      task_type='maintenance',action_key='weed',operation_class='remove_uproot',operation_class_source='manual',
      task_series_key='weed-turnover:selected-crop:'||v_cycle::text,
      engine_instance_key='weed-selected-crop-turnover:'||v_cycle::text,
      note='Turn over only the finished Muncher cucumber crop. Do not clear the other crops from the beds at the feet of the arches.',
      metadata=metadata||jsonb_build_object(
        'canonical_card_family','weed',
        'weed_card_managed',true,
        'weed_management_mode','clear_selected_crop',
        'turnover_scope','selected_crop',
        'whole_bed_turnover',false,
        'selected_crop_cycle_id',v_cycle,
        'selected_crop_root_bed_position_known',false,
        'turnover_collection_label','Curve Garden Arches 1 + 2',
        'display_action','Turn over',
        'display_subject','Muncher cucumber',
        'display_detail','Remove only the finished cucumber crop; leave the other plants in the foot beds.',
        'display_location','Curve Garden Arches 1 + 2',
        'execution_do','Remove the finished Muncher cucumber vines from Curve Garden Arches 1 and 2 and take the removed vines to the compost. Leave the other crops in the beds at the feet of the arches.',
        'execution_done_when','The Muncher cucumber is removed from both arch surfaces and the removed cucumber biomass is in the compost; the other bed crops remain in place.',
        'work_route','weed',
        'operation_class_manual','remove_uproot',
        'arch_capacity_recomputed_on_crop_completion',true
      ),updated_at=now()
  where id=v_task;

  update atlas.task_objects
  set role='work_carrier'
  where task_id=v_task and object_id in (
    select id from atlas.growing_objects where farm_id=v_farm and stable_key in (
      'curve_arch_01_left_bed','curve_arch_01_right_bed','curve_arch_02_left_bed','curve_arch_02_right_bed'
    )
  );

  insert into atlas.task_objects(task_id,object_id,role) values
    (v_task,v_arch1,'capacity_surface'),(v_task,v_arch2,'capacity_surface')
  on conflict(task_id,object_id) do update set role=excluded.role;
end $$;

update atlas.architecture_truth_authorities
set supporting_relations=(select array_agg(distinct x order by x) from unnest(supporting_relations||array['atlas.crop_placements']) x),
    rationale=rationale||' Spatial occupancy may span multiple growing objects through atlas.crop_placements; this does not create another biological crop body.',
    updated_at=now()
where authority_key='crop_occupancy_identity';

insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,consumer_surfaces,
  known_competitors,source_custody,rationale
) values(
  'growing_surface_capacity','crop_lifecycle',
  'Is this physical growing surface occupied or empty and available for another planting, independently of adjacent growing surfaces?',
  'atlas.object_crop_occupancy_v1(uuid)','canonical',
  array['atlas.growing_objects','atlas.crop_cycles','atlas.crop_placements'],
  array['atlas.object_crop_occupancy_v1(uuid)'],
  array['atlas.growing_object_relationships','atlas.crop_observations'],
  array['Weed card','planting readiness','crop task focus','seasonal succession planning'],
  array['inferring arch occupancy from the beds at its feet','marking an entire bed empty when one crop body is cleared'],
  'optical-lift/noel-core-db:supabase/migrations',
  'Capacity belongs to a physical growing surface. Vertical arches and their foot beds are separate capacity surfaces. Crop placements provide spatial occupancy while crop_cycles remains the biological lifecycle authority.'
) on conflict(authority_key) do update set
  authority_owner=excluded.authority_owner,authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,source_custody=excluded.source_custody,
  rationale=excluded.rationale,updated_at=now();

select atlas.assert_architecture_truth_authorities_v1();