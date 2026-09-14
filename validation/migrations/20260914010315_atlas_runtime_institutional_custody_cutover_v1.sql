-- Behavioral postconditions for Atlas Runtime Institutional Custody Cutover v1.

do $function$
declare
  v_payload jsonb;
  v_item jsonb;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_work atlas.work_items%rowtype;
  v_count integer;
begin
  -- Lex: canonical Principal/owner authority.
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','10000000-0000-4000-8000-000000000001',
    'session_id','11000000-0000-4000-8000-000000000001',
    'role','authenticated'
  )::text,true);

  if atlas.current_organization_membership_v1('20000000-0000-4000-8000-000000000002'::uuid)
       is distinct from '51000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'Direct canonical Elm owner membership did not resolve.';
  end if;

  if atlas.current_organization_membership_v1('20000000-0000-4000-8000-000000000001'::uuid) is not null then
    raise exception 'Unresolved legacy owner membership still establishes current institutional membership.';
  end if;

  if not atlas.is_organization_owner('20000000-0000-4000-8000-000000000002'::uuid)
     or not atlas.is_organization_owner('20000000-0000-4000-8000-000000000003'::uuid)
     or atlas.is_organization_owner('20000000-0000-4000-8000-000000000001'::uuid) then
    raise exception 'Canonical Organization owner authority boundary is wrong.';
  end if;

  v_payload:=atlas.principal_ledgers_self_api_v1();
  if v_payload->>'contractVersion'<>'principal_ledgers_self_v2'
     or jsonb_array_length(v_payload->'items')<>2
     or exists (
       select 1 from jsonb_array_elements(v_payload->'items') x
       where x->>'ledgerId'='30000000-0000-4000-8000-000000000001'
     ) then
    raise exception 'Principal Ledger projection still exposes the active compatibility carrier.';
  end if;

  v_payload:=atlas.principal_self_context_api_v1();
  if v_payload->>'contractVersion'<>'principal_self_context_v3'
     or (v_payload->'principal'->>'organizationId') is not null
     or v_payload->'principal'->>'legacyCompatibilityOrganizationId'<>'20000000-0000-4000-8000-000000000001'
     or v_payload->'principal'->>'organizationIdSemantics'<>'legacy_compatibility_only'
     or jsonb_array_length(v_payload->'governedLedgers')<>2
     or jsonb_array_length(v_payload->'governedOrganizations')<>2 then
    raise exception 'Principal context did not cut over to the Principal/Ledger graph.';
  end if;

  if atlas.effective_work_item_organization_v1('70000000-0000-4000-8000-000000000001'::uuid)
       is distinct from '20000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'New compatibility-era Elm Company Work did not inherit canonical custody from the explicit Elm Unit.';
  end if;

  v_payload:=atlas.organization_work_accountability_self_api_v1();
  select value into v_item
  from jsonb_array_elements(v_payload->'pending')
  where value->>'workItemId'='70000000-0000-4000-8000-000000000001'
  limit 1;
  if v_item is null
     or v_item->>'organizationId'<>'20000000-0000-4000-8000-000000000002'
     or v_item->>'physicalOrganizationId'<>'20000000-0000-4000-8000-000000000001'
     or v_item->>'organizationName'<>'Elm Farm' then
    raise exception 'Company Work accountability did not present canonical Elm custody.';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_payload->'organizations') x
    where x->>'organizationId'='20000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'Company Work owner organizations still expose the compatibility carrier.';
  end if;

  if atlas.effective_communication_endpoint_organization_v1('80000000-0000-4000-8000-000000000001'::uuid)
       is distinct from '20000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'New compatibility-era Elm endpoint did not inherit canonical custody from the explicit Elm Unit.';
  end if;

  v_payload:=atlas.institutional_communications_home_self_api_v1();
  select value into v_item
  from jsonb_array_elements(v_payload->'items')
  where value->>'communicationEndpointId'='80000000-0000-4000-8000-000000000001'
  limit 1;
  if v_item is null
     or v_item->>'organizationId'<>'20000000-0000-4000-8000-000000000002'
     or v_item->>'physicalOrganizationId'<>'20000000-0000-4000-8000-000000000001'
     or v_item->>'organizationName'<>'Elm Farm'
     or (v_item->'sourceCapabilities'->>'communicationCapture')::boolean is not true
     or (v_item->'sourceCapabilities'->>'communicationSend')::boolean is not false then
    raise exception 'Correspondence presentation/transport boundary is wrong.';
  end if;

  -- Canonical authority decides preserved physical Company Work.
  v_payload:=atlas.organization_owner_decide_company_work_result_api_v1(
    '71000000-0000-4000-8000-000000000001'::uuid,'accepted','fixture acceptance'
  );
  if v_payload->>'state'<>'decided'
     or v_payload->>'organizationId'<>'20000000-0000-4000-8000-000000000002'
     or v_payload->>'physicalOrganizationId'<>'20000000-0000-4000-8000-000000000001' then
    raise exception 'Company Work decision did not authorize canonically while preserving physical custody.';
  end if;

  select * into v_acceptance
  from atlas.work_result_acceptances
  where execution_result_id='71000000-0000-4000-8000-000000000001'::uuid;
  if v_acceptance.id is null
     or v_acceptance.organization_id<>'20000000-0000-4000-8000-000000000001'::uuid
     or v_acceptance.evidence->>'authorityOrganizationId'<>'20000000-0000-4000-8000-000000000002'
     or v_acceptance.evidence->>'physicalOrganizationId'<>'20000000-0000-4000-8000-000000000001' then
    raise exception 'Company Work acceptance lost physical provenance or canonical authority evidence.';
  end if;

  select * into v_work from atlas.work_items where id='70000000-0000-4000-8000-000000000001'::uuid;
  if v_work.organization_id<>'20000000-0000-4000-8000-000000000001'::uuid or v_work.work_state<>'completed' then
    raise exception 'Company Work physical row was rehomed or failed governed completion.';
  end if;

  -- Anna: preserved physical employment presents canonical Elm.
  perform set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','10000000-0000-4000-8000-000000000002',
    'session_id','11000000-0000-4000-8000-000000000002',
    'role','authenticated'
  )::text,true);

  if atlas.current_organization_membership_v1('20000000-0000-4000-8000-000000000002'::uuid)
       is distinct from '51000000-0000-4000-8000-000000000003'::uuid
     or atlas.current_organization_membership_v1('20000000-0000-4000-8000-000000000001'::uuid) is not null
     or not atlas.is_organization_member('20000000-0000-4000-8000-000000000002'::uuid) then
    raise exception 'Anna effective membership boundary is wrong.';
  end if;

  v_payload:=atlas.organization_access_self_api_v1();
  select value into v_item
  from jsonb_array_elements(v_payload->'items')
  where value->>'employeeSeatId'='52000000-0000-4000-8000-000000000001'
  limit 1;
  if v_item is null
     or v_item->>'organizationId'<>'20000000-0000-4000-8000-000000000002'
     or v_item->>'organizationName'<>'Elm Farm'
     or v_item->>'physicalOrganizationId'<>'20000000-0000-4000-8000-000000000001'
     or v_item->>'organizationMembershipId'<>'51000000-0000-4000-8000-000000000003'
     or v_item->>'employeeSeatId'<>'52000000-0000-4000-8000-000000000001' then
    raise exception 'Employee access did not preserve durable identity while presenting canonical Elm.';
  end if;

  v_payload:=atlas.current_session_context_api_v1();
  if v_payload is null then raise exception 'Session context unexpectedly null.'; end if;
  if v_payload->'profile'->>'default_organization_id'<>'20000000-0000-4000-8000-000000000002'
     or v_payload->'profile'->>'physical_default_organization_id'<>'20000000-0000-4000-8000-000000000001' then
    raise exception 'Profile default Organization did not resolve through effective custody.';
  end if;
  select value into v_item
  from jsonb_array_elements(v_payload->'organizationMemberships')
  where value->>'id'='51000000-0000-4000-8000-000000000003'
  limit 1;
  if v_item is null
     or v_item->>'organization_id'<>'20000000-0000-4000-8000-000000000002'
     or v_item->>'physical_organization_id'<>'20000000-0000-4000-8000-000000000001'
     or v_item->'organization'->>'name'<>'Elm Farm' then
    raise exception 'Session membership did not resolve through effective custody.';
  end if;

  -- Feast Guild clean room remains empty.
  if exists(select 1 from atlas.organization_memberships where organization_id='20000000-0000-4000-8000-000000000003'::uuid)
     or exists(select 1 from atlas.work_items where organization_id='20000000-0000-4000-8000-000000000003'::uuid)
     or exists(select 1 from atlas.communication_endpoints where organization_id='20000000-0000-4000-8000-000000000003'::uuid) then
    raise exception 'Feast Guild clean-room boundary was violated.';
  end if;

  -- No outbound communication was manufactured.
  select count(*) into v_count from atlas.communication_outbound_operations;
  if v_count<>0 then raise exception 'Runtime custody cutover manufactured outbound communication.'; end if;

  -- Compatibility internals and custody helpers are not browser-executable.
  if has_function_privilege('authenticated','atlas.organization_access_physical_compatibility_internal_v1()','execute')
     or has_function_privilege('authenticated','atlas.current_session_context_physical_compatibility_internal_v1()','execute')
     or has_function_privilege('authenticated','atlas.principal_self_context_physical_compatibility_internal_v1()','execute')
     or has_function_privilege('authenticated','atlas.institutional_communications_home_physical_compatibility_internal_v1()','execute')
     or has_function_privilege('authenticated','atlas.effective_work_item_organization_v1(uuid)','execute')
     or has_function_privilege('authenticated','atlas.effective_communication_endpoint_organization_v1(uuid)','execute') then
    raise exception 'Browser role gained direct compatibility/custody execution.';
  end if;

  if not has_function_privilege('authenticated','atlas.organization_access_self_api_v1()','execute')
     or not has_function_privilege('authenticated','atlas.current_session_context_api_v1()','execute')
     or not has_function_privilege('authenticated','atlas.principal_self_context_api_v1()','execute')
     or not has_function_privilege('authenticated','atlas.institutional_communications_home_self_api_v1()','execute') then
    raise exception 'Public authenticated API execution was not restored.';
  end if;

  -- Trigger and FK contracts remain unchanged.
  if exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname in ('atlas','local_intel') and t.tgenabled='D'
  ) then
    raise exception 'A production/runtime user trigger is disabled.';
  end if;

  if (select count(*) from pg_constraint c join pg_class ch on ch.oid=c.conrelid join pg_namespace n on n.oid=ch.relnamespace
      where c.contype='f' and c.condeferrable and n.nspname in ('atlas','local_intel'))<>1
     or not exists(
       select 1 from pg_constraint c join pg_class ch on ch.oid=c.conrelid join pg_namespace n on n.oid=ch.relnamespace
       where n.nspname='atlas' and ch.relname='planned_work_occurrences'
         and c.conname='planned_work_occurrences_released_task_id_fkey'
         and c.contype='f' and c.condeferrable and c.condeferred
     ) then
    raise exception 'Foreign-key deferrability changed during runtime custody cutover.';
  end if;
end;
$function$;
