\set ON_ERROR_STOP on
do $p$
begin
 if has_function_privilege('anon','atlas.personal_bill_notice_source_observations_self_api_v1(integer)','EXECUTE') then
   raise exception 'Anonymous role can invoke personal bill source read';
 end if;
 if not has_function_privilege('authenticated','atlas.personal_bill_notice_source_observations_self_api_v1(integer)','EXECUTE') then
   raise exception 'Principal read grant is missing';
 end if;
end $p$;

set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $p$
declare j jsonb;
begin
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
 j:=atlas.personal_bill_notice_source_observations_self_api_v1(24);
 if jsonb_array_length(j->'items')<>1
 or j#>>'{items,0,source,connectedSourceId}'<>'20000000-0000-4000-8000-000000000002'
 then raise exception 'Principal B could see other scope: %',j; end if;
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
select 'PASS: explicit personal financial scope, Principal isolation, revoked, pending and organization exclusion; no raw mailbox body' result;
