-- Synthetic session claims simulate a database role, NOT real GoTrue JWT proof.
set role authenticated;
do $proof$
begin
 begin
  perform public.person_measurement_recognition_self_api_v1('00000000-0000-4000-8000-000000000001');
  raise exception 'Missing session was accepted';
 exception when insufficient_privilege then null;
 end;
end $proof$;
select pg_catalog.set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select pg_catalog.set_config('atlas.fixture_principal','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',false);
do $proof$
declare r jsonb; first_approval timestamptz;
begin
 r:=public.person_measurement_recognition_self_api_v1('00000000-0000-4000-8000-000000000001');
 if r->>'recognition'<>'approval_required' then raise exception 'First pattern was not gated'; end if;
 begin
  perform public.person_measurement_recognition_self_api_v1('00000000-0000-4000-8000-000000000003');
  raise exception 'Foreign Person capture was exposed';
 exception when insufficient_privilege then null;
 end;
 r:=public.set_person_measurement_rule_self_api_v1('00000000-0000-4000-8000-000000000001',true);
 if r->>'approved'<>'true' then raise exception 'Rule approval was not recorded'; end if;
 first_approval:=(r->>'approvalAt')::timestamptz;
 r:=public.set_person_measurement_rule_self_api_v1('00000000-0000-4000-8000-000000000001',true);
 if (r->>'approvalAt')::timestamptz is distinct from first_approval
   then raise exception 'Approval retry changed the original receipt timestamp'; end if;
 r:=public.set_person_measurement_rule_self_api_v1('00000000-0000-4000-8000-000000000002',true);
 if r->>'approvalSourceCaptureId'<>'00000000-0000-4000-8000-000000000001'
    or (r->>'approvalAt')::timestamptz is distinct from first_approval
   then raise exception 'A second recognized note replaced the standing approval source'; end if;
 begin
  perform public.set_person_measurement_rule_self_api_v1('00000000-0000-4000-8000-000000000003',true);
  raise exception 'Foreign Person rule approval was permitted';
 exception when insufficient_privilege then null;
 end;
 r:=public.person_measurement_recognition_self_api_v1('00000000-0000-4000-8000-000000000001');
 if r->>'recognition'<>'approved_rule' then raise exception 'Standing rule was not reread'; end if;
end $proof$;
reset role;
insert into atlas.personal_reality_captures
 (id,owner_user_id,principal_id,evidence_id,source_surface,metadata,testimony,capture_context,captured_at)
values
 ('00000000-0000-4000-8000-000000000004',
 '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'e0000000-0000-4000-8000-000000000004',
 'personal_notebook_daily_log','{"notebookEntryKind":"raw_note"}',
 'I weighed 171 pounds today.',jsonb_build_object('notebookDate',current_date::text),
 now()+interval '10 seconds');
set role authenticated;
do $proof$
declare r jsonb; ids text[];
begin
 r:=public.person_measurement_recognition_self_api_v1('00000000-0000-4000-8000-000000000004');
 if r->>'recognition'<>'approved_rule' then raise exception 'Next note did not reuse approved rule'; end if;
 r:=public.person_body_weight_history_self_api_v1(30,'UTC');
 if r->>'ruleApproved'<>'true' or jsonb_array_length(r->'items')<>2 then
  raise exception 'History must contain first-approved and future note only: %',r;
 end if;
 select array_agg(item->>'captureId') into ids
 from jsonb_array_elements(r->'items') item;
 if not ('00000000-0000-4000-8000-000000000001'=any(ids))
   or not ('00000000-0000-4000-8000-000000000004'=any(ids))
   or '00000000-0000-4000-8000-000000000002'=any(ids)
   or '00000000-0000-4000-8000-000000000003'=any(ids) then
   raise exception 'Source identity, no-retroactivity or privacy failure';
 end if;
 r:=public.set_person_measurement_rule_self_api_v1('00000000-0000-4000-8000-000000000001',false);
 if r->>'approved'<>'false' then raise exception 'Revoke failed'; end if;
 r:=public.person_body_weight_history_self_api_v1(30,'UTC');
 if r->>'ruleApproved'<>'false' or jsonb_array_length(r->'items')<>0 then
   raise exception 'Revoked rule continues projecting measurements';
 end if;
end $proof$;
reset role;
do $proof$
begin
 if (select count(*) from atlas.personal_reality_captures)<>4 then
  raise exception 'Original human notes changed during permission cycle';
 end if;
end $proof$;
