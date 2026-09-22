begin;

-- Atlas Reality Reconciliation Protocol v1
--
-- Continuation Candidate -> lawful handling mode.
-- No generic resolver registry, queue, dynamic dispatch, or cross-domain mutation engine.

create or replace function atlas.reality_reconciliation_plan_normalize_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = pg_catalog, atlas
as $function$
declare
  v_source jsonb;
  v_targets jsonb;
  v_truth jsonb;
  v_provenance jsonb;
  v_target jsonb;
begin
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Reality Reconciliation Plan must be a JSON object.'
      using errcode='22023';
  end if;

  if coalesce(nullif(btrim(p_input->>'contractVersion'),''),'reality_reconciliation_plan_v1')
     <> 'reality_reconciliation_plan_v1' then
    raise exception 'Unsupported Reality Reconciliation Plan contract version.'
      using errcode='22023';
  end if;

  v_source:=p_input->'source';
  v_targets:=coalesce(p_input->'targets','[]'::jsonb);
  v_truth:=coalesce(p_input->'truthBoundary','{}'::jsonb);
  v_provenance:=coalesce(p_input->'provenance','{}'::jsonb);

  if jsonb_typeof(v_source)<>'object'
     or nullif(btrim(v_source->>'domain'),'') is null
     or nullif(btrim(v_source->>'kind'),'') is null
     or nullif(btrim(v_source->>'ref'),'') is null then
    raise exception 'Reality Reconciliation source identity is incomplete.'
      using errcode='22023';
  end if;

  if v_source ? 'changedAt'
     and nullif(btrim(v_source->>'changedAt'),'') is not null then
    begin
      perform (v_source->>'changedAt')::timestamptz;
    exception when others then
      raise exception 'Reality Reconciliation source changedAt is not a timestamp.'
        using errcode='22023';
    end;
  end if;

  if jsonb_typeof(v_targets)<>'array' then
    raise exception 'Reality Reconciliation targets must be an array.'
      using errcode='22023';
  end if;

  for v_target in select value from jsonb_array_elements(v_targets)
  loop
    if jsonb_typeof(v_target)<>'object'
       or jsonb_typeof(v_target->'target')<>'object'
       or nullif(btrim(v_target#>>'{target,domain}'),'') is null
       or nullif(btrim(v_target#>>'{target,kind}'),'') is null
       or nullif(btrim(v_target#>>'{target,ref}'),'') is null
       or jsonb_typeof(v_target->'resolver')<>'object'
       or nullif(btrim(v_target#>>'{resolver,key}'),'') is null
       or coalesce(v_target->>'handlingMode','') not in (
         'automatic_domain_reconcile',
         'authority_required',
         'external_evidence_required',
         'invariant_repair_required',
         'settled',
         'not_applicable'
       )
       or jsonb_typeof(v_target->'reason')<>'object'
       or nullif(btrim(v_target#>>'{reason,kind}'),'') is null
       or (
         v_target#>'{target,scope}' is not null
         and jsonb_typeof(v_target#>'{target,scope}')<>'object'
       )
       or (
         v_target#>'{reason,basisRefs}' is not null
         and jsonb_typeof(v_target#>'{reason,basisRefs}')<>'array'
       )
       or (
         v_target->'current' is not null
         and jsonb_typeof(v_target->'current')<>'object'
       )
       or (
         v_target->'blockers' is not null
         and jsonb_typeof(v_target->'blockers')<>'array'
       )
       or (
         v_target->'automation' is not null
         and jsonb_typeof(v_target->'automation')<>'object'
       ) then
      raise exception 'Reality Reconciliation target shape is invalid.'
        using errcode='22023';
    end if;

    if coalesce((v_target#>>'{automation,eligible}')::boolean,false)
       and v_target->>'handlingMode'<>'automatic_domain_reconcile' then
      raise exception 'Only automatic_domain_reconcile targets may be automation-eligible.'
        using errcode='22023';
    end if;

    if v_target->>'handlingMode'='automatic_domain_reconcile'
       and (
         coalesce((v_target#>>'{automation,eligible}')::boolean,false)=false
         or nullif(btrim(v_target#>>'{automation,adapterKey}'),'') is null
       ) then
      raise exception 'Automatic reconciliation requires an explicit bounded adapter key.'
        using errcode='22023';
    end if;
  end loop;

  if jsonb_typeof(v_truth)<>'object'
     or jsonb_typeof(v_provenance)<>'object' then
    raise exception 'Reality Reconciliation truthBoundary/provenance must be objects.'
      using errcode='22023';
  end if;

  return jsonb_build_object(
    'contractVersion','reality_reconciliation_plan_v1',
    'source',jsonb_strip_nulls(jsonb_build_object(
      'domain',btrim(v_source->>'domain'),
      'kind',btrim(v_source->>'kind'),
      'ref',btrim(v_source->>'ref'),
      'state',nullif(btrim(v_source->>'state'),''),
      'changedAt',nullif(btrim(v_source->>'changedAt'),''),
      'details',case
        when v_source ? 'details' and jsonb_typeof(v_source->'details')='object'
        then v_source->'details'
        else null
      end
    )),
    'targets',v_targets,
    'truthBoundary',v_truth||jsonb_build_object(
      'readOnly',true,
      'doesNotExecute',true,
      'doesNotGrantAuthority',true,
      'doesNotCreateEvidence',true,
      'doesNotDetermineOutcome',true
    ),
    'provenance',v_provenance
  );
end;
$function$;

comment on function atlas.reality_reconciliation_plan_normalize_v1(jsonb) is
  'Schema-only normalizer for lawful reconciliation handling plans. It does not classify domains, execute resolvers, grant authority, create evidence, or determine downstream outcomes.';

revoke all on function atlas.reality_reconciliation_plan_normalize_v1(jsonb)
  from public,anon,authenticated,service_role;


create or replace function atlas.company_work_result_reconciliation_plan_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_cont jsonb;
  v_targets jsonb := '[]'::jsonb;
  x jsonb;
  v_key text;
  v_mode text;
begin
  v_cont:=atlas.company_work_result_continuation_v1(p_execution_result_id);

  for x in select value from jsonb_array_elements(coalesce(v_cont->'targets','[]'::jsonb))
  loop
    v_key:=x#>>'{resolver,key}';
    v_mode:=case
      when v_key='company_work_result_adjudication' then 'authority_required'
      when v_key='company_work_completion_projection' then 'invariant_repair_required'
      else 'invariant_repair_required'
    end;

    v_targets:=v_targets||jsonb_build_array(
      jsonb_build_object(
        'target',x->'target',
        'resolver',x->'resolver',
        'handlingMode',v_mode,
        'reason',jsonb_build_object(
          'kind',case
            when v_mode='authority_required' then 'institutional_result_adjudication_requires_authority'
            else 'company_work_projection_invariant_requires_bounded_repair'
          end,
          'basisRefs',coalesce(x#>'{reason,basisRefs}','[]'::jsonb)
        ),
        'current',coalesce(x->'current','{}'::jsonb),
        'blockers',coalesce(x->'blockers','[]'::jsonb),
        'automation',jsonb_build_object('eligible',false,'adapterKey',null)
      )
    );
  end loop;

  return atlas.reality_reconciliation_plan_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_reconciliation_plan_v1',
      'source',v_cont->'source',
      'targets',v_targets,
      'provenance',jsonb_build_object(
        'adapter','company_work_result_reconciliation_plan_v1',
        'continuationAdapter','company_work_result_continuation_v1',
        'emptyTargetsMeanSettled',true,
        'readOnly',true
      )
    )
  );
end;
$function$;

comment on function atlas.company_work_result_reconciliation_plan_v1(uuid) is
  'Read-only reconciliation classification for Company Work results. Result adjudication requires authority; missing completion projection is an invariant-repair condition.';

revoke all on function atlas.company_work_result_reconciliation_plan_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.commercial_financial_reconciliation_plan_v1(
  p_commercial_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_cont jsonb;
  v_targets jsonb := '[]'::jsonb;
  x jsonb;
  v_key text;
  v_state text;
  v_mode text;
begin
  v_cont:=atlas.commercial_financial_continuation_v1(p_commercial_order_id);
  v_state:=nullif(v_cont->'source'->>'state','');

  for x in select value from jsonb_array_elements(coalesce(v_cont->'targets','[]'::jsonb))
  loop
    v_key:=x#>>'{resolver,key}';

    v_mode:=case
      when v_key in ('commercial_collection_or_settlement','commercial_refund_resolution')
        then 'external_evidence_required'
      when v_key='commercial_financial_reconciliation' and v_state='invariant_gap'
        then 'invariant_repair_required'
      when v_key='commercial_financial_reconciliation'
        then 'external_evidence_required'
      else 'invariant_repair_required'
    end;

    v_targets:=v_targets||jsonb_build_array(
      jsonb_build_object(
        'target',x->'target',
        'resolver',x->'resolver',
        'handlingMode',v_mode,
        'reason',jsonb_build_object(
          'kind',case
            when v_mode='external_evidence_required' then 'commercial_state_requires_new_source_backed_evidence'
            else 'commercial_financial_invariant_requires_bounded_repair'
          end,
          'basisRefs',coalesce(x#>'{reason,basisRefs}','[]'::jsonb)
        ),
        'current',coalesce(x->'current','{}'::jsonb),
        'blockers',coalesce(x->'blockers','[]'::jsonb),
        'automation',jsonb_build_object('eligible',false,'adapterKey',null)
      )
    );
  end loop;

  return atlas.reality_reconciliation_plan_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_reconciliation_plan_v1',
      'source',v_cont->'source',
      'targets',v_targets,
      'provenance',jsonb_build_object(
        'adapter','commercial_financial_reconciliation_plan_v1',
        'continuationAdapter','commercial_financial_continuation_v1',
        'fulfillmentIsNotSettlementEvidence',true,
        'emptyTargetsMeanSettled',true,
        'readOnly',true
      )
    )
  );
end;
$function$;

comment on function atlas.commercial_financial_reconciliation_plan_v1(uuid) is
  'Read-only reconciliation classification for Commercial Financial Reality. Missing settlement/refund evidence remains external-evidence work; invariant gaps remain bounded repair work.';

revoke all on function atlas.commercial_financial_reconciliation_plan_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.bed_readiness_reconciliation_plan_v1(
  p_maintenance_object_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_cont jsonb;
  v_targets jsonb := '[]'::jsonb;
  x jsonb;
  v_task atlas.tasks%rowtype;
  v_disposition text;
  v_ready boolean;
  v_gate_active boolean;
  v_mode text;
  v_reason text;
begin
  v_cont:=atlas.bed_readiness_continuation_v1(p_maintenance_object_id);

  for x in select value from jsonb_array_elements(coalesce(v_cont->'targets','[]'::jsonb))
  loop
    select * into v_task
    from atlas.tasks
    where id=(x#>>'{target,ref}')::uuid;

    v_disposition:=x->>'disposition';
    v_ready:=coalesce((x#>>'{current,taskReady}')::boolean,false);
    v_gate_active:=coalesce(v_task.metadata->>'execution_lock_kind','')='bed_weeding'
      or coalesce(v_task.metadata->>'bed_readiness_gate_state','')='blocked_visible';

    if v_disposition='not_applicable' then
      v_mode:='not_applicable';
      v_reason:='bed_readiness_target_not_applicable';
    elsif v_disposition='reconsider' then
      -- Source/dependency disagreement is upstream of the Task gate. Do not let
      -- the bounded gate adapter silently repair dependency truth.
      v_mode:='invariant_repair_required';
      v_reason:='maintenance_dependency_state_requires_bounded_repair';
    elsif v_ready and v_gate_active then
      v_mode:='automatic_domain_reconcile';
      v_reason:='ready_task_still_has_bed_readiness_gate';
    elsif not v_ready
          and (
            v_task.status<>'blocked'
            or not v_gate_active
          ) then
      v_mode:='automatic_domain_reconcile';
      v_reason:='blocked_readiness_not_reflected_in_task_gate';
    else
      v_mode:='settled';
      v_reason:=case
        when v_ready then 'bed_readiness_already_converged_ready'
        else 'bed_readiness_already_converged_blocked'
      end;
    end if;

    v_targets:=v_targets||jsonb_build_array(
      jsonb_build_object(
        'target',x->'target',
        'resolver',x->'resolver',
        'handlingMode',v_mode,
        'reason',jsonb_build_object(
          'kind',v_reason,
          'basisRefs',coalesce(x#>'{reason,basisRefs}','[]'::jsonb)
        ),
        'current',coalesce(x->'current','{}'::jsonb)||jsonb_build_object(
          'taskGateActive',v_gate_active,
          'taskGateState',v_task.metadata->>'bed_readiness_gate_state',
          'executionLockKind',v_task.metadata->>'execution_lock_kind',
          'taskBlockerText',v_task.blocker_text
        ),
        'blockers',coalesce(x->'blockers','[]'::jsonb),
        'automation',jsonb_build_object(
          'eligible',v_mode='automatic_domain_reconcile',
          'adapterKey',case
            when v_mode='automatic_domain_reconcile' then 'bed_readiness_reconcile_v1'
            else null
          end
        )
      )
    );
  end loop;

  return atlas.reality_reconciliation_plan_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_reconciliation_plan_v1',
      'source',v_cont->'source',
      'targets',v_targets,
      'provenance',jsonb_build_object(
        'adapter','bed_readiness_reconciliation_plan_v1',
        'continuationAdapter','bed_readiness_continuation_v1',
        'boundedAutomaticAdapter','reconcile_bed_readiness_continuation_service_v1',
        'readOnly',true
      )
    )
  );
end;
$function$;

comment on function atlas.bed_readiness_reconciliation_plan_v1(uuid) is
  'Read-only Bed Readiness reconciliation plan. Correctly blocked/ready gates are settled; only stale Task gate projections are automatic-domain-reconcile. Dependency truth mismatches remain invariant-repair work.';

revoke all on function atlas.bed_readiness_reconciliation_plan_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.reconcile_bed_readiness_continuation_service_v1(
  p_maintenance_object_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_before jsonb;
  v_after jsonb;
  v_attempts jsonb := '[]'::jsonb;
  x jsonb;
  v_task_id uuid;
  v_result jsonb;
  v_remaining integer;
begin
  if p_maintenance_object_id is null then
    raise exception 'Maintenance Object is required.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'atlas.reality.reconciliation:bed_readiness:'||p_maintenance_object_id::text,
      0
    )
  );

  v_before:=atlas.bed_readiness_reconciliation_plan_v1(p_maintenance_object_id);

  for x in
    select value
    from jsonb_array_elements(coalesce(v_before->'targets','[]'::jsonb))
    where value->>'handlingMode'='automatic_domain_reconcile'
      and coalesce((value#>>'{automation,eligible}')::boolean,false)
      and value#>>'{automation,adapterKey}'='bed_readiness_reconcile_v1'
  loop
    v_task_id:=(x#>>'{target,ref}')::uuid;

    -- Static bounded dispatch: this service can invoke only this one domain resolver.
    v_result:=atlas.reconcile_bed_weeding_gate_v1(v_task_id,coalesce(p_as_of,now()));

    v_attempts:=v_attempts||jsonb_build_array(
      jsonb_build_object(
        'target',x->'target',
        'resolver',x->'resolver',
        'adapterKey','bed_readiness_reconcile_v1',
        'domainResult',v_result
      )
    );
  end loop;

  v_after:=atlas.bed_readiness_reconciliation_plan_v1(p_maintenance_object_id);

  select count(*)::integer into v_remaining
  from jsonb_array_elements(coalesce(v_after->'targets','[]'::jsonb)) t(value)
  where t.value->>'handlingMode'='automatic_domain_reconcile';

  return jsonb_build_object(
    'contractVersion','reality_reconciliation_execution_v1',
    'source',v_before->'source',
    'before',v_before,
    'attempts',v_attempts,
    'after',v_after,
    'converged',v_remaining=0,
    'truthBoundary',jsonb_build_object(
      'boundedDomainAdapter',true,
      'noDynamicDispatch',true,
      'doesNotCreateAuthority',true,
      'doesNotCreateEvidence',true,
      'doesNotInvokeCompanyWorkAdjudication',true,
      'doesNotInvokeCommercialEvidenceMutation',true
    )
  );
end;
$function$;

comment on function atlas.reconcile_bed_readiness_continuation_service_v1(uuid,timestamptz) is
  'Internal bounded reconciliation adapter for stale Bed Readiness Task gates. It statically calls only reconcile_bed_weeding_gate_v1, then re-reads the reconciliation plan to prove convergence.';

revoke all on function atlas.reconcile_bed_readiness_continuation_service_v1(uuid,timestamptz)
  from public,anon,authenticated,service_role;

commit;
