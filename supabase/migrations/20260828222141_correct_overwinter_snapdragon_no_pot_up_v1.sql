do $$
declare
  v_farm_id uuid;
begin
  select id into v_farm_id from atlas.farms where stable_key='elm_farm';
  if v_farm_id is null then
    raise exception 'Elm Farm was not found.' using errcode='P0002';
  end if;

  update atlas.crop_profiles
  set metadata=(coalesce(metadata,'{}'::jsonb)
      - 'pot_up_days_min'
      - 'pot_up_days_max'
      - 'pot_up_readiness_cue'
      - 'thin_or_prick_out_days_min'
      - 'thin_or_prick_out_days_max')
      || jsonb_build_object(
        'container_kind','3/4-inch soil blocks',
        'pot_up_required',false,
        'pot_up_disposition','not_applicable',
        'container_persists_through_transplant',true,
        'grow_out_container_kind','3/4-inch soil blocks',
        'thin_in_block_as_needed',true,
        'elm_overwinter_method','Remain in 3/4-inch soil blocks from sowing through hardening and field planting; no fall or winter pot-up.',
        'owner_correction_date','2026-08-28',
        'source_basis_override','Generic larger-cell propagation guidance is not applied to Elm Farm overwinter snapdragons; owner production method governs this cohort.'
      ),
      updated_at=now()
  where stable_key in (
    'snapdragon_chantilly_overwinter_2026',
    'snapdragon_first_lady_overwinter_2026',
    'snapdragon_potomac_overwinter_2026',
    'snapdragon_rocket_overwinter_2026'
  );

  insert into atlas.crop_lifecycle_stage_rules(
    crop_profile_id,stage_key,disposition,timing_min_days,timing_max_days,trigger_spec,rule_payload,confidence,source,note,active
  )
  select cp.id,'pot_up','not_applicable',null,null,'{}'::jsonb,
         jsonb_build_object('container_kind','3/4-inch soil blocks','same_container_through','transplant','pot_up_required',false),
         'explicit','owner_correction_20260828',
         'Elm Farm overwinter snapdragons are not potted up in fall or winter; they remain in 3/4-inch soil blocks through planting.',true
  from atlas.crop_profiles cp
  where cp.stable_key in (
    'snapdragon_chantilly_overwinter_2026',
    'snapdragon_first_lady_overwinter_2026',
    'snapdragon_potomac_overwinter_2026',
    'snapdragon_rocket_overwinter_2026'
  )
  on conflict(crop_profile_id,stage_key) do update set
    disposition=excluded.disposition,timing_min_days=null,timing_max_days=null,trigger_spec=excluded.trigger_spec,
    rule_payload=excluded.rule_payload,confidence=excluded.confidence,source=excluded.source,note=excluded.note,active=true,updated_at=now();

  insert into atlas.crop_lifecycle_stage_rules(
    crop_profile_id,stage_key,disposition,timing_min_days,timing_max_days,trigger_spec,rule_payload,confidence,source,note,active
  )
  select cp.id,'grow_out','required',null,null,
         jsonb_build_object('from_stage','seedling_care','through_stage','hardening'),
         jsonb_build_object('container_kind','3/4-inch soil blocks','same_container',true,'ends_at','field_planting'),
         'explicit','owner_correction_20260828',
         'Grow out the overwinter snapdragon cohort in the original 3/4-inch soil blocks until hardening and field planting.',true
  from atlas.crop_profiles cp
  where cp.stable_key in (
    'snapdragon_chantilly_overwinter_2026',
    'snapdragon_first_lady_overwinter_2026',
    'snapdragon_potomac_overwinter_2026',
    'snapdragon_rocket_overwinter_2026'
  )
  on conflict(crop_profile_id,stage_key) do update set
    disposition=excluded.disposition,timing_min_days=excluded.timing_min_days,timing_max_days=excluded.timing_max_days,
    trigger_spec=excluded.trigger_spec,rule_payload=excluded.rule_payload,confidence=excluded.confidence,
    source=excluded.source,note=excluded.note,active=true,updated_at=now();

  update atlas.production_programs
  set metadata=(coalesce(metadata,'{}'::jsonb)
      - 'pot_up_container_kind' - 'pot_up_container_status' - 'pot_up_container_decided_at'
      - 'pot_up_container_decision_task_id' - 'pot_up_container_decision_note')
      || jsonb_build_object('pot_up_required',false,'container_contract','3/4-inch soil blocks through field planting','owner_correction_date','2026-08-28'),
      updated_at=now()
  where farm_id=v_farm_id and stable_key='overwinter_2026_snapdragon_program';

  update atlas.production_lots
  set metadata=(coalesce(metadata,'{}'::jsonb)-'pot_up_container_kind'-'pot_up_container_status'-'pot_up_container_decision_task_id')
      || jsonb_build_object('pot_up_required',false,'current_container_kind','3/4-inch soil blocks','container_persists_through_transplant',true,'owner_correction_date','2026-08-28'),
      updated_at=now()
  where farm_id=v_farm_id and stable_key in (
    'snapdragon_chantilly_overwinter_2026_live','snapdragon_first_lady_overwinter_2026_live',
    'snapdragon_potomac_overwinter_2026_live','snapdragon_rocket_overwinter_2026_live'
  );

  update atlas.tasks
  set status='archived',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'retired_at',now(),'retired_reason','Owner correction: overwinter snapdragons remain in 3/4-inch soil blocks through planting; no pot-up decision exists.',
      'continuity_gate',false,'false_stage_retired',true,'owner_correction_date','2026-08-28'),updated_at=now()
  where farm_id=v_farm_id and metadata->>'task_key'='owner_choose_overwinter_snapdragon_pot_up_container_20260828' and status in ('open','blocked');

  update atlas.planned_work_occurrences
  set state='cancelled',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'cancelled_at',now(),'cancelled_reason','Owner correction: no pot-up stage exists for overwinter snapdragons.',
      'false_stage_retired',true,'owner_correction_date','2026-08-28'),updated_at=now()
  where farm_id=v_farm_id and id in (
    select nullif(t.metadata->>'planned_occurrence_id','')::uuid from atlas.tasks t
    where t.farm_id=v_farm_id and t.metadata->>'task_key'='owner_choose_overwinter_snapdragon_pot_up_container_20260828'
      and nullif(t.metadata->>'planned_occurrence_id','') is not null
  );

  with mapping(lot_key,task_key) as (
    values
      ('snapdragon_rocket_overwinter_2026_live','anna_20260711_sow_rocket_snapdragons'),
      ('snapdragon_potomac_overwinter_2026_live','anna_20260710_sow_snapdragon_trays'),
      ('snapdragon_first_lady_overwinter_2026_live','anna_20260714_sow_first_lady_replacement'),
      ('snapdragon_chantilly_overwinter_2026_live','anna_20260711_sow_chantilly_snapdragons_split')
  ), resolved as (
    select pl.id production_lot_id,t.id task_id,plc.crop_cycle_id
    from mapping m join atlas.production_lots pl on pl.farm_id=v_farm_id and pl.stable_key=m.lot_key
    join atlas.production_lot_crop_cycles plc on plc.production_lot_id=pl.id and plc.relation_role='primary'
    join atlas.tasks t on t.farm_id=v_farm_id and t.metadata->>'task_key'=m.task_key
  )
  insert into atlas.production_lot_tasks(production_lot_id,task_id,link_role,source,metadata)
  select production_lot_id,task_id,'sowing','owner_correction_20260828',jsonb_build_object('crop_cycle_id',crop_cycle_id,'lineage_recovered',true) from resolved
  on conflict(production_lot_id,task_id,link_role) do update set source=excluded.source,metadata=atlas.production_lot_tasks.metadata||excluded.metadata;

  with mapping(lot_key,task_key) as (
    values
      ('snapdragon_rocket_overwinter_2026_live','anna_20260711_sow_rocket_snapdragons'),
      ('snapdragon_potomac_overwinter_2026_live','anna_20260710_sow_snapdragon_trays'),
      ('snapdragon_first_lady_overwinter_2026_live','anna_20260714_sow_first_lady_replacement'),
      ('snapdragon_chantilly_overwinter_2026_live','anna_20260711_sow_chantilly_snapdragons_split')
  ), resolved as (
    select pl.id production_lot_id,pl.stable_key lot_key,pl.current_quantity,pl.current_unit,plc.crop_cycle_id,
           cc.object_id,cc.sown_date,cc.coverage_amount,t.id task_id,t.metadata,cp.metadata profile_metadata
    from mapping m join atlas.production_lots pl on pl.farm_id=v_farm_id and pl.stable_key=m.lot_key
    join atlas.production_lot_crop_cycles plc on plc.production_lot_id=pl.id and plc.relation_role='primary'
    join atlas.crop_cycles cc on cc.id=plc.crop_cycle_id
    join atlas.crop_profiles cp on cp.id=pl.crop_profile_id
    join atlas.tasks t on t.farm_id=v_farm_id and t.metadata->>'task_key'=m.task_key
  )
  insert into atlas.production_tray_batches(
    farm_id,production_lot_id,source_task_id,crop_cycle_id,batch_number,batch_label,container_kind,block_size_in,
    seeds_sown,seed_unit,tray_count,status,sown_date,expected_germination_start,expected_germination_end,
    viable_seedlings,current_quantity,current_unit,idempotency_key,metadata,action_required,source_object_id
  )
  select v_farm_id,r.production_lot_id,r.task_id,r.crop_cycle_id,1,'Original 3/4-inch soil-block cohort','3/4-inch soil blocks',0.75,
         nullif(r.metadata->>'block_count_total','')::numeric,'seeds',coalesce(r.coverage_amount,1),'seedling_care',r.sown_date,
         nullif(r.metadata->>'projected_germination_start','')::date,nullif(r.metadata->>'projected_germination_end','')::date,
         r.current_quantity,r.current_quantity,coalesce(r.current_unit,'seedlings'),'overwinter-2026-snapdragon-original-blocks:'||r.lot_key,
         jsonb_build_object('lineage_kind','original_sowing_container','no_pot_up',true,'pot_up_required',false,
           'container_persists_through_transplant',true,'owner_correction_date','2026-08-28','source_task_key',r.metadata->>'task_key',
           'target_transplant_date',r.profile_metadata->>'target_transplant_date','target_transplant_window_end',r.profile_metadata->>'target_transplant_window_end'),
         false,r.object_id
  from resolved r
  on conflict(farm_id,idempotency_key) do update set
    source_task_id=excluded.source_task_id,crop_cycle_id=excluded.crop_cycle_id,container_kind=excluded.container_kind,block_size_in=excluded.block_size_in,
    seeds_sown=excluded.seeds_sown,tray_count=excluded.tray_count,viable_seedlings=excluded.viable_seedlings,current_quantity=excluded.current_quantity,
    current_unit=excluded.current_unit,metadata=atlas.production_tray_batches.metadata||excluded.metadata,updated_at=now();

  with cohorts as (
    select pl.id production_lot_id,pl.stable_key lot_key,pl.lot_label,pl.expected_transplant_start,pl.expected_transplant_end,
           plc.crop_cycle_id,cc.variety,cp.metadata profile_metadata,ptb.id tray_batch_id,t.zone_id,t.assigned_membership_id,t.assigned_user_id,
           f.organization_id,wd.id work_definition_id,rp.id release_policy_id,
           coalesce(nullif(cp.metadata->>'hardening_start_date','')::date,'2026-09-01'::date) hardening_date
    from atlas.production_lots pl
    join atlas.production_lot_crop_cycles plc on plc.production_lot_id=pl.id and plc.relation_role='primary'
    join atlas.crop_cycles cc on cc.id=plc.crop_cycle_id
    join atlas.crop_profiles cp on cp.id=pl.crop_profile_id
    join atlas.production_tray_batches ptb on ptb.production_lot_id=pl.id and ptb.idempotency_key='overwinter-2026-snapdragon-original-blocks:'||pl.stable_key
    join atlas.production_lot_tasks plt on plt.production_lot_id=pl.id and plt.link_role='sowing'
    join atlas.tasks t on t.id=plt.task_id
    join atlas.farms f on f.id=pl.farm_id
    join atlas.work_definitions wd on wd.farm_id=pl.farm_id and wd.stable_key='production:hardening:v1' and wd.active
    join atlas.work_release_policies rp on rp.work_definition_id=wd.id and rp.stable_key='production:hardening:v1:time-window' and rp.active
    where pl.farm_id=v_farm_id and pl.lifecycle_status='active' and pl.stable_key in (
      'snapdragon_chantilly_overwinter_2026_live','snapdragon_first_lady_overwinter_2026_live',
      'snapdragon_potomac_overwinter_2026_live','snapdragon_rocket_overwinter_2026_live'
    )
  )
  insert into atlas.planned_work_occurrences(
    farm_id,work_definition_id,release_policy_id,occurrence_key,source_kind,source_id,title,planned_due_date,not_before_date,state,
    task_payload,relation_payload,metadata,work_lane,commitment_kind,effort_units,earliest_lawful_date,preferred_start_date,preferred_end_date,
    latest_lawful_date,hard_finish_date,miss_consequence,temporal_contract_source
  )
  select v_farm_id,c.work_definition_id,c.release_policy_id,'production:hardening:'||c.tray_batch_id::text,'production_tray_batch',c.tray_batch_id,
         'Harden off · '||coalesce(c.variety,c.lot_label)||' snapdragons',c.hardening_date,c.hardening_date,'planned',
         jsonb_build_object('title','Harden off · '||coalesce(c.variety,c.lot_label)||' snapdragons','task_type','hardening_off','priority','high',
           'zone_id',c.zone_id,'note','Begin hardening this overwinter snapdragon cohort while it remains in the same 3/4-inch soil blocks. Do not pot up. Preserve the cohort identity and record any meaningful loss or condition change.',
           'action_key','hardening_off','work_class','standard','visibility_scope','assigned_worker','assigned_membership_id',c.assigned_membership_id,
           'assigned_user_id',c.assigned_user_id,'origin_kind','generated','task_scope','farm_operation','organization_id',c.organization_id,
           'work_lane','process_continuation','commitment_kind','dependency','metadata',jsonb_build_object(
             'task_key','production_hardening_'||c.lot_key,'anna_task',true,'owner_task',false,'work_route','hardening_off','assigned_to','Anna',
             'assignee_key','anna','executor_worker_key','anna','executor_membership_id',c.assigned_membership_id,'collection_zone','Grow Room / hardening area',
             'collection_label','Overwinter Snapdragon Hardening','display_action','Harden off','display_subject',coalesce(c.variety,c.lot_label),
             'display_detail','Keep in 3/4-inch soil blocks · no pot-up','production_lot_id',c.production_lot_id,'production_lot_key',c.lot_key,
             'production_tray_batch_id',c.tray_batch_id,'crop_cycle_id',c.crop_cycle_id,'container_kind','3/4-inch soil blocks','pot_up_required',false,
             'container_persists_through_transplant',true,'hardening_start_date',c.hardening_date,'target_transplant_start',c.expected_transplant_start,
             'target_transplant_end',c.expected_transplant_end,'readiness_cue',c.profile_metadata->>'transplant_readiness_cue',
             'structured_result_required',true,'continuity_contract','seedling_care_to_hardening_to_transplant_v1')),
         jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object(
             'crop_cycle_id',c.crop_cycle_id,'role','preserves','confidence','confirmed','source','owner_correction_20260828','metadata',jsonb_build_object(
               'tray_batch_id',c.tray_batch_id,'container_kind','3/4-inch soil blocks','pot_up_required',false))),
           'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',c.production_lot_id,'link_role','hardening',
             'source','owner_correction_20260828','metadata',jsonb_build_object('tray_batch_id',c.tray_batch_id,'crop_cycle_id',c.crop_cycle_id,
               'container_kind','3/4-inch soil blocks'))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
         jsonb_build_object('continuity_contract','seedling_care_to_hardening_to_transplant_v1','production_lot_id',c.production_lot_id,
           'tray_batch_id',c.tray_batch_id,'crop_cycle_id',c.crop_cycle_id,'container_kind','3/4-inch soil blocks','pot_up_required',false,
           'owner_correction_date','2026-08-28'),'process_continuation','dependency',1,c.hardening_date,c.hardening_date,c.hardening_date,
         coalesce(c.expected_transplant_start,c.hardening_date+14),coalesce(c.expected_transplant_start,c.hardening_date+14),
         jsonb_build_object('kind','biological_pressure','effect','Hardening must begin in time for the governed fall transplant window; no pot-up stage intervenes.'),
         'crop_profile_hardening_window'
  from cohorts c
  on conflict(farm_id,work_definition_id,occurrence_key) do update set
    title=excluded.title,planned_due_date=excluded.planned_due_date,not_before_date=excluded.not_before_date,
    state=case when atlas.planned_work_occurrences.state='completed' then 'completed' else 'planned' end,task_payload=excluded.task_payload,
    relation_payload=excluded.relation_payload,metadata=atlas.planned_work_occurrences.metadata||excluded.metadata,work_lane=excluded.work_lane,
    commitment_kind=excluded.commitment_kind,effort_units=excluded.effort_units,earliest_lawful_date=excluded.earliest_lawful_date,
    preferred_start_date=excluded.preferred_start_date,preferred_end_date=excluded.preferred_end_date,latest_lawful_date=excluded.latest_lawful_date,
    hard_finish_date=excluded.hard_finish_date,miss_consequence=excluded.miss_consequence,temporal_contract_source=excluded.temporal_contract_source,updated_at=now();

  update atlas.crop_cycles cc
  set metadata=coalesce(cc.metadata,'{}'::jsonb)||jsonb_build_object('pot_up_required',false,'current_container_kind','3/4-inch soil blocks',
        'container_persists_through_transplant',true,'next_action','hardening_off','next_action_occurrence_id',pwo.id,
        'next_action_due_date',pwo.planned_due_date,'owner_correction_date','2026-08-28'),updated_at=now()
  from atlas.production_lot_crop_cycles plc
  join atlas.production_lots pl on pl.id=plc.production_lot_id
  join atlas.production_tray_batches ptb on ptb.production_lot_id=pl.id and ptb.crop_cycle_id=plc.crop_cycle_id
  join atlas.work_definitions wd on wd.farm_id=pl.farm_id and wd.stable_key='production:hardening:v1'
  join atlas.planned_work_occurrences pwo on pwo.farm_id=pl.farm_id and pwo.work_definition_id=wd.id and pwo.occurrence_key='production:hardening:'||ptb.id::text
  where cc.id=plc.crop_cycle_id and plc.relation_role='primary' and pl.farm_id=v_farm_id and pl.stable_key in (
    'snapdragon_chantilly_overwinter_2026_live','snapdragon_first_lady_overwinter_2026_live',
    'snapdragon_potomac_overwinter_2026_live','snapdragon_rocket_overwinter_2026_live');

  update atlas.production_lots pl
  set metadata=coalesce(pl.metadata,'{}'::jsonb)||jsonb_build_object('pot_up_required',false,'current_container_kind','3/4-inch soil blocks',
        'container_persists_through_transplant',true,'next_action','hardening_off','next_action_occurrence_id',pwo.id,
        'next_action_due_date',pwo.planned_due_date,'owner_correction_date','2026-08-28'),updated_at=now()
  from atlas.production_tray_batches ptb
  join atlas.work_definitions wd on wd.farm_id=ptb.farm_id and wd.stable_key='production:hardening:v1'
  join atlas.planned_work_occurrences pwo on pwo.farm_id=ptb.farm_id and pwo.work_definition_id=wd.id and pwo.occurrence_key='production:hardening:'||ptb.id::text
  where ptb.production_lot_id=pl.id and pl.farm_id=v_farm_id and pl.stable_key in (
    'snapdragon_chantilly_overwinter_2026_live','snapdragon_first_lady_overwinter_2026_live',
    'snapdragon_potomac_overwinter_2026_live','snapdragon_rocket_overwinter_2026_live');
end $$;

create or replace function atlas.resolve_overwinter_snapdragon_pot_up_container_v1(
  p_task_id uuid,p_container_kind text,p_note text default null,p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas','auth' as $$
begin
  raise exception 'Retired lifecycle path: Elm Farm overwinter snapdragons remain in 3/4-inch soil blocks through field planting and do not receive a fall/winter pot-up operation.' using errcode='23514';
end;$$;

create or replace function atlas.record_production_hardening_v1(
  p_task_id uuid,p_observed_date date default current_date,p_note text default null,p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas','auth' as $$
declare
  v_task atlas.tasks%rowtype; v_lot atlas.production_lots%rowtype; v_lot_id uuid; v_batch atlas.production_tray_batches%rowtype; v_batch_id uuid;
  v_cycle atlas.crop_cycles%rowtype; v_profile atlas.crop_profiles%rowtype; v_readiness_occurrence_id uuid;
  v_readiness_work_definition_id uuid; v_readiness_release_policy_id uuid; v_readiness_date date; v_readiness_latest date; v_key text; v_existing_event uuid;
begin
  if p_task_id is null or p_observed_date is null then raise exception 'Hardening task and observed date are required.' using errcode='22023'; end if;
  v_key:=coalesce(nullif(btrim(p_idempotency_key),''),'production-hardening:'||p_task_id::text||':'||p_observed_date::text);
  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Hardening task was not found.' using errcode='P0002'; end if;
  if lower(coalesce(v_task.action_key,'')) not in ('hardening_off','harden','hardening') and lower(coalesce(v_task.task_type,'')) not in ('hardening_off','hardening') then raise exception 'Task is not a governed hardening operation.' using errcode='23514'; end if;
  select plt.production_lot_id,coalesce(v_task.generated_from_id,nullif(plt.metadata->>'tray_batch_id','')::uuid) into v_lot_id,v_batch_id
  from atlas.production_lot_tasks plt where plt.task_id=p_task_id and plt.link_role='hardening' order by plt.created_at desc limit 1;
  if v_lot_id is null or v_batch_id is null then raise exception 'Hardening task is missing production lot or tray-batch lineage.' using errcode='23514'; end if;
  select * into v_lot from atlas.production_lots where id=v_lot_id for update;
  select * into v_batch from atlas.production_tray_batches where id=v_batch_id and production_lot_id=v_lot.id for update;
  if v_batch.id is null or v_batch.status not in ('seedling_care','hardening') then raise exception 'Hardening task is missing an eligible seedling tray batch.' using errcode='23514'; end if;
  select * into v_cycle from atlas.crop_cycles where id=v_batch.crop_cycle_id for update;
  select * into v_profile from atlas.crop_profiles where id=v_lot.crop_profile_id;
  select id into v_existing_event from atlas.production_lot_events where farm_id=v_lot.farm_id and idempotency_key=v_key||':event';
  if v_existing_event is not null then return jsonb_build_object('contractVersion','record_production_hardening_v1','applied',false,'state','already_applied','taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'eventId',v_existing_event); end if;
  if v_task.status not in ('open','blocked') then raise exception 'Hardening task is not actionable.' using errcode='23514'; end if;
  update atlas.production_tray_batches set status='hardening',last_action_at=now(),last_observed_at=now(),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('hardening_started_date',p_observed_date,'hardening_task_id',p_task_id,'hardening_note',p_note),updated_at=now() where id=v_batch.id;
  update atlas.production_lots set current_stage='hardening',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('last_biological_event','hardening_started','hardening_started_date',p_observed_date,'hardening_task_id',p_task_id),updated_at=now() where id=v_lot.id;
  if v_cycle.id is not null then update atlas.crop_cycles set cycle_state='hardening_off',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('hardening_started_date',p_observed_date,'hardening_task_id',p_task_id,'production_tray_batch_id',v_batch.id),updated_at=now() where id=v_cycle.id; end if;
  insert into atlas.production_lot_events(farm_id,production_lot_id,tray_batch_id,crop_cycle_id,task_id,event_type,event_date,quantity,unit,note,idempotency_key,source,metadata)
  values(v_lot.farm_id,v_lot.id,v_batch.id,v_batch.crop_cycle_id,p_task_id,'hardening_started',p_observed_date,v_batch.current_quantity,coalesce(v_batch.current_unit,'seedlings'),p_note,v_key||':event','record_production_hardening_v1',jsonb_build_object('containerKind',v_batch.container_kind,'trayCount',v_batch.tray_count,'potUpRequired',false,'readinessCue',v_profile.metadata->>'transplant_readiness_cue'));
  select wd.id,rp.id into v_readiness_work_definition_id,v_readiness_release_policy_id from atlas.work_definitions wd join atlas.work_release_policies rp on rp.work_definition_id=wd.id and rp.active
  where wd.farm_id=v_lot.farm_id and wd.stable_key='production:transplant-readiness:v1' and rp.stable_key='production:transplant-readiness:v1:time-window' and wd.active limit 1;
  if v_readiness_work_definition_id is null or v_readiness_release_policy_id is null then raise exception 'Canonical production readiness reservoir contract is missing.' using errcode='23514'; end if;
  v_readiness_date:=greatest(p_observed_date,coalesce(v_lot.expected_transplant_start,p_observed_date+coalesce(nullif(v_profile.metadata->>'hardening_duration_days_min','')::integer,10)));
  v_readiness_latest:=coalesce(v_lot.expected_transplant_end,v_readiness_date+5);
  select id into v_readiness_occurrence_id from atlas.planned_work_occurrences where farm_id=v_lot.farm_id and occurrence_key='production:transplant-readiness:'||v_batch.id::text limit 1;
  if v_readiness_occurrence_id is null then
    insert into atlas.planned_work_occurrences(farm_id,work_definition_id,release_policy_id,occurrence_key,source_kind,source_id,title,planned_due_date,not_before_date,state,task_payload,relation_payload,metadata,work_lane,commitment_kind,effort_units,earliest_lawful_date,preferred_start_date,preferred_end_date,latest_lawful_date,hard_finish_date,miss_consequence,temporal_contract_source)
    values(v_lot.farm_id,v_readiness_work_definition_id,v_readiness_release_policy_id,'production:transplant-readiness:'||v_batch.id::text,'production_tray_batch',v_batch.id,'Check transplant readiness · '||v_lot.lot_label,
      v_readiness_date,v_readiness_date,'planned',
      jsonb_build_object('title','Check transplant readiness · '||v_lot.lot_label,'task_type','transplant_readiness','priority','high','zone_id',v_task.zone_id,
        'note','Check the hardened cohort against its stored readiness cue while it remains in the same 3/4-inch soil blocks. Count the living seedlings and trays. If it is not ready, record a later recheck date rather than forcing transplant.',
        'action_key','transplant_readiness','work_class','standard','visibility_scope','assigned_worker','assigned_membership_id',v_task.assigned_membership_id,'assigned_user_id',v_task.assigned_user_id,
        'origin_kind','generated','task_scope','farm_operation','organization_id',v_task.organization_id,'generated_from','production_tray_batch','generated_from_id',v_batch.id,'work_lane','process_continuation','commitment_kind','dependency',
        'metadata',jsonb_build_object('task_key','production_transplant_readiness_'||v_lot.stable_key,'anna_task',true,'owner_task',false,'work_route','transplant_readiness','assigned_to','Anna','assignee_key','anna','executor_worker_key','anna','executor_membership_id',v_task.assigned_membership_id,
          'collection_zone','Hardening area','collection_label','Overwinter Snapdragon Readiness','display_action','Check readiness','display_subject',v_lot.lot_label,'display_detail',coalesce(v_profile.metadata->>'transplant_readiness_cue','Hardened, rooted seedlings ready for field conditions'),
          'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'hardening_started_date',p_observed_date,
          'readiness_cue',v_profile.metadata->>'transplant_readiness_cue','container_kind','3/4-inch soil blocks','pot_up_required',false,'target_transplant_start',v_lot.expected_transplant_start,'target_transplant_end',v_lot.expected_transplant_end,
          'structured_result_required',true,'continuity_contract','hardening_to_transplant_readiness_v1')),
      jsonb_build_object('task_objects',jsonb_build_array(),'task_crop_cycles',jsonb_build_array(jsonb_build_object('crop_cycle_id',v_batch.crop_cycle_id,'role','observes','confidence','confirmed','source','record_production_hardening_v1','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'container_kind','3/4-inch soil blocks','pot_up_required',false))),
        'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','transplant_readiness','source','record_production_hardening_v1','metadata',jsonb_build_object('tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,'container_kind','3/4-inch soil blocks'))),
        'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
      jsonb_build_object('continuity_contract','hardening_to_transplant_readiness_v1','production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'crop_cycle_id',v_batch.crop_cycle_id,
        'readiness_cue',v_profile.metadata->>'transplant_readiness_cue','container_kind','3/4-inch soil blocks','pot_up_required',false),'process_continuation','dependency',1,
      v_readiness_date,v_readiness_date,v_readiness_latest,v_readiness_latest,v_readiness_latest,jsonb_build_object('kind','biological_pressure','effect','Readiness must be checked before the governed transplant window closes.'),'production_transplant_window')
    returning id into v_readiness_occurrence_id;
  end if;
  if v_cycle.id is not null then update atlas.crop_cycles set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','transplant_readiness','next_action_occurrence_id',v_readiness_occurrence_id,'next_action_due_date',v_readiness_date),updated_at=now() where id=v_cycle.id; end if;
  update atlas.production_lots set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('next_action','transplant_readiness','next_action_occurrence_id',v_readiness_occurrence_id,'next_action_due_date',v_readiness_date),updated_at=now() where id=v_lot.id;
  perform atlas.record_task_transition_v1_internal(p_task_id,'done',v_key||':task',null,p_note,'Hardening start was recorded before the task completed.','hardening_off','production_hardening',jsonb_build_object('production_lot_id',v_lot.id,'tray_batch_id',v_batch.id,'hardening_started_date',p_observed_date,'readiness_occurrence_id',v_readiness_occurrence_id,'readiness_due_date',v_readiness_date,'container_kind','3/4-inch soil blocks','pot_up_required',false),null);
  return jsonb_build_object('contractVersion','record_production_hardening_v1','applied',true,'state','hardening_started','taskId',p_task_id,'productionLotId',v_lot.id,'trayBatchId',v_batch.id,'hardeningStartedDate',p_observed_date,'readinessOccurrenceId',v_readiness_occurrence_id,'readinessDueDate',v_readiness_date,'containerKind','3/4-inch soil blocks','potUpRequired',false);
end;$$;