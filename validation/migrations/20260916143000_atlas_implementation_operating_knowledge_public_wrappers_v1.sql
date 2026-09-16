do $validation$
declare
  v_row record;
  v_public_oid oid;
  v_atlas_oid oid;
  v_public_def text;
  v_public_secdef boolean;
  v_atlas_secdef boolean;
  v_public_execute boolean;
  v_named_count integer;
begin
  for v_row in
    select *
    from (values
      (
        'public.implementation_operating_knowledge_self_api_v1(uuid)',
        'atlas.implementation_operating_knowledge_self_api_v1(uuid)',
        'implementation_operating_knowledge_self_api_v1'
      ),
      (
        'public.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)',
        'atlas.propose_implementation_operating_knowledge_self_api_v1(uuid,uuid,text,text,text,text,text,jsonb,jsonb,integer,numeric,text,text)',
        'propose_implementation_operating_knowledge_self_api_v1'
      ),
      (
        'public.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric)',
        'atlas.revise_implementation_operating_knowledge_candidate_self_v1(uuid,uuid,text,text,jsonb,jsonb,integer,numeric)',
        'revise_implementation_operating_knowledge_candidate_self_v1'
      ),
      (
        'public.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)',
        'atlas.replace_implementation_operating_knowledge_self_api_v1(uuid,uuid,uuid,text,text,jsonb,jsonb,integer,numeric,text,text)',
        'replace_implementation_operating_knowledge_self_api_v1'
      ),
      (
        'public.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamptz)',
        'atlas.add_implementation_operating_knowledge_evidence_self_v1(uuid,uuid,text,text,jsonb,jsonb,text,timestamptz)',
        'add_implementation_operating_knowledge_evidence_self_v1'
      ),
      (
        'public.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamptz)',
        'atlas.adjudicate_implementation_operating_knowledge_self_v1(uuid,uuid,text,text,text,timestamptz)',
        'adjudicate_implementation_operating_knowledge_self_v1'
      )
    ) as expected(public_signature, atlas_signature, function_name)
  loop
    v_public_oid := to_regprocedure(v_row.public_signature);
    v_atlas_oid := to_regprocedure(v_row.atlas_signature);

    if v_public_oid is null then
      raise exception 'Expected public implementation Operating Knowledge wrapper %', v_row.public_signature;
    end if;
    if v_atlas_oid is null then
      raise exception 'Expected underlying Atlas implementation Operating Knowledge authority %', v_row.atlas_signature;
    end if;

    select p.prosecdef, pg_get_functiondef(p.oid)
      into v_public_secdef, v_public_def
    from pg_proc p
    where p.oid = v_public_oid;

    select p.prosecdef
      into v_atlas_secdef
    from pg_proc p
    where p.oid = v_atlas_oid;

    if v_public_secdef then
      raise exception 'Public implementation Operating Knowledge wrapper must remain SECURITY INVOKER: %', v_row.public_signature;
    end if;
    if not v_atlas_secdef then
      raise exception 'Underlying Atlas implementation Operating Knowledge authority unexpectedly lost SECURITY DEFINER: %', v_row.atlas_signature;
    end if;
    if pg_get_function_result(v_public_oid) <> 'jsonb' then
      raise exception 'Public implementation Operating Knowledge wrapper must return jsonb: %', v_row.public_signature;
    end if;
    if position(('atlas.' || v_row.function_name || '(') in v_public_def) = 0 then
      raise exception 'Public implementation Operating Knowledge wrapper does not delegate to expected Atlas authority: %', v_row.public_signature;
    end if;

    if not has_function_privilege('authenticated', v_public_oid, 'execute') then
      raise exception 'authenticated must execute public implementation Operating Knowledge wrapper %', v_row.public_signature;
    end if;
    if not has_function_privilege('service_role', v_public_oid, 'execute') then
      raise exception 'service_role must execute public implementation Operating Knowledge wrapper %', v_row.public_signature;
    end if;
    if has_function_privilege('anon', v_public_oid, 'execute') then
      raise exception 'anon must not execute public implementation Operating Knowledge wrapper %', v_row.public_signature;
    end if;

    select exists (
      select 1
      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      where acl.grantee = 0
        and acl.privilege_type = 'EXECUTE'
    )
      into v_public_execute
    from pg_proc p
    where p.oid = v_public_oid;

    if v_public_execute then
      raise exception 'PUBLIC must not execute public implementation Operating Knowledge wrapper %', v_row.public_signature;
    end if;
  end loop;

  select count(*)
    into v_named_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'implementation_operating_knowledge_self_api_v1',
      'propose_implementation_operating_knowledge_self_api_v1',
      'revise_implementation_operating_knowledge_candidate_self_v1',
      'replace_implementation_operating_knowledge_self_api_v1',
      'add_implementation_operating_knowledge_evidence_self_v1',
      'adjudicate_implementation_operating_knowledge_self_v1'
    );

  if v_named_count <> 6 then
    raise exception 'Expected exactly six public implementation Operating Knowledge browser wrappers; found %', v_named_count;
  end if;
end;
$validation$;
