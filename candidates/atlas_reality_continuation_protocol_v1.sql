begin;

-- Atlas Reality Continuation Protocol v1
--
-- Read-only explanation/proof membrane.
-- No generic dependency storage, queue, resolver registry, or mutation engine.

create or replace function atlas.reality_continuation_normalize_v1(
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
    raise exception 'Reality Continuation input must be a JSON object.'
      using errcode='22023';
  end if;

  if coalesce(nullif(btrim(p_input->>'contractVersion'),''),'reality_continuation_v1')
     <> 'reality_continuation_v1' then
    raise exception 'Unsupported Reality Continuation contract version.'
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
    raise exception 'Reality Continuation source identity is incomplete.'
      using errcode='22023';
  end if;

  if v_source ? 'changedAt'
     and nullif(btrim(v_source->>'changedAt'),'') is not null then
    begin
      perform (v_source->>'changedAt')::timestamptz;
    exception when others then
      raise exception 'Reality Continuation source changedAt is not a timestamp.'
        using errcode='22023';
    end;
  end if;

  if jsonb_typeof(v_targets)<>'array' then
    raise exception 'Reality Continuation targets must be an array.'
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
       or jsonb_typeof(v_target->'reason')<>'object'
       or nullif(btrim(v_target#>>'{reason,kind}'),'') is null
       or coalesce(v_target->>'disposition','') not in (
         'reconsider','blocked','settled','not_applicable'
       )
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
       ) then
      raise exception 'Reality Continuation target shape is invalid.'
        using errcode='22023';
    end if;
  end loop;

  if jsonb_typeof(v_truth)<>'object'
     or jsonb_typeof(v_provenance)<>'object' then
    raise exception 'Reality Continuation truthBoundary/provenance must be objects.'
      using errcode='22023';
  end if;

  return jsonb_build_object(
    'contractVersion','reality_continuation_v1',
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
      'doesNotInvokeResolver',true,
      'doesNotCreateDependency',true,
      'doesNotDetermineOutcome',true,
      'doesNotGrantAuthority',true
    ),
    'provenance',v_provenance
  );
end;
$function$;

comment on function atlas.reality_continuation_normalize_v1(jsonb) is
  'Read-only schema normalizer for continuation/reconsideration candidates. It does not discover dependencies, invoke resolvers, determine outcomes, grant authority, or persist continuation state.';

revoke all on function atlas.reality_continuation_normalize_v1(jsonb)
  from public,anon,authenticated,service_role;


create or replace function atlas.company_work_result_continuation_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_receipt jsonb;
  v_targets jsonb := '[]'::jsonb;
  v_key text;
  v_blockers jsonb;
begin
  v_receipt:=atlas.company_work_result_transition_receipt_v1(p_execution_result_id);
  v_blockers:=coalesce(v_receipt#>'{continuation,blockers}','[]'::jsonb);

  for v_key in
    select value
    from jsonb_array_elements_text(
      coalesce(v_receipt#>'{continuation,reconsider}','[]'::jsonb)
    )
  loop
    v_targets:=v_targets||jsonb_build_array(
      jsonb_build_object(
        'target',jsonb_build_object(
          'domain','company_work',
          'kind','work_item',
          'ref',v_receipt#>>'{subject,ref}',
          'scope',coalesce(v_receipt#>'{subject,scope}','{}'::jsonb)
        ),
        'resolver',jsonb_build_object(
          'key',v_key,
          'version','v1'
        ),
        'reason',jsonb_build_object(
          'kind','local_transition_unresolved',
          'basisRefs',coalesce(v_receipt#>'{resolution,basisRefs}','[]'::jsonb)
        ),
        'disposition','reconsider',
        'current',jsonb_strip_nulls(jsonb_build_object(
          'transitionResolution',v_receipt#>>'{resolution,state}',
          'workState',v_receipt#>>'{resolution,details,workState}'
        )),
        'blockers',v_blockers
      )
    );
  end loop;

  return atlas.reality_continuation_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_continuation_v1',
      'source',jsonb_build_object(
        'domain','company_work',
        'kind','work_execution_result',
        'ref',v_receipt#>>'{source,ref}',
        'state',v_receipt#>>'{resolution,state}',
        'changedAt',v_receipt#>>'{source,occurredAt}',
        'details',jsonb_build_object(
          'transitionReceiptKind',v_receipt->>'receiptKind'
        )
      ),
      'targets',v_targets,
      'provenance',jsonb_build_object(
        'adapter','company_work_result_continuation_v1',
        'transitionReceiptAdapter','company_work_result_transition_receipt_v1',
        'readOnly',true
      )
    )
  );
end;
$function$;

comment on function atlas.company_work_result_continuation_v1(uuid) is
  'Read-only local continuation adapter for Company Work result transitions. It names unresolved domain resolvers but does not accept results, complete Work, or project Ledger consequences.';

revoke all on function atlas.company_work_result_continuation_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.commercial_financial_continuation_v1(
  p_commercial_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_receipt jsonb;
  v_targets jsonb := '[]'::jsonb;
  v_key text;
  v_blockers jsonb;
begin
  v_receipt:=atlas.commercial_financial_transition_receipt_v1(p_commercial_order_id);
  v_blockers:=coalesce(v_receipt#>'{continuation,blockers}','[]'::jsonb);

  for v_key in
    select value
    from jsonb_array_elements_text(
      coalesce(v_receipt#>'{continuation,reconsider}','[]'::jsonb)
    )
  loop
    v_targets:=v_targets||jsonb_build_array(
      jsonb_build_object(
        'target',jsonb_build_object(
          'domain','commercial',
          'kind','commercial_order',
          'ref',v_receipt#>>'{subject,ref}',
          'scope',coalesce(v_receipt#>'{subject,scope}','{}'::jsonb)
        ),
        'resolver',jsonb_build_object(
          'key',v_key,
          'version','v1'
        ),
        'reason',jsonb_build_object(
          'kind','derived_financial_state_requires_reconsideration',
          'basisRefs',coalesce(v_receipt#>'{resolution,basisRefs}','[]'::jsonb)
        ),
        'disposition',case
          when jsonb_array_length(v_blockers)>0 then 'blocked'
          else 'reconsider'
        end,
        'current',jsonb_strip_nulls(jsonb_build_object(
          'transitionResolution',v_receipt#>>'{resolution,state}',
          'financialState',v_receipt#>>'{consequence,state}'
        )),
        'blockers',v_blockers
      )
    );
  end loop;

  return atlas.reality_continuation_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_continuation_v1',
      'source',jsonb_build_object(
        'domain',v_receipt#>>'{source,domain}',
        'kind','commercial_financial_position',
        'ref',v_receipt#>>'{subject,ref}',
        'state',v_receipt#>>'{consequence,state}',
        'changedAt',v_receipt#>>'{resolution,effectiveAt}',
        'details',jsonb_build_object(
          'transitionReceiptKind',v_receipt->>'receiptKind'
        )
      ),
      'targets',v_targets,
      'provenance',jsonb_build_object(
        'adapter','commercial_financial_continuation_v1',
        'transitionReceiptAdapter','commercial_financial_transition_receipt_v1',
        'fulfillmentDoesNotCreateFinancialContinuation',true,
        'readOnly',true
      )
    )
  );
end;
$function$;

comment on function atlas.commercial_financial_continuation_v1(uuid) is
  'Read-only local continuation adapter for Commercial Financial Reality. It preserves collection/refund/reconciliation semantics and does not use fulfillment as financial evidence.';

revoke all on function atlas.commercial_financial_continuation_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.bed_readiness_continuation_v1(
  p_maintenance_object_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_object atlas.maintenance_objects%rowtype;
  v_targets jsonb := '[]'::jsonb;
  v_readiness jsonb;
  v_disposition text;
  v_blockers jsonb;
  r record;
begin
  select mo.* into v_object
  from atlas.maintenance_objects mo
  where mo.id=p_maintenance_object_id;

  if v_object.id is null then
    raise exception 'Maintenance Object not found.'
      using errcode='P0002';
  end if;

  for r in
    select
      md.id as dependency_id,
      md.active,
      md.satisfied_at,
      md.dependency_type,
      md.dependent_task_id,
      md.metadata as dependency_metadata,
      t.status as task_status,
      t.organization_id,
      t.farm_id
    from atlas.maintenance_dependencies md
    join atlas.tasks t on t.id=md.dependent_task_id
    where md.maintenance_object_id=v_object.id
      and md.metadata->>'source'='automatic_bed_readiness'
    order by md.created_at,md.id
  loop
    if not r.active
       or r.task_status not in ('open','blocked')
       or not atlas.task_requires_weed_free_bed_readiness_v1(r.dependent_task_id) then
      v_disposition:='not_applicable';
      v_blockers:='[]'::jsonb;
      v_readiness:=null;
    else
      v_readiness:=atlas.task_bed_weeding_readiness_v1(r.dependent_task_id);

      if v_object.condition='maintained' and r.satisfied_at is null then
        v_disposition:='reconsider';
        v_blockers:=jsonb_build_array('source_dependency_not_yet_satisfied');
      elsif v_object.condition<>'maintained' and r.satisfied_at is not null then
        v_disposition:='reconsider';
        v_blockers:=jsonb_build_array('source_dependency_requires_reopen');
      elsif coalesce((v_readiness->>'ready')::boolean,false) then
        v_disposition:='settled';
        v_blockers:='[]'::jsonb;
      else
        v_disposition:='blocked';
        v_blockers:=coalesce(v_readiness->'blockingBeds','[]'::jsonb);
      end if;
    end if;

    v_targets:=v_targets||jsonb_build_array(
      jsonb_build_object(
        'target',jsonb_build_object(
          'domain','production',
          'kind','task',
          'ref',r.dependent_task_id::text,
          'scope',jsonb_strip_nulls(jsonb_build_object(
            'organizationId',r.organization_id,
            'farmId',r.farm_id
          ))
        ),
        'resolver',jsonb_build_object(
          'key','task_bed_weeding_readiness',
          'version','v2'
        ),
        'reason',jsonb_build_object(
          'kind','maintenance_dependency',
          'basisRefs',jsonb_build_array(
            jsonb_build_object(
              'kind','maintenance_object',
              'ref',v_object.id
            ),
            jsonb_build_object(
              'kind','maintenance_dependency',
              'ref',r.dependency_id,
              'satisfiedAt',r.satisfied_at
            )
          )
        ),
        'disposition',v_disposition,
        'current',jsonb_strip_nulls(jsonb_build_object(
          'sourceCondition',v_object.condition,
          'dependencyActive',r.active,
          'dependencySatisfied',r.satisfied_at is not null,
          'taskStatus',r.task_status,
          'taskReady',case
            when v_readiness is null then null
            else (v_readiness->>'ready')::boolean
          end,
          'blockingDependencyCount',case
            when v_readiness is null then null
            else (v_readiness->>'blockingBedCount')::integer
          end
        )),
        'blockers',v_blockers
      )
    );
  end loop;

  return atlas.reality_continuation_normalize_v1(
    jsonb_build_object(
      'contractVersion','reality_continuation_v1',
      'source',jsonb_build_object(
        'domain','maintenance',
        'kind','maintenance_object',
        'ref',v_object.id::text,
        'state',v_object.condition,
        'changedAt',coalesce(
          v_object.condition_reported_at,
          v_object.last_completed_at,
          v_object.updated_at
        ),
        'details',jsonb_build_object(
          'maintenanceType',v_object.maintenance_type
        )
      ),
      'targets',v_targets,
      'provenance',jsonb_build_object(
        'adapter','bed_readiness_continuation_v1',
        'dependencySource','maintenance_dependencies',
        'readinessResolver','task_bed_weeding_readiness_v1',
        'doesNotMutateDependency',true,
        'doesNotMutateTask',true,
        'readOnly',true
      )
    )
  );
end;
$function$;

comment on function atlas.bed_readiness_continuation_v1(uuid) is
  'Read-only dependent-continuation adapter. One maintenance source may affect many planting tasks; one satisfied dependency does not imply overall task readiness.';

revoke all on function atlas.bed_readiness_continuation_v1(uuid)
  from public,anon,authenticated,service_role;

commit;
