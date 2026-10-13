\set ON_ERROR_STOP on
do $p$
begin
 if has_function_privilege('anon','atlas.personal_bill_notice_source_observations_self_api_v1(integer)','EXECUTE') then
   raise exception 'Anonymous role can invoke personal bill source read';
 end if;
 if not has_function_privilege('authenticated','atlas.personal_bill_notice_source_observations_self_api_v1(integer)','EXECUTE') then
   raise exception 'Principal read grant is missing';
 end if;
 if has_function_privilege('anon','atlas.set_personal_bill_recognition_consent_self_api_v1(uuid,boolean,text)','EXECUTE') then
   raise exception 'Anon can grant financial interpretation consent';
 end if;
end $p$;

set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $p$
declare j jsonb;
begin
 j:=atlas.personal_bill_notice_source_observations_self_api_v1(5000);
 if j->>'personalBillRecognitionReady'<>'false' or jsonb_array_length(j->'items')<>0 then
   raise exception 'Without owner consent, personal bills must remain invisible';
 end if;
 perform atlas.set_personal_bill_recognition_consent_self_api_v1(
  '20000000-0000-4000-8000-000000000001',true,'a-consent-1');
 j:=atlas.personal_bill_notice_source_observations_self_api_v1(5000);
 if j->>'identityRoot'<>'authorized_personal_source_observation'
 or j->>'personalBillRecognitionReady'<>'true'
 or jsonb_array_length(j->'items')<>1
 or j#>>'{items,0,source,connectedSourceId}'<>'20000000-0000-4000-8000-000000000001'
 or j#>>'{items,0,notice,billerName,value}'<>'Example Electric'
 then raise exception 'Principal A source scope incorrect: %',j; end if;
 if j::text like '%private raw email body%' then
   raise exception 'Raw email content leaked in source read';
 end if;
end $p$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
do $p$
declare j jsonb;
begin
 perform atlas.set_personal_bill_recognition_consent_self_api_v1(
  '20000000-0000-4000-8000-000000000002',true,'b-consent-1');
 j:=atlas.personal_bill_notice_source_observations_self_api_v1(24);
 if jsonb_array_length(j->'items')<>1
 or j#>>'{items,0,source,connectedSourceId}'<>'20000000-0000-4000-8000-000000000002'
 then raise exception 'Principal B could see other scope: %',j; end if;
end $p$;

-- Principal B may not opt in to Principal A's source.
do $p$
begin
 begin
  perform atlas.set_personal_bill_recognition_consent_self_api_v1(
   '20000000-0000-4000-8000-000000000001',true,'b-cross-owner');
  raise exception 'Cross-principal consent write accepted';
 exception when sqlstate '42501' then null;
 end;
end $p$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $p$
declare j jsonb; replay jsonb;
begin
 replay:=atlas.set_personal_bill_recognition_consent_self_api_v1(
  '20000000-0000-4000-8000-000000000001',true,'a-consent-1');
 if replay->>'idempotentReplay'<>'true' then raise exception 'Consent replay duplicated'; end if;
 begin
  perform atlas.set_personal_bill_recognition_consent_self_api_v1(
   '20000000-0000-4000-8000-000000000001',false,'a-consent-1');
  raise exception 'Source action drift accepted';
 exception when sqlstate '23505' then null;
 end;
 begin
  perform atlas.set_personal_bill_recognition_consent_self_api_v1(
   '20000000-0000-4000-8000-000000000004',true,'a-unauthorized');
  raise exception 'Generic correspondence source was granted bill consent';
 exception when sqlstate '42501' then null;
 end;
 perform atlas.set_personal_bill_recognition_consent_self_api_v1(
  '20000000-0000-4000-8000-000000000001',false,'a-revoke-2');
 j:=atlas.personal_bill_notice_source_observations_self_api_v1(24);
 if jsonb_array_length(j->'items')<>0 then
   raise exception 'Revoked interpretation consent still sees bill candidates';
 end if;
end $p$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000009',false);
do $p$
declare j jsonb;
begin
 j:=atlas.personal_bill_notice_source_observations_self_api_v1();
 if j->>'ok'<>'false' or jsonb_array_length(j->'items')<>0 then
   raise exception 'Unaffiliated user could read candidate observations';
 end if;
end $p$;
reset role;
select 'PASS: provider scope remains separate, explicit owner opt-in/revocation, idempotence, isolation, no raw body' result;
