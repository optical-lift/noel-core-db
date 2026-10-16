-- Postconditions to run only on disposable production-schema clone after candidate applied.
-- Positive authenticated fixture with a test native Personal Atlas remains required.
do $check$
begin
 if to_regprocedure('atlas.personal_week_planning_context_self_api_v1(date)') is null
  or to_regprocedure('public.personal_week_planning_context_self_api_v1(date)') is null
  or to_regprocedure('atlas.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)') is null
  or to_regprocedure('public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)') is null then
   raise exception 'Personal week fit contract functions are missing';
 end if;
 if has_function_privilege('anon','public.personal_week_planning_context_self_api_v1(date)','EXECUTE')
  or has_function_privilege('anon','public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','EXECUTE')
  or has_function_privilege('authenticated','atlas.personal_week_planning_context_self_api_v1(date)','EXECUTE')
  or has_function_privilege('authenticated','atlas.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','EXECUTE') then
   raise exception 'Private/internal planning contracts leaked to an unauthorized caller';
 end if;
 if not has_function_privilege('authenticated','public.personal_week_planning_context_self_api_v1(date)','EXECUTE')
  or not has_function_privilege('authenticated','public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','EXECUTE') then
   raise exception 'Missing authenticated read-only proxy EXECUTE grant';
 end if;
 if (select count(*) from atlas.authenticated_rpc_registry where signature in (
  'public.personal_week_planning_context_self_api_v1(date)',
  'public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)'
 ) and classification='app_endpoint' and review_status='active'
     and authenticated_execute_expected=true and anonymous_execute_expected=false)<>2 then
   raise exception 'Personal planning RPC registry is incomplete';
 end if;
end
$check$;

-- Disposable-clone behavioral proof. The earlier fixture contains only
-- synthetic auth users, compatibility principals, access grants and source kernels.
do $weekfit$
declare
 u_a uuid := '60000000-0000-4000-8000-000000000001';
 u_b uuid := '60000000-0000-4000-8000-000000000002';
 principal_a uuid;
 hh_a uuid;
 hh_b uuid;
 v_week date;
 v_state jsonb;
 v_context jsonb;
 v_anchor uuid;
 v_foreign uuid;
 v_denied boolean;
 before_tasks bigint;
 before_rhythms bigint;
 before_obligations bigint;
 before_commitments bigint;
begin
 -- A real Personal Atlas enrollment contract must establish native Person,
 -- current Household and unique compatibility Principal before a reader works.
 perform set_config('request.jwt.claim.sub',u_a::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 perform set_config('request.jwt.claims',
   jsonb_build_object('sub',u_a::text,'role','authenticated')::text,true);
 perform atlas.begin_personal_atlas_self_api_v1('Clone Weekly Fit A','America/Chicago');
 select id,active_household_id into strict principal_a,hh_a
 from atlas.principals where user_id=u_a;
 if hh_a is null then raise exception 'Fixture A lacks actual Household'; end if;
 v_week := (statement_timestamp() at time zone 'America/Chicago')::date;
 v_week := v_week-(extract(isodow from v_week)::integer-1);

 v_context:=atlas.personal_week_planning_context_self_api_v1(v_week);
 if (v_context->>'householdId')::uuid<>hh_a
   or jsonb_array_length(v_context->'days')<>7 then
   raise exception 'Owner A planning context not exactly 7 owner-scoped days';
 end if;

 v_state:=atlas.personal_week_work_fit_preview_self_api_v1('household.cleaning',v_week,null,30);
 if v_state->>'state'<>'capacity_anchor_required'
   or jsonb_typeof(v_state->'recommendation')<>'null' then
   raise exception 'Missing capacity produced placement: %',v_state->>'state';
 end if;

 insert into atlas.principal_capacity_policies(
   principal_id,stable_key,name,weekdays,local_start,local_end,
   default_discretionary_minutes,maximum_planned_minutes,effective_from,active
 ) values (
   principal_a,'clone-week-fit-all-days','Known availability for test only',
   array[0,1,2,3,4,5,6]::smallint[],
   '08:00'::time,'18:00'::time,120,120,v_week,true
 );

 v_state:=atlas.personal_week_work_fit_preview_self_api_v1('household.cleaning',v_week,null,30);
 if v_state->>'state'<>'provisional_ranked'
   or v_state->>'availableKnownCapacityDays'<>'7'
   or v_state#>>'{recommendation,epistemicState}'<>'provisional_candidate_not_approved'
   or v_state#>>'{recommendation,localDate}'<>v_week::text then
   raise exception 'Known source capacity did not produce provisional earliest fit: %',v_state->>'state';
 end if;

 insert into atlas.household_events(
   household_id,stable_key,title,event_kind,starts_at,ends_at,fixed,
   blocks_capacity,expected_minutes,protection_level,floor_class,
   interruptibility,principal_required,source
 ) values (
   hh_a,'clone-friday-guests','Synthetic Friday guests','family_commitment',
   ((v_week+4) + time '10:00') at time zone 'America/Chicago',
   ((v_week+4) + time '12:00') at time zone 'America/Chicago',
   true,true,120,'protected',3,'interruptible',true,'isolated_clone_fixture'
 ) returning id into v_anchor;

 v_state:=atlas.personal_week_work_fit_preview_self_api_v1(
   'household.cleaning',v_week,v_anchor,30
 );
 if v_state->>'state'<>'provisional_ranked'
   or v_state#>>'{recommendation,localDate}'<>(v_week+3)::text
   or (v_state#>>'{recommendation,localDate}')::date>=(v_week+4) then
   raise exception 'Friday source event failed Thursday preparation preview: %',v_state->>'state';
 end if;

 select count(*) into before_tasks from atlas.tasks;
 select count(*) into before_rhythms from atlas.household_rhythms;
 select count(*) into before_obligations from atlas.owner_obligations;
 select count(*) into before_commitments from atlas.commitment_plans;

 -- Foreign fixed Household event must never be available to the caller.
 perform set_config('request.jwt.claim.sub',u_b::text,true);
 perform set_config('request.jwt.claims',
   jsonb_build_object('sub',u_b::text,'role','authenticated')::text,true);
 perform atlas.begin_personal_atlas_self_api_v1('Clone Weekly Fit B','America/Chicago');
 select active_household_id into strict hh_b from atlas.principals where user_id=u_b;
 if hh_b is null or hh_b=hh_a then
   raise exception 'Fixture household identity isolation failed';
 end if;
 insert into atlas.household_events(
   household_id,stable_key,title,event_kind,starts_at,ends_at,fixed,
   blocks_capacity,expected_minutes,protection_level,floor_class,
   interruptibility,principal_required,source
 ) values (
   hh_b,'clone-foreign-guests','Synthetic foreign guests','family_commitment',
   ((v_week+4) + time '10:00') at time zone 'America/Chicago',
   ((v_week+4) + time '11:00') at time zone 'America/Chicago',
   true,true,60,'protected',3,'interruptible',true,'isolated_clone_fixture'
 ) returning id into v_foreign;

 perform set_config('request.jwt.claim.sub',u_a::text,true);
 perform set_config('request.jwt.claims',
   jsonb_build_object('sub',u_a::text,'role','authenticated')::text,true);
 v_denied:=false;
 begin
   perform atlas.personal_week_work_fit_preview_self_api_v1(
    'household.cleaning',v_week,v_foreign,30);
 exception when invalid_parameter_value then v_denied:=true;
 end;
 if not v_denied then
  raise exception 'Foreign Household event was silently accepted as source anchor';
 end if;

 -- Two independent read calls are stable and must not mutate any source.
 perform atlas.personal_week_work_fit_preview_self_api_v1(
  'household.cleaning',v_week,v_anchor,30);
 if (select count(*) from atlas.tasks)<>before_tasks
   or (select count(*) from atlas.household_rhythms)<>before_rhythms
   or (select count(*) from atlas.owner_obligations)<>before_obligations
   or (select count(*) from atlas.commitment_plans)<>before_commitments then
   raise exception 'Read-only preview changed source-owned durable records';
 end if;

 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);
end
$weekfit$;
