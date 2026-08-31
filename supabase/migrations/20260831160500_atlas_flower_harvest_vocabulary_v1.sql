BEGIN;

-- Canonical flower vocabulary v1
--
-- Harvest truth:
--   florist_grade = usable stems cut at florist harvest stage
--   event_grade   = usable stems cut after opening beyond florist stage
--   deadheaded    = non-harvest removal for cut-and-come-again material
--   crop_loss     = non-harvest loss for one-cut material
--
-- Prepared sellable form:
--   stem | bundle | posy | bouquet | arrangement
--   bundle is exactly 5, 10, or 20 stems.
--
-- Historical vocabulary is retained as evidence. New writers are normalized at
-- the Ready-inventory membrane so older application callers cannot create new
-- bunch/lobby_arrangement truth.

alter table atlas.flower_harvest_bucket_observations
  add column if not exists harvest_grade text;

alter table atlas.flower_harvest_bucket_observations
  drop constraint if exists flower_harvest_bucket_observations_harvest_grade_check;
alter table atlas.flower_harvest_bucket_observations
  add constraint flower_harvest_bucket_observations_harvest_grade_check
  check (harvest_grade is null or harvest_grade in ('florist_grade','event_grade'));

comment on column atlas.flower_harvest_bucket_observations.harvest_grade is
  'Canonical grade for usable harvested flower stems. florist_grade and event_grade are harvest truth; deadheading and crop loss never create harvest observations.';

alter table atlas.weekly_harvest_task_results
  add column if not exists harvest_grade text;

alter table atlas.weekly_harvest_task_results
  drop constraint if exists weekly_harvest_task_results_harvest_grade_check;
alter table atlas.weekly_harvest_task_results
  add constraint weekly_harvest_task_results_harvest_grade_check
  check (harvest_grade is null or harvest_grade in ('florist_grade','event_grade'));

alter table atlas.weekly_harvest_task_results
  drop constraint if exists weekly_harvest_task_results_result_kind_check;
alter table atlas.weekly_harvest_task_results
  add constraint weekly_harvest_task_results_result_kind_check
  check (result_kind in ('harvest_amount','food_picked','not_ready','deadheaded','crop_exhausted','crop_loss'));

alter table atlas.weekly_harvest_task_results
  drop constraint if exists weekly_harvest_task_results_v2_shape_check;
alter table atlas.weekly_harvest_task_results
  add constraint weekly_harvest_task_results_v2_shape_check
  check (
    (
      result_kind = 'harvest_amount'
      and bucket_halves is not null
      and bucket_halves >= 1
      and bucket_band is null
      and more_availability is null
    )
    or (
      result_kind in ('food_picked','not_ready','deadheaded','crop_exhausted','crop_loss')
      and bucket_halves is null
      and bucket_band is null
      and more_availability is null
      and harvest_grade is null
    )
  );

alter table atlas.crop_harvest_events
  drop constraint if exists crop_harvest_events_outcome_check;
alter table atlas.crop_harvest_events
  add constraint crop_harvest_events_outcome_check
  check (outcome in (
    'not_ready','beginning','harvestable','declining','finished','problem_or_uncertain',
    'harvested_more','harvested_finished','harvested_uncertain','harvested_amount',
    'deadheaded','crop_exhausted','crop_loss'
  ));

comment on column atlas.weekly_harvest_task_results.harvest_grade is
  'Canonical grade only when the result is an actual usable flower harvest. Non-harvest removals carry no harvest grade.';

-- Preserve old directive rows while preventing any new bundle direction from
-- using an arbitrary stem count.
alter table atlas.flower_preparation_directive_lines
  drop constraint if exists flower_preparation_directive_lines_bundle_size_check;
alter table atlas.flower_preparation_directive_lines
  add constraint flower_preparation_directive_lines_bundle_size_check
  check (
    (output_kind = 'bundle' and stems_per_unit in (5,10,20))
    or (output_kind <> 'bundle' and stems_per_unit is null)
  );

comment on column atlas.flower_preparation_directive_lines.stems_per_unit is
  'Bundle size. Canonical florist bundles contain exactly 5, 10, or 20 stripped, rubber-banded stems.';

-- Ready inventory keeps legacy kinds readable, but adds the canonical forms.
alter table atlas.flower_ready_inventory_lots
  drop constraint if exists flower_ready_inventory_lots_kind_check;
alter table atlas.flower_ready_inventory_lots
  add constraint flower_ready_inventory_lots_kind_check
  check (inventory_kind in (
    'conditioned_bucket','counted_stems',
    'stem','bundle','posy','bouquet','arrangement',
    'bunch','lobby_arrangement'
  ));

alter table atlas.flower_ready_inventory_lots
  drop constraint if exists flower_ready_inventory_lots_semantics_check;
alter table atlas.flower_ready_inventory_lots
  add constraint flower_ready_inventory_lots_semantics_check
  check (
    (inventory_kind = 'conditioned_bucket' and unit = 'bucket_equivalent' and quantity_exactness in ('exact','lower_bound') and mod(quantity * 4, 1) = 0)
    or (inventory_kind = 'counted_stems' and unit = 'stem' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
    or (inventory_kind = 'stem' and unit = 'stem' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
    or (
      inventory_kind = 'bundle'
      and unit = 'bundle'
      and quantity_exactness = 'exact'
      and mod(quantity,1) = 0
      and coalesce(metadata->>'stemsPerUnit','') in ('5','10','20')
    )
    or (inventory_kind = 'posy' and unit = 'posy' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
    or (inventory_kind = 'bouquet' and unit = 'bouquet' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
    or (inventory_kind = 'arrangement' and unit = 'arrangement' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
    -- Historical rows only. A BEFORE INSERT trigger below prevents new legacy vocabulary.
    or (inventory_kind = 'bunch' and unit = 'bunch' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
    or (inventory_kind = 'lobby_arrangement' and unit = 'arrangement' and quantity_exactness = 'exact' and mod(quantity,1) = 0)
  );

create or replace function atlas.normalize_new_flower_ready_inventory_vocabulary_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_output_kind text := lower(btrim(coalesce(new.metadata->>'outputKind','')));
  v_stems text := btrim(coalesce(new.metadata->>'stemsPerUnit',''));
begin
  if new.inventory_kind = 'bunch' then
    if v_output_kind <> 'bundle' or v_stems not in ('5','10','20') then
      raise exception 'New flower Ready inventory may not use bunch. A bundle must contain exactly 5, 10, or 20 stems.' using errcode='22023';
    end if;
    new.inventory_kind := 'bundle';
    new.unit := 'bundle';
    new.metadata := coalesce(new.metadata,'{}'::jsonb) || jsonb_build_object(
      'vocabularyNormalizedFrom','bunch',
      'canonicalInventoryKind','bundle',
      'flowerVocabularyVersion',1
    );
  elsif new.inventory_kind = 'lobby_arrangement' then
    new.inventory_kind := 'arrangement';
    new.unit := 'arrangement';
    new.metadata := coalesce(new.metadata,'{}'::jsonb) || jsonb_build_object(
      'vocabularyNormalizedFrom','lobby_arrangement',
      'canonicalInventoryKind','arrangement',
      'flowerVocabularyVersion',1
    );
  elsif new.inventory_kind = 'bundle' then
    if v_stems not in ('5','10','20') then
      raise exception 'A flower bundle must contain exactly 5, 10, or 20 stems.' using errcode='22023';
    end if;
    new.unit := 'bundle';
  elsif new.inventory_kind = 'arrangement' then
    new.unit := 'arrangement';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.normalize_new_flower_ready_inventory_vocabulary_v1() from public;

drop trigger if exists normalize_new_flower_ready_inventory_vocabulary_v1 on atlas.flower_ready_inventory_lots;
create trigger normalize_new_flower_ready_inventory_vocabulary_v1
before insert on atlas.flower_ready_inventory_lots
for each row execute function atlas.normalize_new_flower_ready_inventory_vocabulary_v1();

-- Existing Ready birth records are append-only source evidence. Keep historical
-- bunch/lobby_arrangement rows byte-for-byte in their original vocabulary; new
-- writes normalize at the insertion membrane and read compatibility remains below.
create or replace function atlas.flower_demand_line_unit_v1(p_inventory_kind text)
returns text
language sql
immutable
set search_path to 'pg_catalog','atlas'
as $function$
  select case lower(btrim(coalesce(p_inventory_kind,'')))
    when 'conditioned_bucket' then 'bucket_equivalent'
    when 'counted_stems' then 'stem'
    when 'stem' then 'stem'
    when 'bundle' then 'bundle'
    when 'posy' then 'posy'
    when 'bouquet' then 'bouquet'
    when 'arrangement' then 'arrangement'
    -- Legacy inventory remains fulfillable; new UI and Ready writers do not create this term.
    when 'bunch' then 'bunch'
    when 'lobby_arrangement' then 'arrangement'
    else null
  end;
$function$;

comment on function atlas.flower_demand_line_unit_v1(text) is
  'Returns the physical unit for flower demand inventory kinds. Canonical sale forms are stem, bundle, posy, bouquet, arrangement; bunch/lobby_arrangement are legacy-read compatibility only.';

create or replace function atlas.record_weekly_harvest_row_core_v3(
  p_task_id uuid,
  p_crop_cycle_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_result_kind text,
  p_harvest_grade text,
  p_bucket_halves integer,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_existing atlas.weekly_harvest_task_results%rowtype;
  v_kind text := lower(btrim(coalesce(p_result_kind,'')));
  v_grade text := lower(btrim(coalesce(p_harvest_grade,'')));
  v_halves integer := p_bucket_halves;
  v_band text;
  v_floor numeric(10,2);
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_next_thursday date;
  v_event atlas.crop_harvest_events%rowtype;
  v_batch_id uuid;
  v_observation atlas.flower_harvest_bucket_observations%rowtype;
  v_result atlas.weekly_harvest_task_results%rowtype;
  v_unresolved integer := 0;
  v_transition jsonb;
  v_next jsonb;
  v_season_end date;
  v_cut_and_come_again boolean := false;
begin
  if v_kind not in ('harvest_amount','not_ready','deadheaded','crop_loss') then
    raise exception 'Choose Harvest, Not ready, Deadheaded, or Crop loss.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then
    raise exception 'Harvest idempotency key is required.' using errcode='22023';
  end if;
  if v_kind = 'harvest_amount' then
    if coalesce(v_halves,0) < 1 then
      raise exception 'Harvest amount must be at least one half bucket.' using errcode='22023';
    end if;
    if v_grade not in ('florist_grade','event_grade') then
      raise exception 'Usable flower harvest requires florist_grade or event_grade.' using errcode='22023';
    end if;
  else
    if v_halves is not null then
      raise exception 'Not ready, Deadheaded, and Crop loss do not take a harvest amount.' using errcode='22023';
    end if;
    if v_grade <> '' then
      raise exception 'Only usable harvested stems receive a harvest grade.' using errcode='22023';
    end if;
    v_grade := null;
  end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Weekly Harvest task not found.' using errcode='P0002'; end if;
  if v_task.status not in ('open','blocked') or v_task.task_type<>'harvest' or v_task.task_series_key<>'anna_harvest_thursday_weekly' then
    raise exception 'Weekly Harvest card is not open.' using errcode='22023';
  end if;

  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_task.farm_id then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  if p_effective_role not in ('owner','manager','farm_hand') then raise exception 'Harvest access denied.' using errcode='42501'; end if;
  if p_effective_role='farm_hand' and v_task.assigned_membership_id is distinct from p_effective_membership_id then
    raise exception 'Weekly Harvest is not assigned to this worker.' using errcode='42501';
  end if;

  select * into v_existing from atlas.weekly_harvest_task_results
  where farm_id=v_task.farm_id and idempotency_key=p_idempotency_key;
  if v_existing.id is null then
    select * into v_existing from atlas.weekly_harvest_task_results where task_id=v_task.id and crop_cycle_id=p_crop_cycle_id;
  end if;
  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','weekly_harvest_round_v3','deduplicated',true,
      'resultId',v_existing.id,'taskId',v_task.id,'cropCycleId',v_existing.crop_cycle_id,
      'resultKind',v_existing.result_kind,'harvestGrade',v_existing.harvest_grade,'bucketHalves',v_existing.bucket_halves
    );
  end if;

  select cc.* into v_cycle
  from atlas.weekly_harvest_candidate_cycles_v1(v_task.id) c
  join atlas.crop_cycles cc on cc.id=c.crop_cycle_id
  where c.crop_cycle_id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop is not on this weekly Harvest card.' using errcode='22023'; end if;

  select coalesce(cp.metadata->'use_tags','[]'::jsonb) ? 'cut_and_come_again'
  into v_cut_and_come_again
  from atlas.crop_profiles cp
  where cp.id=v_cycle.crop_profile_id;
  v_cut_and_come_again := coalesce(v_cut_and_come_again,false);

  if v_kind='crop_loss' and v_cut_and_come_again then
    raise exception 'This crop is classified cut-and-come-again; remove unusable blooms as Deadheaded, not Crop loss.' using errcode='22023';
  end if;

  insert into atlas.task_crop_cycles(task_id,crop_cycle_id,role,confidence,source,metadata)
  values(v_task.id,v_cycle.id,'harvests','confirmed','weekly_harvest_round_v3',jsonb_build_object('weeklyHarvestTaskId',v_task.id))
  on conflict(task_id,crop_cycle_id,role) do nothing;

  v_next_thursday := v_today + case when ((4-extract(isodow from v_today)::integer+7)%7)=0 then 7 else ((4-extract(isodow from v_today)::integer+7)%7) end;

  if v_kind='harvest_amount' then
    v_band := case when v_halves=1 then 'half' when v_halves=2 then 'one' else 'more_than_one' end;
    v_floor := v_halves::numeric/2;

    insert into atlas.flower_harvest_batches(
      farm_id,harvest_date,recorded_by_membership_id,batch_key,metadata,created_by_user_id
    ) values (
      v_task.farm_id,v_today,p_effective_membership_id,'weekly-harvest:'||v_task.id::text,
      jsonb_build_object('physicalOutputMode','half_bucket_counter','precision','half_bucket','weeklyHarvestTaskId',v_task.id),auth.uid()
    )
    on conflict(farm_id,batch_key) do update set updated_at=now()
    returning id into v_batch_id;

    insert into atlas.flower_harvest_bucket_observations(
      farm_id,batch_id,crop_cycle_id,task_id,recorded_by_membership_id,observed_date,
      bucket_band,bucket_equivalent_floor,bucket_halves,more_available,note,idempotency_key,
      created_by_user_id,metadata,harvest_grade
    ) values (
      v_task.farm_id,v_batch_id,v_cycle.id,v_task.id,p_effective_membership_id,v_today,
      v_band,v_floor,v_halves,null,null,p_idempotency_key,auth.uid(),
      jsonb_build_object(
        'physicalOutputMode','half_bucket_counter','precision','half_bucket','weeklyHarvestTaskId',v_task.id,
        'bucketHalves',v_halves,'bucketQuantity',v_floor,'quantityExactness','exact',
        'harvestGrade',v_grade,'flowerVocabularyVersion',1,'operatorMode',p_operator_mode
      ),v_grade
    ) returning * into v_observation;

    insert into atlas.crop_harvest_events(
      farm_id,crop_cycle_id,task_id,event_kind,outcome,observed_date,more_available,note,
      idempotency_key,created_by_user_id,metadata
    ) values (
      v_task.farm_id,v_cycle.id,v_task.id,'cut','harvested_amount',v_today,null,null,
      p_idempotency_key,auth.uid(),
      jsonb_build_object(
        'weeklyHarvestTaskId',v_task.id,'flowerHarvestBatchId',v_batch_id,
        'flowerHarvestObservationId',v_observation.id,'bucketHalves',v_halves,
        'bucketQuantity',v_floor,'quantityExactness','exact','physicalOutputMode','half_bucket_counter',
        'harvestGrade',v_grade,'flowerVocabularyVersion',1
      )
    ) returning * into v_event;

    update atlas.crop_cycles
    set harvest_started_date=coalesce(harvest_started_date,v_today),
        last_harvest_date=v_today,
        cycle_state='harvest_watch',
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'last_harvest_event_id',v_event.id,
          'last_flower_harvest_observation_id',v_observation.id,
          'last_harvest_bucket_halves',v_halves,
          'last_harvest_bucket_quantity',v_floor,
          'last_harvest_grade',v_grade,
          'flower_vocabulary_version',1,
          'physical_output_mode','half_bucket_counter'
        ),
        updated_at=now()
    where id=v_cycle.id;

    insert into atlas.crop_harvest_availability(
      crop_cycle_id,farm_id,status,observed_date,source_event_id,
      current_watch_task_id,current_watch_occurrence_id,current_harvest_task_id,current_harvest_occurrence_id,metadata
    ) values (
      v_cycle.id,v_task.farm_id,'watching',v_today,v_event.id,null,null,null,null,
      jsonb_build_object(
        'weeklyHarvestTaskId',v_task.id,'lastCutEventId',v_event.id,
        'bucketHalves',v_halves,'bucketQuantity',v_floor,'quantityExactness','exact',
        'harvestGrade',v_grade,'flowerVocabularyVersion',1,'physicalOutputMode','half_bucket_counter'
      )
    )
    on conflict(crop_cycle_id) do update
    set status=excluded.status,observed_date=excluded.observed_date,source_event_id=excluded.source_event_id,
        current_watch_task_id=null,current_watch_occurrence_id=null,current_harvest_task_id=null,current_harvest_occurrence_id=null,
        metadata=atlas.crop_harvest_availability.metadata||excluded.metadata,updated_at=now();
  else
    insert into atlas.crop_harvest_events(
      farm_id,crop_cycle_id,task_id,event_kind,outcome,observed_date,next_check_date,note,
      idempotency_key,created_by_user_id,metadata
    ) values (
      v_task.farm_id,v_cycle.id,v_task.id,'watch',v_kind,v_today,
      case when v_kind in ('not_ready','deadheaded') then v_next_thursday else null end,
      null,p_idempotency_key,auth.uid(),
      jsonb_build_object(
        'weeklyHarvestTaskId',v_task.id,
        'physicalObservationRecorded',true,
        'harvestInventoryCreated',false,
        'flowerVocabularyVersion',1,
        'operatorMode',p_operator_mode
      )
    ) returning * into v_event;

    update atlas.crop_cycles
    set cycle_state=case when v_kind='crop_loss' then 'finished_harvest' else 'harvest_watch' end,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'last_harvest_watch_action',v_kind,
          'last_harvest_watch_date',v_today,
          'weekly_harvest_task_id',v_task.id,
          'flower_vocabulary_version',1
        ),
        updated_at=now()
    where id=v_cycle.id;

    insert into atlas.crop_harvest_availability(
      crop_cycle_id,farm_id,status,observed_date,source_event_id,
      current_watch_task_id,current_watch_occurrence_id,current_harvest_task_id,current_harvest_occurrence_id,metadata
    ) values (
      v_cycle.id,v_task.farm_id,case when v_kind='crop_loss' then 'finished' else 'watching' end,
      v_today,v_event.id,null,null,null,null,
      jsonb_build_object(
        'weeklyHarvestTaskId',v_task.id,'lastAction',v_kind,
        'harvestInventoryCreated',false,'flowerVocabularyVersion',1
      )
    )
    on conflict(crop_cycle_id) do update
    set status=excluded.status,observed_date=excluded.observed_date,source_event_id=excluded.source_event_id,
        current_watch_task_id=null,current_watch_occurrence_id=null,current_harvest_task_id=null,current_harvest_occurrence_id=null,
        metadata=atlas.crop_harvest_availability.metadata||excluded.metadata,updated_at=now();
  end if;

  insert into atlas.weekly_harvest_task_results(
    farm_id,task_id,crop_cycle_id,result_kind,harvest_grade,bucket_halves,bucket_band,more_availability,note,
    crop_harvest_event_id,flower_harvest_observation_id,resolved_by_membership_id,idempotency_key,metadata
  ) values (
    v_task.farm_id,v_task.id,v_cycle.id,v_kind,v_grade,
    case when v_kind='harvest_amount' then v_halves else null end,
    null,null,null,v_event.id,v_observation.id,p_effective_membership_id,p_idempotency_key,
    jsonb_build_object('operatorMode',p_operator_mode,'contractVersion','weekly_harvest_round_v3','flowerVocabularyVersion',1)
  ) returning * into v_result;

  perform atlas.reconcile_crop_cycle_requirement_state_v1(v_cycle.id);

  select count(*)::integer into v_unresolved
  from atlas.weekly_harvest_candidate_cycles_v1(v_task.id) c
  left join atlas.weekly_harvest_task_results r on r.task_id=v_task.id and r.crop_cycle_id=c.crop_cycle_id
  where r.id is null;

  if v_unresolved=0 and exists(select 1 from atlas.weekly_harvest_task_results where task_id=v_task.id) then
    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'done','weekly-harvest:auto:v3:'||v_task.id::text,null,
      'Every crop on this week''s Harvest card was physically resolved.',null,'harvest','weekly_harvest_round',
      jsonb_build_object('completion_source','weekly_harvest_crop_results_v3','last_result_id',v_result.id),null
    );
    begin v_season_end:=nullif(v_task.metadata->>'season_end','')::date; exception when others then v_season_end:=date '2026-11-12'; end;
    v_season_end:=coalesce(v_season_end,date '2026-11-12');
    if v_task.due_date is not null and v_task.due_date+7<=v_season_end then
      v_next:=atlas.ensure_weekly_harvest_card_v1(v_task.farm_id,v_task.due_date+7);
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','weekly_harvest_round_v3','deduplicated',false,
    'resultId',v_result.id,'taskId',v_task.id,'cropCycleId',v_cycle.id,
    'resultKind',v_kind,'harvestGrade',v_grade,
    'bucketHalves',case when v_kind='harvest_amount' then v_halves else null end,
    'bucketQuantity',case when v_kind='harvest_amount' then v_floor else null end,
    'harvestInventoryCreated',v_kind='harvest_amount',
    'remainingRows',v_unresolved,'taskCompleted',v_transition is not null,'nextWeeklyCard',v_next
  );
end;
$function$;

create or replace function atlas.record_weekly_harvest_row_for_member_v3(
  p_farm_id uuid,
  p_task_id uuid,
  p_crop_cycle_id uuid,
  p_result_kind text,
  p_harvest_grade text,
  p_bucket_halves integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_role text;
  v_membership uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is null or v_membership is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;
  return atlas.record_weekly_harvest_row_core_v3(
    p_task_id,p_crop_cycle_id,v_membership,v_role,p_result_kind,p_harvest_grade,p_bucket_halves,p_idempotency_key,false
  );
end;
$function$;

revoke all on function atlas.record_weekly_harvest_row_core_v3(uuid,uuid,uuid,text,text,text,integer,text,boolean) from public;
revoke all on function atlas.record_weekly_harvest_row_for_member_v3(uuid,uuid,uuid,text,text,integer,text) from public;
grant execute on function atlas.record_weekly_harvest_row_for_member_v3(uuid,uuid,uuid,text,text,integer,text) to authenticated;
grant execute on function atlas.record_weekly_harvest_row_core_v3(uuid,uuid,uuid,text,text,text,integer,text,boolean) to service_role;
grant execute on function atlas.record_weekly_harvest_row_for_member_v3(uuid,uuid,uuid,text,text,integer,text) to service_role;

COMMIT;
