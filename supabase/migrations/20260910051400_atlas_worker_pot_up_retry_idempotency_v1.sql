begin;

-- If the domain transition committed but the client lost the response, a retry
-- against the same Worker Day projection returns the durable accepted result
-- instead of failing because Company Work and the execution task are now closed.
do $repair$
declare
  v_oid oid;
  v_def text;
  v_old text:=$needle$  select * into v_work from atlas.work_items w where w.id=v_work_ids[1] and w.organization_id=(v_context->>'organizationId')::uuid and w.organization_unit_id=(v_context->>'organizationUnitId')::uuid and w.work_state='open' and w.result_contract_key='production_pot_up_v1'; if v_work.id is null then raise exception 'This Worker Day item is not open governed production pot-up work.' using errcode='23514'; end if;$needle$;
  v_new text:=$needle$  select * into v_result from atlas.work_execution_results r where r.work_item_id=v_work_ids[1] and r.organization_id=(v_context->>'organizationId')::uuid and r.result_contract_key='production_pot_up_v1' and r.result_kind='completed' order by r.reported_at desc,r.id desc limit 1;
  if v_result.id is not null then
    select * into v_acceptance from atlas.work_result_acceptances a where a.execution_result_id=v_result.id and a.decision='accepted';
    if v_acceptance.id is not null then
      return jsonb_build_object('ok',true,'status','pot_up_completed','deduplicated',true,'projectionId',p_projection_id,'workItemId',v_result.work_item_id,'taskId',v_result.task_id,'executionResultId',v_result.id,'acceptanceKind',v_acceptance.acceptance_kind);
    end if;
  end if;
  select * into v_work from atlas.work_items w where w.id=v_work_ids[1] and w.organization_id=(v_context->>'organizationId')::uuid and w.organization_unit_id=(v_context->>'organizationUnitId')::uuid and w.work_state='open' and w.result_contract_key='production_pot_up_v1'; if v_work.id is null then raise exception 'This Worker Day item is not open governed production pot-up work.' using errcode='23514'; end if;$needle$;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas'
    and p.proname='worker_record_production_pot_up_self_api_v1'
    and pg_get_function_identity_arguments(p.oid)='p_delivery_membership_id uuid, p_projection_id uuid, p_outputs jsonb, p_care_date date, p_note text, p_idempotency_key text';

  if v_oid is null then raise exception 'worker_record_production_pot_up_self_api_v1 signature not found.'; end if;
  v_def:=pg_get_functiondef(v_oid);
  if position(v_old in v_def)=0 then raise exception 'Expected open-work clause not found; refusing retry patch.'; end if;
  execute replace(v_def,v_old,v_new);
end;
$repair$;

commit;
