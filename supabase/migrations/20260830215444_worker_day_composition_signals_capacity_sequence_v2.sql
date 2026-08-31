create or replace function atlas.get_worker_day_composition_signals_v2(
  p_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_facts jsonb;
  v_item jsonb;
  v_active jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_ambiguities jsonb := '[]'::jsonb;
  v_due date;
  v_commitment text;
  v_lane text;
  v_status text;
  v_visibility text;
  v_operation text;
  v_claim_strength text;
  v_task_id uuid;
  v_expected_minutes integer;
  v_physical_load text;
  v_capacity_source text;
  v_total_minutes integer := 0;
  v_heavy_minutes integer := 0;
  v_missing_capacity integer := 0;
  v_missing_sequence integer := 0;
  v_source_order integer;
  v_time_window text;
  v_capacity record;
  v_actual_only integer := 0;
  v_snapshot_only integer := 0;
begin
  v_facts := atlas.get_worker_day_composition_facts_v1(p_membership_id,p_service_date);
  if v_facts is null then raise exception 'worker-day facts unavailable'; end if;

  select regular_target_minutes,recovery_target_minutes,maximum_planned_minutes,heavy_minutes_soft_cap
    into v_capacity
  from atlas.member_capacity_settings
  where membership_id=p_membership_id and active=true
  order by updated_at desc limit 1;

  for v_item in select value from jsonb_array_elements(coalesce(v_facts->'candidate_affordance_carriers','[]'::jsonb)) loop
    v_due := nullif(v_item->>'due_date','')::date;
    v_commitment := coalesce(v_item->>'commitment_kind','');
    v_lane := coalesce(v_item->>'work_lane','');
    v_status := coalesce(v_item->>'current_status','');
    v_visibility := coalesce(v_item->>'visibility_scope','');
    v_operation := coalesce(nullif(v_item->>'declared_operation_class',''), nullif(v_item->>'action_key',''), nullif(v_item->>'task_type',''));

    if coalesce((v_item->'provenance'->>'appeared_in_actual_placement')::boolean,false)
       and not coalesce((v_item->'provenance'->>'appeared_in_latest_day_plan_snapshot')::boolean,false) then v_actual_only:=v_actual_only+1;
    elsif coalesce((v_item->'provenance'->>'appeared_in_latest_day_plan_snapshot')::boolean,false)
       and not coalesce((v_item->'provenance'->>'appeared_in_actual_placement')::boolean,false) then v_snapshot_only:=v_snapshot_only+1;
    end if;

    if v_status <> 'archived'
       and v_visibility <> 'system_internal'
       and (v_due is null or v_due <= p_service_date)
       and (v_commitment in ('hard_date','dependency','persistent')
         or v_lane in ('required','rhythm','process_continuation')
         or coalesce((v_item->'source_metadata'->>'calendar_day_obligation')::boolean,false)
         or coalesce(v_item->>'release_reason','') in ('committed_window','rhythm_serving')) then

      v_claim_strength := case when v_commitment='hard_date' then 'hard'
        when v_commitment in ('dependency','persistent') or v_lane='process_continuation' then 'protected'
        else 'required' end;
      v_task_id := (v_item->>'task_id')::uuid;
      select expected_active_minutes,physical_load,estimate_source
        into v_expected_minutes,v_physical_load,v_capacity_source
      from atlas.task_capacity_profiles where task_id=v_task_id;
      if v_expected_minutes is null then
        v_missing_capacity:=v_missing_capacity+1;
      else
        v_total_minutes:=v_total_minutes+v_expected_minutes;
        if v_physical_load='heavy' then v_heavy_minutes:=v_heavy_minutes+v_expected_minutes; end if;
      end if;

      v_time_window := coalesce(nullif(v_item->'source_metadata'->>'window_key',''),nullif(v_item->'source_metadata'->>'time_of_day',''));
      v_source_order := coalesce(
        nullif(v_item->'source_metadata'->>'day_order','')::integer,
        nullif(v_item->'source_metadata'->>'day_work_order','')::integer,
        nullif(v_item->'source_metadata'->>'run_sheet_order','')::integer
      );
      if v_time_window is null and v_source_order is null then v_missing_sequence:=v_missing_sequence+1; end if;

      v_active := v_active || jsonb_build_array(jsonb_build_object(
        'claim_key',v_item->>'carrier_ref',
        'claim_type',coalesce(nullif(v_commitment,''),nullif(v_lane,''),'operational_claim'),
        'claim_strength',v_claim_strength,
        'carrier_ref',v_item->>'carrier_ref',
        'operation_hint',v_operation,
        'before_state',jsonb_build_object('service_date',p_service_date,'task_status_now',v_status,'due_date',v_due),
        'expected_after_state',jsonb_build_object('task_contract_satisfied',true),
        'entry_condition','claim is active for the service date and assigned carrier is eligible',
        'exit_condition',coalesce(v_item->'source_metadata'->>'execution_done_when',v_item->'source_metadata'->>'execution_checklist_completion_label','task completion contract satisfied'),
        'blocker',nullif(v_item->>'blocker_text',''),
        'timing_hint',v_time_window,
        'source_order_hint',v_source_order,
        'expected_active_minutes',v_expected_minutes,
        'physical_load',v_physical_load,
        'evidence',jsonb_build_object(
          'due_date',v_due,'commitment_kind',v_commitment,'work_lane',v_lane,
          'release_reason',v_item->>'release_reason','provenance',v_item->'provenance',
          'capacity_estimate_source',v_capacity_source,'operation_hint_source',v_item->>'operation_class_source'
        )
      ));
      v_expected_minutes:=null; v_physical_load:=null; v_capacity_source:=null;
    end if;
  end loop;

  if v_actual_only>0 or v_snapshot_only>0 then
    v_ambiguities := v_ambiguities || jsonb_build_array(jsonb_build_object(
      'key','prior_plan_and_actual_placement_disagree','actual_only_count',v_actual_only,
      'latest_snapshot_only_count',v_snapshot_only,'blocking',false,
      'effect','do not reuse either prior candidate set or prior order as autonomous authority'
    ));
  end if;
  if v_missing_capacity>0 then
    v_ambiguities := v_ambiguities || jsonb_build_array(jsonb_build_object('key','missing_capacity_estimates','count',v_missing_capacity,'blocking',true));
  end if;
  if v_missing_sequence>0 then
    v_ambiguities := v_ambiguities || jsonb_build_array(jsonb_build_object(
      'key','missing_independent_sequence_authority','count',v_missing_sequence,'blocking',true,
      'effect','claims may fit capacity but cannot be totally ordered without an independent timing/dependency rule'
    ));
  end if;

  if v_capacity.regular_target_minutes is not null then
    v_constraints := v_constraints || jsonb_build_array(
      jsonb_build_object('key','regular_target_minutes','value',v_capacity.regular_target_minutes,'source','member_capacity_settings'),
      jsonb_build_object('key','maximum_planned_minutes','value',v_capacity.maximum_planned_minutes,'source','member_capacity_settings'),
      jsonb_build_object('key','heavy_minutes_soft_cap','value',v_capacity.heavy_minutes_soft_cap,'source','member_capacity_settings')
    );
  end if;
  if v_facts->'available_time_policy' is not null then
    v_constraints := v_constraints || jsonb_build_array(jsonb_build_object(
      'key','worker_day_window','local_start',v_facts->'available_time_policy'->>'local_start',
      'local_end',v_facts->'available_time_policy'->>'local_end','source','worker_day_shape_policy'
    ));
  end if;

  return jsonb_build_object(
    'signal_contract_version','composition_signals_v1','source_domain','atlas_worker_day',
    'subject',v_facts->'subject','present_state',jsonb_build_object('service_date',p_service_date,'day_state',v_facts->'day_state'),
    'active_claims',v_active,'explicit_user_end',null,'composition_delegated',false,'constraints',v_constraints,
    'capacity_summary',jsonb_build_object(
      'total_expected_active_minutes',v_total_minutes,'heavy_expected_minutes',v_heavy_minutes,
      'regular_target_minutes',v_capacity.regular_target_minutes,'maximum_planned_minutes',v_capacity.maximum_planned_minutes,
      'heavy_minutes_soft_cap',v_capacity.heavy_minutes_soft_cap,
      'fits_regular_target',case when v_capacity.regular_target_minutes is null then null else v_total_minutes<=v_capacity.regular_target_minutes end,
      'fits_maximum',case when v_capacity.maximum_planned_minutes is null then null else v_total_minutes<=v_capacity.maximum_planned_minutes end,
      'fits_heavy_soft_cap',case when v_capacity.heavy_minutes_soft_cap is null then null else v_heavy_minutes<=v_capacity.heavy_minutes_soft_cap end
    ),
    'candidate_evidence',jsonb_build_object('candidate_count',jsonb_array_length(coalesce(v_facts->'candidate_affordance_carriers','[]'::jsonb)),
      'resolved_affordance_count',jsonb_array_length(v_active),'missing_affordance_count',v_missing_capacity),
    'ambiguities',v_ambiguities,
    'sequence_authority',jsonb_build_object('prior_placements_may_be_reused_as_truth',false,'source_authored_hints_only',true,
      'fixed_reservations',coalesce(v_facts->'fixed_reservations','[]'::jsonb)),
    'provenance',jsonb_build_object('adapter','atlas.get_worker_day_composition_facts_v1',
      'signal_adapter','atlas.get_worker_day_composition_signals_v2','epistemic_contract',v_facts->'epistemic_contract')
  );
end;
$$;
revoke all on function atlas.get_worker_day_composition_signals_v2(uuid,date) from public,anon,authenticated;
grant execute on function atlas.get_worker_day_composition_signals_v2(uuid,date) to postgres;