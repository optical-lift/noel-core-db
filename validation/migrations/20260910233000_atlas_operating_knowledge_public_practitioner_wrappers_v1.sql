do $$
declare
  v_name text;
  v_oid oid;
begin
  foreach v_name in array array[
    'operating_knowledge_workbench_self_api_v1',
    'propose_operating_knowledge_practitioner_self_api_v1',
    'revise_operating_knowledge_candidate_practitioner_self_v1',
    'add_operating_knowledge_evidence_practitioner_self_v1',
    'adjudicate_operating_knowledge_practitioner_self_v1',
    'replace_operating_knowledge_practitioner_self_api_v1'
  ] loop
    select p.oid into v_oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name;

    if v_oid is null then
      raise exception 'Expected public Operating Knowledge wrapper %', v_name;
    end if;
    if not has_function_privilege('authenticated',v_oid,'execute') then
      raise exception 'authenticated must be able to execute public wrapper %', v_name;
    end if;
    if has_function_privilege('anon',v_oid,'execute') then
      raise exception 'anon must not execute public wrapper %', v_name;
    end if;
    v_oid := null;
  end loop;
end;
$$;
