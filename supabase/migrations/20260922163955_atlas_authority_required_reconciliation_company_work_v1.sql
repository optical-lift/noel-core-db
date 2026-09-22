begin;

-- Atlas Authority-Required Reconciliation — Company Work Proof v1
--
-- Domain-local read projection over production-live Reality Reconciliation.
-- No generic decision queue, approval engine, authority grant, or mutation command.

create or replace function atlas.company_work_result_decision_requirement_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_plan jsonb;
  v_result atlas.work_execution_results%rowtype;
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_target jsonb;
  v_target_count integer := 0;
  v_authority_target_count integer := 0;
begin
  if p_execution_result_id is null then
    raise exception 'Company Work execution Result is required.'
      using errcode='22023';
  end if;

  select * into v_result
  from atlas.work_execution_results r
  where r.id=p_execution_result_id;

  if v_result.id is null then
    raise exception 'Company Work execution Result was not found.'
      using errcode='P0002';
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id
    and w.organization_id=v_result.organization_id;

  if v_work.id is null then
    raise exception 'Company Work item for execution Result was not found.'
      using errcode='P0002';
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_result.result_contract_key
    and p.active;

  v_plan:=atlas.company_work_result_reconciliation_plan_v1(v_result.id);
  v_target_count:=jsonb_array_length(coalesce(v_plan->'targets','[]'::jsonb));

  if v_target_count=0 then
    return jsonb_build_object(
      'contractVersion','company_work_result_decision_requirement_v1',
      'state','settled',
      'source',v_plan->'source',
      'work',jsonb_build_object(
        'workItemId',v_work.id,
        'organizationId',v_work.organization_id,
        'title',v_work.title
      ),
      'reportedResult',jsonb_strip_nulls(jsonb_build_object(
        'resultKind',v_result.result_kind,
        'reportedAt',v_result.reported_at
      )),
      'decision',null,
      'authorityRequirement',null,
      'reconciliationPlan',v_plan,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'doesNotDecide',true,
        'doesNotGrantAuthority',true,
        'doesNotCreateWork',true,
        'doesNotCreateQueueState',true,
        'doesNotExposeResultPayload',true
      )
    );
  end if;

  select count(*)::integer
    into v_authority_target_count
  from jsonb_array_elements(coalesce(v_plan->'targets','[]'::jsonb)) x(value)
  where value->>'handlingMode'='authority_required'
    and value#>>'{resolver,key}'='company_work_result_adjudication';

  select value into v_target
  from jsonb_array_elements(coalesce(v_plan->'targets','[]'::jsonb)) x(value)
  where value->>'handlingMode'='authority_required'
    and value#>>'{resolver,key}'='company_work_result_adjudication'
  limit 1;

  if v_authority_target_count<>1 or v_target_count<>1 then
    return jsonb_build_object(
      'contractVersion','company_work_result_decision_requirement_v1',
      'state','not_decision_requirement',
      'source',v_plan->'source',
      'work',jsonb_build_object(
        'workItemId',v_work.id,
        'organizationId',v_work.organization_id,
        'title',v_work.title
      ),
      'reportedResult',jsonb_strip_nulls(jsonb_build_object(
        'resultKind',v_result.result_kind,
        'reportedAt',v_result.reported_at
      )),
      'decision',null,
      'authorityRequirement',null,
      'reconciliationPlan',v_plan,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'doesNotDecide',true,
        'doesNotGrantAuthority',true,
        'doesNotCreateWork',true,
        'doesNotCreateQueueState',true,
        'doesNotExposeResultPayload',true
      )
    );
  end if;

  if v_policy.contract_key is null
     or v_policy.acceptance_mode<>'manager_acceptance' then
    raise exception 'Authority-required Company Work Result does not have the released manager-acceptance contract.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','company_work_result_decision_requirement_v1',
    'state','decision_required',
    'source',v_plan->'source',
    'work',jsonb_build_object(
      'workItemId',v_work.id,
      'organizationId',v_work.organization_id,
      'title',v_work.title
    ),
    'reportedResult',jsonb_strip_nulls(jsonb_build_object(
      'resultKind',v_result.result_kind,
      'reportedAt',v_result.reported_at
    )),
    'decision',jsonb_build_object(
      'kind','company_work_result_acceptance',
      'options',jsonb_build_array('accepted','rejected'),
      'command',jsonb_build_object(
        'key','organization_owner_decide_company_work_result',
        'signature','atlas.organization_owner_decide_company_work_result_api_v1(uuid,text,text)'
      )
    ),
    'authorityRequirement',jsonb_build_object(
      'dimension','institutional_adjudication_authority',
      'currentBasis','transitional_organization_owner_compatibility',
      'exactCurrentAuthorityMembrane','organization_owner_decide_company_work_result_api_v1'
    ),
    'reconciliation',jsonb_build_object(
      'handlingMode',v_target->>'handlingMode',
      'resolver',v_target->'resolver',
      'reason',v_target->'reason',
      'blockers',coalesce(v_target->'blockers','[]'::jsonb)
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotDecide',true,
      'doesNotGrantAuthority',true,
      'doesNotCreateWork',true,
      'doesNotCreateQueueState',true,
      'doesNotExposeResultPayload',true,
      'doesNotUseBroaderManagementCompatibility',true
    )
  );
end;
$function$;

comment on function atlas.company_work_result_decision_requirement_v1(uuid) is
  'Internal read-only Company Work proof for authority-required Reality Reconciliation. Converts only the exact company_work_result_adjudication target into a domain-local Decision Requirement and names the currently released owner-only result-acceptance command without invoking it or granting authority.';

revoke all on function atlas.company_work_result_decision_requirement_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.company_work_result_decision_requirement_self_api_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_requirement jsonb;
  v_organization_id uuid;
  v_owner_membership_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_requirement:=atlas.company_work_result_decision_requirement_v1(p_execution_result_id);
  v_organization_id:=nullif(v_requirement#>>'{work,organizationId}','')::uuid;

  if v_organization_id is null then
    raise exception 'Company Work decision requirement has no Organization authority scope.'
      using errcode='23514';
  end if;

  if not atlas.is_organization_owner(v_organization_id) then
    raise exception 'Organization owner result-adjudication authority required.'
      using errcode='42501';
  end if;

  select om.id into v_owner_membership_id
  from atlas.organization_memberships om
  where om.organization_id=v_organization_id
    and om.user_id=v_uid
    and om.active
    and om.role='owner'
  order by om.created_at,om.id
  limit 1;

  if v_owner_membership_id is null then
    raise exception 'Active Organization owner membership required.'
      using errcode='42501';
  end if;

  return v_requirement||jsonb_build_object(
    'actorAuthority',jsonb_build_object(
      'canDecide',v_requirement->>'state'='decision_required',
      'actorOrganizationMembershipId',v_owner_membership_id,
      'basis','transitional_organization_owner_compatibility',
      'matchesExactCurrentCommandAuthority',true
    )
  );
end;
$function$;

comment on function atlas.company_work_result_decision_requirement_self_api_v1(uuid) is
  'Actor-safe browser read for one Company Work Result Decision Requirement. It fails closed unless the signed-in actor matches the exact current owner authority of the existing result-acceptance command. It exposes no arbitrary Result payload and performs no decision.';

revoke all on function atlas.company_work_result_decision_requirement_self_api_v1(uuid)
  from public,anon;
grant execute on function atlas.company_work_result_decision_requirement_self_api_v1(uuid)
  to authenticated,service_role;


create or replace function atlas.company_work_decision_requirements_self_api_v1(
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_items jsonb:='[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if coalesce(p_limit,0)<1 or p_limit>100 then
    raise exception 'Decision Requirement limit must be between 1 and 100.'
      using errcode='22023';
  end if;

  select coalesce(
    jsonb_agg(q.requirement order by q.reported_at,q.execution_result_id),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      r.id execution_result_id,
      r.reported_at,
      atlas.company_work_result_decision_requirement_v1(r.id)
        || jsonb_build_object(
          'actorAuthority',jsonb_build_object(
            'canDecide',true,
            'actorOrganizationMembershipId',om.id,
            'basis','transitional_organization_owner_compatibility',
            'matchesExactCurrentCommandAuthority',true
          )
        ) requirement
    from atlas.work_execution_results r
    join atlas.work_items w
      on w.id=r.work_item_id
     and w.organization_id=r.organization_id
    join atlas.work_result_contract_policies p
      on p.contract_key=r.result_contract_key
     and p.active
     and p.acceptance_mode='manager_acceptance'
    join lateral (
      select owner_membership.id
      from atlas.organization_memberships owner_membership
      where owner_membership.organization_id=w.organization_id
        and owner_membership.user_id=v_uid
        and owner_membership.active
        and owner_membership.role='owner'
      order by owner_membership.created_at,owner_membership.id
      limit 1
    ) om on true
    where atlas.is_organization_owner(w.organization_id)
      and not exists (
        select 1
        from atlas.work_result_acceptances a
        where a.execution_result_id=r.id
      )
      and (
        atlas.company_work_result_decision_requirement_v1(r.id)->>'state'
      )='decision_required'
    order by r.reported_at,r.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','company_work_decision_requirements_self_v1',
    'items',v_items,
    'count',jsonb_array_length(v_items),
    'derivedProjection',true,
    'persistedQueue',false,
    'authorityBasis','transitional_organization_owner_compatibility',
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotDecide',true,
      'doesNotGrantAuthority',true,
      'doesNotCreateWork',true,
      'doesNotCreateQueueState',true,
      'doesNotExposeResultPayload',true
    )
  );
end;
$function$;

comment on function atlas.company_work_decision_requirements_self_api_v1(integer) is
  'Derived current-state list of Company Work Result Decision Requirements for which the signed-in actor matches the exact current owner-only result-acceptance authority. It is not a persisted queue and disappears as canonical reconciliation settles.';

revoke all on function atlas.company_work_decision_requirements_self_api_v1(integer)
  from public,anon;
grant execute on function atlas.company_work_decision_requirements_self_api_v1(integer)
  to authenticated,service_role;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
(
  'atlas.company_work_result_decision_requirement_v1(uuid)',
  'service_internal','verified','active',
  false,true,false,0,1,
  jsonb_build_object(
    'source','atlas_authority_required_reconciliation_company_work_v1',
    'purpose','Project a Company Work authority-required Reconciliation target into a domain-local Decision Requirement without executing or granting the decision.',
    'truthBoundary','Internal only. Read-only. No queue, Work, authority grant, Result payload disclosure, or mutation command invocation.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.company_work_result_decision_requirement_self_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,true,0,1,
  jsonb_build_object(
    'source','atlas_authority_required_reconciliation_company_work_v1',
    'purpose','Expose one minimal Company Work Result Decision Requirement only to a signed-in actor who matches the exact current owner-only result-acceptance authority.',
    'truthBoundary','Read-only current projection. Fails closed for non-owner actors and exposes no arbitrary Result payload.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.company_work_decision_requirements_self_api_v1(integer)',
  'app_endpoint','verified','active',
  true,true,true,0,1,
  jsonb_build_object(
    'source','atlas_authority_required_reconciliation_company_work_v1',
    'purpose','List current Company Work Result Decision Requirements for the exact current owner-authorized actor.',
    'truthBoundary','Derived projection only; no persisted queue or decision mutation.',
    'classificationRuleVersion',3
  ),
  false
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
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
