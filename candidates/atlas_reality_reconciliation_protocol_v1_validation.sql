begin;

do $validation$
declare
  v_value jsonb;
  v_exec jsonb;
  v_def text;
  v_before_acceptances integer;
  v_after_acceptances integer;
  v_before_payment_events integer;
  v_after_payment_events integer;
  v_dep_satisfied integer;
begin
  -- Schema normalizer fails closed and universal truth boundaries cannot be
  -- weakened by caller-supplied metadata.
  begin
    perform atlas.reality_reconciliation_plan_normalize_v1(
      '{"source":{},"targets":[]}'::jsonb
    );
    raise exception 'Reconciliation normalizer accepted incomplete source identity.';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform atlas.reality_reconciliation_plan_normalize_v1(
      '{
        "source":{"domain":"x","kind":"y","ref":"z"},
        "targets":[{
          "target":{"domain":"a","kind":"b","ref":"c"},
          "resolver":{"key":"r"},
          "handlingMode":"authority_required",
          "reason":{"kind":"q"},
          "automation":{"eligible":true,"adapterKey":"forbidden"}
        }]
      }'::jsonb
    );
    raise exception 'Non-automatic reconciliation was allowed to advertise automation.';
  exception when sqlstate '22023' then null;
  end;

  v_value:=atlas.reality_reconciliation_plan_normalize_v1(
    '{
      "source":{"domain":"validation","kind":"source","ref":"truth-boundary"},
      "targets":[],
      "truthBoundary":{
        "readOnly":false,
        "doesNotExecute":false,
        "doesNotGrantAuthority":false,
        "doesNotCreateEvidence":false,
        "doesNotDetermineOutcome":false,
        "callerNote":"preserved"
      }
    }'::jsonb
  );

  if coalesce((v_value#>>'{truthBoundary,readOnly}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotExecute}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotGrantAuthority}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotCreateEvidence}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotDetermineOutcome}')::boolean,false)=false
     or v_value#>>'{truthBoundary,callerNote}'<>'preserved' then
    raise exception 'Reconciliation truth-boundary invariants are caller-overridable: %',v_value;
  end if;

  -- Company Work: unresolved result requires authority and the plan does not
  -- create a result acceptance.
  select count(*) into v_before_acceptances
  from atlas.work_result_acceptances
  where execution_result_id='f4800000-0000-4000-8000-000000000112'::uuid;

  v_value:=atlas.company_work_result_reconciliation_plan_v1(
    'f4800000-0000-4000-8000-000000000112'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,handlingMode}'<>'authority_required'
     or v_value#>>'{targets,0,resolver,key}'<>'company_work_result_adjudication'
     or coalesce((v_value#>>'{targets,0,automation,eligible}')::boolean,true) then
    raise exception 'Company Work unresolved result was not authority-bound: %',v_value;
  end if;

  select count(*) into v_after_acceptances
  from atlas.work_result_acceptances
  where execution_result_id='f4800000-0000-4000-8000-000000000112'::uuid;

  if v_before_acceptances<>v_after_acceptances or v_after_acceptances<>0 then
    raise exception 'Company Work reconciliation plan mutated result acceptance.';
  end if;

  -- Settled Company Work has no fabricated handling target.
  v_value:=atlas.company_work_result_reconciliation_plan_v1(
    'f4800000-0000-4000-8000-000000000111'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>0 then
    raise exception 'Settled Company Work fabricated reconciliation work: %',v_value;
  end if;

  -- Commercial open state requires external evidence, not an internal payment.
  select count(*) into v_before_payment_events from atlas.commercial_payment_events;

  v_value:=atlas.commercial_financial_reconciliation_plan_v1(
    'f4800000-0000-4000-8000-000000000202'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,handlingMode}'<>'external_evidence_required'
     or v_value#>>'{targets,0,resolver,key}'<>'commercial_collection_or_settlement'
     or coalesce((v_value#>>'{targets,0,automation,eligible}')::boolean,true) then
    raise exception 'Open Commercial Financial Reality was not evidence-bound: %',v_value;
  end if;

  v_value:=atlas.commercial_financial_reconciliation_plan_v1(
    'f4800000-0000-4000-8000-000000000203'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,handlingMode}'<>'external_evidence_required'
     or v_value#>>'{targets,0,resolver,key}'<>'commercial_financial_reconciliation' then
    raise exception 'Unknown Commercial collection was not evidence-bound: %',v_value;
  end if;

  v_value:=atlas.commercial_financial_reconciliation_plan_v1(
    'f4800000-0000-4000-8000-000000000201'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>0 then
    raise exception 'Paid Commercial Financial Reality fabricated reconciliation work: %',v_value;
  end if;

  select count(*) into v_after_payment_events from atlas.commercial_payment_events;
  if v_before_payment_events<>v_after_payment_events then
    raise exception 'Commercial reconciliation planning fabricated Payment Events.';
  end if;

  -- Bed Readiness: fixture deliberately staled the Task gate while preserving
  -- dependency truth. The plan must admit exactly one automatic domain repair.
  v_value:=atlas.bed_readiness_reconciliation_plan_v1(
    'f4900000-0000-4000-8000-000000000021'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,handlingMode}'<>'automatic_domain_reconcile'
     or v_value#>>'{targets,0,automation,adapterKey}'<>'bed_readiness_reconcile_v1'
     or coalesce((v_value#>>'{targets,0,automation,eligible}')::boolean,false)=false
     or v_value#>>'{targets,0,reason,kind}'<>'blocked_readiness_not_reflected_in_task_gate' then
    raise exception 'Stale Bed Readiness gate was not admitted to bounded automatic reconciliation: %',v_value;
  end if;

  -- Automatic adapter invokes only the exact bed gate resolver and converges
  -- the target to a correctly blocked state.
  v_exec:=atlas.reconcile_bed_readiness_continuation_service_v1(
    'f4900000-0000-4000-8000-000000000021'::uuid,
    '2026-09-22 16:20:00+00'
  );

  if coalesce((v_exec->>'converged')::boolean,false)=false
     or jsonb_array_length(v_exec->'attempts')<>1
     or v_exec#>>'{attempts,0,adapterKey}'<>'bed_readiness_reconcile_v1'
     or v_exec#>>'{attempts,0,domainResult,state}'<>'blocked_visible'
     or v_exec#>>'{after,targets,0,handlingMode}'<>'settled' then
    raise exception 'Bounded Bed Readiness reconciliation did not converge: %',v_exec;
  end if;

  if not exists(
    select 1
    from atlas.tasks t
    where t.id='f4900000-0000-4000-8000-000000000031'::uuid
      and t.status='blocked'
      and t.metadata->>'execution_lock_kind'='bed_weeding'
      and t.metadata->>'bed_readiness_gate_state'='blocked_visible'
  ) then
    raise exception 'Bed Readiness resolver did not restore the governed Task gate.';
  end if;

  select count(*) into v_dep_satisfied
  from atlas.maintenance_dependencies
  where dependent_task_id='f4900000-0000-4000-8000-000000000031'::uuid
    and satisfied_at is not null;

  if v_dep_satisfied<>1 then
    raise exception 'Bounded Task-gate reconciliation changed Maintenance Dependency truth.';
  end if;

  -- Repeating after convergence is a no-op: no automatic targets, no attempt.
  v_exec:=atlas.reconcile_bed_readiness_continuation_service_v1(
    'f4900000-0000-4000-8000-000000000021'::uuid,
    '2026-09-22 16:21:00+00'
  );

  if coalesce((v_exec->>'converged')::boolean,false)=false
     or jsonb_array_length(v_exec->'attempts')<>0
     or v_exec#>>'{after,targets,0,handlingMode}'<>'settled' then
    raise exception 'Repeated Bed Readiness reconciliation was not convergent/idempotent: %',v_exec;
  end if;

  -- There is deliberately no generic orchestration/reconciliation storage.
  if to_regclass('atlas.reconciliation_queue') is not null
     or to_regclass('atlas.reconciliation_jobs') is not null
     or to_regclass('atlas.reconciliation_receipts') is not null
     or to_regclass('atlas.resolver_registry') is not null
     or to_regclass('atlas.reality_orchestration_tasks') is not null then
    raise exception 'Reality Reconciliation candidate introduced forbidden generic orchestration storage.';
  end if;

  -- Browser roles receive no cross-domain reconciliation authority.
  if has_function_privilege('authenticated','atlas.reality_reconciliation_plan_normalize_v1(jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.company_work_result_reconciliation_plan_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.commercial_financial_reconciliation_plan_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.bed_readiness_reconciliation_plan_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.reconcile_bed_readiness_continuation_service_v1(uuid,timestamp with time zone)','EXECUTE')
     or has_function_privilege('anon','atlas.reality_reconciliation_plan_normalize_v1(jsonb)','EXECUTE')
     or has_function_privilege('anon','atlas.company_work_result_reconciliation_plan_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.commercial_financial_reconciliation_plan_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.bed_readiness_reconciliation_plan_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.reconcile_bed_readiness_continuation_service_v1(uuid,timestamp with time zone)','EXECUTE') then
    raise exception 'Reality Reconciliation functions leaked to browser roles.';
  end if;

  -- Universal normalizer is schema-only.
  select lower(pg_get_functiondef(
    'atlas.reality_reconciliation_plan_normalize_v1(jsonb)'::regprocedure
  )) into v_def;

  if v_def like '% from atlas.%'
     or v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%execute %' then
    raise exception 'Reconciliation normalizer escaped schema-only authority.';
  end if;

  -- The bounded automatic adapter contains one static domain call and no
  -- dynamic dispatch or cross-domain authority/evidence mutations.
  select lower(pg_get_functiondef(
    'atlas.reconcile_bed_readiness_continuation_service_v1(uuid,timestamp with time zone)'::regprocedure
  )) into v_def;

  if v_def not like '%atlas.reconcile_bed_weeding_gate_v1%'
     or v_def like '%execute %'
     or v_def like '%work_result_acceptances%'
     or v_def like '%commercial_payment_events%'
     or v_def like '%record_connected_source_commercial_payment%'
     or v_def like '%accept_company_work%' then
    raise exception 'Bounded Bed Readiness adapter crossed its domain execution membrane.';
  end if;
end;
$validation$;

rollback;
