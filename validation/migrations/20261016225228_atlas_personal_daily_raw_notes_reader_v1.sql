-- Disposable two-Person native Atlas proof. No production writes.
do $test$
declare
  user_a uuid := '62000000-0000-4000-8000-000000000001';
  user_b uuid := '62000000-0000-4000-8000-000000000002';
  d date := (statement_timestamp() at time zone 'America/Chicago')::date;
  receipt jsonb;
  page_a jsonb;
  page_b jsonb;
  other_day jsonb;
  captured uuid;
  before_tasks bigint;
  after_tasks bigint;
begin
  if has_function_privilege('anon','public.personal_daily_raw_notes_self_api_v1(date)','EXECUTE')
    or not has_function_privilege('authenticated','public.personal_daily_raw_notes_self_api_v1(date)','EXECUTE')
    or has_function_privilege('authenticated','atlas.personal_daily_raw_notes_self_api_v1(date)','EXECUTE')
  then raise exception 'Daily source read privileges are not owner-constrained'; end if;
  perform set_config('request.jwt.claim.sub',user_a::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_a::text,'role','authenticated')::text,true);
  perform atlas.begin_personal_atlas_self_api_v1('Synthetic Daily Log A','America/Chicago');
  select count(*) into before_tasks from atlas.task_entries where owner_user_id=user_a;
  page_a:=public.personal_daily_raw_notes_self_api_v1(d);
  if page_a->>'ok'<>'true' or page_a->>'contractVersion'<>'personal_daily_raw_notes_self_v1'
    or jsonb_array_length(page_a->'items')<>0 then
    raise exception 'Empty daily notes not correctly read for owner A'; end if;
  receipt:=public.capture_personal_reality_self_api_v1(jsonb_build_object(
    'sourceActionId','clone:daily-note-1',
    'testimony','A first-person observation that must stay testimony.',
    'sourceSurface','personal_notebook_daily_log',
    'captureContext',jsonb_build_object('notebookDate',d::text,'entryKind','note','dateIsPageContextNotObservedAt',true),
    'metadata',jsonb_build_object('notebookEntryKind','raw_note','subjectUnresolved',true)
  ));
  if receipt->>'ok'<>'true' or receipt->>'contractVersion'<>'personal_reality_capture_v1' then
    raise exception 'Canonical capture did not produce first-party testimony'; end if;
  captured:=(receipt->>'captureId')::uuid;
  page_a:=public.personal_daily_raw_notes_self_api_v1(d);
  if page_a->>'total'<>'1'
    or page_a->>'truncated'<>'false'
    or page_a#>>'{items,0,id}'<>captured::text
    or page_a#>>'{items,0,text}'<>'A first-person observation that must stay testimony.'
    or page_a#>>'{items,0,subjectUnresolved}'<>'true' then
    raise exception 'Saved note did not reappear as same canonical evidence identity: %',page_a; end if;
  other_day:=public.personal_daily_raw_notes_self_api_v1(d+1);
  if other_day->>'total'<>'0' then raise exception 'Note leaked across diary dates'; end if;
  select count(*) into after_tasks from atlas.task_entries where owner_user_id=user_a;
  if after_tasks<>before_tasks then raise exception 'Raw capture created a task'; end if;
  perform set_config('request.jwt.claim.sub',user_b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_b::text,'role','authenticated')::text,true);
  perform atlas.begin_personal_atlas_self_api_v1('Synthetic Daily Log B','America/Chicago');
  page_b:=public.personal_daily_raw_notes_self_api_v1(d);
  if page_b->>'total'<>'0' or jsonb_array_length(page_b->'items')<>0 then
    raise exception 'Other Person received first owner''s observation'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  raise notice 'Personal day capture and owner-only source readback proved, no task inferred';
end
$test$;
