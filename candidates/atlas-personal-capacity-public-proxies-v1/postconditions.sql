-- Only disposable production-schema clone tests. No production effects.
do $check$
begin
 if to_regprocedure('public.personal_capacity_policies_self_api_v1()') is null
   or to_regprocedure('public.personal_set_capacity_policy_self_api_v1(jsonb)') is null then
   raise exception 'Personal capacity public RPC proxies missing';
 end if;
 if has_function_privilege('anon','public.personal_capacity_policies_self_api_v1()','EXECUTE')
   or has_function_privilege('anon','public.personal_set_capacity_policy_self_api_v1(jsonb)','EXECUTE')
   or not has_function_privilege('authenticated','public.personal_capacity_policies_self_api_v1()','EXECUTE')
   or not has_function_privilege('authenticated','public.personal_set_capacity_policy_self_api_v1(jsonb)','EXECUTE') then
   raise exception 'Personal capacity browser authorization grants are incorrect';
 end if;
 if (select count(*) from atlas.authenticated_rpc_registry
   where signature in (
    'public.personal_capacity_policies_self_api_v1()',
    'public.personal_set_capacity_policy_self_api_v1(jsonb)'
   ) and classification='app_endpoint' and review_status='active'
   and authenticated_execute_expected and not anonymous_execute_expected)<>2 then
   raise exception 'Personal capacity public API registry incomplete';
 end if;
end
$check$;

do $capacity$
declare
 u_a uuid := '62000000-0000-4000-8000-000000000001';
 u_b uuid := '62000000-0000-4000-8000-000000000002';
 v_policy_id uuid;
 v_first jsonb;
 v_again jsonb;
 v_a_read jsonb;
 v_b_read jsonb;
 v_today date := (statement_timestamp() at time zone 'America/Chicago')::date;
 v_count integer;
 v_denied boolean := false;
begin
 perform set_config('request.jwt.claim.sub',u_a::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 perform set_config('request.jwt.claims',
  jsonb_build_object('sub',u_a::text,'role','authenticated')::text,true);

 -- Native Person + native Personal Atlas must exist: the internal writer
 -- fails closed when these identity prerequisites are absent.
 if atlas.current_person_id_v1() is null then
   raise exception 'Native Person was not established by current fixture identity';
 end if;

 v_a_read:=public.personal_capacity_policies_self_api_v1();
 if v_a_read->>'contractVersion'<>'personal_capacity_policies_self_v1'
   or jsonb_array_length(v_a_read->'policies')<>0 then
   raise exception 'Fresh owner capacity reader was not empty or source-confirmed';
 end if;

 v_first:=public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
  'stableKey','ci-ordinary-capacity',
  'name','Explicitly confirmed synthetic availability',
  'weekdays',jsonb_build_array(0,1,2,3,4,5,6),
  'localStart','08:00','localEnd','18:00',
  'defaultDiscretionaryMinutes',120,
  'maximumPlannedMinutes',120,
  'effectiveFrom',v_today::text,
  'metadata',jsonb_build_object('source','isolated_clone_fixture')
 ));
 if v_first->>'contractVersion'<>'personal_capacity_policy_authoring_v1'
  or v_first#>>'{policy,stable_key}'<>'ci-ordinary-capacity'
  or v_first#>>'{capacityOnEffectiveFrom,capacityKnown}'<>'true' then
   raise exception 'Canonical source writer did not accept confirmed policy';
 end if;
 v_policy_id:=(v_first#>>'{policy,id}')::uuid;

 -- Stable identity and effective day, not a second generated record.
 v_again:=public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
  'stableKey','ci-ordinary-capacity',
  'name','Explicitly confirmed synthetic availability',
  'weekdays',jsonb_build_array(0,1,2,3,4,5,6),
  'localStart','08:00','localEnd','18:00',
  'defaultDiscretionaryMinutes',120,
  'maximumPlannedMinutes',120,
  'effectiveFrom',v_today::text,
  'metadata',jsonb_build_object('source','isolated_clone_fixture')
 ));
 select count(*) into v_count from atlas.principal_capacity_policies
 where stable_key='ci-ordinary-capacity' and effective_from=v_today;
 if (v_again#>>'{policy,id}')::uuid is distinct from v_policy_id
    or v_count<>1 then
   raise exception 'Repeated source write duplicated the policy or changed its identity';
 end if;
 v_a_read:=public.personal_capacity_policies_self_api_v1();
 if jsonb_array_length(v_a_read->'policies')<>1
    or v_a_read#>>'{policies,0,stableKey}'<>'ci-ordinary-capacity' then
   raise exception 'Confirmed policy did not read back with its source identity';
 end if;

 perform set_config('request.jwt.claim.sub',u_b::text,true);
 perform set_config('request.jwt.claims',
  jsonb_build_object('sub',u_b::text,'role','authenticated')::text,true);
 v_b_read:=public.personal_capacity_policies_self_api_v1();
 if v_b_read#>>'{personEntityId}'=v_a_read#>>'{personEntityId}'
    or jsonb_array_length(v_b_read->'policies')<>0 then
   raise exception 'Cross-Person capacity source was disclosed';
 end if;

 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);
 begin
   perform public.personal_capacity_policies_self_api_v1();
 exception when insufficient_privilege then v_denied:=true;
 end;
 if not v_denied then
   raise exception 'Anonymous session received native Person capacity projection';
 end if;
 perform set_config('request.jwt.claim.sub',u_a::text,true);
 perform set_config('request.jwt.claims',
  jsonb_build_object('sub',u_a::text,'role','authenticated')::text,true);

 -- Explicit invalid user input must fail closed, not create a second policy.
 v_denied:=false;
 begin
   perform public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
    'stableKey','ci-invalid-weekday',
    'name','Bad test policy',
    'weekdays',jsonb_build_array(7),
    'localStart','08:00','localEnd','18:00',
    'defaultDiscretionaryMinutes',120,
    'maximumPlannedMinutes',120,
    'effectiveFrom',v_today::text
   ));
 exception when invalid_parameter_value then v_denied:=true;
 end;
 if not v_denied then
  raise exception 'Invalid weekday source write was not rejected';
 end if;
 raise notice 'Owner-authenticated Personal capacity read/write, stable retry, cross-person isolation and invalid source input passed.';
end
$capacity$;
