\set ON_ERROR_STOP on
-- No authenticated principal may write another person's Encounter bearing.
do $proof$
begin
 if has_function_privilege('anon','atlas.set_reality_discovery_bearing_self_api_v1(uuid,text,text,text,text)','EXECUTE') then
  raise exception 'Anonymous bearing write was granted';
 end if;
 if not has_function_privilege('authenticated','atlas.set_reality_discovery_bearing_self_api_v1(uuid,text,text,text,text)','EXECUTE') then
  raise exception 'Authenticated bearing writer absent';
 end if;
end $proof$;
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $proof$
declare
 before_set jsonb;
 after_set jsonb;
 result jsonb;
 replay jsonb;
begin
 before_set:=atlas.reality_discovery_question_set_self_api_v1(4);
 if before_set#>>'{items,0,questionKey}' <> 'business.one' then
   raise exception 'First day did not begin in original orientation: %',before_set;
 end if;
 result:=atlas.set_reality_discovery_bearing_self_api_v1(
  '20000000-0000-4000-8000-000000000001','job','focus:job:a','change_direction',null);
 after_set:=atlas.reality_discovery_question_set_self_api_v1(4);
 if result->>'focusDomain'<>'job'
  or after_set#>>'{items,0,questionKey}'<>'job.one'
  or after_set->>'focusDomain'<>'job' then
   raise exception 'Explicit job direction failed to allow manual question under first-day scope: %',after_set;
 end if;
 replay:=atlas.set_reality_discovery_bearing_self_api_v1(
  '20000000-0000-4000-8000-000000000001','job','focus:job:a','change_direction',null);
 if replay->>'idempotentReplay'<>'true' then
   raise exception 'Same source action did not replay idempotently';
 end if;
 begin
   perform atlas.set_reality_discovery_bearing_self_api_v1(
   '20000000-0000-4000-8000-000000000001','property','focus:job:a','change_direction',null);
   raise exception 'Source action drift was accepted';
 exception when sqlstate '23505' then null; end;
 result:=atlas.set_reality_discovery_bearing_self_api_v1(
  '20000000-0000-4000-8000-000000000001','job','focus:wrong:a','question_does_not_fit','job.one');
 if result#>>'{set,items,0,questionKey}'='job.one' then
  raise exception 'Question marked not fitting was repeated without change';
 end if;
 result:=atlas.set_reality_discovery_bearing_self_api_v1(
  '20000000-0000-4000-8000-000000000001','property','focus:property:a','change_direction',null);
 if result#>>'{set,items,0,questionKey}'<>'property.one' then
  raise exception 'Property switching did not recompute to current admitted question: %',result;
 end if;
 result:=atlas.set_reality_discovery_bearing_self_api_v1(
  '20000000-0000-4000-8000-000000000001',null,'focus:original:a','change_direction',null);
 if result#>>'{set,items,0,questionKey}'<>'business.one' then
  raise exception 'Return to original Field did not preserve original branch';
 end if;
end $proof$;
reset role;
do $proof$
declare meta jsonb;
begin
 select metadata into meta from atlas.reality_discovery_sessions
  where id='20000000-0000-4000-8000-000000000001';
 if jsonb_array_length(meta->'bearingHistory')<>4 then
  raise exception 'Idempotent retry created duplicate encounter bearing history: %',meta;
 end if;
 if not (meta->'skippedQuestionKeys' ? 'job.one') then
  raise exception 'Not-fitting question feedback was not preserved';
 end if;
end $proof$;
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
do $proof$
begin
 begin
  perform atlas.set_reality_discovery_bearing_self_api_v1(
  '20000000-0000-4000-8000-000000000001','home','attacker:one','change_direction',null);
  raise exception 'Cross-owner session write was accepted';
 exception when sqlstate '42501' then null; end;
end $proof$;
reset role;
do $proof$
begin
 if (select metadata->'bearingHistory' from atlas.reality_discovery_sessions
   where id='20000000-0000-4000-8000-000000000002') is not null then
  raise exception 'Other user's bearing was affected';
 end if;
end $proof$;
select 'PASS: session bearer isolation, original orientation, explicit focused admission, answered routing, question fit feedback, idempotence and rejection' as result;
