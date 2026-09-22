begin;

do $validation$
declare
  v_requirement jsonb;
  v_list jsonb;
  v_decision jsonb;
  v_plan jsonb;
  v_before_acceptances integer;
  v_after_acceptances integer;
  v_def text;
begin
  -- Internal projection is a pure consequence of the released Reconciliation Plan.
  select count(*)::integer into v_before_acceptances
  from atlas.work_result_acceptances
  where execution_result_id='f4a00000-0000-4000-8000-000000000111'::uuid;

  v_requirement:=atlas.company_work_result_decision_requirement_v1(
    'f4a00000-0000-4000-8000-000000000111'::uuid
  );

  if v_requirement->>'contractVersion'<>'company_work_result_decision_requirement_v1'
     or v_requirement->>'state'<>'decision_required'
     or v_requirement#>>'{decision,kind}'<>'company_work_result_acceptance'
     or v_requirement#>>'{decision,command,signature}'<>'atlas.organization_owner_decide_company_work_result_api_v1(uuid,text,text)'
     or v_requirement#>>'{authorityRequirement,currentBasis}'<>'transitional_organization_owner_compatibility'
     or v_requirement#>>'{reconciliation,handlingMode}'<>'authority_required'
     or v_requirement#>>'{reconciliation,resolver,key}'<>'company_work_result_adjudication'
     or coalesce((v_requirement#>>'{truthBoundary,doesNotCreateQueueState}')::boolean,false)=false
     or coalesce((v_requirement#>>'{truthBoundary,doesNotExposeResultPayload}')::boolean,false)=false then
    raise exception 'Company Work Decision Requirement is incorrect: %',v_requirement;
  end if;

  if v_requirement::text like '%fixture payload must not cross%' then
    raise exception 'Decision Requirement leaked arbitrary Result payload.';
  end if;

  select count(*)::integer into v_after_acceptances
  from atlas.work_result_acceptances
  where execution_result_id='f4a00000-0000-4000-8000-000000000111'::uuid;

  if v_before_acceptances<>v_after_acceptances or v_after_acceptances<>0 then
    raise exception 'Decision Requirement read mutated Result Acceptance.';
  end if;

  -- Non-owner is not routed the decision and cannot invoke the existing command.
  perform set_config(
    'request.jwt.claim.sub',
    'f4a00000-0000-4000-8000-000000000002',
    true
  );

  begin
    perform atlas.company_work_result_decision_requirement_self_api_v1(
      'f4a00000-0000-4000-8000-000000000111'::uuid
    );
    raise exception 'Non-owner read the owner-bound Company Work Decision Requirement.';
  exception when sqlstate '42501' then
    null;
  end;

  v_list:=atlas.company_work_decision_requirements_self_api_v1(50);

  if (v_list->>'count')::integer<>0
     or jsonb_array_length(v_list->'items')<>0 then
    raise exception 'Non-owner self list exposed an owner-bound Decision Requirement: %',v_list;
  end if;

  begin
    perform atlas.organization_owner_decide_company_work_result_api_v1(
      'f4a00000-0000-4000-8000-000000000111'::uuid,
      'accepted',
      'non-owner must fail'
    );
    raise exception 'Non-owner invoked the existing owner result-acceptance command.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Exact current owner receives the minimal derived requirement.
  perform set_config(
    'request.jwt.claim.sub',
    'f4a00000-0000-4000-8000-000000000001',
    true
  );

  v_requirement:=atlas.company_work_result_decision_requirement_self_api_v1(
    'f4a00000-0000-4000-8000-000000000111'::uuid
  );

  if v_requirement->>'state'<>'decision_required'
     or coalesce((v_requirement#>>'{actorAuthority,canDecide}')::boolean,false)=false
     or v_requirement#>>'{actorAuthority,basis}'<>'transitional_organization_owner_compatibility'
     or v_requirement#>>'{actorAuthority,actorOrganizationMembershipId}'
        <>'f4a00000-0000-4000-8000-000000000031' then
    raise exception 'Owner self Decision Requirement authority is incorrect: %',v_requirement;
  end if;

  if v_requirement::text like '%fixture payload must not cross%' then
    raise exception 'Owner Decision Requirement leaked arbitrary Result payload.';
  end if;

  v_list:=atlas.company_work_decision_requirements_self_api_v1(50);

  if (v_list->>'count')::integer<>1
     or jsonb_array_length(v_list->'items')<>1
     or v_list#>>'{items,0,source,ref}'
        <>'f4a00000-0000-4000-8000-000000000111'
     or coalesce((v_list#>>'{persistedQueue}')::boolean,true) then
    raise exception 'Owner Decision Requirement list is incorrect: %',v_list;
  end if;

  -- Human judgment crosses only the existing owning-domain command membrane.
  v_decision:=atlas.organization_owner_decide_company_work_result_api_v1(
    'f4a00000-0000-4000-8000-000000000111'::uuid,
    'accepted',
    'clone proof of authority-required reconciliation convergence'
  );

  if v_decision->>'state'<>'decided'
     or v_decision->>'decision'<>'accepted'
     or v_decision->>'companyWorkState'<>'completed' then
    raise exception 'Existing Company Work result-acceptance command did not establish the decision: %',v_decision;
  end if;

  -- Completion is proved by Reconciliation convergence, not command return alone.
  v_plan:=atlas.company_work_result_reconciliation_plan_v1(
    'f4a00000-0000-4000-8000-000000000111'::uuid
  );

  if jsonb_array_length(v_plan->'targets')<>0 then
    raise exception 'Company Work remained unreconciled after accepted decision: %',v_plan;
  end if;

  v_requirement:=atlas.company_work_result_decision_requirement_v1(
    'f4a00000-0000-4000-8000-000000000111'::uuid
  );

  if v_requirement->>'state'<>'settled'
     or v_requirement->'decision' is distinct from 'null'::jsonb then
    raise exception 'Decision Requirement did not settle after canonical reconciliation: %',v_requirement;
  end if;

  v_list:=atlas.company_work_decision_requirements_self_api_v1(50);

  if (v_list->>'count')::integer<>0
     or jsonb_array_length(v_list->'items')<>0 then
    raise exception 'Settled Decision Requirement remained in derived current list: %',v_list;
  end if;

  -- No generic decision or reconciliation queue storage was introduced.
  if to_regclass('atlas.decision_requirements') is not null
     or to_regclass('atlas.approval_queue') is not null
     or to_regclass('atlas.decision_queue') is not null
     or to_regclass('atlas.reconciliation_queue') is not null
     or to_regclass('atlas.reconciliation_jobs') is not null then
    raise exception 'Authority-required Company Work proof introduced forbidden generic queue/storage.';
  end if;

  -- Internal contracts remain internal; only the two actor-safe projections are browser-readable.
  if has_function_privilege(
       'authenticated',
       'atlas.company_work_result_decision_requirement_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.company_work_result_decision_requirement_v1(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.company_work_result_decision_requirement_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.company_work_result_decision_requirement_self_api_v1(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.company_work_decision_requirements_self_api_v1(integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.company_work_decision_requirements_self_api_v1(integer)',
       'EXECUTE'
     ) then
    raise exception 'Decision Requirement browser grants are incorrect.';
  end if;

  -- Reads statically describe the existing command but never invoke it.
  select lower(pg_get_functiondef(
    'atlas.company_work_result_decision_requirement_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%perform atlas.organization_owner_decide_company_work_result_api_v1%'
     or v_def like '%select atlas.organization_owner_decide_company_work_result_api_v1%'
     or v_def like '%execute %'
     or v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Internal Decision Requirement reader contains mutation/dynamic execution authority.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.company_work_result_decision_requirement_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%perform atlas.organization_owner_decide_company_work_result_api_v1%'
     or v_def like '%select atlas.organization_owner_decide_company_work_result_api_v1%'
     or v_def like '%execute %'
     or v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Self Decision Requirement reader contains mutation/dynamic execution authority.';
  end if;
end;
$validation$;

rollback;
