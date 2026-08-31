create or replace function atlas.get_worker_day_composition_facts_v1(
  p_membership_id uuid,
  p_service_date date
) returns jsonb
language sql
stable
set search_path = pg_catalog
as $$
with member as (
  select fm.id as membership_id, fm.user_id, fm.farm_id, fm.role, fm.worker_key, fm.active,
         f.organization_id, f.name as farm_name, up.display_name
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  left join atlas.user_profiles up on up.user_id=fm.user_id
  where fm.id=p_membership_id
),
shape as (
  select wsp.*
  from atlas.worker_day_shape_policies wsp
  join member m on m.farm_id=wsp.farm_id and m.membership_id=wsp.membership_id
  where wsp.active
    and wsp.effective_from <= p_service_date
    and (wsp.effective_through is null or wsp.effective_through >= p_service_date)
    and extract(isodow from p_service_date)::integer = any(wsp.weekdays)
  order by wsp.effective_from desc, wsp.version desc
  limit 1
),
latest_snapshot as (
  select dps.*
  from atlas.day_plan_snapshots dps
  where dps.membership_id=p_membership_id and dps.service_date=p_service_date
  order by dps.prepared_at desc
  limit 1
),
placement_ids as (
  select distinct wdtp.task_id
  from atlas.worker_day_task_placements wdtp
  where wdtp.membership_id=p_membership_id and wdtp.service_date=p_service_date
),
snapshot_ids as (
  select unnest(ls.candidate_task_ids) task_id from latest_snapshot ls
),
carrier_ids as (
  select task_id from placement_ids
  union
  select task_id from snapshot_ids
),
carriers as (
  select t.id,t.title,t.status,t.priority,t.due_date,t.task_type,t.work_class,t.work_lane,
         t.commitment_kind,t.effort_units,t.operation_class,t.operation_class_source,t.action_key,
         t.unlock_text,t.blocker_text,t.origin_kind,t.task_scope,t.visibility_scope,
         t.assigned_membership_id,t.assigned_user_id,t.parent_task_id,t.planned_occurrence_id,
         t.generated_from,t.generated_from_id,t.released_at,t.release_reason,t.metadata,
         case when pi.task_id is not null then true else false end as appeared_in_placement,
         case when si.task_id is not null then true else false end as appeared_in_latest_snapshot
  from carrier_ids ci
  join atlas.tasks t on t.id=ci.task_id
  left join placement_ids pi on pi.task_id=t.id
  left join snapshot_ids si on si.task_id=t.id
),
placements as (
  select jsonb_agg(jsonb_build_object(
      'task_id',p.task_id,'day_window',p.day_window,'sort_order',p.sort_order,
      'planned_start_at',p.planned_start_at,'planned_duration_minutes',p.planned_duration_minutes,
      'placement_source',p.placement_source,'placement_reason',p.placement_reason,'state',p.state,
      'planned_occurrence_id',p.planned_occurrence_id
    ) order by p.sort_order) as value
  from atlas.worker_day_task_placements p
  where p.membership_id=p_membership_id and p.service_date=p_service_date
),
reservations as (
  select jsonb_agg(jsonb_build_object(
      'reservation_id',r.id,'stable_key',r.stable_key,'kind',r.kind,'title',r.title,
      'starts_at',r.starts_at,'ends_at',r.ends_at,'source',r.source,'source_reference',r.source_reference,
      'metadata',r.metadata
    ) order by r.starts_at) as value
  from atlas.day_reservations r
  where r.membership_id=p_membership_id and r.service_date=p_service_date and r.active
),
dispositions as (
  select jsonb_agg(jsonb_build_object(
      'task_id',d.task_id,'disposition',d.disposition,'due_date_snapshot',d.due_date_snapshot,
      'safe_boundary_date',d.safe_boundary_date,'clock_state_snapshot',d.clock_state_snapshot,
      'consequence',d.consequence,'overdue_days',d.overdue_days,'deferral_number',d.deferral_number,
      'returns_on',d.returns_on,'requested_return_date',d.requested_return_date,'metadata',d.metadata,
      'created_at',d.created_at
    ) order by d.created_at) as value
  from atlas.task_day_dispositions d
  join member m on m.farm_id=d.farm_id
  where d.actor_membership_id=p_membership_id and d.service_date=p_service_date
),
deps as (
  select jsonb_agg(jsonb_build_object(
      'dependency_clock_id',dc.id,'source_task_id',dc.source_task_id,'downstream_task_id',dc.downstream_task_id,
      'downstream_occurrence_id',dc.downstream_occurrence_id,'source_transitions',dc.source_transitions,
      'source_result_path',dc.source_result_path,'source_result_equals',dc.source_result_equals,
      'delay_interval',dc.delay_interval::text,'state',dc.state,'source_satisfied_at',dc.source_satisfied_at,
      'ready_at',dc.ready_at,'released_at',dc.released_at,'metadata',dc.metadata
    ) order by dc.created_at) as value
  from atlas.task_dependency_clocks dc
  join member m on m.farm_id=dc.farm_id
  where dc.source_task_id in (select task_id from carrier_ids)
     or dc.downstream_task_id in (select task_id from carrier_ids)
),
cues as (
  select jsonb_agg(jsonb_build_object(
      'cue_id',c.id,'cue_kind',c.cue_kind,'anchor_kind',c.anchor_kind,'anchor_task_id',c.anchor_task_id,
      'scheduled_at',c.scheduled_at,'title',c.title,'body',c.body,'payload',c.payload,
      'result_contract',c.result_contract,'status',c.status,'recovery_policy',c.recovery_policy,
      'available_from',c.available_from,'expires_at',c.expires_at
    ) order by coalesce(c.scheduled_at,c.available_from,c.created_at)) as value
  from atlas.worker_day_cues c
  where c.membership_id=p_membership_id and c.service_date=p_service_date
),
day_state as (
  select jsonb_build_object('mode',wds.mode,'routing_mode',wds.routing_mode,
      'recovery_moves_remaining',wds.recovery_moves_remaining,'metadata',wds.metadata) as value
  from atlas.worker_day_states wds
  where wds.worker_membership_id=p_membership_id and wds.work_date=p_service_date
  order by wds.updated_at desc limit 1
),
carrier_json as (
  select jsonb_agg(jsonb_build_object(
      'carrier_ref','task:'||c.id::text,'carrier_type','atlas_task','task_id',c.id,'title',c.title,
      'current_status',c.status,'declared_priority',c.priority,'due_date',c.due_date,
      'task_type',c.task_type,'work_class',c.work_class,'work_lane',c.work_lane,
      'commitment_kind',c.commitment_kind,'effort_units',c.effort_units,
      'declared_operation_class',c.operation_class,'operation_class_source',c.operation_class_source,
      'action_key',c.action_key,'unlock_text',c.unlock_text,'blocker_text',c.blocker_text,
      'origin_kind',c.origin_kind,'task_scope',c.task_scope,'visibility_scope',c.visibility_scope,
      'assignment',jsonb_build_object('membership_id',c.assigned_membership_id,'user_id',c.assigned_user_id),
      'parent_task_id',c.parent_task_id,'planned_occurrence_id',c.planned_occurrence_id,
      'generated_from',c.generated_from,'generated_from_id',c.generated_from_id,
      'released_at',c.released_at,'release_reason',c.release_reason,
      'provenance',jsonb_build_object('appeared_in_actual_placement',c.appeared_in_placement,'appeared_in_latest_day_plan_snapshot',c.appeared_in_latest_snapshot),
      'source_metadata',c.metadata
    ) order by c.due_date nulls last,c.title) as value
  from carriers c
)
select jsonb_build_object(
  'adapter_version','atlas_worker_day_composition_facts_v1',
  'adapter_role','truth_projection_only_no_journey_selection',
  'service_date',p_service_date,
  'subject',jsonb_build_object(
    'membership_id',m.membership_id,'user_id',m.user_id,'display_name',m.display_name,
    'role',m.role,'worker_key',m.worker_key,'membership_active',m.active,
    'farm_id',m.farm_id,'farm_name',m.farm_name,'organization_id',m.organization_id
  ),
  'available_time_policy',coalesce((select jsonb_build_object(
    'policy_key',s.policy_key,'policy_name',s.policy_name,'version',s.version,
    'local_start',s.local_start,'local_end',s.local_end,'authored_reason',s.authored_reason,'metadata',s.metadata
  ) from shape s),'null'::jsonb),
  'fixed_reservations',coalesce((select value from reservations),'[]'::jsonb),
  'day_state',coalesce((select value from day_state),'null'::jsonb),
  'latest_day_plan_snapshot',coalesce((select jsonb_build_object(
    'candidate_task_ids',ls.candidate_task_ids,'planned_task_ids',ls.planned_task_ids,
    'required_task_ids',ls.required_task_ids,'flexible_task_ids',ls.flexible_task_ids,
    'withheld_flexible_task_ids',ls.withheld_flexible_task_ids,'carryover_count',ls.carryover_count,
    'flexible_reduction',ls.flexible_reduction,'prepared_at',ls.prepared_at,'metadata',ls.metadata
  ) from latest_snapshot ls),'null'::jsonb),
  'actual_placements',coalesce((select value from placements),'[]'::jsonb),
  'candidate_affordance_carriers',coalesce((select value from carrier_json),'[]'::jsonb),
  'task_dispositions',coalesce((select value from dispositions),'[]'::jsonb),
  'dependency_clocks',coalesce((select value from deps),'[]'::jsonb),
  'worker_day_cues',coalesce((select value from cues),'[]'::jsonb),
  'epistemic_contract',jsonb_build_object(
    'declared_priority_is_not_canon_priority',true,
    'declared_operation_class_is_company_fact_not_canon_function',true,
    'placement_is_evidence_of_prior_day_composer_state_not_universal_truth',true,
    'snapshot_and_actual_placement_may_disagree',true,
    'missing_day_state_is_unknown_not_negative',true,
    'adapter_does_not_select_fruit_operations_sequence_or_branches',true
  )
)
from member m;
$$;

revoke all on function atlas.get_worker_day_composition_facts_v1(uuid,date) from public;