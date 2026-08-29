-- Repair missing crop-cycle pointers only when there is exactly one live occurrence
-- that explicitly carries the cycle in relation_payload and matches the declared next action.
with candidate_links as (
  select
    cc.id as crop_cycle_id,
    min(pwo.id::text)::uuid as occurrence_id,
    count(distinct pwo.id) as candidate_count
  from atlas.crop_cycles cc
  join atlas.planned_work_occurrences pwo
    on pwo.state in ('planned','eligible','releasing','released')
   and lower(coalesce(pwo.task_payload ->> 'action_key','')) = lower(coalesce(cc.metadata ->> 'next_action',''))
  cross join lateral jsonb_array_elements(
    case
      when jsonb_typeof(pwo.relation_payload -> 'task_crop_cycles') = 'array'
        then pwo.relation_payload -> 'task_crop_cycles'
      else '[]'::jsonb
    end
  ) item
  where cc.lifecycle_status = 'active'
    and coalesce(cc.metadata ->> 'next_action','') <> ''
    and coalesce(cc.metadata ->> 'next_action_occurrence_id','') = ''
    and (item ->> 'crop_cycle_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and (item ->> 'crop_cycle_id')::uuid = cc.id
  group by cc.id
  having count(distinct pwo.id) = 1
)
update atlas.crop_cycles cc
set metadata = coalesce(cc.metadata,'{}'::jsonb)
      || jsonb_build_object(
        'next_action_occurrence_id', cl.occurrence_id,
        'continuity_pointer_reconciled_at', now(),
        'continuity_pointer_reconciliation', 'unique_live_relation_payload_match'
      ),
    updated_at = now()
from candidate_links cl
where cc.id = cl.crop_cycle_id;

create or replace view atlas.v_crop_lifecycle_continuity_audit_v1
with (security_invoker = true)
as
with contract_summary as (
  select
    crop_profile_id,
    array_agg(stage_key order by stage_order) filter (where disposition = 'unknown') as unknown_stages,
    array_agg(stage_key order by stage_order) filter (where disposition = 'required') as required_stages,
    bool_or(stage_key = 'transplant' and disposition = 'required') as transplant_required,
    bool_or(stage_key = 'pinch' and disposition = 'unknown') as pinch_unknown,
    bool_or(stage_key in ('harvest_watch','harvest_or_service') and disposition = 'unknown') as harvest_unknown,
    bool_or(stage_key = 'terminal_disposition' and disposition = 'unknown') as terminal_unknown,
    bool_or(stage_key = 'winter' and disposition = 'unknown') as winter_unknown,
    bool_or(stage_key = 'spring_return' and disposition = 'unknown') as spring_return_unknown
  from atlas.v_crop_lifecycle_contract_v1
  group by crop_profile_id
), live_cycle_tasks as (
  select tc.crop_cycle_id,
    count(*) filter (where t.status in ('open','blocked'))::integer as live_task_count,
    count(*) filter (
      where t.status in ('open','blocked')
        and lower(coalesce(t.action_key,'')) = any (array[
          'seed','sow','germination_check','pot_up','thin','harden','hardening',
          'transplant','record_planting_result','establish','water','weed','pinch',
          'train','cut_back','harvest','clear'
        ])
    )::integer as lifecycle_task_count,
    count(*) filter (
      where t.status in ('open','blocked')
        and coalesce(cc.metadata ->> 'next_action','') <> ''
        and lower(coalesce(t.action_key,'')) = lower(cc.metadata ->> 'next_action')
    )::integer as declared_next_action_task_count
  from atlas.task_crop_cycles tc
  join atlas.tasks t on t.id = tc.task_id
  join atlas.crop_cycles cc on cc.id = tc.crop_cycle_id
  group by tc.crop_cycle_id
), cycle_task_destinations as (
  select tc.crop_cycle_id,
    count(distinct tor.object_id) filter (
      where t.status in ('open','blocked')
        and tor.role in ('transplant_destination','target','destination')
    )::integer as destination_object_count
  from atlas.task_crop_cycles tc
  join atlas.tasks t on t.id = tc.task_id
  join atlas.task_objects tor on tor.task_id = t.id
  group by tc.crop_cycle_id
), cycle_task_dependency_pressure as (
  select tc.crop_cycle_id,
    count(distinct t.id) filter (
      where t.status = 'blocked'
        and t.due_date is not null
        and t.due_date <= current_date
        and exists (
          select 1
          from atlas.task_prerequisites tp
          left join atlas.tasks pre on pre.id = tp.prerequisite_task_id
          where tp.downstream_task_id = t.id
            and tp.active
            and tp.satisfied_at is null
            and coalesce(pre.status,'') <> tp.required_status
        )
    )::integer as due_blocked_task_count
  from atlas.task_crop_cycles tc
  join atlas.tasks t on t.id = tc.task_id
  group by tc.crop_cycle_id
), cycle_lot_links as (
  select crop_cycle_id, count(*)::integer as production_lot_count
  from atlas.production_lot_crop_cycles
  group by crop_cycle_id
), cycle_lot_destinations as (
  select plc.crop_cycle_id,
    count(distinct pba.object_id) filter (where pba.assignment_status not in ('cancelled','released'))::integer as destination_object_count
  from atlas.production_lot_crop_cycles plc
  join atlas.production_bed_assignments pba on pba.production_lot_id = plc.production_lot_id
  group by plc.crop_cycle_id
), occurrence_cycle_links as (
  select distinct
    pwo.id as occurrence_id,
    pwo.state,
    pwo.planned_due_date,
    pwo.not_before_date,
    lower(coalesce(pwo.task_payload ->> 'action_key','')) as action_key,
    (item ->> 'crop_cycle_id')::uuid as crop_cycle_id
  from atlas.planned_work_occurrences pwo
  cross join lateral jsonb_array_elements(
    case
      when jsonb_typeof(pwo.relation_payload -> 'task_crop_cycles') = 'array'
        then pwo.relation_payload -> 'task_crop_cycles'
      else '[]'::jsonb
    end
  ) item
  where pwo.state in ('planned','eligible','releasing','released')
    and (item ->> 'crop_cycle_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  union
  select
    pwo.id,
    pwo.state,
    pwo.planned_due_date,
    pwo.not_before_date,
    lower(coalesce(pwo.task_payload ->> 'action_key','')),
    cc.id
  from atlas.crop_cycles cc
  join atlas.planned_work_occurrences pwo
    on pwo.id = case
      when (cc.metadata ->> 'next_action_occurrence_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (cc.metadata ->> 'next_action_occurrence_id')::uuid
      else null
    end
  where pwo.state in ('planned','eligible','releasing','released')
), occurrence_queue_state as (
  select qi.planned_occurrence_id as occurrence_id,
    bool_or(qi.state = 'queued') as is_queued,
    bool_or(qi.state = 'active') as is_active,
    bool_or(qi.state = 'queued' and exists (
      select 1
      from atlas.task_release_queue_items active_qi
      where active_qi.farm_id = qi.farm_id
        and active_qi.queue_key = qi.queue_key
        and active_qi.state = 'active'
    )) as waiting_on_active_predecessor
  from atlas.task_release_queue_items qi
  group by qi.planned_occurrence_id
), cycle_occurrences as (
  select ocl.crop_cycle_id,
    count(distinct ocl.occurrence_id)::integer as live_occurrence_count,
    count(distinct ocl.occurrence_id) filter (
      where coalesce(cc.metadata ->> 'next_action','') <> ''
        and ocl.action_key = lower(cc.metadata ->> 'next_action')
    )::integer as declared_next_action_occurrence_count,
    count(distinct ocl.occurrence_id) filter (
      where ocl.state in ('planned','eligible')
        and ocl.planned_due_date is not null
        and ocl.planned_due_date < current_date
        and coalesce(oqs.waiting_on_active_predecessor,false) = false
        and atlas.work_occurrence_gate_satisfied_v1(ocl.occurrence_id,current_date)
    )::integer as overdue_ready_unreleased_count,
    count(distinct ocl.occurrence_id) filter (
      where ocl.state = 'planned'
        and ocl.planned_due_date is not null
        and ocl.planned_due_date <= current_date
        and coalesce(oqs.waiting_on_active_predecessor,false)
    )::integer as overdue_dependency_waiting_count
  from occurrence_cycle_links ocl
  join atlas.crop_cycles cc on cc.id = ocl.crop_cycle_id
  left join occurrence_queue_state oqs on oqs.occurrence_id = ocl.occurrence_id
  group by ocl.crop_cycle_id
), seed_allocations as (
  select production_lot_id,
    count(*) filter (where allocation_status in ('reserved','allocated','consumed'))::integer as allocation_count,
    coalesce(sum(allocated_quantity) filter (where allocation_status in ('reserved','allocated','consumed')),0)::numeric as allocated_quantity
  from atlas.seed_lot_allocations
  group by production_lot_id
), lot_cycle_links as (
  select production_lot_id, count(*)::integer as crop_cycle_count
  from atlas.production_lot_crop_cycles
  group by production_lot_id
), lot_beds as (
  select production_lot_id,
    count(*) filter (where assignment_status not in ('cancelled','released'))::integer as bed_assignment_count
  from atlas.production_bed_assignments
  group by production_lot_id
), lot_harvest as (
  select pl.id as production_lot_id,
    (hr.id is not null) as has_harvest_rule,
    (hg.id is not null) as has_harvest_gate
  from atlas.production_lots pl
  left join atlas.production_harvest_rules hr on hr.production_lot_id = pl.id
  left join atlas.production_harvest_gates hg on hg.production_lot_id = pl.id
), lot_future_work as (
  select
    (item ->> 'production_lot_id')::uuid as production_lot_id,
    count(*) filter (where pwo.state in ('planned','eligible','releasing','released'))::integer as live_occurrence_count,
    count(*) filter (
      where pwo.state in ('planned','eligible','releasing','released')
        and (
          lower(coalesce(pwo.task_payload ->> 'action_key','')) in ('seed','sow')
          or lower(pwo.title) like '%sow%'
          or lower(pwo.title) like '%seed sowing%'
        )
    )::integer as sow_occurrence_count
  from atlas.planned_work_occurrences pwo
  cross join lateral jsonb_array_elements(
    case
      when jsonb_typeof(pwo.relation_payload -> 'production_lot_tasks') = 'array'
        then pwo.relation_payload -> 'production_lot_tasks'
      else '[]'::jsonb
    end
  ) item
  where (item ->> 'production_lot_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  group by (item ->> 'production_lot_id')::uuid
), cycle_rows as (
  select
    'crop_cycle'::text as subject_kind,
    cc.id as subject_id,
    cc.farm_id,
    cc.crop_profile_id,
    cp.stable_key as crop_profile_stable_key,
    cc.crop_label,
    cc.variety,
    cc.lifecycle_status,
    cc.cycle_state as current_stage,
    coalesce(cc.sown_date, cc.planted_date, cc.created_at::date) as anchor_date,
    coalesce(cs.unknown_stages, array[]::text[]) as unknown_contract_stages,
    coalesce(cs.required_stages, array[]::text[]) as required_contract_stages,
    coalesce(cl.production_lot_count,0) > 0 as has_production_lineage,
    null::boolean as has_input_custody,
    (coalesce(lct.lifecycle_task_count,0) > 0 or coalesce(co.live_occurrence_count,0) > 0) as has_next_work,
    (
      cc.metadata ? 'future_destination'
      or cc.metadata ? 'future_destination_object_id'
      or cc.metadata ? 'future_destination_program'
      or cc.metadata ? 'future_destination_program_object_ids'
      or cc.metadata ? 'batch_destination_plan'
      or coalesce(ctd.destination_object_count,0) > 0
      or coalesce(cld.destination_object_count,0) > 0
      or (cc.planted_date is not null and go.object_type is distinct from 'seed_room')
    ) as has_destination_truth,
    (
      cc.expected_harvest_watch_start is not null
      or cc.expected_harvest_watch_end is not null
      or (cs.harvest_unknown is false)
    ) as has_harvest_plan,
    (
      cc.expected_clear_date is not null
      or cc.cleared_date is not null
      or cc.turnover_date is not null
      or (cs.terminal_unknown is false)
    ) as has_terminal_contract,
    cs.transplant_required,
    cs.pinch_unknown,
    cs.harvest_unknown,
    cs.terminal_unknown,
    cs.winter_unknown,
    cs.spring_return_unknown,
    array_remove(array[
      case when cc.crop_profile_id is null then 'missing_crop_profile' end,
      case when cc.crop_profile_id is not null and cs.pinch_unknown then 'pinch_rule_unknown' end,
      case when cc.crop_profile_id is not null and cs.harvest_unknown then 'harvest_or_service_unknown' end,
      case when cc.crop_profile_id is not null and cs.terminal_unknown then 'terminal_behavior_unknown' end,
      case when cc.crop_profile_id is not null and cs.winter_unknown then 'winter_behavior_unknown' end,
      case when cc.crop_profile_id is not null and cs.spring_return_unknown then 'spring_return_unknown' end,
      case when coalesce(cs.transplant_required,false)
        and not (
          cc.metadata ? 'future_destination'
          or cc.metadata ? 'future_destination_object_id'
          or cc.metadata ? 'future_destination_program'
          or cc.metadata ? 'future_destination_program_object_ids'
          or cc.metadata ? 'batch_destination_plan'
          or coalesce(ctd.destination_object_count,0) > 0
          or coalesce(cld.destination_object_count,0) > 0
        )
        and go.object_type = 'seed_room'
        and (
          cc.cycle_state in ('hardening_off','transplant_ready')
          or lower(coalesce(cc.metadata ->> 'next_action','')) = 'transplant'
        )
        then 'transplant_destination_missing' end,
      case when coalesce(cs.transplant_required,false)
        and not (
          cc.metadata ? 'future_destination'
          or cc.metadata ? 'future_destination_object_id'
          or cc.metadata ? 'future_destination_program'
          or cc.metadata ? 'future_destination_program_object_ids'
          or cc.metadata ? 'batch_destination_plan'
          or coalesce(ctd.destination_object_count,0) > 0
          or coalesce(cld.destination_object_count,0) > 0
        )
        and go.object_type = 'seed_room'
        and not (
          cc.cycle_state in ('hardening_off','transplant_ready')
          or lower(coalesce(cc.metadata ->> 'next_action','')) = 'transplant'
        )
        then 'future_transplant_destination_missing' end,
      case when cc.cycle_state in ('sown','germinated','seedling','seedling_care','transplant_ready','hardening_off')
        and coalesce(lct.lifecycle_task_count,0) = 0
        and coalesce(co.live_occurrence_count,0) = 0
        then 'next_operation_missing' end,
      case when coalesce(cc.metadata ->> 'next_action','') <> ''
        and coalesce(lct.declared_next_action_task_count,0) = 0
        and coalesce(co.declared_next_action_occurrence_count,0) = 0
        then 'declared_next_action_unwired' end,
      case when coalesce(co.overdue_ready_unreleased_count,0) > 0
        then 'overdue_ready_occurrence_unreleased' end,
      case when coalesce(co.overdue_dependency_waiting_count,0) > 0
          or coalesce(ctdp.due_blocked_task_count,0) > 0
        then 'due_operation_waiting_on_dependency' end,
      case when go.object_type = 'seed_room' and coalesce(cl.production_lot_count,0) = 0
        then 'production_lineage_missing' end
    ], null)::text[] as gap_types
  from atlas.crop_cycles cc
  left join atlas.crop_profiles cp on cp.id = cc.crop_profile_id
  left join contract_summary cs on cs.crop_profile_id = cc.crop_profile_id
  left join atlas.growing_objects go on go.id = cc.object_id
  left join live_cycle_tasks lct on lct.crop_cycle_id = cc.id
  left join cycle_task_destinations ctd on ctd.crop_cycle_id = cc.id
  left join cycle_task_dependency_pressure ctdp on ctdp.crop_cycle_id = cc.id
  left join cycle_lot_links cl on cl.crop_cycle_id = cc.id
  left join cycle_lot_destinations cld on cld.crop_cycle_id = cc.id
  left join cycle_occurrences co on co.crop_cycle_id = cc.id
  where cc.lifecycle_status = 'active'
), lot_rows as (
  select
    'production_lot'::text as subject_kind,
    pl.id as subject_id,
    pl.farm_id,
    pl.crop_profile_id,
    cp.stable_key as crop_profile_stable_key,
    cp.crop_label,
    cp.variety,
    pl.lifecycle_status,
    pl.current_stage,
    coalesce(pl.actual_sow_date, pl.planned_sow_date, pl.created_at::date) as anchor_date,
    coalesce(cs.unknown_stages, array[]::text[]) as unknown_contract_stages,
    coalesce(cs.required_stages, array[]::text[]) as required_contract_stages,
    true as has_production_lineage,
    case
      when lower(coalesce(pl.planned_input_unit,'')) like '%seed%'
        or lower(coalesce(cp.default_planting_method,'')) like '%seed%'
        or lower(coalesce(cp.default_planting_method,'')) like '%sow%'
      then coalesce(sa.allocation_count,0) > 0
      else true
    end as has_input_custody,
    coalesce(lfw.live_occurrence_count,0) > 0 as has_next_work,
    coalesce(lb.bed_assignment_count,0) > 0 as has_destination_truth,
    (
      pl.expected_harvest_start is not null
      or pl.expected_harvest_end is not null
      or coalesce(lh.has_harvest_rule,false)
    ) as has_harvest_plan,
    (cs.terminal_unknown is false) as has_terminal_contract,
    cs.transplant_required,
    cs.pinch_unknown,
    cs.harvest_unknown,
    cs.terminal_unknown,
    cs.winter_unknown,
    cs.spring_return_unknown,
    array_remove(array[
      case when pl.crop_profile_id is null then 'missing_crop_profile' end,
      case when pl.crop_profile_id is not null and cs.pinch_unknown then 'pinch_rule_unknown' end,
      case when pl.crop_profile_id is not null and cs.harvest_unknown then 'harvest_or_service_unknown' end,
      case when pl.crop_profile_id is not null and cs.terminal_unknown then 'terminal_behavior_unknown' end,
      case when pl.crop_profile_id is not null and cs.winter_unknown then 'winter_behavior_unknown' end,
      case when pl.crop_profile_id is not null and cs.spring_return_unknown then 'spring_return_unknown' end,
      case when (
          lower(coalesce(pl.planned_input_unit,'')) like '%seed%'
          or lower(coalesce(cp.default_planting_method,'')) like '%seed%'
          or lower(coalesce(cp.default_planting_method,'')) like '%sow%'
        ) and coalesce(sa.allocation_count,0) = 0
        then 'input_custody_missing' end,
      case when lower(coalesce(pl.planned_input_unit,'')) like '%seed%'
        and pl.planned_input_quantity is null
        then 'input_quantity_unknown' end,
      case when pl.planned_sow_date is not null and coalesce(lfw.sow_occurrence_count,0) = 0
        then 'sow_occurrence_missing' end,
      case when coalesce(lcl.crop_cycle_count,0) = 0 then 'crop_cycle_lineage_missing' end,
      case when coalesce(cs.transplant_required,false) and coalesce(lb.bed_assignment_count,0) = 0
        then 'destination_assignment_missing' end,
      case when pl.crop_profile_id is not null and not (
          pl.expected_harvest_start is not null
          or pl.expected_harvest_end is not null
          or coalesce(lh.has_harvest_rule,false)
        ) then 'harvest_plan_missing' end
    ], null)::text[] as gap_types
  from atlas.production_lots pl
  left join atlas.crop_profiles cp on cp.id = pl.crop_profile_id
  left join contract_summary cs on cs.crop_profile_id = pl.crop_profile_id
  left join seed_allocations sa on sa.production_lot_id = pl.id
  left join lot_cycle_links lcl on lcl.production_lot_id = pl.id
  left join lot_beds lb on lb.production_lot_id = pl.id
  left join lot_harvest lh on lh.production_lot_id = pl.id
  left join lot_future_work lfw on lfw.production_lot_id = pl.id
  where pl.lifecycle_status in ('planned','active')
)
select *,
  cardinality(gap_types) as gap_count,
  case
    when cardinality(gap_types) = 0 then 'pass'
    when 'missing_crop_profile' = any(gap_types) then 'identity_blocked'
    when 'next_operation_missing' = any(gap_types) or 'declared_next_action_unwired' = any(gap_types) or 'overdue_ready_occurrence_unreleased' = any(gap_types) or 'sow_occurrence_missing' = any(gap_types) then 'continuity_broken'
    when 'input_custody_missing' = any(gap_types) or 'transplant_destination_missing' = any(gap_types) or 'destination_assignment_missing' = any(gap_types) then 'execution_blocked'
    when 'due_operation_waiting_on_dependency' = any(gap_types) then 'dependency_pressure'
    else 'contract_incomplete'
  end as audit_status
from cycle_rows
union all
select *,
  cardinality(gap_types) as gap_count,
  case
    when cardinality(gap_types) = 0 then 'pass'
    when 'missing_crop_profile' = any(gap_types) then 'identity_blocked'
    when 'next_operation_missing' = any(gap_types) or 'declared_next_action_unwired' = any(gap_types) or 'overdue_ready_occurrence_unreleased' = any(gap_types) or 'sow_occurrence_missing' = any(gap_types) then 'continuity_broken'
    when 'input_custody_missing' = any(gap_types) or 'transplant_destination_missing' = any(gap_types) or 'destination_assignment_missing' = any(gap_types) then 'execution_blocked'
    when 'due_operation_waiting_on_dependency' = any(gap_types) then 'dependency_pressure'
    else 'contract_incomplete'
  end as audit_status
from lot_rows;

revoke all on atlas.v_crop_lifecycle_continuity_audit_v1 from anon, authenticated;
grant select on atlas.v_crop_lifecycle_continuity_audit_v1 to service_role;