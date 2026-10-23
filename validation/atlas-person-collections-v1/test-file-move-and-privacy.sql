-- SQL behavior on a throwaway fictional fixture only.
begin;
do $body$
declare
  a uuid:='11111111-1111-4111-8111-111111111111';
  b uuid:='22222222-2222-4222-8222-222222222222';
  cap_a uuid:='00000000-0000-4000-8000-000000000001';
  h_a uuid;h_b uuid;another uuid;receipt uuid;payload jsonb;num integer;replay jsonb;
begin
 perform set_config('request.jwt.claim.sub',a::text,true);
 payload:=public.person_collections_self_api_v1();
 if payload->>'contractVersion'<>'person_collections_v1'
    or jsonb_array_length(payload->'items')<>1
 then raise exception 'Person A should see one private Health Collection'; end if;
 h_a:=(payload->'items'->0->>'spreadInstanceId')::uuid;
 if not exists(select 1 from atlas.notebook_spread_instances
       where id=h_a and scope_kind='person' and scope_id=a::text
       and spread_key='personal.health' and spread_state='open') then
    raise exception 'A does not own a canonical live Health Spread'; end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 payload:=public.person_collections_self_api_v1();
 if jsonb_array_length(payload->'items')<>1
    then raise exception 'Person B should see one private Health Collection'; end if;
 h_b:=(payload->'items'->0->>'spreadInstanceId')::uuid;
 if h_a=h_b then raise exception 'Two People share Health collection identity'; end if;

 -- Actual internal guards are exercised with an isolated SQL-auth simulation.
 -- Separate genuine GoTrue-signed HTTP session proof remains compulsory.
 begin
   perform public.person_collection_sources_self_api_v1(h_a,100);
   raise exception 'B was able to read A's Collection';
 exception when insufficient_privilege then null;
 end;
 begin
   perform public.person_file_capture_self_api_v1(cap_a,h_b);
   raise exception 'B was able to route A original';
 exception when insufficient_privilege then null;
 end;

 perform set_config('request.jwt.claim.sub',a::text,true);
 begin
   perform public.person_file_capture_self_api_v1(cap_a,h_b);
   raise exception 'A was able to route into B Collection';
 exception when insufficient_privilege then null;
 end;
 payload:=public.person_file_capture_self_api_v1(cap_a,null);
 if payload->>'routed'<>'false' then
   raise exception 'Unapproved auto rule should preserve unfiled source'; end if;

 payload:=public.person_file_capture_self_api_v1(cap_a,h_a);
 if payload->>'routed'<>'true' or payload->>'captureId'<>cap_a::text then
   raise exception 'Explicit signed Person route failed'; end if;
 receipt:=(payload->>'receiptId')::uuid;

 replay:=public.person_file_capture_self_api_v1(cap_a,h_a);
 if replay->>'idempotent'<>'true' or (replay->>'receiptId')::uuid<>receipt then
   raise exception 'Duplicate retry did not reuse receipt'; end if;
 if (select count(*) from atlas.person_collection_filing_events_v1 where capture_id=cap_a)<>1
 then raise exception 'Duplicate receipt was created'; end if;

 payload:=public.person_collection_sources_self_api_v1(h_a,100);
 if jsonb_array_length(payload->'items')<>1 or
    payload->'items'->0->>'captureId'<>cap_a::text or
    payload->'items'->0->>'receiptId'<>receipt::text then
   raise exception 'Original capture/source receipt not readable from Collection'; end if;
 if payload->'items'->0->>'testimony'<>'I weighed 172 pounds this morning.' then
   raise exception 'Original source words changed'; end if;

 insert into atlas.notebook_spread_instances(
  principal_id,spread_key,scope_kind,scope_id,subject_domain,subject_kind,
  subject_id,purpose_key,horizon_key,thread_key,creation_mode,spread_state,
  title,section_key
 ) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','personal.extra',
 'person',a::text,'personal','private_collection',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','collection','permanent',
 'personal.extra','explicit','open','Extra','Private') returning id into another;
 payload:=public.person_file_capture_self_api_v1(cap_a,another);
 if payload->>'eventKind'<>'moved' then raise exception 'Move event absent'; end if;
 payload:=public.person_collection_sources_self_api_v1(h_a,100);
 if jsonb_array_length(payload->'items')<>0 then
   raise exception 'Old Collection still shows moved source'; end if;
 payload:=public.person_file_capture_self_api_v1(cap_a,h_a);
 if payload->>'eventKind'<>'moved' then raise exception 'Move-back event absent'; end if;
 payload:=public.person_collection_sources_self_api_v1(h_a,100);
 if jsonb_array_length(payload->'items')<>1 then
   raise exception 'Moved-back original not independently retrievable'; end if;
 select count(*) into num from atlas.notebook_spread_source_bindings
   where source_id=cap_a::text and binding_state='active';
 if num<>1 then raise exception 'Moved source has % active current locations',num; end if;
 select count(*) into num from atlas.person_collection_filing_events_v1
   where capture_id=cap_a;
 if num<>3 then raise exception 'Expected one file and two move event records'; end if;
 payload:=public.person_today_filing_receipts_self_api_v1(null);
 if jsonb_array_length(payload->'items')<>1 then
   raise exception 'Current Today must display only latest movement'; end if;

 -- An explicit manual route remains distinct from rule-derived recognition.
 -- New matching source beyond an existing approval is covered by Build 2.
end;
$body$;
rollback;

-- Structural permissions, RLS and canonical seeding checks:
\i candidates/atlas_person_health_collections_filing_v1/validation.sql
