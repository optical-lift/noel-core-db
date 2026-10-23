-- Entire test uses synthetic roles, no production credentials.
do $test$ declare r jsonb; begin
 if has_function_privilege('anon','public.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)','EXECUTE')
  or not has_function_privilege('authenticated','public.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)','EXECUTE')
  or has_function_privilege('authenticated','atlas.person_period_source_history_self_api_v1(date,date,text,integer,date,timestamptz,text,uuid)','EXECUTE')
 then raise exception 'Function grant boundary incorrect'; end if;
end $test$;
set role authenticated;
do $test$ begin
 begin
  perform public.person_period_source_history_self_api_v1('2026-10-22','2026-10-23');
  raise exception 'Anonymous JWT was accepted';
 exception when insufficient_privilege then null;
 end;
end $test$;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select set_config('atlas.fixture_principal','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
do $test$
declare r jsonb; more jsonb; ids text[]; c jsonb;
begin
 r:=public.person_period_source_history_self_api_v1('2026-10-22','2026-10-23','UTC',100);
 if jsonb_array_length(r->'items')<>3 or r->>'hasMore'<>'false' then
  raise exception 'Expected two notes and one done task only: %',r;
 end if;
 if (select count(*) from jsonb_array_elements(r->'items') i where i->>'entryKind'='first_party_observation')<>2
  or (select count(*) from jsonb_array_elements(r->'items') i where i->>'entryKind'='personal_task_marked_complete')<>1
 then raise exception 'Source families collapsed'; end if;
 if exists(select 1 from jsonb_array_elements(r->'items') i where i->>'text' like 'Other Person%')
   or exists(select 1 from jsonb_array_elements(r->'items') i where i->>'text'='Still outstanding')
 then raise exception 'Foreign person or open task leaked'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'entryKind'='personal_task_marked_complete' and i->>'evidenceStanding'='task_status_only')
 then raise exception 'Task status was promoted to physical outcome'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'items') i where i->>'entryKind'='first_party_observation' and i->>'timeStanding'='page_context_only')
 then raise exception 'Notebook page was promoted to event time'; end if;
 r:=public.person_period_source_history_self_api_v1('2026-10-22','2026-10-23','UTC',1);
 if r->>'hasMore'<>'true' or jsonb_array_length(r->'items')<>1
   or r->'nextCursor' is null then raise exception 'First page incorrect: %',r; end if;
 c:=r->'nextCursor';
 more:=public.person_period_source_history_self_api_v1('2026-10-22','2026-10-23','UTC',1,
   (c->>'day')::date,(c->>'recordedAt')::timestamptz,c->>'kind',(c->>'sourceId')::uuid);
 if jsonb_array_length(more->'items')<>1
   or (more->'items'->0->'source'->>'id')=(r->'items'->0->'source'->>'id')
 then raise exception 'Cursor yielded duplicate/empty second page'; end if;
 begin
  perform public.person_period_source_history_self_api_v1('2026-10-23','2026-10-22','UTC');
  raise exception 'Inverted period accepted';
 exception when invalid_parameter_value then null;
 end;
 begin
  perform public.person_period_source_history_self_api_v1('2026-10-22','2026-10-23','UTC',201);
  raise exception 'Oversize limit accepted';
 exception when invalid_parameter_value then null;
 end;
end $test$;
reset role;
select 'PASS: source split, privacy, page time, cursor and grants in disposable PostgreSQL' as result;
