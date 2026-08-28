-- Atlas Harvest workbench writers v1
-- Permanent Harvest cards and scheduled task cards write into the same flower
-- harvest / preparation / Ready ledgers. Workbench actions get a completed task
-- carrier for provenance, but the permanent card itself never disappears.

create or replace function atlas.record_flower_harvest_workbench_core_v1(
  p_farm_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_rows jsonb,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_farm atlas.farms%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_task atlas.tasks%rowtype;
  v_batch atlas.flower_harvest_batches%rowtype;
  v_existing atlas.flower_harvest_batches%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_row jsonb;
  v_cycle_id uuid;
  v_halves integer;
  v_more text;
  v_more_bool boolean;
  v_band text;
  v_event atlas.crop_harvest_events%rowtype;
  v_observation atlas.flower_harvest_bucket_observations%rowtype;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_role text := lower(btrim(coalesce(p_effective_role,'')));
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_key text := nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_seen uuid[] := '{}'::uuid[];
  v_events jsonb := '[]'::jsonb;
  v_transition jsonb;
  v_bridge jsonb;
begin
  if p_farm_id is null or p_effective_membership_id is null then
    raise exception 'Farm and active membership are required.' using errcode='22023';
  end if;
  if v_role not in ('owner','manager','farm_hand') then
    raise exception 'Selected account cannot record harvest.' using errcode='42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>24 then
    raise exception 'Harvest workbench requires between 1 and 24 crop rows.' using errcode='22023';
  end if;
  if v_key is null or char_length(v_key)>96 then
    raise exception 'A valid Harvest workbench idempotency key is required.' using errcode='22023';
  end if;
  if v_note is not null and char_length(v_note)>1000 then
    raise exception 'Harvest note must be 1000 characters or fewer.' using errcode='22023';
  end if;

  select * into v_farm from atlas.farms where id=p_farm_id;
  if v_farm.id is null then raise exception 'Farm was not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_farm.id then
    raise exception 'Active membership in this farm is required.' using errcode='42501';
  end if;

  select * into v_existing
  from atlas.flower_harvest_batches
  where farm_id=v_farm.id and batch_key='harvest-workbench:'||v_key;
  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','harvest_workbench_v1','deduplicated',true,
      'harvestBatchId',v_existing.id,
      'taskId',nullif(v_existing.metadata->>'workbenchTaskId','')::uuid,
      'rowCount',(select count(*) from atlas.flower_harvest_bucket_observations h where h.batch_id=v_existing.id)
    );
  end if;

  insert into atlas.tasks(
    organization_id,farm_id,title,task_type,status,priority,due_date,
    action_key,work_class,task_series_key,engine_instance_key,
    visibility_scope,assigned_membership_id,assigned_user_id,
    task_scope,origin_kind,work_lane,commitment_kind,effort_units,
    sky_deferral_mode,created_by_user_id,metadata
  ) values (
    v_farm.organization_id,v_farm.id,'Harvest Stems','harvest','open','high',v_today,
    'harvest','harvest','harvest-workbench','harvest-workbench:'||v_key,
    'assigned_worker',v_member.id,v_member.user_id,
    'farm_operation','generated','process_continuation','floating',1,
    'never',auth.uid(),jsonb_build_object(
      'task_style','weekly_harvest_round',
      'result_contract','harvest_workbench_batch_v1',
      'harvest_workbench',true,
      'workbenchSource','harvest_tab',
      'workbenchIdempotencyKey',v_key,
      'operatorMode',p_operator_mode,
      'effectiveMembershipId',v_member.id,
      'time_claims_physical_condition',false
    )
  ) returning * into v_task;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v_row)<>'object' then raise exception 'Each Harvest row must be an object.' using errcode='22023'; end if;
    begin v_cycle_id:=nullif(btrim(coalesce(v_row->>'cropCycleId','')),'')::uuid;
    exception when invalid_text_representation then raise exception 'Each Harvest row needs a valid crop cycle.' using errcode='22023'; end;
    if v_cycle_id is null then raise exception 'Each Harvest row needs a crop cycle.' using errcode='22023'; end if;
    if array_position(v_seen,v_cycle_id) is not null then raise exception 'A crop may appear only once in one Harvest batch.' using errcode='22023'; end if;
    v_seen:=array_append(v_seen,v_cycle_id);
    begin v_halves:=(v_row->>'bucketHalves')::integer;
    exception when others then raise exception 'Harvest amount must use half-bucket increments.' using errcode='22023'; end;
    if v_halves is null or v_halves<1 or v_halves>40 then raise exception 'Harvest amount must be between one half-bucket and 20 buckets.' using errcode='22023'; end if;
    v_more:=lower(btrim(coalesce(v_row->>'moreAvailability','unsure')));
    if v_more not in ('yes','no','unsure') then raise exception 'Record whether more remains: yes, no, or unsure.' using errcode='22023'; end if;

    select * into v_cycle from atlas.crop_cycles where id=v_cycle_id for update;
    if v_cycle.id is null or v_cycle.farm_id is distinct from v_farm.id then raise exception 'Harvest crop is outside this farm.' using errcode='42501'; end if;
    if coalesce(v_cycle.lifecycle_status,'active')<>'active' or lower(coalesce(v_cycle.cycle_state,'')) in ('failed','cleared','finished','finished_harvest') then
      raise exception 'Harvest can only be recorded for an active crop cycle.' using errcode='22023';
    end if;
  end loop;

  insert into atlas.flower_harvest_batches(
    farm_id,harvest_date,recorded_by_membership_id,batch_key,note,metadata,created_by_user_id
  ) values (
    v_farm.id,v_today,v_member.id,'harvest-workbench:'||v_key,v_note,
    jsonb_build_object(
      'source','harvest_workbench_v1','workbenchTaskId',v_task.id,
      'operatorMode',p_operator_mode,'effectiveMembershipId',v_member.id,
      'physicalOutputMode','bucket_scale','precision','half_bucket',
      'truthBoundary','actual_harvest_output_evidence'
    ),auth.uid()
  ) returning * into v_batch;

  foreach v_cycle_id in array v_seen loop
    select value into v_row from jsonb_array_elements(p_rows) where (value->>'cropCycleId')::uuid=v_cycle_id limit 1;
    v_halves:=(v_row->>'bucketHalves')::integer;
    v_more:=lower(btrim(coalesce(v_row->>'moreAvailability','unsure')));
    v_more_bool:=case when v_more='yes' then true when v_more='no' then false else null end;
    v_band:=case when v_halves=1 then 'half' when v_halves=2 then 'one' else 'more_than_one' end;
    select * into v_cycle from atlas.crop_cycles where id=v_cycle_id for update;

    insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role,confidence,source,metadata)
    values(v_task.id,v_cycle.id,'preserves','confirmed','harvest_workbench_v1',jsonb_build_object('workbenchBatchId',v_batch.id));

    insert into atlas.flower_harvest_bucket_observations(
      farm_id,batch_id,crop_cycle_id,task_id,recorded_by_membership_id,observed_date,
      bucket_band,bucket_equivalent_floor,more_available,note,idempotency_key,
      created_by_user_id,metadata,more_availability,bucket_halves
    ) values (
      v_farm.id,v_batch.id,v_cycle.id,v_task.id,v_member.id,v_today,
      v_band,(v_halves::numeric/2),v_more_bool,nullif(btrim(coalesce(v_row->>'note','')),''),
      left(v_key||':harvest:'||v_cycle.id::text,160),auth.uid(),
      jsonb_build_object(
        'source','harvest_workbench_v1','workbenchTaskId',v_task.id,'workbenchBatchId',v_batch.id,
        'physicalOutputMode','bucket_scale','precision','half_bucket','bucketHalves',v_halves,
        'bucketEquivalentFloor',(v_halves::numeric/2),'moreAvailability',v_more,
        'operatorMode',p_operator_mode,'effectiveMembershipId',v_member.id
      ),v_more,v_halves
    ) returning * into v_observation;

    insert into atlas.crop_harvest_events(
      farm_id,crop_cycle_id,task_id,event_kind,outcome,observed_date,more_available,
      note,idempotency_key,created_by_user_id,metadata
    ) values (
      v_farm.id,v_cycle.id,v_task.id,'cut',
      case when v_more='yes' then 'harvested_more' when v_more='no' then 'harvested_finished' else 'harvested_uncertain' end,
      v_today,v_more_bool,nullif(btrim(coalesce(v_row->>'note','')),''),
      left(v_key||':event:'||v_cycle.id::text,160),auth.uid(),
      jsonb_build_object(
        'source','harvest_workbench_v1','physicalOutputMode','bucket_scale','precision','half_bucket',
        'flowerHarvestBatchId',v_batch.id,'flowerHarvestObservationId',v_observation.id,
        'bucketBand',v_band,'bucketHalves',v_halves,'bucketEquivalentFloor',(v_halves::numeric/2),
        'moreAvailability',v_more,'operatorMode',p_operator_mode,'effectiveMembershipId',v_member.id
      )
    ) returning * into v_event;

    update atlas.crop_cycles
    set harvest_started_date=coalesce(harvest_started_date,v_today),last_harvest_date=v_today,
        cycle_state=case when v_more='no' then 'finished_harvest' else 'harvest_watch' end,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'last_harvest_event_id',v_event.id,'last_flower_harvest_batch_id',v_batch.id,
          'last_flower_harvest_observation_id',v_observation.id,'last_flower_harvest_bucket_halves',v_halves,
          'physical_output_mode','bucket_scale','more_available',v_more_bool,'more_availability',v_more,
          'lastHarvestSource','harvest_workbench_v1'
        ),updated_at=now()
    where id=v_cycle.id;

    update atlas.crop_harvest_availability
    set status=case when v_more='no' then 'finished' else 'watching' end,
        estimated_quantity=null,unit=null,observed_date=v_today,source_event_id=v_event.id,
        current_harvest_task_id=null,current_harvest_occurrence_id=null,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'lastCutEventId',v_event.id,'lastFlowerHarvestBatchId',v_batch.id,
          'lastFlowerHarvestObservationId',v_observation.id,'lastFlowerHarvestBucketHalves',v_halves,
          'physicalOutputMode','bucket_scale','moreAvailable',v_more_bool,'moreAvailability',v_more,
          'lastHarvestSource','harvest_workbench_v1'
        ),updated_at=now()
    where crop_cycle_id=v_cycle.id;

    if v_more<>'no' then
      perform atlas.enroll_harvest_watch_v1(v_cycle.id,null,v_today+1);
    else
      update atlas.rhythm_state
      set state='paused',state_reason=jsonb_build_object('source','harvest_workbench_finished','eventId',v_event.id,'observationId',v_observation.id),
          current_task_id=null,current_occurrence_id=null,updated_at=now()
      where farm_id=v_cycle.farm_id and rhythm_key='harvest_watch' and subject_kind='crop_cycle' and subject_id=v_cycle.id;
    end if;

    v_bridge:=atlas.bridge_flower_harvest_to_production_v1(v_event.id);
    v_events:=v_events||jsonb_build_array(jsonb_build_object(
      'cropCycleId',v_cycle.id,'observationId',v_observation.id,'eventId',v_event.id,
      'bucketHalves',v_halves,'bucketEquivalent',(v_halves::numeric/2),'moreAvailability',v_more,
      'productionReconciliation',v_bridge
    ));
  end loop;

  v_transition:=atlas.record_task_transition_v1_internal(
    v_task.id,'done','harvest-workbench-done:'||v_key,null,v_note,null,'harvest','harvest_workbench',
    jsonb_build_object(
      'source','harvest_workbench_v1','flower_harvest_batch_id',v_batch.id,
      'row_count',jsonb_array_length(p_rows),'truthBoundary','actual_harvest_output_evidence'
    ),null
  );

  return jsonb_build_object(
    'contractVersion','harvest_workbench_v1','deduplicated',false,
    'harvestBatchId',v_batch.id,'taskId',v_task.id,'rowCount',jsonb_array_length(p_rows),
    'events',v_events,'transition',v_transition
  );
end;
$function$;

create or replace function atlas.record_flower_harvest_workbench_for_member_v1(
  p_farm_id uuid,p_rows jsonb,p_note text,p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_role text; v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  return atlas.record_flower_harvest_workbench_core_v1(p_farm_id,v_membership,v_role,p_rows,p_note,p_idempotency_key,false);
end;
$function$;

create or replace function atlas.owner_operator_record_flower_harvest_workbench_v1(
  p_effective_membership_id uuid,p_farm_id uuid,p_rows jsonb,p_note text,p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_context jsonb; v_membership uuid; v_role text; v_farm uuid;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  v_membership:=(v_context #>> '{effective,membershipId}')::uuid;
  v_role:=v_context #>> '{effective,role}';
  select farm_id into v_farm from atlas.farm_memberships where id=v_membership;
  if v_farm is distinct from p_farm_id then raise exception 'Selected account is outside the requested farm.' using errcode='42501'; end if;
  return atlas.record_flower_harvest_workbench_core_v1(p_farm_id,v_membership,v_role,p_rows,p_note,p_idempotency_key,true);
end;
$function$;

create or replace function atlas.record_flower_preparation_workbench_core_v1(
  p_farm_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_harvest_batch_id uuid,
  p_outputs jsonb,
  p_note text,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_farm atlas.farms%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_harvest atlas.flower_harvest_batches%rowtype;
  v_task atlas.tasks%rowtype;
  v_existing atlas.flower_preparation_batches%rowtype;
  v_prep atlas.flower_preparation_batches%rowtype;
  v_output jsonb;
  v_kind text;
  v_inventory_kind text;
  v_unit text;
  v_quantity numeric;
  v_label text;
  v_crop_profile_id uuid;
  v_stems_per_unit integer;
  v_index integer:=0;
  v_ready jsonb:='[]'::jsonb;
  v_ready_row atlas.flower_ready_inventory_lots%rowtype;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_role text:=lower(btrim(coalesce(p_effective_role,'')));
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_transition jsonb;
begin
  if p_farm_id is null or p_effective_membership_id is null or p_harvest_batch_id is null then raise exception 'Farm, member, and source harvest batch are required.' using errcode='22023'; end if;
  if v_role not in ('owner','manager','farm_hand') then raise exception 'Selected account cannot record finished flower preparation.' using errcode='42501'; end if;
  if p_outputs is null or jsonb_typeof(p_outputs)<>'array' or jsonb_array_length(p_outputs)<1 or jsonb_array_length(p_outputs)>24 then raise exception 'Condition + Bunch requires between 1 and 24 finished output lines.' using errcode='22023'; end if;
  if v_key is null or char_length(v_key)>96 then raise exception 'A valid Condition + Bunch idempotency key is required.' using errcode='22023'; end if;
  if v_note is not null and char_length(v_note)>1000 then raise exception 'Preparation note must be 1000 characters or fewer.' using errcode='22023'; end if;

  select * into v_farm from atlas.farms where id=p_farm_id;
  if v_farm.id is null then raise exception 'Farm was not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_farm.id then raise exception 'Active membership in this farm is required.' using errcode='42501'; end if;
  select * into v_harvest from atlas.flower_harvest_batches where id=p_harvest_batch_id;
  if v_harvest.id is null or v_harvest.farm_id is distinct from v_farm.id then raise exception 'Source harvest batch is outside this farm.' using errcode='42501'; end if;

  select * into v_existing from atlas.flower_preparation_batches where farm_id=v_farm.id and idempotency_key=v_key;
  if v_existing.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',r.id,'inventoryKind',r.inventory_kind,'productLabel',r.product_label,'quantity',r.quantity,
      'unit',r.unit,'readyDate',r.ready_date,'stemsPerUnit',r.metadata->'stemsPerUnit'
    ) order by r.created_at),'[]'::jsonb) into v_ready
    from atlas.flower_ready_inventory_lots r where r.preparation_batch_id=v_existing.id;
    return jsonb_build_object('contractVersion','preparation_workbench_v1','deduplicated',true,'preparationBatchId',v_existing.id,'taskId',v_existing.task_id,'readyLots',v_ready);
  end if;

  for v_output in select value from jsonb_array_elements(p_outputs) loop
    if jsonb_typeof(v_output)<>'object' then raise exception 'Each finished output line must be an object.' using errcode='22023'; end if;
    v_kind:=lower(btrim(coalesce(v_output->>'kind',v_output->>'outputKind','')));
    if v_kind not in ('bundle','bunch','posy','bouquet','lobby_arrangement','conditioned_bucket','counted_stems') then raise exception 'Choose a supported finished flower form.' using errcode='22023'; end if;
    v_label:=nullif(btrim(coalesce(v_output->>'productLabel','')),'');
    if v_label is null or char_length(v_label)>160 then raise exception 'Each finished output needs a flower/product label.' using errcode='22023'; end if;
    begin v_quantity:=(v_output->>'quantity')::numeric; exception when others then raise exception 'Finished quantity must be numeric.' using errcode='22023'; end;
    if v_quantity is null or v_quantity<=0 or v_quantity>10000 then raise exception 'Finished quantity must be greater than zero.' using errcode='22023'; end if;
    if v_kind='conditioned_bucket' then
      if mod(v_quantity*4,1)<>0 then raise exception 'Conditioned bucket quantity must use quarter-bucket increments.' using errcode='22023'; end if;
    elsif mod(v_quantity,1)<>0 then raise exception 'Finished bunches, stems, posies, bouquets, and arrangements must be whole numbers.' using errcode='22023';
    end if;
    if v_kind in ('bundle','bunch') then
      begin v_stems_per_unit:=(v_output->>'stemsPerUnit')::integer; exception when others then raise exception 'Bunches require stems per bunch.' using errcode='22023'; end;
      if v_stems_per_unit is null or v_stems_per_unit<1 or v_stems_per_unit>1000 then raise exception 'Bunches require a valid stems-per-bunch count.' using errcode='22023'; end if;
    end if;
    begin v_crop_profile_id:=nullif(v_output->>'cropProfileId','')::uuid; exception when others then raise exception 'Crop profile id is invalid.' using errcode='22023'; end;
  end loop;

  insert into atlas.tasks(
    organization_id,farm_id,title,task_type,status,priority,due_date,
    action_key,work_class,task_series_key,engine_instance_key,
    visibility_scope,assigned_membership_id,assigned_user_id,
    task_scope,origin_kind,work_lane,commitment_kind,effort_units,
    sky_deferral_mode,created_by_user_id,metadata
  ) values (
    v_farm.organization_id,v_farm.id,'Condition + Bunch','flower_preparation','open','high',v_today,
    'prepare','postharvest','flower-preparation-workbench','flower-preparation-workbench:'||v_key,
    'assigned_worker',v_member.id,v_member.user_id,
    'farm_operation','generated','process_continuation','floating',1,
    'never',auth.uid(),jsonb_build_object(
      'task_style','flower_preparation','structured_result_required',true,
      'flower_harvest_batch_id',v_harvest.id,'harvest_workbench',true,
      'workbenchSource','harvest_tab','workbenchIdempotencyKey',v_key,
      'operatorMode',p_operator_mode,'effectiveMembershipId',v_member.id,
      'truthBoundary','worker_observed_finished_preparation_run','time_claims_physical_condition',false
    )
  ) returning * into v_task;

  insert into atlas.flower_preparation_batches(
    farm_id,harvest_batch_id,task_id,prepared_date,recorded_by_membership_id,
    result_kind,note,idempotency_key,created_by_user_id,metadata
  ) values (
    v_farm.id,v_harvest.id,v_task.id,v_today,v_member.id,'ready',v_note,v_key,auth.uid(),
    jsonb_build_object(
      'source','flower_preparation_workbench_v1','operatorMode',p_operator_mode,
      'effectiveMembershipId',v_member.id,'sourceHarvestBatchId',v_harvest.id,
      'inputAllocation','unquantified_existing_harvest_custody',
      'truthBoundary','worker_observed_finished_preparation_run'
    )
  ) returning * into v_prep;

  for v_output in select value from jsonb_array_elements(p_outputs) loop
    v_index:=v_index+1;
    v_kind:=lower(btrim(coalesce(v_output->>'kind',v_output->>'outputKind','')));
    v_inventory_kind:=case when v_kind in ('bundle','bunch') then 'bunch' else v_kind end;
    v_unit:=case v_inventory_kind when 'bunch' then 'bunch' when 'posy' then 'posy' when 'bouquet' then 'bouquet' when 'lobby_arrangement' then 'arrangement' when 'conditioned_bucket' then 'bucket_equivalent' when 'counted_stems' then 'stem' end;
    v_quantity:=(v_output->>'quantity')::numeric;
    v_label:=btrim(v_output->>'productLabel');
    v_stems_per_unit:=case when v_inventory_kind='bunch' then (v_output->>'stemsPerUnit')::integer else null end;
    begin v_crop_profile_id:=nullif(v_output->>'cropProfileId','')::uuid; exception when others then v_crop_profile_id:=null; end;

    insert into atlas.flower_ready_inventory_lots(
      farm_id,preparation_batch_id,inventory_kind,quantity,unit,quantity_exactness,ready_date,
      idempotency_key,created_by_user_id,metadata,crop_profile_id,product_label
    ) values (
      v_farm.id,v_prep.id,v_inventory_kind,v_quantity,v_unit,'exact',v_today,
      left(v_key||':ready:'||v_index::text,160),auth.uid(),
      jsonb_build_object(
        'source','flower_preparation_workbench_v1','sourceHarvestBatchId',v_harvest.id,
        'sourcePreparationBatchId',v_prep.id,'workbenchTaskId',v_task.id,
        'stemsPerUnit',v_stems_per_unit,'outputKind',case when v_inventory_kind='bunch' then 'bundle' else v_inventory_kind end,
        'inputAllocation','unquantified_existing_harvest_custody',
        'truthBoundary','finished_saleable_inventory'
      ),v_crop_profile_id,v_label
    ) returning * into v_ready_row;

    v_ready:=v_ready||jsonb_build_array(jsonb_build_object(
      'id',v_ready_row.id,'inventoryKind',v_ready_row.inventory_kind,'productLabel',v_ready_row.product_label,
      'quantity',v_ready_row.quantity,'unit',v_ready_row.unit,'readyDate',v_ready_row.ready_date,
      'stemsPerUnit',v_stems_per_unit
    ));
  end loop;

  v_transition:=atlas.record_task_transition_v1_internal(
    v_task.id,'done','flower-preparation-workbench-done:'||v_key,null,v_note,null,'prepare','flower_preparation_workbench',
    jsonb_build_object(
      'source','flower_preparation_workbench_v1','flower_harvest_batch_id',v_harvest.id,
      'flower_preparation_batch_id',v_prep.id,'ready_lot_count',jsonb_array_length(v_ready),
      'truthBoundary','worker_observed_finished_preparation_run'
    ),null
  );

  return jsonb_build_object(
    'contractVersion','preparation_workbench_v1','deduplicated',false,
    'preparationBatchId',v_prep.id,'harvestBatchId',v_harvest.id,'taskId',v_task.id,
    'readyLots',v_ready,'transition',v_transition
  );
end;
$function$;

create or replace function atlas.record_flower_preparation_workbench_for_member_v1(
  p_farm_id uuid,p_harvest_batch_id uuid,p_outputs jsonb,p_note text,p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_role text; v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  return atlas.record_flower_preparation_workbench_core_v1(p_farm_id,v_membership,v_role,p_harvest_batch_id,p_outputs,p_note,p_idempotency_key,false);
end;
$function$;

create or replace function atlas.owner_operator_record_flower_preparation_workbench_v1(
  p_effective_membership_id uuid,p_farm_id uuid,p_harvest_batch_id uuid,p_outputs jsonb,p_note text,p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare v_context jsonb; v_membership uuid; v_role text; v_farm uuid;
begin
  v_context:=atlas.owner_operator_context_v1(p_effective_membership_id);
  v_membership:=(v_context #>> '{effective,membershipId}')::uuid;
  v_role:=v_context #>> '{effective,role}';
  select farm_id into v_farm from atlas.farm_memberships where id=v_membership;
  if v_farm is distinct from p_farm_id then raise exception 'Selected account is outside the requested farm.' using errcode='42501'; end if;
  return atlas.record_flower_preparation_workbench_core_v1(p_farm_id,v_membership,v_role,p_harvest_batch_id,p_outputs,p_note,p_idempotency_key,true);
end;
$function$;

revoke all on function atlas.record_flower_harvest_workbench_core_v1(uuid,uuid,text,jsonb,text,text,boolean) from public,anon,authenticated,service_role;
revoke all on function atlas.record_flower_harvest_workbench_for_member_v1(uuid,jsonb,text,text) from public,anon,authenticated,service_role;
revoke all on function atlas.owner_operator_record_flower_harvest_workbench_v1(uuid,uuid,jsonb,text,text) from public,anon,authenticated,service_role;
revoke all on function atlas.record_flower_preparation_workbench_core_v1(uuid,uuid,text,uuid,jsonb,text,text,boolean) from public,anon,authenticated,service_role;
revoke all on function atlas.record_flower_preparation_workbench_for_member_v1(uuid,uuid,jsonb,text,text) from public,anon,authenticated,service_role;
revoke all on function atlas.owner_operator_record_flower_preparation_workbench_v1(uuid,uuid,uuid,jsonb,text,text) from public,anon,authenticated,service_role;

grant execute on function atlas.record_flower_harvest_workbench_for_member_v1(uuid,jsonb,text,text) to authenticated;
grant execute on function atlas.owner_operator_record_flower_harvest_workbench_v1(uuid,uuid,jsonb,text,text) to authenticated;
grant execute on function atlas.record_flower_preparation_workbench_for_member_v1(uuid,uuid,jsonb,text,text) to authenticated;
grant execute on function atlas.owner_operator_record_flower_preparation_workbench_v1(uuid,uuid,uuid,jsonb,text,text) to authenticated;

with targets as (
  select p.oid,
    format('%I.%I(%s)',n.nspname,p.proname,oidvectortypes(p.proargtypes)) as signature,
    p.prosecdef as security_definer,
    has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
    has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_execute,
    has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute,
    (select count(*)::integer from pg_proc caller join pg_namespace cn on cn.oid=caller.pronamespace and cn.nspname='atlas'
      where caller.oid<>p.oid and caller.prokind='f' and (position(lower(p.proname)||'(' in lower(pg_get_functiondef(caller.oid)))>0 or position(lower(p.proname)||' (' in lower(pg_get_functiondef(caller.oid)))>0)) as caller_count,
    (select count(*)::integer from pg_policies policy where position(lower(p.proname)||'(' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0 or position(lower(p.proname)||' (' in lower(coalesce(policy.qual,'')||' '||coalesce(policy.with_check,'')))>0) as policy_reference_count
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname in (
    'record_flower_harvest_workbench_for_member_v1','owner_operator_record_flower_harvest_workbench_v1',
    'record_flower_preparation_workbench_for_member_v1','owner_operator_record_flower_preparation_workbench_v1'
  )
)
insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at,reviewed_at
)
select signature,'app_endpoint','verified','active',authenticated_execute,anonymous_execute,security_definer,service_execute,
  caller_count,policy_reference_count,
  jsonb_build_object(
    'source','atlas_harvest_workbench_writers_v1','reason','permanent_harvest_task_cards_same_canonical_ledgers',
    'functionOid',oid,'classificationRuleVersion',3,
    'truthBoundary','Permanent Harvest cards create completed task-carried actuals in the existing flower harvest/preparation/Ready ledgers; they do not create a parallel inventory system.'
  ),now(),now()
from targets
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,
  evidence=coalesce(atlas.authenticated_rpc_registry.evidence,'{}'::jsonb)||excluded.evidence,reviewed_at=now();

do $verification$
declare v_count integer; v_drift integer;
begin
  select count(*) into v_count from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname in (
    'record_flower_harvest_workbench_for_member_v1','owner_operator_record_flower_harvest_workbench_v1',
    'record_flower_preparation_workbench_for_member_v1','owner_operator_record_flower_preparation_workbench_v1'
  ) and has_function_privilege('authenticated',p.oid,'EXECUTE') and not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE');
  if v_count<>4 then raise exception 'Harvest workbench RPC custody verification failed.'; end if;
  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1()
  where signature in (
    'atlas.record_flower_harvest_workbench_for_member_v1(uuid, jsonb, text, text)',
    'atlas.owner_operator_record_flower_harvest_workbench_v1(uuid, uuid, jsonb, text, text)',
    'atlas.record_flower_preparation_workbench_for_member_v1(uuid, uuid, jsonb, text, text)',
    'atlas.owner_operator_record_flower_preparation_workbench_v1(uuid, uuid, uuid, jsonb, text, text)'
  );
  if v_drift<>0 then raise exception 'Harvest workbench endpoints ended with % custody drift rows.',v_drift; end if;
end
$verification$;