-- Identity-free postconditions for Personal Reality -> Household Claim Route v1.

do $$
declare
  v_guard_def text;
  v_writer_def text;
  v_apply_def text;
begin
  select pg_get_functiondef(
    'atlas.guard_personal_reality_household_claim_scope_v1()'::regprocedure
  ) into v_guard_def;

  select pg_get_functiondef(
    'atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)'::regprocedure
  ) into v_writer_def;

  select pg_get_functiondef(
    'atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::regprocedure
  ) into v_apply_def;

  if v_guard_def is null or v_writer_def is null or v_apply_def is null then
    raise exception 'Household Personal Reality claim route functions are missing.';
  end if;

  if position('new.scope_kind=''person''' in v_guard_def)=0
     or position('new.source_kind=''personal_reality_claim''' in v_guard_def)=0
     or position('new.subject_domain like ''household.%''' in v_guard_def)=0 then
    raise exception 'Legacy person-route fail-closed guard is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='claim_records'
      and t.tgname='personal_reality_household_claim_scope_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Personal Reality Household claim scope guard trigger is missing.';
  end if;

  if position('sourceEvidenceScope' in v_writer_def)=0
     or position('rawTestimonyNotCopied' in v_writer_def)=0
     or position('crossScopeClaimEvidenceLinkCreated' in v_writer_def)=0 then
    raise exception 'Household promotion writer does not preserve cross-scope provenance boundary.';
  end if;

  if position('insert into atlas.claim_evidence_links' in v_writer_def)=0 then
    raise exception 'Household promotion writer does not link same-scope interpretation Evidence.';
  end if;

  if position('record_current_household_claim_from_capture_evidence_v1' in v_apply_def)=0
     or position('Household Personal Reality correction must remain on the same subject.' in v_apply_def)=0 then
    raise exception 'Household Personal Reality apply route is not bound to same-subject Household promotion.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute internal Household capture promotion writer.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Household Personal Reality apply route.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not execute Household Personal Reality apply route.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Household Personal Reality apply RPC registry entry is missing or incorrect.';
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
      ('atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)'::text)
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

