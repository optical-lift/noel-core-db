-- Read-only source/ACL postconditions for held private executor candidate.
-- No real source, user, profile, media, publication or listener is written.
DO $private_executor_postconditions$
DECLARE
  role_name text := 'transcript_core_private_callback_executor_v1';
  f regprocedure;
  original regprocedure :=
    'transcript_core.register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)'::regprocedure;
  completion regprocedure :=
    'transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)'::regprocedure;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles r WHERE r.rolname=role_name
      AND NOT r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolbypassrls
      AND NOT r.rolcreaterole AND NOT r.rolcreatedb AND NOT r.rolreplication
  ) THEN RAISE EXCEPTION 'Missing or overpowered NOLOGIN private executor'; END IF;
  IF NOT has_schema_privilege(role_name,'transcript_core_callback_v1','USAGE')
     OR has_schema_privilege(role_name,'transcript_core_callback_v1','CREATE')
     OR has_schema_privilege(role_name,'transcript_core','USAGE')
     OR has_schema_privilege(role_name,'auth','USAGE')
     OR has_schema_privilege(role_name,'storage','USAGE')
     OR has_schema_privilege('anon','transcript_core_callback_v1','USAGE')
     OR has_schema_privilege('authenticated','transcript_core_callback_v1','USAGE')
     OR has_schema_privilege('service_role','transcript_core_callback_v1','USAGE')
  THEN RAISE EXCEPTION 'Dedicated callback schema boundary or client grants changed'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='transcript_core_callback_v1')<>2
  THEN RAISE EXCEPTION 'Dedicated callback namespace must contain exactly two functions'; END IF;
  IF has_function_privilege(role_name,original,'EXECUTE')
     OR has_function_privilege(role_name,completion,'EXECUTE')
  THEN RAISE EXCEPTION 'Private role must not invoke original invoker functions'; END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='transcript_core'
    AND c.relkind IN ('r','p','v','m','f')
    AND (has_table_privilege(role_name,c.oid,'SELECT') OR
         has_table_privilege(role_name,c.oid,'INSERT') OR
         has_table_privilege(role_name,c.oid,'UPDATE') OR
         has_table_privilege(role_name,c.oid,'DELETE'))
  ) THEN RAISE EXCEPTION 'Private executor acquired direct source table privilege'; END IF;

  FOREACH f IN ARRAY ARRAY[
    'transcript_core_callback_v1.private_register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)'::regprocedure,
    'transcript_core_callback_v1.private_complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)'::regprocedure
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.oid=f AND p.prosecdef
        AND pg_get_userbyid(p.proowner)='postgres'
        AND p.proconfig @> ARRAY['search_path=pg_catalog']::text[]
    ) THEN RAISE EXCEPTION 'Private callback wrapper owner/definer/search_path mismatch'; END IF;
    IF NOT has_function_privilege(role_name,f,'EXECUTE')
       OR has_function_privilege('anon',f,'EXECUTE')
       OR has_function_privilege('authenticated',f,'EXECUTE')
       OR has_function_privilege('service_role',f,'EXECUTE')
    THEN RAISE EXCEPTION 'Private callback wrapper grant escaped executor'; END IF;
  END LOOP;
  IF (
    SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='transcript_core_callback_v1'
      AND has_function_privilege(role_name,p.oid,'EXECUTE')
  )<>2 THEN RAISE EXCEPTION 'Private executor has more than the two fixed callbacks'; END IF;
END $private_executor_postconditions$;
