-- Atlas worker flower quick-log provenance v1
-- Reuse the canonical Harvest workbench writers while preserving the surface that observed the work.

create or replace function atlas.record_flower_harvest_worker_quick_log_v1(
  p_farm_id uuid,
  p_rows jsonb,
  p_note text,
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
  v_result jsonb;
  v_task_id uuid;
  v_batch_id uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is distinct from 'farm_hand' or v_membership is null then
    raise exception 'Farm Hand membership is required for worker flower quick logging.' using errcode='42501';
  end if;

  v_result:=atlas.record_flower_harvest_workbench_for_member_v1(
    p_farm_id,p_rows,p_note,p_idempotency_key
  );
  begin v_task_id:=nullif(v_result->>'taskId','')::uuid; exception when others then v_task_id:=null; end;
  begin v_batch_id:=nullif(v_result->>'harvestBatchId','')::uuid; exception when others then v_batch_id:=null; end;

  if v_task_id is not null then
    update atlas.tasks
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'workbenchSource','worker_day',
      'workerQuickLog',true,
      'workerQuickLogMembershipId',v_membership
    )
    where id=v_task_id and farm_id=p_farm_id and assigned_membership_id=v_membership;
  end if;

  if v_batch_id is not null then
    update atlas.flower_harvest_batches
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'entrySurface','worker_day',
      'workerQuickLog',true,
      'workerQuickLogMembershipId',v_membership
    )
    where id=v_batch_id and farm_id=p_farm_id and recorded_by_membership_id=v_membership;

    update atlas.flower_harvest_bucket_observations
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'entrySurface','worker_day',
      'workerQuickLog',true,
      'workerQuickLogMembershipId',v_membership
    )
    where batch_id=v_batch_id and farm_id=p_farm_id and recorded_by_membership_id=v_membership;
  end if;

  return v_result||jsonb_build_object(
    'contractVersion','worker_flower_harvest_quick_log_v1',
    'entrySurface','worker_day'
  );
end;
$function$;

create or replace function atlas.record_flower_preparation_worker_quick_log_v1(
  p_farm_id uuid,
  p_harvest_batch_id uuid,
  p_outputs jsonb,
  p_note text,
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
  v_result jsonb;
  v_task_id uuid;
  v_prep_id uuid;
begin
  v_role:=atlas.current_farm_role(p_farm_id);
  v_membership:=atlas.current_membership_id(p_farm_id);
  if auth.uid() is null or v_role is distinct from 'farm_hand' or v_membership is null then
    raise exception 'Farm Hand membership is required for worker flower quick logging.' using errcode='42501';
  end if;

  v_result:=atlas.record_flower_preparation_workbench_for_member_v1(
    p_farm_id,p_harvest_batch_id,p_outputs,p_note,p_idempotency_key
  );
  begin v_task_id:=nullif(v_result->>'taskId','')::uuid; exception when others then v_task_id:=null; end;
  begin v_prep_id:=nullif(v_result->>'preparationBatchId','')::uuid; exception when others then v_prep_id:=null; end;

  if v_task_id is not null then
    update atlas.tasks
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'workbenchSource','worker_day',
      'workerQuickLog',true,
      'workerQuickLogMembershipId',v_membership
    )
    where id=v_task_id and farm_id=p_farm_id and assigned_membership_id=v_membership;
  end if;

  if v_prep_id is not null then
    update atlas.flower_preparation_batches
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'entrySurface','worker_day',
      'workerQuickLog',true,
      'workerQuickLogMembershipId',v_membership
    )
    where id=v_prep_id and farm_id=p_farm_id and recorded_by_membership_id=v_membership;

    update atlas.flower_ready_inventory_lots
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'entrySurface','worker_day',
      'workerQuickLog',true,
      'workerQuickLogMembershipId',v_membership
    )
    where preparation_batch_id=v_prep_id and farm_id=p_farm_id;
  end if;

  return v_result||jsonb_build_object(
    'contractVersion','worker_flower_preparation_quick_log_v1',
    'entrySurface','worker_day'
  );
end;
$function$;

revoke all on function atlas.record_flower_harvest_worker_quick_log_v1(uuid,jsonb,text,text) from public,anon,authenticated,service_role;
revoke all on function atlas.record_flower_preparation_worker_quick_log_v1(uuid,uuid,jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function atlas.record_flower_harvest_worker_quick_log_v1(uuid,jsonb,text,text) to authenticated,service_role;
grant execute on function atlas.record_flower_preparation_worker_quick_log_v1(uuid,uuid,jsonb,text,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,
  security_definer_expected,service_execute_expected,caller_count,policy_reference_count,
  evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.record_flower_harvest_worker_quick_log_v1(uuid, jsonb, text, text)',
  'app_endpoint','verified','active',true,true,true,1,0,
  jsonb_build_object(
    'source','atlas_worker_flower_quick_log_v1',
    'scope','current_farm_hand_only',
    'purpose','Record extra physical flower harvest from Worker Day through the canonical Harvest workbench writer while preserving worker_day provenance.'
  ),now(),false
),
(
  'atlas.record_flower_preparation_worker_quick_log_v1(uuid, uuid, jsonb, text, text)',
  'app_endpoint','verified','active',true,true,true,1,0,
  jsonb_build_object(
    'source','atlas_worker_flower_quick_log_v1',
    'scope','current_farm_hand_only',
    'purpose','Record extra finished flower preparation from Worker Day through the canonical preparation workbench writer while preserving worker_day provenance.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

comment on function atlas.record_flower_harvest_worker_quick_log_v1(uuid,jsonb,text,text) is 'Farm Hand-only quick-log surface for extra harvest work. Canonical harvest writer remains authoritative; this wrapper records worker_day provenance atomically.';
comment on function atlas.record_flower_preparation_worker_quick_log_v1(uuid,uuid,jsonb,text,text) is 'Farm Hand-only quick-log surface for extra post-harvest preparation. Canonical preparation writer remains authoritative; this wrapper records worker_day provenance atomically.';
