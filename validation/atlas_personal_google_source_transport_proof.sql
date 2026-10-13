-- Run ONLY in isolated scratch/protected schema clone after candidate SQL.
-- Contracts: no anon/authenticated/PUBLIC execution; service_role exactly.
do $check$
declare
  v_sig regprocedure;
  v_specs text[] := array[
    'public.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb)',
    'public.activate_provider_connection_service_v1(uuid,text,jsonb)'
  ];
  v_text text;
begin
  foreach v_text in array v_specs loop
    v_sig := to_regprocedure(v_text);
    if v_sig is null then
      raise exception 'Missing service transport membrane: %', v_text;
    end if;
    if has_function_privilege('anon',v_sig,'execute')
       or has_function_privilege('authenticated',v_sig,'execute') then
      raise exception 'Browser execution unexpectedly allowed: %', v_text;
    end if;
    if not has_function_privilege('service_role',v_sig,'execute') then
      raise exception 'Service transport cannot execute: %', v_text;
    end if;
    if exists (
      select 1 from pg_proc where oid=v_sig::oid and prosecdef
    ) then
      raise exception 'A forwarding transport may not escalate to SECURITY DEFINER: %', v_text;
    end if;
  end loop;
end;
$check$;
