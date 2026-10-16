-- Disposable clone only; validates native Person ownership and weekly fit.
do $zero$
declare
 u_a uuid := '62000000-0000-4000-8000-000000000001';
 u_b uuid := '62000000-0000-4000-8000-000000000002';
 v_today date := (statement_timestamp() at time zone 'America/Chicago')::date;
 v_monday date;
 v_owner uuid;
 v_before jsonb;
 v_after_positive jsonb;
 v_pos jsonb;
 v_zero jsonb;
 v_zero_repeat jsonb;
 v_reader jsonb;
 v_zero_day jsonb;
 v_pos_day jsonb;
 v_fit jsonb;
 v_other jsonb;
 v_denied boolean;
begin
 v_monday:=v_today-(extract(isodow from v_today)::integer-1)+7;
 if has_function_privilege('anon','public.personal_set_capacity_policy_self_api_v1(jsonb)','EXECUTE')
   or not has_function_privilege('authenticated','public.personal_set_capacity_policy_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Self-owned capacity source API privilege regression';
 end if;

 perform set_config('request.jwt.claim.sub',u_a::text,true);
 perform set_config('request.jwt.claim.role','authenticated',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u_a::text,'role','authenticated')::text,true);
 perform atlas.begin_personal_atlas_self_api_v1('Synthetic Capacity Principal A','America/Chicago');
 select id into strict v_owner from atlas.principals where user_id=u_a;

 v_before:=public.personal_week_work_fit_preview_self_api_v1('household.cleaning',v_monday,null,30);
 if v_before->>'state'<>'capacity_anchor_required' then
   raise exception 'Unknown source days must not be assumed known: %',v_before->>'state';
 end if;

 v_pos:=public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
  'stableKey','ci-positive-weekdays','name','Synthetic positive weekdays',
  'availabilityState','confirmed_available',
  'weekdays',jsonb_build_array(1,2,3,4,5),
  'localStart','08:00','localEnd','18:00',
  'defaultDiscretionaryMinutes',120,'maximumPlannedMinutes',120,
  'effectiveFrom',v_monday::text,'metadata',jsonb_build_object('source','isolated_clone_fixture')
 ));
 if v_pos->>'contractVersion'<>'personal_capacity_policy_authoring_v1'
   or v_pos#>>'{policy,stable_key}'<>'ci-positive-weekdays' then
   raise exception 'Original positive window writer regressed';
 end if;
 v_after_positive:=public.personal_week_work_fit_preview_self_api_v1('household.cleaning',v_monday,null,30);
 if v_after_positive->>'state'<>'capacity_anchor_required' then
   raise exception 'Unanswered weekend must remain unknown';
 end if;

 v_zero:=public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
  'stableKey','ci-confirmed-unavailable-weekend',
  'name','Owner confirmed no discretionary capacity on weekends',
  'availabilityState','confirmed_unavailable',
  'weekdays',jsonb_build_array(0,6),
  'defaultDiscretionaryMinutes',0,'maximumPlannedMinutes',0,
  'effectiveFrom',v_monday::text,'metadata',jsonb_build_object('source','isolated_clone_fixture')
 ));
 if v_zero->>'contractVersion'<>'personal_capacity_policy_authoring_v1'
   or v_zero#>>'{policy,stable_key}'<>'ci-confirmed-unavailable-weekend'
   or v_zero#>>'{policy,local_start}' is not null
   or v_zero#>>'{policy,local_end}' is not null then
   raise exception 'Zero weekday writer invented a time window or rejected source';
 end if;
 v_zero_repeat:=public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
  'stableKey','ci-confirmed-unavailable-weekend',
  'name','Owner confirmed no discretionary capacity on weekends',
  'availabilityState','confirmed_unavailable',
  'weekdays',jsonb_build_array(0,6),
  'defaultDiscretionaryMinutes',0,'maximumPlannedMinutes',0,
  'effectiveFrom',v_monday::text,'metadata',jsonb_build_object('source','isolated_clone_fixture')
 ));
 if (v_zero_repeat#>>'{policy,id}')::uuid is distinct from (v_zero#>>'{policy,id}')::uuid then
   raise exception 'Retried zero weekday policy duplicated identity';
 end if;
 if (select count(*) from atlas.principal_capacity_policies
  where principal_id=v_owner and stable_key='ci-confirmed-unavailable-weekend')<>1 then
   raise exception 'Retried unavailable weekday created duplicate source rows';
 end if;

 v_zero_day:=atlas.principal_capacity_day_state_v1(v_owner,v_monday+5);
 v_pos_day:=atlas.principal_capacity_day_state_v1(v_owner,v_monday);
 if v_zero_day->>'state'<>'resolved'
  or v_zero_day->>'capacityKnown'<>'true'
  or v_zero_day->>'discretionaryCapacityMinutes'<>'0'
  or v_zero_day->>'maximumPlannedMinutes'<>'0'
  or v_zero_day#>>'{truthBoundary,noFabricatedTimeInterval}'<>'true'
  or jsonb_typeof(v_zero_day->'startsAt')<>'null'
  or jsonb_typeof(v_zero_day->'endsAt')<>'null' then
  raise exception 'Known-zero Saturday not faithfully projected: %',v_zero_day;
 end if;
 if v_pos_day->>'capacityKnown'<>'true'
  or v_pos_day->>'discretionaryCapacityMinutes'<>'120'
  or v_pos_day->>'availableElapsedMinutes'<>'600' then
   raise exception 'Legacy positive day capacity lost: %',v_pos_day;
 end if;
 v_reader:=public.personal_capacity_policies_self_api_v1();
 if jsonb_array_length(v_reader->'policies')<>2
   or not exists(select 1 from jsonb_array_elements(v_reader->'policies') p
     where p->>'stableKey'='ci-confirmed-unavailable-weekend'
       and p->>'availabilityState'='confirmed_unavailable'
       and jsonb_typeof(p->'localStart')='null'
       and jsonb_typeof(p->'localEnd')='null') then
   raise exception 'Native Person reader did not preserve known zero source';
 end if;

 v_fit:=public.personal_week_work_fit_preview_self_api_v1('household.cleaning',v_monday,null,30);
 if v_fit->>'state'<>'provisional_ranked'
   or v_fit->>'availableKnownCapacityDays'<>'7'
   or v_fit#>>'{recommendation,localDate}'<>v_monday::text then
   raise exception 'Mixed positive/zero known capacity cannot rank available Monday: %',v_fit;
 end if;
 v_denied:=false;
 begin
  perform public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
   'stableKey','ci-invalid-zero','name','Bad zero with fictional time',
   'availabilityState','confirmed_unavailable',
   'weekdays',jsonb_build_array(6),
   'localStart','08:00','localEnd','18:00',
   'defaultDiscretionaryMinutes',0,'maximumPlannedMinutes',0,'effectiveFrom',v_monday::text
  ));
 exception when invalid_parameter_value then v_denied:=true;
 end;
 if not v_denied then raise exception 'Fictional time on explicit unavailable weekday was not rejected'; end if;

 v_denied:=false;
 begin
  perform public.personal_set_capacity_policy_self_api_v1(jsonb_build_object(
   'stableKey','ci-conflicting-weekday','name','Bad overlap',
   'availabilityState','confirmed_available','weekdays',jsonb_build_array(6),
   'localStart','08:00','localEnd','10:00',
   'defaultDiscretionaryMinutes',30,'maximumPlannedMinutes',30,'effectiveFrom',v_monday::text
  ));
 exception when invalid_parameter_value then v_denied:=true;
 end;
 if not v_denied then raise exception 'Distinct positive source silently overrode confirmed zero weekend'; end if;

 perform set_config('request.jwt.claim.sub',u_b::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u_b::text,'role','authenticated')::text,true);
 perform atlas.begin_personal_atlas_self_api_v1('Synthetic Capacity Principal B','America/Chicago');
 v_other:=public.personal_capacity_policies_self_api_v1();
 if jsonb_array_length(v_other->'policies')<>0 then
  raise exception 'Foreign Person learned owner A positive/zero capacity source';
 end if;
 perform set_config('request.jwt.claim.sub','',true);
 perform set_config('request.jwt.claims','{}',true);
 raise notice 'Owner capacity known-zero vs unknown, no fake window, existing positive, retry, mixed week fit, conflicting source and other-Person isolation proved.';
end
$zero$;
