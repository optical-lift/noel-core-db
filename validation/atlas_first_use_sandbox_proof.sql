\set ON_ERROR_STOP on
-- Genuine SQL execution in isolated PostgreSQL, with synthetic users only.
grant usage on schema atlas to authenticated;
do $$
begin
  if has_function_privilege('anon','public.create_atlas_task_self_api_v1(text,date,text)','EXECUTE')
     or has_function_privilege('anon','public.atlas_task_day_self_api_v1(date)','EXECUTE')
     or has_function_privilege('anon','public.set_atlas_task_done_self_api_v1(uuid,boolean)','EXECUTE') then
    raise exception 'anonymous task privilege leak';
  end if;
  if has_table_privilege('authenticated','atlas.task_entries','SELECT') then
    raise exception 'direct private task table access leak';
  end if;
end $$;

-- Only the two authenticated principals have source-custodied task access.
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select public.create_atlas_task_self_api_v1('Return the borrowed book','2026-11-01','task:one');
select public.create_atlas_task_self_api_v1('Return the borrowed book','2026-11-01','task:one');
do $$
declare v jsonb;
begin
  v:=public.atlas_task_day_self_api_v1('2026-11-01');
  if jsonb_array_length(v->'items') <> 1
    or v#>>'{items,0,sentence}' <> 'Return the borrowed book'
    or v#>>'{items,0,status}' <> 'open' then
    raise exception 'task readback did not preserve the sentence and date: %',v;
  end if;
  if jsonb_array_length(public.atlas_task_day_self_api_v1('2026-11-02')->'items')<>0 then
    raise exception 'task erroneously appears on another date';
  end if;
end $$;
reset role;
do $$
begin
  if (select count(*) from atlas.task_entries) <> 1 then
    raise exception 'idempotent replay duplicated a task';
  end if;
end $$;
set role authenticated;
do $$
declare v uuid;
begin
  select (public.atlas_task_day_self_api_v1('2026-11-01')#>>'{items,0,id}')::uuid into v;
  perform public.set_atlas_task_done_self_api_v1(v,true);
  if public.atlas_task_day_self_api_v1('2026-11-01')#>>'{items,0,status}' <> 'done' then
    raise exception 'completion not persisted';
  end if;
  perform public.set_atlas_task_done_self_api_v1(v,false);
  if public.atlas_task_day_self_api_v1('2026-11-01')#>>'{items,0,status}' <> 'open' then
    raise exception 'completion undo not persisted';
  end if;
end $;
reset role;

-- Populate a synthetic guessed/leaked ID in this *test session* as admin.
select set_config('atlas.fixture.task_a_id',
  (select id::text from atlas.task_entries limit 1),false);
-- Identity B cannot read or complete that specific A-owned task.
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
do $$
declare v uuid := current_setting('atlas.fixture.task_a_id')::uuid;
begin
  if jsonb_array_length(public.atlas_task_day_self_api_v1('2026-11-01')->'items')<>0 then
    raise exception 'cross-user task was visible';
  end if;
  begin
    perform public.set_atlas_task_done_self_api_v1(v,true);
    raise exception 'cross-user completion was accepted';
  exception when sqlstate '42501' then null;
  end;
end $$;
reset role;

-- Index orientation evidence from authenticated Principal and established answer.
insert into atlas.reality_discovery_orientation_events
(principal_id,owner_user_id,orientation_version,world_domains,occurred_at)
values ('10000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000001',3,'["property"]','2026-10-13T00:00:00Z');
insert into atlas.reality_discovery_questions(question_key,metadata,prompt,options)
values ('family-first','{"orientationWorldDomains":["family"]}','Who is at home?','[]');
insert into atlas.reality_discovery_answer_events
(principal_id,owner_user_id,question_key,answer_value)
values ('10000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000001','family-first','"Parent"');
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $$
declare v jsonb; sections jsonb;
begin
  v:=atlas.atlas_notebook_index_self_api_v1();
  sections:=v->'items';
  if not exists(select 1 from jsonb_array_elements(sections) x
    where x->>'spreadKey'='section:property') then
    raise exception 'selected Field did not become an Index section: %',v;
  end if;
  if not exists(select 1 from jsonb_array_elements(sections) x
    where x->>'spreadKey'='section:family') then
    raise exception 'established answer did not become an Index section: %',v;
  end if;
  v:=atlas.personal_atlas_section_root_self_api_v1('family');
  if coalesce((v->>'selected')::boolean,false)=false
     or jsonb_array_length(v->'facts')<>1 then
    raise exception 'evidenced section root missing: %',v;
  end if;
end $$;
-- User B's Index must not show A's Field or established answer.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
do $$
declare v jsonb;
begin
  v:=atlas.atlas_notebook_index_self_api_v1();
  if exists(select 1 from jsonb_array_elements(v->'items') x
    where x->>'addressKind'='section') then
    raise exception 'Index leaked another Principal section';
  end if;
end $$;
reset role;
select 'PASS: isolated task ownership, idempotence, completion, exact day, Foundry-derived Index, evidence sections' as result;
