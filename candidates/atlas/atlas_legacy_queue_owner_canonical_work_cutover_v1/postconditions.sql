-- Source-only postconditions for protected disposable current-schema proof.
DO $queue_owner_post$
DECLARE reader oid;writer oid; transport_reader oid;transport_writer oid;
BEGIN
 reader:=to_regprocedure('atlas.company_work_legacy_queue_owner_self_api_v1(uuid,uuid,integer,uuid)');
 writer:=to_regprocedure('atlas.decide_company_work_legacy_queue_owner_self_api_v1(uuid,uuid,uuid,text,timestamptz,uuid,text,text,text,text,uuid)');
 transport_reader:=to_regprocedure('public.company_work_legacy_queue_owner_self_api_v1(uuid,uuid,integer,uuid)');
 transport_writer:=to_regprocedure('public.decide_company_work_legacy_queue_owner_self_api_v1(uuid,uuid,uuid,text,timestamptz,uuid,text,text,text,text,uuid)');
 IF reader IS NULL OR writer IS NULL OR transport_reader IS NULL OR transport_writer IS NULL THEN
   RAISE EXCEPTION 'Both private owner review RPCs and public transports required';
 END IF;
 IF EXISTS (
   SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid IN(transport_reader,transport_writer)
     AND (p.prosecdef OR p.proconfig IS NULL
       OR NOT ('search_path=""'=ANY(p.proconfig)))
 ) THEN RAISE EXCEPTION 'Public transport must be invoker-only with empty search path';
 END IF;
 IF EXISTS(
   SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid IN(reader,writer)
     AND (NOT p.prosecdef OR p.proconfig IS NULL
       OR NOT ('search_path=""'=ANY(p.proconfig)))
 ) THEN RAISE EXCEPTION 'Review RPC must be security definer with empty search_path';
 END IF;
 IF NOT has_function_privilege('authenticated',reader,'EXECUTE')
 OR NOT has_function_privilege('authenticated',writer,'EXECUTE')
 OR has_function_privilege('anon',reader,'EXECUTE')
 OR has_function_privilege('anon',writer,'EXECUTE')
 OR has_function_privilege('service_role',reader,'EXECUTE')
 OR has_function_privilege('service_role',writer,'EXECUTE')
 OR NOT has_function_privilege('authenticated',transport_reader,'EXECUTE')
 OR NOT has_function_privilege('authenticated',transport_writer,'EXECUTE')
 OR has_function_privilege('anon',transport_reader,'EXECUTE')
 OR has_function_privilege('anon',transport_writer,'EXECUTE')
 OR has_function_privilege('service_role',transport_reader,'EXECUTE')
 OR has_function_privilege('service_role',transport_writer,'EXECUTE')
 THEN RAISE EXCEPTION 'Owner RPC or public transport effective grants changed';
 END IF;
 IF (SELECT count(*) FROM atlas.tasks
   WHERE id IN (
     'e5200000-0000-4000-8000-000000000d11'::uuid,
     'e5200000-0000-4000-8000-000000000d12'::uuid,
     'e5200000-0000-4000-8000-000000000d13'::uuid))<>3
 OR (SELECT count(*) FROM atlas.task_release_queue_items
   WHERE id IN (
     'e5200000-0000-4000-8000-000000000d21'::uuid,
     'e5200000-0000-4000-8000-000000000d22'::uuid,
     'e5200000-0000-4000-8000-000000000d23'::uuid,
     'e5200000-0000-4000-8000-000000000d24'::uuid))<>4
 THEN RAISE EXCEPTION 'Synthetic original evidence lost';
 END IF;
 IF EXISTS (SELECT 1 FROM atlas.company_work_legacy_task_reviews_v1
   WHERE source_task_id IN (
     'e5200000-0000-4000-8000-000000000d11'::uuid,
     'e5200000-0000-4000-8000-000000000d12'::uuid,
     'e5200000-0000-4000-8000-000000000d13'::uuid))
 THEN RAISE EXCEPTION 'Original owner review unexpectedly pre-populated';
 END IF;
END;$queue_owner_post$;
