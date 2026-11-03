-- Read-only postconditions for a disposable production-schema clone.
DO $check$
DECLARE
 w oid:=to_regprocedure('atlas.append_personal_task_progress_self_api_v1(uuid,uuid,text)');
 r oid:=to_regprocedure('atlas.read_personal_task_progress_self_api_v1(uuid,integer,timestamp with time zone,uuid)');
 pw oid:=to_regprocedure('public.append_personal_task_progress_self_api_v1(uuid,uuid,text)');
 pr oid:=to_regprocedure('public.read_personal_task_progress_self_api_v1(uuid,integer,timestamp with time zone,uuid)');
 body text;
BEGIN
 IF w IS NULL OR r IS NULL OR pw IS NULL OR pr IS NULL
 THEN RAISE EXCEPTION 'Original personal progress RPC absent'; END IF;
 IF NOT (SELECT prosecdef AND provolatile='v' FROM pg_proc WHERE oid=w)
 OR NOT (SELECT prosecdef AND provolatile='s' FROM pg_proc WHERE oid=r)
 OR (SELECT prosecdef FROM pg_proc WHERE oid=pw)
 OR (SELECT prosecdef FROM pg_proc WHERE oid=pr)
 THEN RAISE EXCEPTION 'Progress function privilege mode invalid'; END IF;
 IF has_function_privilege('anon',pw,'EXECUTE')
 OR has_function_privilege('anon',pr,'EXECUTE')
 OR NOT has_function_privilege('authenticated',pw,'EXECUTE')
 OR NOT has_function_privilege('authenticated',pr,'EXECUTE')
 THEN RAISE EXCEPTION 'Personal progress exposed to unauthenticated users'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class
   WHERE oid='atlas.personal_task_progress_events_v1'::regclass)
 OR has_table_privilege('authenticated','atlas.personal_task_progress_events_v1','SELECT')
 OR has_table_privilege('authenticated','atlas.personal_task_progress_events_v1','INSERT')
 THEN RAISE EXCEPTION 'Private source-linked progress table exposed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
   WHERE conrelid='atlas.personal_task_progress_events_v1'::regclass
     AND confrelid='atlas.task_entries'::regclass AND confdeltype='c')
 THEN RAISE EXCEPTION 'Original deletion must cascade private progress'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
   WHERE conrelid='atlas.personal_task_progress_events_v1'::regclass
     AND conname='personal_task_progress_owner_action_v1' AND contype='u')
 THEN RAISE EXCEPTION 'One action can duplicate across originals'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger
   WHERE tgrelid='atlas.personal_task_progress_events_v1'::regclass
     AND tgname='personal_task_progress_immutable_v1' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'Durable progress update protection absent'; END IF;
 body:=pg_get_functiondef(w);
 IF strpos(body,'FOR UPDATE')=0
 OR strpos(body,'owner_user_id=auth.uid()')=0
 OR strpos(body,'require_active_task_principal_v1')=0
 OR strpos(body,'v_task.status<>''open''')=0
 OR strpos(body,'source_object_type=''personal_dated_task''')=0
 OR strpos(body,'source_action_id=p_source_action_id')=0
 THEN RAISE EXCEPTION 'Source identity or custody guard absent'; END IF;
END
$check$;
