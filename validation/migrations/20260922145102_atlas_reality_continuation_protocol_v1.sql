begin;

do $validation$
declare
  v_value jsonb;
  v_def text;
begin
  -- Universal normalizer fails closed.
  begin
    perform atlas.reality_continuation_normalize_v1(
      '{"source":{},"targets":[]}'::jsonb
    );
    raise exception 'Continuation normalizer accepted incomplete source identity.';
  exception when sqlstate '22023' then null;
  end;

  begin
    perform atlas.reality_continuation_normalize_v1(
      '{"source":{"domain":"x","kind":"y","ref":"z"},"targets":[{"target":{"domain":"a","kind":"b","ref":"c"},"resolver":{"key":"r"},"reason":{"kind":"q"},"disposition":"invented"}]}'::jsonb
    );
    raise exception 'Continuation normalizer accepted unsupported disposition.';
  exception when sqlstate '22023' then null;
  end;

  -- Universal truth-boundary invariants cannot be weakened by caller input.
  v_value:=atlas.reality_continuation_normalize_v1(
    '{
      "contractVersion":"reality_continuation_v1",
      "source":{"domain":"validation","kind":"source","ref":"1"},
      "targets":[],
      "truthBoundary":{
        "readOnly":false,
        "doesNotInvokeResolver":false,
        "doesNotCreateDependency":false,
        "doesNotDetermineOutcome":false,
        "doesNotGrantAuthority":false,
        "domainSpecificNote":"preserved"
      }
    }'::jsonb
  );

  if coalesce((v_value#>>'{truthBoundary,readOnly}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotInvokeResolver}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotCreateDependency}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotDetermineOutcome}')::boolean,false)=false
     or coalesce((v_value#>>'{truthBoundary,doesNotGrantAuthority}')::boolean,false)=false
     or v_value#>>'{truthBoundary,domainSpecificNote}'<>'preserved' then
    raise exception 'Continuation normalizer allowed universal truth-boundary weakening: %',v_value;
  end if;

  -- Company Work unresolved result names adjudication as continuation but does
  -- not accept/complete it.
  v_value:=atlas.company_work_result_continuation_v1(
    'f4800000-0000-4000-8000-000000000112'::uuid
  );

  if v_value->>'contractVersion'<>'reality_continuation_v1'
     or jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,resolver,key}'<>'company_work_result_adjudication'
     or v_value#>>'{targets,0,disposition}'<>'reconsider'
     or not (v_value#>'{targets,0,blockers}' @> '["result_acceptance_missing"]'::jsonb) then
    raise exception 'Unresolved Company Work continuation is incorrect: %',v_value;
  end if;

  if exists(
    select 1 from atlas.work_result_acceptances
    where execution_result_id='f4800000-0000-4000-8000-000000000112'::uuid
  ) then
    raise exception 'Continuation adapter mutated Company Work result acceptance.';
  end if;

  -- Settled Company Work has no fabricated downstream continuation.
  v_value:=atlas.company_work_result_continuation_v1(
    'f4800000-0000-4000-8000-000000000111'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>0 then
    raise exception 'Settled Company Work fabricated continuation: %',v_value;
  end if;

  -- Commercial open state retains collection/settlement continuation even when
  -- fulfillment exists independently.
  v_value:=atlas.commercial_financial_continuation_v1(
    'f4800000-0000-4000-8000-000000000202'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,resolver,key}'<>'commercial_collection_or_settlement'
     or v_value#>>'{targets,0,disposition}'<>'reconsider'
     or v_value#>>'{targets,0,current,financialState}'<>'open'
     or coalesce((v_value#>>'{provenance,fulfillmentDoesNotCreateFinancialContinuation}')::boolean,false)=false then
    raise exception 'Open Commercial continuation is incorrect: %',v_value;
  end if;

  -- Paid commercial state is financially settled.
  v_value:=atlas.commercial_financial_continuation_v1(
    'f4800000-0000-4000-8000-000000000201'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>0 then
    raise exception 'Paid Commercial order fabricated financial continuation: %',v_value;
  end if;

  -- Unknown collection stays blocked/reconcilable, not fabricated into open/paid.
  v_value:=atlas.commercial_financial_continuation_v1(
    'f4800000-0000-4000-8000-000000000203'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,resolver,key}'<>'commercial_financial_reconciliation'
     or v_value#>>'{targets,0,disposition}'<>'blocked'
     or not (v_value#>'{targets,0,blockers}' @> '["collection_evidence_unknown"]'::jsonb) then
    raise exception 'Unknown Commercial collection continuation is incorrect: %',v_value;
  end if;

  -- One satisfied source dependency does not declare the downstream target ready
  -- when two other dependencies still block it.
  v_value:=atlas.bed_readiness_continuation_v1(
    'f4900000-0000-4000-8000-000000000021'::uuid
  );

  if jsonb_array_length(v_value->'targets')<>1
     or v_value#>>'{targets,0,resolver,key}'<>'task_bed_weeding_readiness'
     or v_value#>>'{targets,0,disposition}'<>'blocked'
     or coalesce((v_value#>>'{targets,0,current,dependencySatisfied}')::boolean,false)=false
     or coalesce((v_value#>>'{targets,0,current,taskReady}')::boolean,true)
     or (v_value#>>'{targets,0,current,blockingDependencyCount}')::integer<>2 then
    raise exception 'Partial bed-readiness continuation was collapsed into target readiness: %',v_value;
  end if;

  -- Reopening the source must reopen its native dependency through the existing
  -- domain trigger; the continuation adapter merely reports the resulting state.
  update atlas.maintenance_objects
  set condition='moderate',
      condition_reported_at='2026-09-22 17:00:00+00',
      updated_at='2026-09-22 17:00:00+00'
  where id='f4900000-0000-4000-8000-000000000021'::uuid;

  if (select satisfied_at from atlas.maintenance_dependencies
      where id='f4900000-0000-4000-8000-000000000041'::uuid) is not null then
    raise exception 'Native maintenance dependency did not reopen when source condition changed.';
  end if;

  v_value:=atlas.bed_readiness_continuation_v1(
    'f4900000-0000-4000-8000-000000000021'::uuid
  );

  if v_value#>>'{targets,0,disposition}'<>'blocked'
     or coalesce((v_value#>>'{targets,0,current,dependencySatisfied}')::boolean,true)
     or (v_value#>>'{targets,0,current,blockingDependencyCount}')::integer<>3 then
    raise exception 'Reopened dependency was not represented as current blocked continuation: %',v_value;
  end if;

  -- No generic continuation/dependency persistence.
  if to_regclass('atlas.reality_continuations') is not null
     or to_regclass('atlas.reality_dependencies') is not null
     or to_regclass('atlas.continuation_edges') is not null
     or to_regclass('atlas.reconsideration_queue') is not null then
    raise exception 'Reality Continuation candidate introduced forbidden generic storage.';
  end if;

  -- No browser-level generic cross-domain authority.
  if has_function_privilege('authenticated','atlas.reality_continuation_normalize_v1(jsonb)','EXECUTE')
     or has_function_privilege('authenticated','atlas.company_work_result_continuation_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.commercial_financial_continuation_v1(uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.bed_readiness_continuation_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.reality_continuation_normalize_v1(jsonb)','EXECUTE')
     or has_function_privilege('anon','atlas.company_work_result_continuation_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.commercial_financial_continuation_v1(uuid)','EXECUTE')
     or has_function_privilege('anon','atlas.bed_readiness_continuation_v1(uuid)','EXECUTE') then
    raise exception 'Reality Continuation functions leaked to browser roles.';
  end if;

  -- Universal normalizer is schema-only, not a resolver.
  select lower(pg_get_functiondef(
    'atlas.reality_continuation_normalize_v1(jsonb)'::regprocedure
  )) into v_def;

  if v_def like '% from atlas.%'
     or v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%execute %' then
    raise exception 'Reality Continuation normalizer escaped schema-only authority.';
  end if;

  -- Domain adapters may read their native resolvers but must not mutate.
  select lower(
    pg_get_functiondef('atlas.company_work_result_continuation_v1(uuid)'::regprocedure)
    || pg_get_functiondef('atlas.commercial_financial_continuation_v1(uuid)'::regprocedure)
    || pg_get_functiondef('atlas.bed_readiness_continuation_v1(uuid)'::regprocedure)
  ) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%execute %'
     or v_def like '%perform atlas.%' then
    raise exception 'Reality Continuation adapter contains mutation/dynamic execution authority.';
  end if;
end;
$validation$;

rollback;
