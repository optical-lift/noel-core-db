-- Atlas crop terminal lifecycle + Muncher cucumber specimen v1
--
-- Separates management disposition from biological stage and physical observation,
-- then carries an owner-confirmed finished crop through a governed clear/compost
-- operation. Completing a crop does NOT imply the growing object is vacant.

create table if not exists atlas.crop_cycle_management_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  crop_cycle_id uuid not null references atlas.crop_cycles(id) on delete cascade,
  event_date date not null,
  management_purpose text,
  disposition text not null check (disposition in (
    'continue','retain','harvest','clear','clear_and_compost','clearance_completed','unknown'
  )),
  biomass_destination text,
  confidence text not null check (confidence in ('low','medium','high','owner_confirmed')),
  source_kind text not null,
  source_id text,
  note text,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(farm_id,idempotency_key)
);

create index if not exists crop_cycle_management_events_cycle_date_idx
  on atlas.crop_cycle_management_events(crop_cycle_id,event_date desc,created_at desc);

comment on table atlas.crop_cycle_management_events is
  'Append-only management intent/disposition evidence for a crop body. Biological stage remains crop_cycles; physical observation remains crop_observations.';

revoke all on table atlas.crop_cycle_management_events from public, anon, authenticated;
grant select,insert on table atlas.crop_cycle_management_events to service_role;

create or replace function atlas.crop_cycle_postproduction_state_v1(
  p_crop_cycle_id uuid,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_management atlas.crop_cycle_management_events%rowtype;
  v_observation atlas.crop_observations%rowtype;
  v_open_clear_task uuid;
  v_state text;
  v_operation text;
begin
  if p_crop_cycle_id is null then raise exception 'Crop cycle is required.' using errcode='22023'; end if;
  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop cycle not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select * into v_management
  from atlas.crop_cycle_management_events
  where crop_cycle_id=v_cycle.id and event_date<=coalesce(p_as_of_date,current_date)
  order by event_date desc,created_at desc limit 1;

  select * into v_observation
  from atlas.crop_observations
  where crop_cycle_id=v_cycle.id and coalesce(observed_date,created_at::date)<=coalesce(p_as_of_date,current_date)
  order by coalesce(observed_date,created_at::date) desc,created_at desc limit 1;

  select t.id into v_open_clear_task
  from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and tc.role='clears'
    and t.task_type='crop_clear' and t.status in ('open','blocked')
  order by t.created_at desc limit 1;

  if v_cycle.lifecycle_status in ('complete','archived') or v_cycle.cycle_state='cleared' then
    v_state:='cleared_complete';
    v_operation:=null;
  elsif v_management.disposition in ('clear','clear_and_compost') and v_open_clear_task is not null then
    v_state:='clearance_operation_present';
    v_operation:='clear_crop';
  elsif v_management.disposition in ('clear','clear_and_compost') then
    v_state:='clearance_carrier_required';
    v_operation:='create_clear_operation';
  elsif v_cycle.cycle_state in ('finished','finished_harvest','declining') then
    v_state:='management_disposition_required';
    v_operation:='choose_continue_retain_or_clear';
  else
    v_state:='not_postproduction';
    v_operation:=null;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','crop_cycle_postproduction_state_v1',
    'cropCycleId',v_cycle.id,
    'asOfDate',coalesce(p_as_of_date,current_date),
    'state',v_state,
    'fittingOperation',v_operation,
    'biologicalState',jsonb_build_object(
      'cycleState',v_cycle.cycle_state,
      'lifecycleStatus',v_cycle.lifecycle_status,
      'clearedDate',v_cycle.cleared_date
    ),
    'physicalObservation',case when v_observation.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'observedDate',v_observation.observed_date,
      'stage',v_observation.stage,
      'condition',v_observation.condition,
      'confidence',v_observation.confidence
    )) end,
    'managementState',case when v_management.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'eventDate',v_management.event_date,
      'managementPurpose',v_management.management_purpose,
      'disposition',v_management.disposition,
      'biomassDestination',v_management.biomass_destination,
      'confidence',v_management.confidence
    )) end,
    'clearTaskId',v_open_clear_task,
    'truthBoundary',jsonb_build_object(
      'biologicalStageIsNotPhysicalCondition',true,
      'physicalConditionIsNotManagementDisposition',true,
      'cropCompletionDoesNotImplyObjectVacancy',true,
      'clearanceDoesNotTerminateOtherCropBodiesOnSameObject',true,
      'compostIsBiomassDispositionNotAPlantBiologicalStage',true
    )
  ));
end;
$$;

revoke all on function atlas.crop_cycle_postproduction_state_v1(uuid,date) from public,anon;
grant execute on function atlas.crop_cycle_postproduction_state_v1(uuid,date) to authenticated,service_role;

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
begin
  if new.task_type<>'crop_clear' or new.status<>'done' or old.status='done' then
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
          'object_vacancy_not_inferred',true
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
      'Crop body was physically cleared; removed biomass was taken to '||v_destination||'.',
      'crop-clear:'||new.id::text||':'||v_cycle.id::text,
      jsonb_build_object('biomassDestination',v_destination,'cropCompletionDoesNotImplyObjectVacancy',true)
    ) on conflict(farm_id,idempotency_key) do nothing;

    insert into atlas.crop_cycle_management_events(
      farm_id,crop_cycle_id,event_date,management_purpose,disposition,biomass_destination,
      confidence,source_kind,source_id,note,idempotency_key,metadata
    ) values(
      v_cycle.farm_id,v_cycle.id,v_clear_date,null,'clearance_completed',v_destination,
      'high','task_result',new.id::text,'Physical clearance completed.',
      'crop-clear-management:'||new.id::text||':'||v_cycle.id::text,
      jsonb_build_object('taskId',new.id)
    ) on conflict(farm_id,idempotency_key) do nothing;

    insert into atlas.object_activity_events(
      farm_id,object_id,event_type,event_date,note,created_by,source,metadata,crop_cycle_id,idempotency_key
    )
    select new.farm_id,link.object_id,'cleared',v_clear_date,
      'Muncher cucumber vines cleared and biomass moved to '||v_destination||'.',
      'task_result','crop_terminal_lifecycle_v1',
      jsonb_build_object('task_id',new.id,'biomass_destination',v_destination,'crop_cycle_id',v_cycle.id),
      v_cycle.id,'crop-clear-object:'||new.id::text||':'||link.object_id::text
    from atlas.task_objects link
    where link.task_id=new.id
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

drop trigger if exists trg_sync_completed_crop_cycle_clear_v1 on atlas.tasks;
create trigger trg_sync_completed_crop_cycle_clear_v1
after update of status on atlas.tasks
for each row execute function atlas.sync_completed_crop_cycle_clear_v1();

-- Make the new authority discoverable without replacing the expected-state work still underway.
insert into atlas.architecture_truth_authorities(
  authority_key,domain_key,truth_question,authority_owner,authority_status,
  canonical_relations,canonical_functions,supporting_relations,consumer_surfaces,
  known_competitors,source_custody,rationale
) values(
  'crop_postproduction_transition','crop_lifecycle',
  'After a crop is finished or management orders removal, how does it proceed through clearance and biomass disposition without falsely vacating the growing object?',
  'atlas.crop_cycle_postproduction_state_v1(uuid,date)','canonical',
  array['atlas.crop_cycles','atlas.crop_cycle_management_events'],
  array['atlas.crop_cycle_postproduction_state_v1(uuid,date)'],
  array['atlas.crop_observations','atlas.crop_harvest_events','atlas.tasks','atlas.task_crop_cycles','atlas.task_objects'],
  array['crop task focus','farm continuity','worker day','crop cleanup'],
  array['marking an entire growing object vacant when one interplanted crop ends','treating compost as a crop biological stage'],
  'optical-lift/noel-core-db:supabase/migrations',
  'Crop biological state, observed physical condition, and management disposition are separate. A clear operation terminates only its linked crop body; biomass may go to compost while other crop bodies on the same object continue.'
) on conflict(authority_key) do update set
  authority_owner=excluded.authority_owner,authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,source_custody=excluded.source_custody,
  rationale=excluded.rationale,updated_at=now();

-- Backfill the already-established MG11 navy-bean management purpose into the separated management axis.
do $$
declare
  v_farm uuid;
  v_cycle uuid;
begin
  select id into strict v_farm from atlas.farms where stable_key='elm_farm';
  select cc.id into strict v_cycle
  from atlas.crop_cycles cc join atlas.growing_objects go on go.id=cc.object_id
  where cc.farm_id=v_farm and go.stable_key='mg11' and cc.lifecycle_status='active'
    and cc.crop_profile_id=(select id from atlas.crop_profiles where stable_key='bush_bean');

  insert into atlas.crop_cycle_management_events(
    farm_id,crop_cycle_id,event_date,management_purpose,disposition,biomass_destination,
    confidence,source_kind,source_id,note,idempotency_key,metadata
  ) values(
    v_farm,v_cycle,date '2026-08-26','soil_fixing','retain',null,
    'owner_confirmed','owner_report','owner_report_20260826_mg11_navy_beans',
    'Retain the heavily deer-browsed living navy beans for soil fixing; nonproduction does not imply clearance.',
    'owner-management-20260826-mg11-navy-beans',
    jsonb_build_object('productionExpected',false,'retainWhileAlive',true)
  ) on conflict(farm_id,idempotency_key) do nothing;
end $$;

-- Muncher cucumber: owner-confirmed location + end-of-cycle disposition.
do $$
declare
  v_farm uuid;
  v_org uuid;
  v_cycle atlas.crop_cycles%rowtype;
  v_event_id uuid;
  v_task_id uuid;
  v_anna uuid;
  v_anna_user uuid;
begin
  select id,organization_id into strict v_farm,v_org from atlas.farms where stable_key='elm_farm';
  select cc.* into strict v_cycle from atlas.crop_cycles cc
  join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
  where cc.farm_id=v_farm and cc.lifecycle_status='active' and cp.stable_key='muncher_cucumber';
  select id,user_id into strict v_anna,v_anna_user from atlas.farm_memberships
  where farm_id=v_farm and worker_key='anna' and active=true;

  insert into atlas.crop_harvest_events(
    farm_id,crop_cycle_id,event_kind,outcome,observed_date,note,idempotency_key,metadata
  ) values(
    v_farm,v_cycle.id,'watch','finished',date '2026-08-26',
    'Owner reports the Muncher cucumber on Curve Garden Arches 1 and 2 is at end of cycle and should be removed.',
    'owner-finished-20260826-muncher-cucumber',
    jsonb_build_object('source','owner_report_with_photo','locationScope','Curve Garden Arches 1 and 2')
  ) on conflict(farm_id,idempotency_key) do update set note=excluded.note,metadata=excluded.metadata
  returning id into v_event_id;

  insert into atlas.crop_harvest_availability(
    crop_cycle_id,farm_id,status,observed_date,source_event_id,metadata
  ) values(
    v_cycle.id,v_farm,'finished',date '2026-08-26',v_event_id,
    jsonb_build_object('source','owner_report_with_photo','disposition','clear_and_compost')
  ) on conflict(crop_cycle_id) do update set
    status='finished',observed_date=excluded.observed_date,source_event_id=excluded.source_event_id,
    current_watch_task_id=null,current_watch_occurrence_id=null,current_harvest_task_id=null,current_harvest_occurrence_id=null,
    metadata=atlas.crop_harvest_availability.metadata||excluded.metadata,updated_at=now();

  insert into atlas.crop_observations(
    farm_id,object_id,crop_cycle_id,observed_date,stage,condition,confidence,
    source_kind,source_id,note,idempotency_key,metadata
  ) values(
    v_farm,v_cycle.object_id,v_cycle.id,date '2026-08-26','finished','declining_end_of_cycle','owner_confirmed',
    'owner_report_with_photo','owner_report_20260826_curve_arch_cucumber',
    'Owner identifies the Muncher cucumber as the vines on Curve Garden Arches 1 and 2 and says they are ready to be cleaned up and taken to compost.',
    'owner-report-20260826-muncher-cucumber-finished',
    jsonb_build_object('photoEvidence',true,'locationScope','Curve Garden Arches 1 and 2','clearNow',true)
  ) on conflict(farm_id,idempotency_key) do update set
    observed_date=excluded.observed_date,stage=excluded.stage,condition=excluded.condition,
    confidence=excluded.confidence,note=excluded.note,metadata=excluded.metadata,updated_at=now();

  insert into atlas.crop_cycle_management_events(
    farm_id,crop_cycle_id,event_date,management_purpose,disposition,biomass_destination,
    confidence,source_kind,source_id,note,idempotency_key,metadata
  ) values(
    v_farm,v_cycle.id,date '2026-08-26','food_vine','clear_and_compost','compost',
    'owner_confirmed','owner_report_with_photo','owner_report_20260826_curve_arch_cucumber',
    'End the cucumber crop cycle by removing the vines from Curve Garden Arches 1 and 2 and taking the biomass to compost.',
    'owner-management-20260826-muncher-cucumber',
    jsonb_build_object('locationScope','Curve Garden Arches 1 and 2','cropCompletionDoesNotImplyObjectVacancy',true)
  ) on conflict(farm_id,idempotency_key) do nothing;

  update atlas.crop_cycles
  set cycle_state='finished_harvest',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'location_status','owner_confirmed_scope',
        'physical_location_known',true,
        'location_scope','Curve Garden Arches 1 and 2',
        'location_precision','arch_set_not_root_position',
        'management_disposition','clear_and_compost',
        'biomass_destination','compost',
        'owner_disposition_date','2026-08-26'
      ),updated_at=now()
  where id=v_cycle.id;

  select t.id into v_task_id
  from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and tc.role='clears' and t.task_type='crop_clear' and t.status in ('open','blocked')
  order by t.created_at desc limit 1;

  if v_task_id is null then
    insert into atlas.tasks(
      farm_id,organization_id,title,task_type,status,priority,due_date,note,metadata,
      action_key,work_class,task_series_key,engine_instance_key,visibility_scope,
      assigned_membership_id,assigned_user_id,work_lane,commitment_kind,origin_kind,sky_deferral_mode
    ) values(
      v_farm,v_org,'Clear finished Muncher cucumber — Curve Garden Arches 1 + 2','crop_clear','open','high',date '2026-08-26',
      'Remove only the finished Muncher cucumber vines. Other living crops in these arch beds remain separate crop bodies.',
      jsonb_build_object(
        'display_action','Clear + compost',
        'display_subject','Muncher cucumber vines',
        'display_detail','Curve Garden Arches 1 + 2',
        'display_location','Curve Garden Arches 1 + 2',
        'execution_do','Remove the finished Muncher cucumber vines from Curve Garden Arches 1 and 2 and take the removed vines to the compost.',
        'execution_done_when','The Muncher cucumber vines are off both arches and the removed cucumber biomass is in the compost.',
        'biomass_destination','compost',
        'operation_class_manual','remove_uproot',
        'work_route','crop_cycle',
        'crop_cycle_id',v_cycle.id,
        'source_crop_cycle_id',v_cycle.id,
        'source_management_disposition','clear_and_compost',
        'other_crop_bodies_preserved',true,
        'object_vacancy_not_inferred',true,
        'owner_instruction_source','owner_report_with_photo_20260826'
      ),
      'clear','standard','crop-cycle:'||v_cycle.id::text||':clear','crop-clear:'||v_cycle.id::text,
      'assigned_worker',v_anna,v_anna_user,'process_continuation','persistent','owner_assigned','never'
    ) returning id into v_task_id;

    insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role,confidence,source,metadata)
    values(v_task_id,v_cycle.id,'clears','confirmed','owner_report_with_photo_20260826',jsonb_build_object('biomassDestination','compost'))
    on conflict do nothing;

    insert into atlas.task_objects(task_id,object_id,role)
    select v_task_id,go.id,'cleanup_scope'
    from atlas.growing_objects go
    where go.farm_id=v_farm and go.stable_key in (
      'curve_arch_01_left_bed','curve_arch_01_right_bed','curve_arch_02_left_bed','curve_arch_02_right_bed'
    ) on conflict do nothing;
  end if;

  update atlas.crop_cycles
  set metadata=metadata||jsonb_build_object('current_clear_task_id',v_task_id)
  where id=v_cycle.id;
end $$;

select atlas.assert_architecture_truth_authorities_v1();