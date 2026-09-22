begin;

do $validation$
declare
  v_authority jsonb;
  v_grant jsonb;
  v_requirement jsonb;
  v_list jsonb;
  v_decision jsonb;
  v_plan jsonb;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_def text;
begin
  -- Owner role by itself is no longer Result-decision authority for fixture rows
  -- created after migration cutover.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000001',
    true
  );

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4b00000-0000-4000-8000-000000000111'::uuid,
    'f4b00000-0000-4000-8000-000000000031'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,true)
     or v_authority->>'reason'<>'explicit_adjudication_grant_required' then
    raise exception 'Owner role was treated as Result-adjudication authority: %',v_authority;
  end if;

  begin
    perform atlas.organization_decide_company_work_result_self_api_v1(
      'f4b00000-0000-4000-8000-000000000111'::uuid,
      'accepted',
      'owner without grant must fail'
    );
    raise exception 'Owner decided Company Work Result without explicit grant.';
  exception when sqlstate '42501' then
    null;
  end;

  begin
    perform atlas.company_work_result_decision_requirement_self_api_v1(
      'f4b00000-0000-4000-8000-000000000111'::uuid
    );
    raise exception 'Owner saw grant-governed Decision Requirement without grant.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Owner root governance may establish a bounded exact-Work grant.
  v_grant:=atlas.set_company_work_adjudication_authority_self_api_v1(
    'f4b00000-0000-4000-8000-000000000032'::uuid,
    'work_item',
    'f4b00000-0000-4000-8000-000000000101'::uuid,
    true,
    'grant exact Work adjudication for clone proof'
  );

  if v_grant->>'grantBasisKind'<>'explicit_owner_grant'
     or v_grant->>'scopeKind'<>'work_item'
     or v_grant->>'scopeId'<>'f4b00000-0000-4000-8000-000000000101'
     or v_grant->>'grantState'<>'active' then
    raise exception 'Exact Work adjudication grant was not established: %',v_grant;
  end if;

  -- Non-owner cannot grant authority.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000003',
    true
  );

  begin
    perform atlas.set_company_work_adjudication_authority_self_api_v1(
      'f4b00000-0000-4000-8000-000000000033'::uuid,
      'organization',
      'f4b00000-0000-4000-8000-000000000020'::uuid,
      true,
      'must fail'
    );
    raise exception 'Non-owner established Company Work adjudication authority.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Exact Work grantee gets A but not sibling B.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000002',
    true
  );

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4b00000-0000-4000-8000-000000000111'::uuid,
    'f4b00000-0000-4000-8000-000000000032'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,false)=false
     or v_authority->>'scopeKind'<>'work_item'
     or v_authority->>'grantBasisKind'<>'explicit_owner_grant' then
    raise exception 'Exact Work grant did not authorize its target Result: %',v_authority;
  end if;

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4b00000-0000-4000-8000-000000000112'::uuid,
    'f4b00000-0000-4000-8000-000000000032'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,true) then
    raise exception 'Exact Work adjudication grant leaked to sibling Work: %',v_authority;
  end if;

  v_requirement:=atlas.company_work_result_decision_requirement_self_api_v1(
    'f4b00000-0000-4000-8000-000000000111'::uuid
  );

  if v_requirement#>>'{authorityRequirement,currentBasis}'
       <>'explicit_company_work_adjudication_grant'
     or v_requirement#>>'{decision,command,signature}'
       <>'atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)'
     or v_requirement#>>'{actorAuthority,scopeKind}'<>'work_item'
     or v_requirement::text like '%must remain outside minimal%' then
    raise exception 'Decision Requirement did not cut over to explicit adjudication authority: %',v_requirement;
  end if;

  v_list:=atlas.company_work_decision_requirements_self_api_v1(50);

  if (v_list->>'count')::integer<>1
     or v_list#>>'{items,0,source,ref}'
        <>'f4b00000-0000-4000-8000-000000000111' then
    raise exception 'Exact Work grant list visibility is incorrect: %',v_list;
  end if;

  -- Organization scope can deliberately widen the same actor's authority.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000001',
    true
  );

  v_grant:=atlas.set_company_work_adjudication_authority_self_api_v1(
    'f4b00000-0000-4000-8000-000000000032'::uuid,
    'organization',
    'f4b00000-0000-4000-8000-000000000020'::uuid,
    true,
    'grant organization-wide adjudication for clone proof'
  );

  if v_grant->>'scopeKind'<>'organization'
     or v_grant->>'grantBasisKind'<>'explicit_owner_grant' then
    raise exception 'Organization adjudication grant was not established: %',v_grant;
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000002',
    true
  );

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4b00000-0000-4000-8000-000000000112'::uuid,
    'f4b00000-0000-4000-8000-000000000032'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,false)=false
     or v_authority->>'scopeKind'<>'organization' then
    raise exception 'Organization grant did not authorize sibling Work: %',v_authority;
  end if;

  -- Unrelated member still has no decision authority.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000003',
    true
  );

  begin
    perform atlas.company_work_result_decision_requirement_self_api_v1(
      'f4b00000-0000-4000-8000-000000000111'::uuid
    );
    raise exception 'Unrelated member saw grant-governed Decision Requirement.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Grant revocation closes authority without rewriting the original grant.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000001',
    true
  );

  perform atlas.set_company_work_adjudication_authority_self_api_v1(
    'f4b00000-0000-4000-8000-000000000032'::uuid,
    'work_item',
    'f4b00000-0000-4000-8000-000000000101'::uuid,
    false,
    'revoke exact grant to prove revocation'
  );

  -- Organization grant still admits A after exact grant revocation.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000002',
    true
  );

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    'f4b00000-0000-4000-8000-000000000111'::uuid,
    'f4b00000-0000-4000-8000-000000000032'::uuid
  );

  if coalesce((v_authority->>'authorized')::boolean,false)=false
     or v_authority->>'scopeKind'<>'organization' then
    raise exception 'Fallback to active Organization grant failed after exact-grant revocation: %',v_authority;
  end if;

  -- Human decision now crosses only the grant-governed command.
  v_decision:=atlas.organization_decide_company_work_result_self_api_v1(
    'f4b00000-0000-4000-8000-000000000111'::uuid,
    'accepted',
    'explicit adjudication authority clone proof'
  );

  if v_decision->>'state'<>'decided'
     or v_decision->>'decision'<>'accepted'
     or v_decision->>'companyWorkState'<>'completed'
     or nullif(v_decision->>'authorityGrantId','') is null then
    raise exception 'Grant-governed Company Work decision failed: %',v_decision;
  end if;

  select * into v_acceptance
  from atlas.work_result_acceptances a
  where a.execution_result_id='f4b00000-0000-4000-8000-000000000111'::uuid;

  if v_acceptance.acceptance_kind<>'institutional_adjudication_authority'
     or v_acceptance.metadata->>'explicitAdjudicationAuthority'<>'true'
     or nullif(v_acceptance.evidence->>'authorityGrantId','') is null
     or v_acceptance.evidence->>'authorityGrantBasisKind'<>'explicit_owner_grant'
     or v_acceptance.evidence->>'authorityScopeKind'<>'organization' then
    raise exception 'Result Acceptance did not preserve adjudication authority provenance: %',row_to_json(v_acceptance);
  end if;

  v_plan:=atlas.company_work_result_reconciliation_plan_v1(
    'f4b00000-0000-4000-8000-000000000111'::uuid
  );

  if jsonb_array_length(v_plan->'targets')<>0 then
    raise exception 'Grant-governed Result decision did not reconcile to settled: %',v_plan;
  end if;

  v_list:=atlas.company_work_decision_requirements_self_api_v1(50);

  if (v_list->>'count')::integer<>1
     or v_list#>>'{items,0,source,ref}'
        <>'f4b00000-0000-4000-8000-000000000112' then
    raise exception 'Settled Result did not disappear while unresolved sibling remained: %',v_list;
  end if;

  -- Old owner RPC is only a compatibility entry and cannot bypass grant authority.
  perform set_config(
    'request.jwt.claim.sub',
    'f4b00000-0000-4000-8000-000000000001',
    true
  );

  begin
    perform atlas.organization_owner_decide_company_work_result_api_v1(
      'f4b00000-0000-4000-8000-000000000112'::uuid,
      'accepted',
      'owner wrapper without owner grant must fail'
    );
    raise exception 'Owner compatibility wrapper bypassed explicit adjudication grant.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Raw grant table remains outside browser access.
  if has_table_privilege('authenticated','atlas.company_work_adjudication_authority_grants','SELECT')
     or has_table_privilege('authenticated','atlas.company_work_adjudication_authority_grants','INSERT')
     or has_table_privilege('authenticated','atlas.company_work_adjudication_authority_grants','UPDATE')
     or has_table_privilege('anon','atlas.company_work_adjudication_authority_grants','SELECT') then
    raise exception 'Company Work adjudication grant table leaked to browser roles.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.company_work_result_adjudication_authority_v1(uuid,uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)',
       'EXECUTE'
     ) then
    raise exception 'Company Work adjudication RPC privilege boundary is incorrect.';
  end if;

  -- Decision command has no role shortcut.
  select lower(pg_get_functiondef(
    'atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)'::regprocedure
  )) into v_def;

  if v_def like '%role=''owner''%'
     or v_def like '%is_effective_organization_owner_v1%'
     or v_def like '%farm_memberships%'
     or v_def not like '%company_work_result_adjudication_authority_v1%' then
    raise exception 'Grant-governed Result decision still contains a role/adapter shortcut.';
  end if;

  -- Decision Requirement self read uses the same canonical authority resolver.
  select lower(pg_get_functiondef(
    'atlas.company_work_result_decision_requirement_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def not like '%company_work_result_adjudication_authority_v1%'
     or v_def like '%role=''owner''%'
     or v_def like '%farm_memberships%' then
    raise exception 'Decision Requirement self read diverged from canonical adjudication authority.';
  end if;

  -- No universal authority/approval queue was introduced.
  if to_regclass('atlas.institutional_authority_grants') is not null
     or to_regclass('atlas.decision_authority_grants') is not null
     or to_regclass('atlas.approval_queue') is not null
     or to_regclass('atlas.decision_queue') is not null then
    raise exception 'Company Work adjudication tranche introduced forbidden universal authority/queue storage.';
  end if;
end;
$validation$;

rollback;
