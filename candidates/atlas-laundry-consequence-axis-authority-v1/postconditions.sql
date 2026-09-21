-- Identity-free postconditions for Laundry Consequence Axis Authority v1.

do $$
declare
  v_carrier_def text;
  v_readiness_def text;
  v_guard_def text;
  v_reconcile_def text;
begin
  select pg_get_functiondef(
    'atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(uuid,uuid,uuid)'::regprocedure
  ) into v_carrier_def;

  select pg_get_functiondef(
    'atlas.personal_laundry_execution_readiness_from_claim_v1(uuid,uuid,uuid)'::regprocedure
  ) into v_readiness_def;

  select pg_get_functiondef(
    'atlas.guard_personal_laundry_consequence_axis_authority_v1()'::regprocedure
  ) into v_guard_def;

  select pg_get_functiondef(
    'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::regprocedure
  ) into v_reconcile_def;

  if v_carrier_def is null
     or v_readiness_def is null
     or v_guard_def is null
     or v_reconcile_def is null then
    raise exception 'Laundry consequence axis authority functions are missing.';
  end if;

  if position('ordinary_responsibility' in v_carrier_def)=0
     or position('sharedDoesNotMeanPrincipal' in v_carrier_def)=0
     or position('principal:' in v_carrier_def)=0 then
    raise exception 'Laundry carrier resolution boundary is incomplete.';
  end if;

  if position('execution_readiness' in v_readiness_def)=0
     or position('blockedDoesNotDeleteRequirement' in v_readiness_def)=0
     or position('unknownDoesNotBecomeReady' in v_readiness_def)=0 then
    raise exception 'Laundry readiness resolution boundary is incomplete.';
  end if;

  if position(
       'personal_laundry_carrier_resolution_from_responsibility_claim_v1'
       in lower(v_guard_def)
     )=0
     or position(
       'personal_laundry_execution_readiness_from_claim_v1'
       in lower(v_guard_def)
     )=0
     or position(
       'new.carrier_ref:=old.carrier_ref'
       in regexp_replace(lower(v_guard_def),'[[:space:]]+','','g')
     )=0
     or position(
       'new.carrier_state:=old.carrier_state'
       in regexp_replace(lower(v_guard_def),'[[:space:]]+','','g')
     )=0
     or position(
       'new.execution_readiness:=old.execution_readiness'
       in regexp_replace(lower(v_guard_def),'[[:space:]]+','','g')
     )=0
     or position(
       'new.placement_stateisdistinctfromold.placement_state'
       in regexp_replace(lower(v_guard_def),'[[:space:]]+','','g')
     )=0 then
    raise exception 'Laundry consequence axis persistence guard does not preserve source-backed carrier/readiness axes while excluding placement authority.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_consequence_instances'
      and t.tgname='person_life_laundry_consequence_axis_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Laundry consequence axis authority trigger is missing.';
  end if;

  if position('placement_state=v_new' in v_reconcile_def)>0
     or position('doesNotCreateClockPlacement' in v_reconcile_def)=0 then
    raise exception 'Laundry reconciliation improperly carries placement authority.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot reconcile owned Laundry consequence axes.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not reconcile Laundry consequence axes.';
  end if;
end
$$;

-- Candidate-scoped authenticated RPC custody proof.
do $$
declare
  v_bad_signature text;
begin
  with expected(signature) as (
    values
      ('atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)'::text)
  )
  select e.signature
  into v_bad_signature
  from expected e
  left join atlas.authenticated_rpc_registry r
    on r.signature=e.signature
  left join pg_proc p
    on p.oid=to_regprocedure(e.signature)::oid
  where r.signature is null
     or p.oid is null
     or r.review_status<>'active'
     or not r.authenticated_execute_expected
     or not r.security_definer_expected
     or not r.service_execute_expected
     or r.anonymous_execute_expected
     or not has_function_privilege('authenticated',p.oid,'EXECUTE')
     or not has_function_privilege('service_role',p.oid,'EXECUTE')
     or has_function_privilege('anon',p.oid,'EXECUTE')
     or p.prosecdef is distinct from true
  limit 1;

  if v_bad_signature is not null then
    raise exception 'Candidate authenticated RPC custody mismatch: %',v_bad_signature;
  end if;
end
$$;

