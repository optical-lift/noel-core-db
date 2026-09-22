begin;

do $validation$
declare
  v_case constant uuid := 'f4500000-0000-4000-8000-000000000111'::uuid;
  v_practitioner constant uuid := 'f4500000-0000-4000-8000-000000000001'::uuid;
  v_sponsor_participant constant uuid := 'f4500000-0000-4000-8000-000000000122'::uuid;
  v_visible_org constant uuid := 'f4500000-0000-4000-8000-000000000301'::uuid;
  v_outside_org constant uuid := 'f4500000-0000-4000-8000-000000000302'::uuid;
  v_visible_ledger constant uuid := 'f4500000-0000-4000-8000-000000000311'::uuid;
  v_entitlement constant uuid := 'f4500000-0000-4000-8000-000000000341'::uuid;
  v_practitioner_participant constant uuid := 'f4500000-0000-4000-8000-000000000121'::uuid;
  v_result jsonb;
  v_items jsonb;
  v_def text;
begin
  if to_regprocedure(
    'public.implementation_initial_scope_options_self_api_v1(uuid,text,integer)'
  ) is null then
    raise exception 'Public Initial Scope discovery membrane is missing.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  v_result:=public.implementation_initial_scope_options_self_api_v1(
    v_case,'Sponsor',25
  );

  if v_result->>'state'<>'ready'
     or not coalesce((v_result->>'canEstablishNewOrganization')::boolean,false) then
    raise exception 'Unbound verified case did not reach scope-discovery ready state: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'availableEntitlements','[]'::jsonb))<>1
     or (v_result->'availableEntitlements'->0->>'ledgerEntitlementId')::uuid<>v_entitlement then
    raise exception 'Available Ledger entitlement was not exposed for scope admission: %',v_result;
  end if;

  v_items:=coalesce(v_result->'items','[]'::jsonb);

  if jsonb_array_length(v_items)<>1
     or (v_items->0->>'organizationId')::uuid<>v_visible_org
     or (v_items->0->>'ledgerId')::uuid<>v_visible_ledger
     or not coalesce((v_items->0->>'availableForAdmission')::boolean,false) then
    raise exception 'Sponsor-governed existing scope was not resolved correctly: %',v_result;
  end if;

  if v_items @> jsonb_build_array(jsonb_build_object('organizationId',v_outside_org)) then
    raise exception 'Organization outside setup-sponsor Principal authority leaked into scope discovery.';
  end if;

  update atlas.implementation_case_participants
  set active=false,ended_at=now(),updated_at=now()
  where id=v_sponsor_participant;

  v_result:=public.implementation_initial_scope_options_self_api_v1(
    v_case,null,25
  );

  if v_result->>'state'<>'setup_sponsor_required'
     or coalesce((v_result->>'canEstablishNewOrganization')::boolean,false) then
    raise exception 'Scope discovery ignored missing verified setup sponsor: %',v_result;
  end if;

  update atlas.implementation_case_participants
  set active=true,ended_at=null,updated_at=now()
  where id=v_sponsor_participant;

  insert into atlas.ledger_entitlement_bindings(
    implementation_case_id,ledger_entitlement_id,organization_id,
    organization_unit_id,bound_by_participant_id,state,binding_basis,
    metadata,ledger_id
  ) values (
    v_case,v_entitlement,v_visible_org,null,v_practitioner_participant,
    'bound','{"validationFixture":true}'::jsonb,
    '{"validationFixture":true}'::jsonb,v_visible_ledger
  );

  update atlas.ledger_entitlements
  set state='bound',updated_at=now()
  where id=v_entitlement;

  v_result:=public.implementation_initial_scope_options_self_api_v1(
    v_case,null,25
  );

  if v_result->>'state'<>'bound'
     or jsonb_array_length(coalesce(v_result->'bindings','[]'::jsonb))<>1
     or (v_result->'bindings'->0->>'organizationId')::uuid<>v_visible_org
     or coalesce((v_result->>'canEstablishNewOrganization')::boolean,true) then
    raise exception 'Already-bound case did not stop initial-scope discovery: %',v_result;
  end if;

  if has_function_privilege(
       'anon',
       'public.implementation_initial_scope_options_self_api_v1(uuid,text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.implementation_initial_scope_options_self_api_v1(uuid,text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.implementation_initial_scope_options_self_api_v1(uuid,text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Initial Scope discovery leaked execution around the public practitioner membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.implementation_initial_scope_options_self_api_v1(uuid,text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute Initial Scope discovery membrane.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.implementation_initial_scope_options_self_api_v1(uuid,text,integer)'::regprocedure
  )) into v_def;

  if v_def not like '%implementation_practitioner_assigned_to_case_self_v1%'
     or v_def not like '%relationship_kind=''setup_sponsor''%'
     or v_def not like '%principal_ledger_authorities%'
     or v_def not like '%ledger_organization_participations%'
     or v_def not like '%authority_kind=''root_governing''%' then
    raise exception 'Initial Scope discovery lost practitioner, setup-sponsor, Principal, or Ledger authority boundary.';
  end if;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Initial Scope discovery contains mutation authority.';
  end if;

  if v_def not like '%price_class=''baseline_first''%' then
    raise exception 'Initial Scope discovery no longer restricts admission to the baseline-first Ledger entitlement.';
  end if;

  if v_def like '%livebindingcaseid%'
     or v_def like '%''livebindingid''%' then
    raise exception 'Initial Scope discovery exposes unrelated implementation binding identifiers.';
  end if;
end;
$validation$;

rollback;
