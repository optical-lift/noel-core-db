-- Behavioral postconditions for Production Current-State Recovery Observation Membrane v1.

do $proof$
declare
  v_result jsonb;
  v_event_id uuid;
  v_ready_result jsonb;
begin
  -- 1. A new physical observation may correct the stale projected count upward
  -- and establish that the cohort is currently hardening.
  v_result:=atlas.record_production_current_state_recovery_v1(
    'e1b00000-0000-4000-8000-000000000001'::uuid,
    'e1700000-0000-4000-8000-000000000001'::uuid,
    'hardening',
    100,
    'seedlings',
    4,
    'counted',
    null,
    'Observed current hardening cohort; historical start date remains unknown.',
    'fixture-hardening-current-state'
  );

  v_event_id:=nullif(v_result->>'recoveryEventId','')::uuid;
  if v_event_id is null then
    raise exception 'Recovery did not append current-state evidence.';
  end if;

  if not exists(
    select 1
    from atlas.production_lot_events e
    where e.id=v_event_id
      and e.event_type='current_state_observed'
      and e.quantity=100
      and e.unit='seedlings'
      and e.task_id='e1b00000-0000-4000-8000-000000000001'::uuid
      and e.metadata->>'observedCurrentState'='hardening'
      and e.event_date=(now() at time zone 'America/Chicago')::date
      and coalesce((e.metadata->>'historicalTransitionDateInferred')::boolean,true)=false
  ) then
    raise exception 'Current hardening evidence is incomplete or backdates history.';
  end if;

  if not exists(
    select 1 from atlas.production_tray_batches
    where id='e1900000-0000-4000-8000-000000000001'::uuid
      and status='hardening'
      and current_quantity=100
      and viable_seedlings=100
  ) then
    raise exception 'Tray batch did not project recovered hardening truth.';
  end if;

  if not exists(
    select 1 from atlas.production_lots
    where id='e1700000-0000-4000-8000-000000000001'::uuid
      and current_stage='hardening'
      and current_quantity=100
      and not (metadata ? 'hardening_started_date')
      and not (metadata ? 'hardening_start_date')
  ) then
    raise exception 'Production Lot did not project hardening without inventing a start date.';
  end if;

  if not exists(
    select 1 from atlas.crop_cycles
    where id='e1500000-0000-4000-8000-000000000001'::uuid
      and cycle_state='hardening_off'
      and coverage_amount=100
      and not (metadata ? 'hardening_started_date')
      and not (metadata ? 'hardening_start_date')
  ) then
    raise exception 'Crop cycle did not project hardening_off without historical invention.';
  end if;

  if not exists(
    select 1
    from atlas.planned_work_occurrences pwo
    where pwo.source_kind='production_tray_batch'
      and pwo.source_id='e1900000-0000-4000-8000-000000000001'::uuid
      and lower(coalesce(pwo.task_payload->>'action_key',''))='transplant_readiness'
      and pwo.state in ('planned','eligible','releasing','released')
  ) then
    raise exception 'Normal Production reconciliation did not derive transplant-readiness work from recovered hardening state.';
  end if;

  if (select status from atlas.tasks
      where id='e1b00000-0000-4000-8000-000000000001'::uuid)<>'open' then
    raise exception 'Multi-body recovery carrier was incorrectly completed by one body observation.';
  end if;

  -- 2. The same idempotency key does not create duplicate evidence.
  perform atlas.record_production_current_state_recovery_v1(
    'e1b00000-0000-4000-8000-000000000001'::uuid,
    'e1700000-0000-4000-8000-000000000001'::uuid,
    'hardening',100,'seedlings',4,'counted',current_date,
    'Replay','fixture-hardening-current-state'
  );

  if (select count(*) from atlas.production_lot_events
      where farm_id='e1200000-0000-4000-8000-000000000001'::uuid
        and idempotency_key='production-current-state-recovery:fixture-hardening-current-state')<>1 then
    raise exception 'Recovery evidence is not idempotent.';
  end if;

  -- 3. A later direct current observation may establish transplant-ready,
  -- including a physical count above the stale pre-recovery viable count.
  v_ready_result:=atlas.record_production_current_state_recovery_v1(
    'e1b00000-0000-4000-8000-000000000001'::uuid,
    'e1700000-0000-4000-8000-000000000001'::uuid,
    'transplant_ready',
    105,
    'seedlings',
    4,
    'counted',
    current_date,
    'Current observation confirms transplant readiness.',
    'fixture-transplant-ready-current-state'
  );

  if nullif(v_ready_result->>'readinessObservationId','')::uuid is null then
    raise exception 'Transplant-ready recovery did not create canonical readiness evidence.';
  end if;

  if not exists(
    select 1
    from atlas.production_readiness_observations ro
    where ro.id=(v_ready_result->>'readinessObservationId')::uuid
      and ro.task_id='e1b00000-0000-4000-8000-000000000001'::uuid
      and ro.observation_outcome='ready'
      and ro.surviving_seedlings=105
      and ro.metadata->>'contractVersion'='production_current_state_recovery_v1'
  ) then
    raise exception 'Canonical readiness evidence did not accept the governed recovery carrier.';
  end if;

  if not exists(
    select 1 from atlas.production_lots
    where id='e1700000-0000-4000-8000-000000000001'::uuid
      and current_stage='transplant_ready'
      and current_quantity=105
  ) then
    raise exception 'Production Lot did not project direct transplant-ready recovery.';
  end if;

  if not exists(
    select 1 from atlas.crop_cycles
    where id='e1500000-0000-4000-8000-000000000001'::uuid
      and cycle_state='transplant_ready'
      and coverage_amount=105
      and metadata->>'transplant_ready_seedlings'='105'
  ) then
    raise exception 'Crop cycle did not project transplant-ready recovery quantity.';
  end if;

  if not exists(
    select 1 from atlas.production_capacity_requirements
    where production_lot_id='e1700000-0000-4000-8000-000000000001'::uuid
      and capacity_kind='bed_feet'
      and calculation_status in ('blocked','calculated','confirmed')
  ) then
    raise exception 'Recovered readiness did not re-enter existing capacity/gate logic.';
  end if;

  -- 4. Recovery cannot cross an unobserved crop-cycle boundary.
  if atlas.production_current_state_recovery_carrier_v1(
       'e1b00000-0000-4000-8000-000000000001'::uuid,
       gen_random_uuid()
     ) then
    raise exception 'Recovery carrier accepted an unrelated Production Lot.';
  end if;

  -- 5. Omitted observed_date is governed by farm civil time, not database current_date.
  if lower(pg_get_function_arguments(
       'atlas.record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)'::regprocedure
     )) not like '%p_observed_date date default null::date%'
     or lower(pg_get_function_arguments(
       'atlas.owner_record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)'::regprocedure
     )) not like '%p_observed_date date default null::date%'
  then
    raise exception 'Recovery APIs do not default observed_date to farm-time resolution.';
  end if;

  if pg_get_functiondef(
       'atlas.record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)'::regprocedure
     ) not ilike '%v_observed_date:=coalesce(p_observed_date,v_today)%'
  then
    raise exception 'Recovery core does not resolve omitted observation date from farm civil time.';
  end if;

  -- 6. Core remains internal; owner wrapper is the browser-facing authority membrane.
  if has_function_privilege(
       'authenticated',
       'atlas.record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Internal recovery core leaked to authenticated.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.owner_record_production_current_state_recovery_v1(uuid,uuid,text,numeric,text,numeric,text,date,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Owner recovery wrapper is not callable by authenticated.';
  end if;
end;
$proof$;
