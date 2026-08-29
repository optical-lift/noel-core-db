create or replace function atlas.reconcile_production_work_v1(p_production_lot_id uuid,p_as_of_date date default null) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_prop jsonb;
  v_down jsonb;
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

  return jsonb_build_object(
    'productionLotId',p_production_lot_id,
    'authority','production_reconciler',
    'currentStage',coalesce(v_down->>'currentStage',v_prop->>'currentStage',v_stage),
    'work',coalesce(v_prop->'work','[]'::jsonb)||coalesce(v_down->'work','[]'::jsonb),
    'transplantGate',v_down->'transplantGate',
    'harvestGate',v_down->'harvestGate'
  );
end;
$function$;
revoke all on function atlas.reconcile_production_work_v1(uuid,date) from public,anon,authenticated;
grant execute on function atlas.reconcile_production_work_v1(uuid,date) to postgres,service_role;