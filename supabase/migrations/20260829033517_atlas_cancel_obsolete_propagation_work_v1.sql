create or replace function atlas.cancel_obsolete_production_propagation_work_v1(p_production_lot_id uuid) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_keep_id uuid;
  v_current_task_id uuid;
  v_cancelled integer:=0;
begin
  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  if v_lot.id is null then return jsonb_build_object('cancelled',0); end if;
  if v_lot.current_stage not in ('germination_pending','reseed_decision','seedling_care','hardening','seedling_failure_decision') then
    return jsonb_build_object('cancelled',0,'skipped',true);
  end if;
  begin v_keep_id:=nullif(v_lot.metadata->>'next_action_occurrence_id','')::uuid; exception when others then v_keep_id:=null; end;
  select task_id into v_current_task_id from atlas.production_lot_events where production_lot_id=v_lot.id order by event_date desc,created_at desc limit 1;

  with candidates as (
    select pwo.id
    from atlas.planned_work_occurrences pwo
    join atlas.work_definitions wd on wd.id=pwo.work_definition_id
    where pwo.farm_id=v_lot.farm_id
      and pwo.state not in ('completed','cancelled')
      and pwo.id is distinct from v_keep_id
      and pwo.released_task_id is distinct from v_current_task_id
      and coalesce(pwo.task_payload->'metadata'->>'production_lot_id',pwo.metadata->>'production_lot_id')=v_lot.id::text
      and (
        coalesce(pwo.metadata->>'production_work_key','') in ('germination','seedling-care','owner-reseed-decision','owner-lifecycle-gap','owner-pot-up-method','pot-up','hardening','transplant-readiness','owner-seedling-recovery')
        or wd.stable_key in ('production:germination:v1','production:seedling-care:v1','production:owner-reseed-decision:v1','production:owner-lifecycle-gap:v1','production:owner-pot-up-method:v1','production:pot-up:v1','production:hardening:v1','production:transplant-readiness:v1','production:owner-seedling-recovery:v1')
      )
  ), updated as (
    update atlas.planned_work_occurrences pwo
    set state='cancelled',
        metadata=coalesce(pwo.metadata,'{}'::jsonb)||jsonb_build_object('cancelled_by','production_reconciler','cancelled_reason','derived_next_state_changed','cancelled_at',now()),
        updated_at=now()
    from candidates c where pwo.id=c.id
    returning pwo.id
  ) select count(*) into v_cancelled from updated;

  return jsonb_build_object('cancelled',v_cancelled,'keptOccurrenceId',v_keep_id,'currentTaskId',v_current_task_id);
end;
$function$;
revoke all on function atlas.cancel_obsolete_production_propagation_work_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.cancel_obsolete_production_propagation_work_v1(uuid) to postgres;

create or replace function atlas.reconcile_production_work_v1(p_production_lot_id uuid,p_as_of_date date default null) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_prop jsonb;
  v_down jsonb;
  v_cleanup jsonb;
  v_stage text;
begin
  if p_production_lot_id is null then raise exception 'Production lot is required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('atlas.production.reconcile:entry:'||p_production_lot_id::text,0));
  select current_stage into v_stage from atlas.production_lots where id=p_production_lot_id;
  if v_stage is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;

  v_prop:=atlas.reconcile_production_propagation_work_v1(p_production_lot_id,p_as_of_date);
  if v_stage in ('germination_pending','reseed_decision','seedling_care') then
    v_down:=jsonb_build_object('currentStage',v_stage,'work','[]'::jsonb,'transplantGate',null,'harvestGate',null);
  else
    v_down:=atlas.reconcile_production_work_downstream_v1(p_production_lot_id,p_as_of_date);
  end if;
  v_cleanup:=atlas.cancel_obsolete_production_propagation_work_v1(p_production_lot_id);

  return jsonb_build_object(
    'productionLotId',p_production_lot_id,
    'authority','production_reconciler',
    'currentStage',coalesce(v_down->>'currentStage',v_prop->>'currentStage',v_stage),
    'work',coalesce(v_prop->'work','[]'::jsonb)||coalesce(v_down->'work','[]'::jsonb),
    'transplantGate',v_down->'transplantGate',
    'harvestGate',v_down->'harvestGate',
    'cleanup',v_cleanup
  );
end;
$function$;
revoke all on function atlas.reconcile_production_work_v1(uuid,date) from public,anon,authenticated;
grant execute on function atlas.reconcile_production_work_v1(uuid,date) to postgres,service_role;