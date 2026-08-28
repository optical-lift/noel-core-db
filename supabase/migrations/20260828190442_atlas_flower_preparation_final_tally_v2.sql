alter table atlas.flower_ready_inventory_lots
  drop constraint if exists flower_ready_inventory_lots_kind_check;

alter table atlas.flower_ready_inventory_lots
  add constraint flower_ready_inventory_lots_kind_check
  check (inventory_kind = any (array[
    'conditioned_bucket'::text,
    'counted_stems'::text,
    'posy'::text,
    'bouquet'::text,
    'lobby_arrangement'::text,
    'bunch'::text
  ]));

alter table atlas.flower_ready_inventory_lots
  drop constraint if exists flower_ready_inventory_lots_semantics_check;

alter table atlas.flower_ready_inventory_lots
  add constraint flower_ready_inventory_lots_semantics_check
  check (
    ((inventory_kind = 'conditioned_bucket'::text) and (unit = 'bucket_equivalent'::text) and (quantity_exactness = any (array['exact'::text, 'lower_bound'::text])) and (mod((quantity * (4)::numeric), (1)::numeric) = (0)::numeric))
    or ((inventory_kind = 'counted_stems'::text) and (unit = 'stem'::text) and (quantity_exactness = 'exact'::text) and (mod(quantity, (1)::numeric) = (0)::numeric))
    or ((inventory_kind = 'posy'::text) and (unit = 'posy'::text) and (quantity_exactness = 'exact'::text) and (mod(quantity, (1)::numeric) = (0)::numeric))
    or ((inventory_kind = 'bouquet'::text) and (unit = 'bouquet'::text) and (quantity_exactness = 'exact'::text) and (mod(quantity, (1)::numeric) = (0)::numeric))
    or ((inventory_kind = 'lobby_arrangement'::text) and (unit = 'arrangement'::text) and (quantity_exactness = 'exact'::text) and (mod(quantity, (1)::numeric) = (0)::numeric))
    or ((inventory_kind = 'bunch'::text) and (unit = 'bunch'::text) and (quantity_exactness = 'exact'::text) and (mod(quantity, (1)::numeric) = (0)::numeric))
  );

create or replace function atlas.record_flower_preparation_directive_result_for_member_v2(
  p_task_id uuid,
  p_actual_lines jsonb,
  p_worker_added_lines jsonb,
  p_remaining_stems jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_membership atlas.farm_memberships%rowtype;
  v_directive atlas.flower_preparation_directives%rowtype;
  v_existing atlas.flower_preparation_directive_results%rowtype;
  v_result atlas.flower_preparation_directive_results%rowtype;
  v_batch atlas.flower_preparation_batches%rowtype;
  v_line jsonb;
  v_directive_line atlas.flower_preparation_directive_lines%rowtype;
  v_line_id uuid;
  v_actual_text text;
  v_actual_quantity integer;
  v_note text;
  v_product_label text;
  v_output_kind text;
  v_inventory_kind text;
  v_unit text;
  v_stems_per_unit integer;
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_fingerprint text;
  v_directive_id uuid;
  v_planned_occurrence_id uuid;
  v_expected_count integer;
  v_seen_line_ids uuid[] := '{}'::uuid[];
  v_transition jsonb;
  v_ready_count integer := 0;
  v_total_saleable integer := 0;
  v_added_index integer := 0;
  v_timezone text := 'America/Chicago';
  v_ready_date date;
begin
  if auth.uid() is null then
    raise exception 'Authenticated assigned farm member required.' using errcode = '42501';
  end if;
  if p_task_id is null then raise exception 'Flower preparation task is required.' using errcode = '22023'; end if;
  if v_key is null or char_length(v_key) > 160 then raise exception 'A valid final-tally idempotency key is required.' using errcode = '22023'; end if;
  if p_actual_lines is null or jsonb_typeof(p_actual_lines) <> 'array' or jsonb_array_length(p_actual_lines) < 1 or jsonb_array_length(p_actual_lines) > 12 then raise exception 'Final tally requires between 1 and 12 requested lines.' using errcode = '22023'; end if;
  if p_worker_added_lines is null or jsonb_typeof(p_worker_added_lines) <> 'array' or jsonb_array_length(p_worker_added_lines) > 12 then raise exception 'Worker-added final tally must be an array of at most 12 lines.' using errcode = '22023'; end if;
  if p_remaining_stems is null or jsonb_typeof(p_remaining_stems) <> 'array' or jsonb_array_length(p_remaining_stems) > 24 then raise exception 'Remaining stems must be an array of at most 24 lines.' using errcode = '22023'; end if;

  select * into v_task from atlas.tasks where id = p_task_id for update;
  if v_task.id is null then raise exception 'Flower preparation task was not found.' using errcode = 'P0002'; end if;
  select * into v_membership from atlas.farm_memberships where user_id = auth.uid() and farm_id = v_task.farm_id and active = true limit 1;
  if v_membership.id is null or v_membership.role not in ('farm_hand', 'manager') or v_task.visibility_scope <> 'assigned_worker' or v_task.assigned_membership_id is distinct from v_membership.id then raise exception 'This final tally is not assigned to the signed-in farm member.' using errcode = '42501'; end if;
  if v_task.task_type <> 'flower_preparation' or coalesce(v_task.metadata->>'task_style', '') <> 'flower_preparation' or coalesce(v_task.metadata->>'requires_owner_preparation_directive', 'false') <> 'true' or coalesce(v_task.metadata->>'flower_preparation_directive_version', '') <> '1' then raise exception 'This task is not governed Owner-directed flower preparation.' using errcode = '22023'; end if;
  begin
    v_directive_id := nullif(v_task.metadata->>'flower_preparation_directive_id', '')::uuid;
    v_planned_occurrence_id := nullif(v_task.metadata->>'planned_occurrence_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Flower preparation task has invalid directive custody.' using errcode = '22023';
  end;
  if v_directive_id is null or v_planned_occurrence_id is null then raise exception 'Flower preparation task is missing directive custody.' using errcode = '22023'; end if;
  select * into v_directive from atlas.flower_preparation_directives where id = v_directive_id;
  if v_directive.id is null or v_directive.farm_id is distinct from v_task.farm_id or v_directive.preparation_occurrence_id is distinct from v_planned_occurrence_id or v_directive.harvest_batch_id::text is distinct from coalesce(v_task.metadata->>'flower_harvest_batch_id', '') then raise exception 'Flower preparation directive does not match this worker task.' using errcode = '22023'; end if;
  select coalesce(nullif(f.metadata->>'timezone', ''), 'America/Chicago') into v_timezone from atlas.farms f where f.id = v_task.farm_id;
  v_ready_date := (now() at time zone coalesce(v_timezone, 'America/Chicago'))::date;
  select count(*)::integer into v_expected_count from atlas.flower_preparation_directive_lines l where l.directive_id = v_directive.id;
  if v_expected_count < 1 or jsonb_array_length(p_actual_lines) <> v_expected_count then raise exception 'Final tally must contain every requested preparation line exactly once.' using errcode = '22023'; end if;
  v_fingerprint := md5(p_task_id::text || '|' || v_directive.id::text || '|' || p_actual_lines::text || '|' || p_worker_added_lines::text || '|' || p_remaining_stems::text);
  select * into v_existing from atlas.flower_preparation_directive_results where farm_id = v_task.farm_id and idempotency_key = v_key;
  if v_existing.id is not null then
    if v_existing.preparation_task_id is distinct from v_task.id or v_existing.directive_id is distinct from v_directive.id or v_existing.request_fingerprint is distinct from v_fingerprint then raise exception 'Final-tally idempotency key was already used for a different result.' using errcode = '22023'; end if;
    return jsonb_build_object('resultId', v_existing.id, 'taskId', v_existing.preparation_task_id, 'directiveId', v_existing.directive_id, 'lineCount', (select count(*) from atlas.flower_preparation_directive_result_lines l where l.result_id = v_existing.id), 'workerAddedLineCount', jsonb_array_length(coalesce(v_existing.metadata->'workerAddedLines', '[]'::jsonb)), 'readyInventoryLotsCreated', (select count(*) from atlas.flower_ready_inventory_lots lot where lot.metadata->>'directiveResultId' = v_existing.id::text), 'deduplicated', true);
  end if;
  if v_task.status not in ('open', 'blocked') then raise exception 'Flower preparation task is no longer open for a new final tally.' using errcode = '22023'; end if;

  for v_line in select value from jsonb_array_elements(p_actual_lines) loop
    if jsonb_typeof(v_line) <> 'object' then raise exception 'Each final-tally line must be an object.' using errcode = '22023'; end if;
    begin v_line_id := nullif(btrim(coalesce(v_line->>'directiveLineId', '')), '')::uuid; exception when invalid_text_representation then raise exception 'Each final-tally line requires a valid directiveLineId.' using errcode = '22023'; end;
    if v_line_id is null or not exists (select 1 from atlas.flower_preparation_directive_lines dl where dl.id = v_line_id and dl.directive_id = v_directive.id) then raise exception 'Final-tally line is outside this Owner directive.' using errcode = '22023'; end if;
    if array_position(v_seen_line_ids, v_line_id) is not null then raise exception 'Each requested preparation line may appear only once in final tally.' using errcode = '22023'; end if;
    v_seen_line_ids := array_append(v_seen_line_ids, v_line_id);
    v_actual_text := btrim(coalesce(v_line->>'actualQuantity', ''));
    if v_actual_text !~ '^[0-9]+$' then raise exception 'Actual quantity must be a whole number including zero.' using errcode = '22023'; end if;
    v_actual_quantity := v_actual_text::integer;
    if v_actual_quantity > 10000 then raise exception 'Actual quantity is outside the supported range.' using errcode = '22023'; end if;
    v_note := nullif(btrim(coalesce(v_line->>'note', '')), '');
    if v_note is not null and char_length(v_note) > 1000 then raise exception 'Final-tally line note must be 1000 characters or fewer.' using errcode = '22023'; end if;
  end loop;

  for v_line in select value from jsonb_array_elements(p_worker_added_lines) loop
    if jsonb_typeof(v_line) <> 'object' then raise exception 'Each worker-added tally line must be an object.' using errcode = '22023'; end if;
    v_product_label := nullif(btrim(coalesce(v_line->>'productLabel', '')), '');
    if v_product_label is null or char_length(v_product_label) > 160 then raise exception 'Each worker-added tally line requires a flower label of 160 characters or fewer.' using errcode = '22023'; end if;
    v_output_kind := btrim(coalesce(v_line->>'outputKind', ''));
    if v_output_kind not in ('bundle', 'posy', 'bouquet', 'lobby_arrangement') then raise exception 'Worker-added tally line has an unsupported pack type.' using errcode = '22023'; end if;
    v_actual_text := btrim(coalesce(v_line->>'actualQuantity', ''));
    if v_actual_text !~ '^[1-9][0-9]*$' then raise exception 'Worker-added actual quantity must be a positive whole number.' using errcode = '22023'; end if;
    v_actual_quantity := v_actual_text::integer;
    if v_actual_quantity > 10000 then raise exception 'Worker-added actual quantity is outside the supported range.' using errcode = '22023'; end if;
    if v_output_kind = 'bundle' then
      if coalesce(v_line->>'stemsPerUnit', '') !~ '^[1-9][0-9]*$' then raise exception 'Worker-added bunches require a positive stems-per-bunch count.' using errcode = '22023'; end if;
      v_stems_per_unit := (v_line->>'stemsPerUnit')::integer;
      if v_stems_per_unit > 1000 then raise exception 'Stems per bunch is outside the supported range.' using errcode = '22023'; end if;
    end if;
  end loop;

  insert into atlas.flower_preparation_directive_results(farm_id,directive_id,preparation_task_id,recorded_by_membership_id,idempotency_key,request_fingerprint,metadata)
  values (v_task.farm_id,v_directive.id,v_task.id,v_membership.id,v_key,v_fingerprint,jsonb_build_object('resultVersion',2,'truthBoundary','worker_finished_preparation_tally','readyInventoryCreated',true,'workerAddedLines',p_worker_added_lines,'remainingStems',p_remaining_stems)) returning * into v_result;

  for v_line in select value from jsonb_array_elements(p_actual_lines) loop
    v_line_id := (v_line->>'directiveLineId')::uuid; v_actual_quantity := (v_line->>'actualQuantity')::integer; v_note := nullif(btrim(coalesce(v_line->>'note', '')), '');
    insert into atlas.flower_preparation_directive_result_lines(farm_id,result_id,directive_line_id,actual_quantity,note) values (v_task.farm_id,v_result.id,v_line_id,v_actual_quantity,v_note);
    v_total_saleable := v_total_saleable + v_actual_quantity;
  end loop;
  for v_line in select value from jsonb_array_elements(p_worker_added_lines) loop v_total_saleable := v_total_saleable + (v_line->>'actualQuantity')::integer; end loop;

  insert into atlas.flower_preparation_batches(farm_id,harvest_batch_id,task_id,prepared_date,recorded_by_membership_id,result_kind,note,idempotency_key,metadata)
  values (v_task.farm_id,v_directive.harvest_batch_id,v_task.id,v_ready_date,v_membership.id,case when v_total_saleable > 0 then 'ready' else 'no_saleable_output' end,'Final tally from Owner-directed flower preparation.',left(v_key || ':ready',160),jsonb_build_object('source','flower_preparation_directive_result_v2','directiveResultId',v_result.id,'directiveId',v_directive.id,'truthBoundary','worker_finished_preparation_tally')) returning * into v_batch;

  for v_line in select value from jsonb_array_elements(p_actual_lines) loop
    v_line_id := (v_line->>'directiveLineId')::uuid; v_actual_quantity := (v_line->>'actualQuantity')::integer;
    if v_actual_quantity > 0 then
      select * into v_directive_line from atlas.flower_preparation_directive_lines where id = v_line_id;
      v_inventory_kind := case v_directive_line.output_kind when 'bundle' then 'bunch' when 'posy' then 'posy' when 'bouquet' then 'bouquet' when 'lobby_arrangement' then 'lobby_arrangement' else null end;
      v_unit := case v_inventory_kind when 'bunch' then 'bunch' when 'posy' then 'posy' when 'bouquet' then 'bouquet' when 'lobby_arrangement' then 'arrangement' else null end;
      if v_inventory_kind is null then raise exception 'Requested preparation line has an unsupported sellable output kind.' using errcode = '22023'; end if;
      insert into atlas.flower_ready_inventory_lots(farm_id,preparation_batch_id,inventory_kind,quantity,unit,quantity_exactness,ready_date,idempotency_key,metadata,crop_profile_id,product_label)
      values (v_task.farm_id,v_batch.id,v_inventory_kind,v_actual_quantity,v_unit,'exact',v_ready_date,left('directive-result:' || v_result.id::text || ':' || v_line_id::text,160),jsonb_build_object('source','worker_confirmed_preparation','directiveResultId',v_result.id,'directiveLineId',v_line_id,'requestedQuantity',v_directive_line.requested_quantity,'stemsPerUnit',v_directive_line.stems_per_unit,'outputKind',v_directive_line.output_kind),v_directive_line.crop_profile_id,v_directive_line.product_label);
      v_ready_count := v_ready_count + 1;
    end if;
  end loop;

  v_added_index := 0;
  for v_line in select value from jsonb_array_elements(p_worker_added_lines) loop
    v_added_index := v_added_index + 1; v_actual_quantity := (v_line->>'actualQuantity')::integer; v_product_label := btrim(v_line->>'productLabel'); v_output_kind := btrim(v_line->>'outputKind'); v_stems_per_unit := case when v_output_kind = 'bundle' then (v_line->>'stemsPerUnit')::integer else null end;
    v_inventory_kind := case v_output_kind when 'bundle' then 'bunch' when 'posy' then 'posy' when 'bouquet' then 'bouquet' when 'lobby_arrangement' then 'lobby_arrangement' else null end;
    v_unit := case v_inventory_kind when 'bunch' then 'bunch' when 'posy' then 'posy' when 'bouquet' then 'bouquet' when 'lobby_arrangement' then 'arrangement' else null end;
    insert into atlas.flower_ready_inventory_lots(farm_id,preparation_batch_id,inventory_kind,quantity,unit,quantity_exactness,ready_date,idempotency_key,metadata,crop_profile_id,product_label)
    values (v_task.farm_id,v_batch.id,v_inventory_kind,v_actual_quantity,v_unit,'exact',v_ready_date,left('directive-result:' || v_result.id::text || ':added:' || v_added_index::text,160),jsonb_build_object('source','worker_added_actual','directiveResultId',v_result.id,'lineNumber',coalesce(v_line->>'lineNumber',(v_expected_count+v_added_index)::text),'stemsPerUnit',v_stems_per_unit,'outputKind',v_output_kind),null,v_product_label);
    v_ready_count := v_ready_count + 1;
  end loop;

  v_transition := atlas.record_task_transition_v1(p_task_id=>v_task.id,p_transition=>'done',p_idempotency_key=>'flower-prep-final-tally-v2:'||v_result.id::text,p_target_date=>null,p_note=>null,p_reason=>null,p_lane_key=>null,p_work_key=>'flower_preparation_directive_final_tally',p_payload=>jsonb_build_object('actor_user_id',auth.uid(),'actor_membership_id',v_membership.id,'actor_role',v_membership.role,'flowerPreparationDirectiveResultVersion',2,'flowerPreparationDirectiveResultId',v_result.id,'flowerPreparationDirectiveId',v_directive.id,'actualLineCount',v_expected_count,'workerAddedLineCount',jsonb_array_length(p_worker_added_lines),'readyInventoryLotsCreated',v_ready_count,'truthBoundary','worker_finished_preparation_tally'),p_existing_field_log_id=>null);
  update atlas.flower_preparation_directive_results set metadata=metadata||jsonb_build_object('readyInventoryLotsCreated',v_ready_count,'preparationBatchId',v_batch.id) where id=v_result.id;
  return jsonb_build_object('resultId',v_result.id,'taskId',v_task.id,'directiveId',v_directive.id,'lineCount',v_expected_count,'workerAddedLineCount',jsonb_array_length(p_worker_added_lines),'preparationBatchId',v_batch.id,'readyInventoryLotsCreated',v_ready_count,'transition',v_transition,'deduplicated',false);
end;
$function$;

revoke all on function atlas.record_flower_preparation_directive_result_for_member_v2(uuid,jsonb,jsonb,jsonb,text) from public;
grant execute on function atlas.record_flower_preparation_directive_result_for_member_v2(uuid,jsonb,jsonb,jsonb,text) to authenticated;