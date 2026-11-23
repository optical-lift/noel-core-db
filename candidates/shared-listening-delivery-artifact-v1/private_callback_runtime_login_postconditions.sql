-- HELD source-only/read-only strict runtime role ACL postconditions.
-- Run on fictional PG17 or disposable full production-schema clone ONLY.
DO $runtime_postconditions$
DECLARE
  runtime text := 'transcript_core_private_callback_runtime_v1';
  executor text := 'transcript_core_private_callback_executor_v1';
  f regprocedure;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles r JOIN pg_authid a ON a.oid=r.oid
    WHERE r.rolname=runtime AND r.rolcanlogin AND NOT r.rolinherit
      AND NOT r.rolsuper AND NOT r.rolbypassrls
      AND NOT r.rolcreaterole AND NOT r.rolcreatedb AND NOT r.rolreplication
      AND a.rolpassword IS NULL
  ) THEN RAISE EXCEPTION 'Runtime login must be powerless and passwordless'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles r WHERE r.rolname=executor
      AND NOT r.rolcanlogin AND NOT r.rolinherit
  ) THEN RAISE EXCEPTION 'Executor changed from NOLOGIN NOINHERIT'; END IF;

  -- EXACTLY one membership: SET-only into fixed executor, never inherited,
  -- never administrative, no unrelated role memberships or role delegates.
  IF (SELECT count(*)
      FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member
      WHERE r.rolname=runtime) <> 1 OR
     -- PostgreSQL 17 creator custody can include one inert
     -- postgres -> runtime administration edge: ADMIN TRUE but
     -- SET FALSE and INHERIT FALSE. Isolated fixtures may have zero.
     -- Reject extra edges or any different privilege-bearing member.
     (SELECT count(*)
      FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.roleid
      WHERE r.rolname=runtime) > 1 OR
     EXISTS (
       SELECT 1 FROM pg_auth_members m
       JOIN pg_roles r ON r.oid=m.roleid
       JOIN pg_roles u ON u.oid=m.member
       WHERE r.rolname=runtime
         AND NOT (u.rolname='postgres' AND m.admin_option
                  AND NOT m.inherit_option AND NOT m.set_option)
     ) OR
     NOT EXISTS (
       SELECT 1 FROM pg_auth_members m
       JOIN pg_roles r ON r.oid=m.roleid
       JOIN pg_roles u ON u.oid=m.member
       WHERE r.rolname=executor AND u.rolname=runtime
         AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option
     )
  THEN RAISE EXCEPTION 'Private runtime acquired unexpected role membership'; END IF;
  IF NOT pg_has_role(runtime,executor,'SET')
     OR pg_has_role(runtime,executor,'USAGE')
     OR pg_has_role('anon',executor,'SET')
     OR pg_has_role('authenticated',executor,'SET')
     OR pg_has_role('service_role',executor,'SET')
  THEN RAISE EXCEPTION 'SET authority or client denial changed'; END IF;

  IF has_schema_privilege(runtime,'transcript_core_callback_v1','USAGE')
     OR has_schema_privilege(runtime,'transcript_core','USAGE')
     OR has_schema_privilege(runtime,'auth','USAGE')
     OR has_schema_privilege(runtime,'storage','USAGE')
     OR has_schema_privilege(runtime,'public','CREATE')
  THEN RAISE EXCEPTION 'Direct runtime schema privilege escaped'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('transcript_core','auth','storage')
      AND c.relkind IN ('r','p','v','m','f')
      AND (has_table_privilege(runtime,c.oid,'SELECT')
        OR has_table_privilege(runtime,c.oid,'INSERT')
        OR has_table_privilege(runtime,c.oid,'UPDATE')
        OR has_table_privilege(runtime,c.oid,'DELETE'))
  ) THEN RAISE EXCEPTION 'Private runtime has direct source table privileges'; END IF;
  -- PostgreSQL roles inherit the baseline grants held by PUBLIC, even
  -- when NOINHERIT is specified. The fresh login MUST NOT expose any
  -- directly callable non-system function unavailable to the existing
  -- anonymous role before an explicit SET LOCAL ROLE to the executor.
  -- This compares effective schema USAGE AND function EXECUTE, not EXECUTE
  -- alone; public SECURITY DEFINER functions remain baseline existing
  -- surface, not newly claimed as one of the two private callbacks.
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname NOT IN ('pg_catalog','information_schema')
      AND has_schema_privilege(runtime,n.oid,'USAGE')
      AND has_function_privilege(runtime,p.oid,'EXECUTE')
      AND NOT (
        has_schema_privilege('anon',n.oid,'USAGE')
        AND has_function_privilege('anon',p.oid,'EXECUTE')
      )
  ) THEN RAISE EXCEPTION 'Runtime direct function surface exceeds anonymous baseline'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname NOT IN ('pg_catalog','information_schema')
      AND c.relkind IN ('r','p','v','m','f')
      AND (
        (has_table_privilege(runtime,c.oid,'SELECT')
         AND NOT has_table_privilege('anon',c.oid,'SELECT'))
        OR (has_table_privilege(runtime,c.oid,'INSERT')
         AND NOT has_table_privilege('anon',c.oid,'INSERT'))
        OR (has_table_privilege(runtime,c.oid,'UPDATE')
         AND NOT has_table_privilege('anon',c.oid,'UPDATE'))
        OR (has_table_privilege(runtime,c.oid,'DELETE')
         AND NOT has_table_privilege('anon',c.oid,'DELETE'))
      )
  ) THEN RAISE EXCEPTION 'Runtime direct table surface exceeds anonymous baseline'; END IF;

  FOREACH f IN ARRAY ARRAY[
    'transcript_core_callback_v1.private_register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)'::regprocedure,
    'transcript_core_callback_v1.private_complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)'::regprocedure
  ] LOOP
    IF has_function_privilege(runtime,f,'EXECUTE')
    THEN RAISE EXCEPTION 'Runtime can execute wrapper without SET ROLE'; END IF;
  END LOOP;
END $runtime_postconditions$;
