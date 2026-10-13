\set ON_ERROR_STOP on
create schema auth;
create schema atlas;
create role authenticated;
create role anon;
grant usage on schema auth,atlas to authenticated,anon;
create function auth.uid() returns uuid language sql stable as $fn$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$fn$;
grant execute on function auth.uid() to authenticated,anon;

create table atlas.principals(id uuid primary key,user_id uuid,status text);
create table atlas.connected_sources(
 id uuid primary key,custodian_user_id uuid,custodian_organization_id uuid,
 custodian_organization_unit_id uuid,provider_key text,authorization_state text,
 revoked_at timestamptz,capabilities jsonb,granted_scopes text[]
);
create table atlas.communication_events(
 id uuid primary key,principal_id uuid,connected_source_id uuid,
 organization_id uuid,occurred_at timestamptz
);
create table atlas.communication_event_source_observations(
 id uuid primary key,principal_id uuid,connected_source_id uuid,event_id uuid,
 organization_id uuid,organization_unit_id uuid,source_event_ref text,
 source_content_hash text,observation_kind text,observed_event jsonb,observed_at timestamptz
);
insert into atlas.principals values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','active'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','active');
-- Only s1 and s2 can carry personal financial-source observations.
insert into atlas.connected_sources values
 ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',null,null,'email','connected',null,'{"personalBillRecognition":true}'::jsonb,array['personal.bill_notice.read']),
 ('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002',null,null,'email','connected',null,'{"personalBillRecognition":true}'::jsonb,array['personal.bill_notice.read']),
 ('20000000-0000-4000-8000-000000000003',null,'30000000-0000-4000-8000-000000000003',null,'email','connected',null,'{"personalBillRecognition":true}'::jsonb,array['personal.bill_notice.read']),
 ('20000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001',null,null,'email','connected',null,'{"communicationCapture":true}'::jsonb,array['communication.capture']),
 ('20000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000001',null,null,'email','connected',now(),'{"personalBillRecognition":true}'::jsonb,array['personal.bill_notice.read']),
 ('20000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000001',null,null,'email','pending',null,'{"personalBillRecognition":true}'::jsonb,array['personal.bill_notice.read']);
insert into atlas.communication_events(id,principal_id,connected_source_id,organization_id,occurred_at)
select gen_random_uuid(),p.id,s.id,null,now()
from atlas.principals p join atlas.connected_sources s on s.custodian_user_id=p.user_id;
insert into atlas.communication_events values
 ('40000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003',
 '30000000-0000-4000-8000-000000000003',now());
-- Source-native statement evidence, never an established debt.
insert into atlas.communication_event_source_observations(
 id,principal_id,connected_source_id,event_id,organization_id,
 source_event_ref,source_content_hash,observation_kind,observed_event,observed_at)
select gen_random_uuid(),e.principal_id,e.connected_source_id,e.id,e.organization_id,
 'msg:'||e.connected_source_id,repeat('a',64),'source_state_enrichment',
 jsonb_build_object(
   'billNotice',jsonb_build_object(
     'kind','statement_notice',
     'billerName',jsonb_build_object('value','Example Electric','sourceFieldRef','document:issuer'),
     'statementPeriodStart',jsonb_build_object('value','2026-01-01','sourceFieldRef','document:period'),
     'accountReference',jsonb_build_object('value','opaque:sampleaccount42','sourceFieldRef','document:account')
   ),
   'body','This private raw email body must never leave the database read'),
 now()
from atlas.communication_events e;
