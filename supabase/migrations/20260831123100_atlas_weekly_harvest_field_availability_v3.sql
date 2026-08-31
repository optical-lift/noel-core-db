-- Atlas Weekly Harvest field availability v3
--
-- Restores one piece of field truth without reviving the legacy lifecycle inference:
--   "More still out there?" = yes / unsure / no is an observation made at this cut.
--   "no" MUST NOT mean crop_exhausted or finished_harvest.
--
-- Physical harvest observations and crop harvest events are append-only. Therefore v3
-- writes availability correctly at INSERT time; it never patches evidence after the fact.

begin;

-- v2 required more_availability to remain NULL. Keep legacy rows valid while making
-- explicit availability mandatory for every new v3 harvest_amount result.
alter table atlas.weekly_harvest_task_results
  drop constraint if exists weekly_harvest_task_results_v2_shape_check;

alter table atlas.weekly_harvest_task_results
  drop constraint if exists weekly_harvest_task_results_v3_shape_check;

alter table atlas.weekly_harvest_task_results
  add constraint weekly_harvest_task_results_v3_shape_check
  check (
    (
      result_kind = 'harvest_amount'
      and bucket_halves is not null
      and bucket_halves >= 1
      and bucket_band is null
      and (
        more_availability in ('yes','no','unsure')
        or (
          more_availability is null
          and coalesce(metadata->>'contractVersion','') <> 'weekly_harvest_round_v3'
        )
      )
    )
    or (
      result_kind in ('food_picked','not_ready','deadheaded','crop_exhausted')
      and bucket_halves is null
      and bucket_band is null
      and more_availability is null
    )
  );

comment on constraint weekly_harvest_task_results_v3_shape_check on atlas.weekly_harvest_task_results is
  'v3 harvest_amount writes require explicit yes/unsure/no field availability. Legacy pre-v3 rows may remain unknown. Exceptions do not take an availability answer.';

-- Clone the proven v2 state machine into v3, changing only the truth contract and the
-- three initial evidence/result inserts. Guard every expected source-shape seam so a
-- future v2 change aborts this migration instead of creating a malformed recorder.
do $migration$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(
    'atlas.record_weekly_harvest_row_core_v2(uuid,uuid,uuid,text,text,integer,text,boolean)'::regprocedure
  ) into v_def;

  if strpos(v_def,
    'CREATE OR REPLACE FUNCTION atlas.record_weekly_harvest_row_core_v2(p_task_id uuid, p_crop_cycle_id uuid, p_effective_membership_id uuid, p_effective_role text, p_result_kind text, p_bucket_halves integer, p_idempotency_key text, p_operator_mode boolean DEFAULT false)'
  ) = 0
  or strpos(v_def,'v_halves integer:=p_bucket_halves;') = 0
  or strpos(v_def,'if nullif(btrim(coalesce(p_idempotency_key,'''')),'''') is null then') = 0
  or strpos(v_def,'v_band,v_floor,v_halves,null,null,p_idempotency_key') = 0
  or strpos(v_def,'v_task.farm_id,v_cycle.id,v_task.id,''cut'',''harvested_amount'',v_today,null,null,') = 0
  or strpos(v_def,'null,null,null,v_event.id,v_observation.id') = 0
  or strpos(v_def,'''resultKind'',v_existing.result_kind,''bucketHalves'',v_existing.bucket_halves') = 0
  or strpos(v_def,'''resultKind'',v_kind,''bucketHalves'',case when v_kind=''harvest_amount'' then v_halves else null end') = 0 then
    raise exception 'Weekly Harvest v2 source shape no longer matches the guarded v3 derivation seams.';
  end if;

  v_next := replace(
    v_def,
    'CREATE OR REPLACE FUNCTION atlas.record_weekly_harvest_row_core_v2(p_task_id uuid, p_crop_cycle_id uuid, p_effective_membership_id uuid, p_effective_role text, p_result_kind text, p_bucket_halves integer, p_idempotency_key text, p_operator_mode boolean DEFAULT false)',
    'CREATE OR REPLACE FUNCTION atlas.record_weekly_harvest_row_core_v3(p_task_id uuid, p_crop_cycle_id uuid, p_effective_membership_id uuid, p_effective_role text, p_result_kind text, p_bucket_halves integer, p_more_availability text, p_idempotency_key text, p_operator_mode boolean DEFAULT false)'
  );

  v_next := replace(
    v_next,
    'v_halves integer:=p_bucket_halves;',
    $new$v_halves integer:=p_bucket_halves;
  v_more text:=lower(btrim(coalesce(p_more_availability,'')));
  v_more_bool boolean;$new$
  );

  v_next := replace(
    v_next,
    $old$if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then$old$,
    $new$if v_kind='harvest_amount' then
    if v_more not in ('yes','unsure','no') then
      raise exception 'Choose Yes, Not sure, or No for more still out there.' using errcode='22023';
    end if;
    v_more_bool:=case v_more when 'yes' then true when 'no' then false else null end;
  elsif nullif(v_more,'') is not null then
    raise exception 'Field availability belongs only to a recorded harvest amount.' using errcode='22023';
  else
    v_more_bool:=null;
  end if;

  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then$new$
  );

  v_next := replace(
    v_next,
    'if v_existing.id is not null then',
    $new$if v_existing.id is not null then
    if v_existing.crop_cycle_id is distinct from p_crop_cycle_id
       or v_existing.result_kind is distinct from v_kind
       or (v_kind='harvest_amount' and v_existing.bucket_halves is distinct from v_halves) then
      raise exception 'Harvest idempotency/result conflict: the crop result is already resolved differently.' using errcode='23505';
    end if;
    if v_kind='harvest_amount'
       and v_existing.more_availability is not null
       and v_existing.more_availability is distinct from v_more then
      raise exception 'Harvest idempotency/result conflict: field availability is already recorded differently.' using errcode='23505';
    end if;$new$
  );

  v_next := replace(
    v_next,
    'v_band,v_floor,v_halves,null,null,p_idempotency_key',
    'v_band,v_floor,v_halves,v_more_bool,null,p_idempotency_key'
  );

  v_next := replace(
    v_next,
    'v_task.farm_id,v_cycle.id,v_task.id,''cut'',''harvested_amount'',v_today,null,null,',
    'v_task.farm_id,v_cycle.id,v_task.id,''cut'',''harvested_amount'',v_today,v_more_bool,null,'
  );

  v_next := replace(
    v_next,
    'null,null,null,v_event.id,v_observation.id',
    'null,case when v_kind=''harvest_amount'' then v_more else null end,null,v_event.id,v_observation.id'
  );

  v_next := replace(
    v_next,
    '''resultKind'',v_existing.result_kind,''bucketHalves'',v_existing.bucket_halves',
    '''resultKind'',v_existing.result_kind,''moreAvailability'',v_existing.more_availability,''moreAvailabilityKnown'',case when v_existing.result_kind=''harvest_amount'' then v_existing.more_availability is not null else true end,''bucketHalves'',v_existing.bucket_halves'
  );

  v_next := replace(
    v_next,
    '''resultKind'',v_kind,''bucketHalves'',case when v_kind=''harvest_amount'' then v_halves else null end',
    '''resultKind'',v_kind,''moreAvailability'',case when v_kind=''harvest_amount'' then v_more else null end,''moreAvailabilityKnown'',true,''bucketHalves'',case when v_kind=''harvest_amount'' then v_halves else null end'
  );

  v_next := replace(
    v_next,
    '''operatorMode'',p_operator_mode',
    '''operatorMode'',p_operator_mode,''moreAvailability'',case when v_kind=''harvest_amount'' then v_more else null end'
  );

  v_next := replace(
    v_next,
    '''weekly_harvest_round_v2''',
    '''weekly_harvest_round_v3'''
  );

  if v_next = v_def
     or strpos(v_next,'record_weekly_harvest_row_core_v3') = 0
     or strpos(v_next,'p_more_availability text') = 0
     or strpos(v_next,'v_band,v_floor,v_halves,v_more_bool,null,p_idempotency_key') = 0
     or strpos(v_next,'v_task.farm_id,v_cycle.id,v_task.id,''cut'',''harvested_amount'',v_today,v_more_bool,null,') = 0
     or strpos(v_next,'null,case when v_kind=''harvest_amount'' then v_more else null end,null,v_event.id,v_observation.id') = 0
     or strpos(v_next,'''weekly_harvest_round_v2''') > 0 then
    raise exception 'Weekly Harvest v3 derivation did not produce the required guarded changes.';
  end if;

  execute v_next;
end;
$migration$;

comment on function atlas.record_weekly_harvest_row_core_v3(uuid,uuid,uuid,text,text,integer,text,text,boolean) is
  'Weekly Harvest v3 recorder. Exact half-bucket output and explicit yes/unsure/no field availability are written atomically into append-only evidence. Availability no does not mean crop exhausted.';

revoke all on function atlas.record_weekly_harvest_row_core_v3(uuid,uuid,uuid,text,text,integer,text,text,boolean) from public, anon, authenticated;
grant execute on function atlas.record_weekly_harvest_row_core_v3(uuid,uuid,uuid,text,text,integer,text,text,boolean) to service_role;

-- Derive authenticated wrappers from the proven v2 authorization membranes, adding
-- only the explicit availability argument and routing into core v3.
do $wrappers$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(
    'atlas.record_weekly_harvest_row_for_member_v2(uuid,uuid,uuid,text,integer,text)'::regprocedure
  ) into v_def;

  if strpos(v_def,'p_bucket_halves integer, p_idempotency_key text') = 0
     or strpos(v_def,'p_result_kind,p_bucket_halves,p_idempotency_key,false') = 0
     or strpos(v_def,'record_weekly_harvest_row_core_v2') = 0 then
    raise exception 'Member weekly Harvest v2 wrapper shape changed.';
  end if;

  v_next := replace(v_def,'record_weekly_harvest_row_for_member_v2','record_weekly_harvest_row_for_member_v3');
  v_next := replace(v_next,'p_bucket_halves integer, p_idempotency_key text','p_bucket_halves integer, p_more_availability text, p_idempotency_key text');
  v_next := replace(v_next,'record_weekly_harvest_row_core_v2','record_weekly_harvest_row_core_v3');
  v_next := replace(v_next,'p_result_kind,p_bucket_halves,p_idempotency_key,false','p_result_kind,p_bucket_halves,p_more_availability,p_idempotency_key,false');
  execute v_next;

  select pg_get_functiondef(
    'atlas.owner_operator_record_weekly_harvest_row_v2(uuid,uuid,uuid,text,integer,text)'::regprocedure
  ) into v_def;

  if strpos(v_def,'p_bucket_halves integer, p_idempotency_key text') = 0
     or strpos(v_def,'p_result_kind,p_bucket_halves,p_idempotency_key,true') = 0
     or strpos(v_def,'record_weekly_harvest_row_core_v2') = 0 then
    raise exception 'Owner-operator weekly Harvest v2 wrapper shape changed.';
  end if;

  v_next := replace(v_def,'owner_operator_record_weekly_harvest_row_v2','owner_operator_record_weekly_harvest_row_v3');
  v_next := replace(v_next,'p_bucket_halves integer, p_idempotency_key text','p_bucket_halves integer, p_more_availability text, p_idempotency_key text');
  v_next := replace(v_next,'record_weekly_harvest_row_core_v2','record_weekly_harvest_row_core_v3');
  v_next := replace(v_next,'p_result_kind,p_bucket_halves,p_idempotency_key,true','p_result_kind,p_bucket_halves,p_more_availability,p_idempotency_key,true');
  execute v_next;
end;
$wrappers$;

revoke all on function atlas.record_weekly_harvest_row_for_member_v3(uuid,uuid,uuid,text,integer,text,text) from public, anon;
grant execute on function atlas.record_weekly_harvest_row_for_member_v3(uuid,uuid,uuid,text,integer,text,text) to authenticated, service_role;

revoke all on function atlas.owner_operator_record_weekly_harvest_row_v3(uuid,uuid,uuid,text,integer,text,text) from public, anon;
grant execute on function atlas.owner_operator_record_weekly_harvest_row_v3(uuid,uuid,uuid,text,integer,text,text) to authenticated, service_role;

-- Augment the proven state reader instead of rebuilding its candidate-row logic.
create or replace function atlas.weekly_harvest_task_state_core_v2(
  p_task_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_state jsonb;
  v_rows jsonb;
begin
  v_state := atlas.weekly_harvest_task_state_core_v1(
    p_task_id,
    p_effective_membership_id,
    p_effective_role,
    p_operator_mode
  );

  select coalesce(
    jsonb_agg(
      e.row_value || jsonb_build_object(
        'moreAvailability',r.more_availability,
        'moreAvailabilityApplicable',case when r.id is null then null else r.result_kind='harvest_amount' end,
        'moreAvailabilityKnown',case
          when r.id is null then null
          when r.result_kind<>'harvest_amount' then true
          else r.more_availability is not null
        end
      )
      order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_rows
  from jsonb_array_elements(coalesce(v_state->'rows','[]'::jsonb)) with ordinality as e(row_value,ordinality)
  left join atlas.weekly_harvest_task_results r
    on r.task_id = p_task_id
   and r.crop_cycle_id = (e.row_value->>'cropCycleId')::uuid;

  v_state := jsonb_set(v_state,'{rows}',v_rows,true);
  v_state := jsonb_set(v_state,'{contractVersion}',to_jsonb('weekly_harvest_round_v3'::text),true);
  v_state := jsonb_set(
    v_state,
    '{truthBoundary}',
    coalesce(v_state->'truthBoundary','{}'::jsonb) || jsonb_build_object(
      'fieldAvailabilityRequiredForHarvestAmount',true,
      'fieldAvailabilityChoices',jsonb_build_array('yes','unsure','no'),
      'availabilityNoDoesNotMeanCropExhausted',true,
      'cropExhaustedRemainsExplicitException',true,
      'appendOnlyHarvestEvidence',true
    ),
    true
  );

  return v_state;
end;
$function$;

comment on function atlas.weekly_harvest_task_state_core_v2(uuid,uuid,text,boolean) is
  'Weekly Harvest state v3 projection: proven candidate-row truth plus explicit field-availability evidence and the no-is-not-exhausted boundary.';

revoke all on function atlas.weekly_harvest_task_state_core_v2(uuid,uuid,text,boolean) from public, anon, authenticated;
grant execute on function atlas.weekly_harvest_task_state_core_v2(uuid,uuid,text,boolean) to service_role;

-- Reuse the existing authorization wrappers for state reads; change only the target core.
do $state_wrappers$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(
    'atlas.weekly_harvest_task_state_for_member_v1(uuid,uuid)'::regprocedure
  ) into v_def;
  if strpos(v_def,'weekly_harvest_task_state_core_v1') = 0 then
    raise exception 'Member weekly Harvest state wrapper shape changed.';
  end if;
  v_next := replace(v_def,'weekly_harvest_task_state_for_member_v1','weekly_harvest_task_state_for_member_v2');
  v_next := replace(v_next,'weekly_harvest_task_state_core_v1','weekly_harvest_task_state_core_v2');
  execute v_next;

  select pg_get_functiondef(
    'atlas.owner_operator_weekly_harvest_task_state_v1(uuid,uuid)'::regprocedure
  ) into v_def;
  if strpos(v_def,'weekly_harvest_task_state_core_v1') = 0 then
    raise exception 'Owner-operator weekly Harvest state wrapper shape changed.';
  end if;
  v_next := replace(v_def,'owner_operator_weekly_harvest_task_state_v1','owner_operator_weekly_harvest_task_state_v2');
  v_next := replace(v_next,'weekly_harvest_task_state_core_v1','weekly_harvest_task_state_core_v2');
  execute v_next;
end;
$state_wrappers$;

revoke all on function atlas.weekly_harvest_task_state_for_member_v2(uuid,uuid) from public, anon;
grant execute on function atlas.weekly_harvest_task_state_for_member_v2(uuid,uuid) to authenticated, service_role;

revoke all on function atlas.owner_operator_weekly_harvest_task_state_v2(uuid,uuid) from public, anon;
grant execute on function atlas.owner_operator_weekly_harvest_task_state_v2(uuid,uuid) to authenticated, service_role;

-- Company Work now advertises the same result contract its execution adapter will use.
update atlas.work_items
set result_contract_key = 'weekly_harvest_round_v3',
    metadata = metadata || jsonb_build_object(
      'resultContract','weekly_harvest_round_v3',
      'fieldAvailabilityRequired',true,
      'availabilityNoMeansCropExhausted',false
    ),
    updated_at = now()
where stable_key like 'weekly_harvest:%'
  and work_state = 'open';

-- Static safety assertions over the derived v3 contract.
do $verify$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'atlas.record_weekly_harvest_row_core_v3(uuid,uuid,uuid,text,text,integer,text,text,boolean)'::regprocedure
  ) into v_def;

  if strpos(v_def,'v_band,v_floor,v_halves,v_more_bool,null,p_idempotency_key') = 0
     or strpos(v_def,'v_task.farm_id,v_cycle.id,v_task.id,''cut'',''harvested_amount'',v_today,v_more_bool,null,') = 0
     or strpos(v_def,'weekly_harvest_round_v3') = 0
     or strpos(v_def,'cycle_state=case when v_kind=''crop_exhausted'' then ''finished_harvest'' else ''harvest_watch'' end') = 0 then
    raise exception 'Weekly Harvest v3 lost an evidence or lifecycle boundary.';
  end if;

  if strpos(v_def,'v_kind=''harvest_amount'' then ''finished_harvest''') > 0
     or strpos(v_def,'v_more=''no'' then ''finished_harvest''') > 0 then
    raise exception 'Field availability No was incorrectly promoted to crop exhaustion.';
  end if;
end;
$verify$;

commit;
