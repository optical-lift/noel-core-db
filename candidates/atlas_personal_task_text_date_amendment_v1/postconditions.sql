-- Read-only postconditions, for disposable production-shaped clone only.
DO $check$
DECLARE
 rd oid:=to_regprocedure('atlas.read_personal_task_text_date_self_api_v1(uuid)');
 wr oid:=to_regprocedure('atlas.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)');
 pubrd oid:=to_regprocedure('public.read_personal_task_text_date_self_api_v1(uuid)');
 pubwr oid:=to_regprocedure('public.amend_personal_task_text_date_self_api_v1(uuid,bigint,text,date)');
 body text;
BEGIN
 IF rd IS NULL OR wr IS NULL OR pubrd IS NULL OR pubwr IS NULL
 THEN RAISE EXCEPTION 'Missing exact personal task RPC'; END IF;
 IF NOT (SELECT prosecdef AND provolatile='s' FROM pg_proc WHERE oid=rd)
 OR NOT (SELECT prosecdef AND provolatile='v' FROM pg_proc WHERE oid=wr)
 OR (SELECT prosecdef FROM pg_proc WHERE oid=pubrd)
 OR (SELECT prosecdef FROM pg_proc WHERE oid=pubwr)
 THEN RAISE EXCEPTION 'Signed internal reader/writer or invoker transport invalid'; END IF;
 IF has_function_privilege('anon',pubrd,'EXECUTE')
 OR has_function_privilege('anon',pubwr,'EXECUTE')
 OR NOT has_function_privilege('authenticated',pubrd,'EXECUTE')
 OR NOT has_function_privilege('authenticated',pubwr,'EXECUTE')
 THEN RAISE EXCEPTION 'Transport grants invalid'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_attribute
  WHERE attrelid='atlas.task_entries'::regclass
  AND attname='amendment_revision' AND attnotnull)
 THEN RAISE EXCEPTION 'Source revision absent'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class
  WHERE oid='atlas.personal_task_amendment_events_v1'::regclass)
 OR has_table_privilege('authenticated','atlas.personal_task_amendment_events_v1','SELECT')
 THEN RAISE EXCEPTION 'Private amendment events exposed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.personal_task_amendment_events_v1'::regclass
  AND confrelid='atlas.task_entries'::regclass AND confdeltype='c')
 THEN RAISE EXCEPTION 'Permanent original task deletion no longer cascades'; END IF;
 body:=pg_get_functiondef(wr);
 IF strpos(body,'FOR UPDATE')=0
 OR strpos(body,'amendment_revision<>p_expected_revision')=0
 OR strpos(body,'source_object_type=''personal_dated_task''')=0
 THEN RAISE EXCEPTION 'Original source custody guard absent'; END IF;
END
$check$;
