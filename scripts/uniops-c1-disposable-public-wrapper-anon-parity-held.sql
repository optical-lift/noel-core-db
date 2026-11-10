-- HELD CI ONLY. Exactly restore the three public wrapper anonymous ACLs
-- that were lost during disposable Supabase schema dump/restore. These three
-- anonymous EXECUTE denials are already present in live Noel production.
-- The source C1 postconditions, fixture, tables, Work and C2 code are intact.
-- Never include this file in a production migration or data/API release.
-- Requires the trusted controller's local-validator-only PGOPTIONS marker.
begin;

do $clone_c1_before$
declare
  v_match_count integer;
begin
  if current_setting('uni_ops.disposable_clone', true) is distinct from 'true'
     or current_database() <> 'postgres' then
    raise exception 'REFUSE C1 anon ACL parity outside disposable clone';
  end if;

  -- Exact observed clone precondition from owner-run #42839466786:
  -- public wrappers allow anon; atlas implementations deny anon;
  -- all six permit authenticated and deny implicit PUBLIC execution.
  select count(*) into v_match_count
  from (values
    ('atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure, false),
    ('atlas.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'::regprocedure, false),
    ('atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure, false),
    ('public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure, true),
    ('public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'::regprocedure, true),
    ('public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure, true)
  ) as t(func_oid,expected_anon)
  join pg_proc p on p.oid=t.func_oid
  where p.proacl is not null
    and has_function_privilege('anon',t.func_oid,'EXECUTE')=t.expected_anon
    and has_function_privilege('authenticated',t.func_oid,'EXECUTE')
    and not exists (
      select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.grantee=0 and acl.privilege_type='EXECUTE'
    );
  if v_match_count<>6 then
    raise exception 'REFUSE unexpected C1 six-function clone grant baseline';
  end if;
end
$clone_c1_before$;

-- Only remove the three excessive anonymous EXECUTE grants from the clone.
-- Never GRANT privileges or rewrite a security-invoker function.
revoke execute on function public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid) from anon;
revoke execute on function public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz) from anon;
revoke execute on function public.operating_requirements_owner_self_api_v1(uuid,uuid,integer) from anon;

do $clone_c1_after$
declare
  v_match_count integer;
begin
  -- All six must match the explicit least-privilege C1 production baseline.
  select count(*) into v_match_count
  from (values
    ('atlas.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure, false),
    ('atlas.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'::regprocedure, false),
    ('atlas.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure, false),
    ('public.establish_operating_requirement_owner_self_api_v1(uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid)'::regprocedure, false),
    ('public.revise_operating_requirement_owner_self_api_v1(uuid,uuid,jsonb,text,uuid,uuid,integer,text,timestamptz)'::regprocedure, false),
    ('public.operating_requirements_owner_self_api_v1(uuid,uuid,integer)'::regprocedure, false)
  ) as t(func_oid,expected_anon)
  join pg_proc p on p.oid=t.func_oid
  where p.proacl is not null
    and has_function_privilege('anon',t.func_oid,'EXECUTE')=t.expected_anon
    and has_function_privilege('authenticated',t.func_oid,'EXECUTE')
    and not exists (
      select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where acl.grantee=0 and acl.privilege_type='EXECUTE'
    );
  if v_match_count<>6 then
    raise exception 'REFUSE C1 clone ACL restoration did not restore parity';
  end if;
end
$clone_c1_after$;

commit;
