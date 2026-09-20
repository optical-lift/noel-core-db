-- Production Current-State Recovery Observation Membrane v1.
-- Re-establishes present Production truth after a continuity/result gap without
-- inventing the date of a missing historical transition.

begin;

create or replace function atlas.production_current_state_recovery_carrier_v1(
  p_task_id uuid,
  p_production_lot_id uuid
)
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','atlas'
as $function$
  select exists(
    select 1
    from atlas.tasks t
    join atlas.production_lots pl
      on pl.id=p_production_lot_id
     and pl.farm_id=t.farm_id
    where t.id=p_task_id
      and t.status in ('open','blocked')
      and lower(coalesce(t.metadata->>'reconciliation_actor',''))='owner'
      and lower(coalesce(t.metadata->>'owner_reconciliation_active','false')) in ('true','yes','1')
      and lower(coalesce(t.metadata->>'work_route',''))='inspect_reconcile'
      and exists(
        select 1
        from atlas.production_lot_crop_cycles plc
        join atlas.task_crop_cycles tc
          on tc.crop_cycle_id=plc.crop_cycle_id
         and tc.task_id=t.id
         and tc.role='observes'
        where plc.production_lot_id=pl.id
      )
  );
$function$;

revoke all on function atlas.production_current_state_recovery_carrier_v1(uuid,uuid)
from public,anon,authenticated;
grant execute on function atlas.production_current_state_recovery_carrier_v1(uuid,uuid)
to service_role;

comment on function atlas.production_current_state_recovery_carrier_v1(uuid,uuid) is
'Internal carrier predicate for owner-led Production continuity recovery. A lawful recovery carrier must be an open/blocked owner reconciliation task that explicitly observes a crop cycle belonging to the target Production Lot.';

create or replace function atlas.validate_production_readiness_observation_v1()
returns trigger
language plpgsql
set search_path='atlas','pg_catalog'
as $function$
declare
  v_batch atlas.production_tray_batches%rowtype;
  v_task_lot uuid;
  v_recovery boolean:=false;
begin
  select * into v_batch
  from atlas.production_tray_batches
  where id=new.tray_batch_id;

  select production_lot_id into v_task_lot
  from atlas.production_lot_tasks
  where task_id=new.task_id
    and link_role='transplant_readiness'
  limit 1;

  if v_batch.id is null
     or v_batch.farm_id is distinct from new.farm_id
     or v_batch.production_lot_id is distinct from new.production_lot_id then
    raise exception 'Readiness observation must stay with its tray batch and farm';
  end if;

  v_recovery:=atlas.production_current_state_recovery_carrier_v1(
    new.task_id,
    new.production_lot_id
  );

  if v_task_lot is distinct from new.production_lot_id and not v_recovery then
    raise exception 'Readiness observation requires the linked readiness task or a governed current-state recovery carrier';
  end if;

  -- During normal execution, the previously projected viable cohort remains
  -- an upper bound. During continuity recovery, that projection is exactly
  -- what may be stale, so a new physical count may correct it upward.
  if not v_recovery
     and new.surviving_seedlings is not null
     and new.surviving_seedlings > coalesce(v_batch.viable_seedlings,v_batch.seeds_sown) then
    raise exception 'Surviving seedling count cannot exceed the viable tray cohort';
  end if;

  if new.observation_outcome='ready'
     and coalesce(new.surviving_seedlings,0)<=0 then
    raise exception 'Ready seedlings require a positive counted cohort';
  end if;

  if new.observation_outcome='failed'
     and coalesce(new.surviving_seedlings,0)<>0 then
    raise exception 'Failed seedling care must record zero survivors';
  end if;

  return new;
end;
$function$;

comment on function atlas.validate_production_readiness_observation_v1() is
'Validates canonical Production readiness evidence. Normal readiness preserves the prior viable-cohort ceiling; governed current-state recovery may correct a stale projected count because the new physical observation is the recovery evidence.';

create or replace function atlas.record_production_current_state_recovery_v1(
  p_task_id uuid,
  p_production_lot_id uuid,
  p_observed_state text,
  p_observed_quantity numeric,
  p_unit text,
  p_tray_count numeric default null,
  p_confidence text default 'counted',
  p_observed_date date default null,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_today date;
  v_observed_date date;
  v_tz text;
  v_state text:=lower(btrim(coalesce(p_observed_state,'')));
  v_unit text:=lower(btrim(coalesce(p_unit,'')));
  v_confidence text:=lower(btrim(coalesce(p_confidence,'')));
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_event_key text;
  v_readiness_key text;
  v_prior text:=current_setting('atlas.production_reconciler_active',true);
  v_task atlas.tasks%rowtype;
  v_lot atlas.production_lots%rowtype;
  v_batch atlas.production_tray_batches%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_event atlas.production_lot_events%rowtype;
  v_readiness atlas.production_readiness_observations%rowtype;
  v_reconcile jsonb;
  v_old_state jsonb;
begin
  if p_task_id is null or p_production_lot_id is null then
    raise exception 'Recovery task and Production Lot are required.' using errcode='22023';
  end if;

  if v_state not in ('seedling_care','hardening','transplant_ready','failed') then
    raise exception 'Observed Production state must be seedling_care, hardening, transplant_ready, or failed.'
      using errcode='22023';
  end if;

  if v_unit not in ('seedling','seedlings','plant','plants') then
    raise exception 'Recovery quantity unit must be seedlings or plants.' using errcode='22023';
  end if;

  v_unit:=case when v_unit in ('plant','plants') then 'plants' else 'seedlings' end;

  if v_confidence not in ('counted','observed','estimated') then
    raise exception 'Recovery confidence must be counted, observed, or estimated.' using errcode='22023';
  end if;

  if v_key is null or length(v_key)>120 then
    raise exception 'A recovery idempotency key of 1-120 characters is required.' using errcode='22023';
  end if;

  if v_state='failed' then
    if coalesce(p_observed_quantity,0)<>0 then
      raise exception 'Failed recovery must record zero surviving plants.' using errcode='22023';
    end if;
  elsif p_observed_quantity is null or p_observed_quantity<=0 then
    raise exception 'A positive current living quantity is required for this recovery state.' using errcode='22023';
  end if;

  if p_tray_count is not null and p_tray_count<0 then
    raise exception 'Tray count cannot be negative.' using errcode='22023';
  end if;
  if v_state<>'failed' and p_tray_count is not null and p_tray_count<=0 then
    raise exception 'A living recovered cohort cannot have zero trays.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.production.current-state-recovery:'||p_production_lot_id::text,0)
  );

  select * into v_lot
  from atlas.production_lots
  where id=p_production_lot_id
  for update;

  if v_lot.id is null then
    raise exception 'Production Lot was not found.' using errcode='P0002';
  end if;

  select * into v_task
  from atlas.tasks
  where id=p_task_id
  for update;

  if v_task.id is null then
    raise exception 'Recovery task was not found.' using errcode='P0002';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
  into v_tz
  from atlas.farms f
  where f.id=v_lot.farm_id;

  if v_tz is null or not exists(select 1 from pg_timezone_names where name=v_tz) then
    v_tz:='America/Chicago';
  end if;

  v_today:=(now() at time zone v_tz)::date;
  v_observed_date:=coalesce(p_observed_date,v_today);
  if v_observed_date>v_today then
    raise exception 'Current-state recovery observation cannot be dated in the future.' using errcode='22023';
  end if;

  if not atlas.production_current_state_recovery_carrier_v1(p_task_id,p_production_lot_id) then
    raise exception 'Task is not a governed owner Production recovery carrier for this Production Lot.'
      using errcode='23514';
  end if;

  select * into v_batch
  from atlas.production_tray_batches
  where production_lot_id=v_lot.id
    and status not in ('transplanted','closed')
  order by batch_number desc,created_at desc
  limit 1
  for update;

  if v_batch.id is null or v_batch.crop_cycle_id is null then
    raise exception 'Production recovery requires an exact active tray batch with crop-cycle lineage.'
      using errcode='23514';
  end if;

  select * into v_cycle
  from atlas.crop_cycles
  where id=v_batch.crop_cycle_id
  for update;

  if v_cycle.id is null
     or v_cycle.farm_id<>v_lot.farm_id
     or not exists(
       select 1
       from atlas.production_lot_crop_cycles plc
       where plc.production_lot_id=v_lot.id
         and plc.crop_cycle_id=v_cycle.id
     )
     or not exists(
       select 1
       from atlas.task_crop_cycles tc
       where tc.task_id=v_task.id
         and tc.crop_cycle_id=v_cycle.id
         and tc.role='observes'
     ) then
    raise exception 'Recovery task, tray batch, Production Lot, and crop cycle do not share exact lineage.'
      using errcode='23514';
  end if;

  v_event_key:=left('production-current-state-recovery:'||v_key,160);
  select * into v_event
  from atlas.production_lot_events
  where farm_id=v_lot.farm_id
    and idempotency_key=v_event_key;

  if v_event.id is not null then
    return jsonb_build_object(
      'state','deduplicated',
      'productionLotId',v_lot.id,
      'trayBatchId',v_batch.id,
      'cropCycleId',v_cycle.id,
      'recoveryEventId',v_event.id,
      'observedState',v_event.metadata->>'observedCurrentState',
      'deduplicated',true
    );
  end if;

  v_old_state:=jsonb_build_object(
    'trayStatus',v_batch.status,
    'trayQuantity',v_batch.current_quantity,
    'trayUnit',v_batch.current_unit,
    'lotStage',v_lot.current_stage,
    'lotQuantity',v_lot.current_quantity,
    'lotUnit',v_lot.current_unit,
    'cropCycleState',v_cycle.cycle_state,
    'cropCycleLifecycleStatus',v_cycle.lifecycle_status,
    'cropCycleCoverageAmount',v_cycle.coverage_amount,
    'cropCycleCoverageUnit',v_cycle.coverage_unit
  );

  perform set_config('atlas.production_reconciler_active','on',true);

  begin
    insert into atlas.production_lot_events(
      farm_id,production_lot_id,event_type,event_date,quantity,unit,
      task_id,tray_batch_id,crop_cycle_id,note,source,idempotency_key,metadata
    ) values(
      v_lot.farm_id,v_lot.id,'current_state_observed',v_observed_date,
      coalesce(p_observed_quantity,0),v_unit,
      v_task.id,v_batch.id,v_cycle.id,p_note,
      'production_continuity_recovery_v1',v_event_key,
      jsonb_build_object(
        'contractVersion','production_current_state_recovery_v1',
        'observedCurrentState',v_state,
        'confidence',v_confidence,
        'trayCount',p_tray_count,
        'priorProjection',v_old_state,
        'historicalTransitionDateInferred',false,
        'recoveryCarrierTaskId',v_task.id,
        'truthBoundary','current physical state observed; missing historical transition date remains unknown'
      )
    )
    returning * into v_event;

    if v_state in ('transplant_ready','failed') then
      v_readiness_key:=left(v_event_key||':readiness',160);
      insert into atlas.production_readiness_observations(
        farm_id,production_lot_id,tray_batch_id,task_id,observation_outcome,
        observed_date,surviving_seedlings,tray_count,confidence,note,idempotency_key,metadata
      ) values(
        v_lot.farm_id,v_lot.id,v_batch.id,v_task.id,
        case when v_state='failed' then 'failed' else 'ready' end,
        v_observed_date,coalesce(p_observed_quantity,0),coalesce(p_tray_count,v_batch.tray_count),
        v_confidence,p_note,v_readiness_key,
        jsonb_build_object(
          'contractVersion','production_current_state_recovery_v1',
          'currentStateRecoveryEventId',v_event.id,
          'crop_cycle_id',v_cycle.id,
          'container_kind',v_batch.container_kind,
          'historicalTransitionDateInferred',false
        )
      )
      returning * into v_readiness;
    end if;

    update atlas.production_tray_batches
    set status=case v_state
          when 'seedling_care' then 'seedling_care'
          when 'hardening' then 'hardening'
          when 'transplant_ready' then 'transplant_ready'
          when 'failed' then 'failed'
        end,
        viable_seedlings=coalesce(p_observed_quantity,0),
        current_quantity=coalesce(p_observed_quantity,0),
        current_unit=v_unit,
        tray_count=coalesce(p_tray_count,tray_count),
        last_observed_at=now(),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
          'current_state_recovery_event_id',v_event.id,
          'current_state_recovery_observed_state',v_state,
          'current_state_recovery_observed_date',v_observed_date,
          'current_state_recovery_confidence',v_confidence,
          'current_state_recovery_readiness_observation_id',v_readiness.id,
          'historical_transition_date_inferred',false
        )),
        updated_at=now()
    where id=v_batch.id;

    update atlas.production_lots
    set current_quantity=coalesce(p_observed_quantity,0),
        current_unit=v_unit,
        current_stage=case v_state
          when 'seedling_care' then 'seedling_care'
          when 'hardening' then 'hardening'
          when 'transplant_ready' then 'transplant_ready'
          when 'failed' then 'seedling_failure_decision'
        end,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
          'last_biological_event','current_state_observed',
          'current_state_recovery_event_id',v_event.id,
          'current_state_recovery_observed_state',v_state,
          'current_state_recovery_observed_date',v_observed_date,
          'current_state_recovery_confidence',v_confidence,
          'current_state_recovery_readiness_observation_id',v_readiness.id,
          'recovered_from_continuity_gap',true,
          'historical_transition_date_inferred',false
        )),
        updated_at=now()
    where id=v_lot.id;

    update atlas.crop_cycles
    set cycle_state=case v_state
          when 'seedling_care' then 'seedling_care'
          when 'hardening' then 'hardening_off'
          when 'transplant_ready' then 'transplant_ready'
          when 'failed' then 'failed'
        end,
        lifecycle_status=case when v_state='failed' then 'archived' else 'active' end,
        coverage_kind='viable_seedlings',
        coverage_amount=coalesce(p_observed_quantity,0),
        coverage_unit=v_unit,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object(
          'current_state_recovery_event_id',v_event.id,
          'current_state_recovery_observed_state',v_state,
          'current_state_recovery_observed_date',v_observed_date,
          'current_state_recovery_confidence',v_confidence,
          'current_state_recovery_readiness_observation_id',v_readiness.id,
          'recovered_from_continuity_gap',true,
          'historical_transition_date_inferred',false,
          'transplant_ready_seedlings',case when v_state='transplant_ready' then p_observed_quantity else null end
        )),
        updated_at=now()
    where id=v_cycle.id;
  exception when others then
    perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
    raise;
  end;

  perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);

  v_reconcile:=atlas.reconcile_production_work_v1(v_lot.id,v_observed_date);

  return jsonb_strip_nulls(jsonb_build_object(
    'state','recovered',
    'productionLotId',v_lot.id,
    'trayBatchId',v_batch.id,
    'cropCycleId',v_cycle.id,
    'recoveryEventId',v_event.id,
    'readinessObservationId',v_readiness.id,
    'observedState',v_state,
    'observedQuantity',coalesce(p_observed_quantity,0),
    'unit',v_unit,
    'observedDate',v_observed_date,
    'confidence',v_confidence,
    'historicalTransitionDateInferred',false,
    'reconcile',v_reconcile,
    'deduplicated',false
  ));
end;
$function$;

revoke all on function atlas.record_production_current_state_recovery_v1(
  uuid,uuid,text,numeric,text,numeric,text,date,text,text
) from public,anon,authenticated;
grant execute on function atlas.record_production_current_state_recovery_v1(
  uuid,uuid,text,numeric,text,numeric,text,date,text,text
) to service_role;

comment on function atlas.record_production_current_state_recovery_v1(
  uuid,uuid,text,numeric,text,numeric,text,date,text,text
) is
'Internal Production continuity recovery membrane. Records a new current physical observation, projects only present state justified by that observation, preserves the unknown date of any missing historical transition, and then re-enters the normal Production reconciler.';

create or replace function atlas.owner_record_production_current_state_recovery_v1(
  p_task_id uuid,
  p_production_lot_id uuid,
  p_observed_state text,
  p_observed_quantity numeric,
  p_unit text,
  p_tray_count numeric default null,
  p_confidence text default 'counted',
  p_observed_date date default null,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas','auth'
as $function$
declare
  v_farm_id uuid;
begin
  select farm_id into v_farm_id
  from atlas.production_lots
  where id=p_production_lot_id;

  if v_farm_id is null then
    raise exception 'Production Lot was not found.' using errcode='P0002';
  end if;

  if not atlas.is_farm_owner(v_farm_id) then
    raise exception 'Owner membership required for Production current-state recovery.'
      using errcode='42501';
  end if;

  return atlas.record_production_current_state_recovery_v1(
    p_task_id,p_production_lot_id,p_observed_state,p_observed_quantity,p_unit,
    p_tray_count,p_confidence,p_observed_date,p_note,p_idempotency_key
  );
end;
$function$;

revoke all on function atlas.owner_record_production_current_state_recovery_v1(
  uuid,uuid,text,numeric,text,numeric,text,date,text,text
) from public,anon;
grant execute on function atlas.owner_record_production_current_state_recovery_v1(
  uuid,uuid,text,numeric,text,numeric,text,date,text,text
) to authenticated,service_role;

comment on function atlas.owner_record_production_current_state_recovery_v1(
  uuid,uuid,text,numeric,text,numeric,text,date,text,text
) is
'Owner-authorized wrapper for the Production current-state recovery membrane. It does not create Worker responsibility or backdate missing biological transitions.';

do $verification$
begin
  if has_function_privilege(
       'authenticated',
       'atlas.record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Internal Production recovery core leaked to authenticated.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.owner_record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Owner Production recovery wrapper is unavailable to authenticated.';
  end if;

  if pg_get_functiondef('atlas.validate_production_readiness_observation_v1()'::regprocedure)
     not ilike '%production_current_state_recovery_carrier_v1%' then
    raise exception 'Readiness validator is not recovery-aware.';
  end if;
end;
$verification$;

commit;
