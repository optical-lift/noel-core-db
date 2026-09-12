-- Validation-only synthetic rows for disposable production-schema clone testing.
-- No production data is read or copied into these fixtures.

insert into auth.users(
  id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
  '00000000-0000-4000-8000-000000001201'::uuid,
  'authenticated','authenticated','atlas-finalizer-fixture@example.invalid',
  '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now()
);

insert into atlas.organizations(
  id,stable_key,name,status,metadata,onboarding_state
) values (
  '00000000-0000-4000-8000-000000001202'::uuid,
  'fixture_outbound_finalizer_org','Outbound Finalizer Validation Organization','active',
  '{"validation_fixture":true}'::jsonb,'ready'
);

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,permissions
) values (
  '00000000-0000-4000-8000-000000001203'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  '00000000-0000-4000-8000-000000001201'::uuid,
  'member',true,'{}'::jsonb
);

insert into atlas.connected_sources(
  id,custodian_organization_id,provider_key,provider_account_key,display_label,account_hint,
  authorization_state,granted_scopes,capabilities,metadata
) values (
  '00000000-0000-4000-8000-000000001204'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  'imap_smtp_email','fixture-mailbox@example.invalid','Fixture Mailbox','fixture-mailbox@example.invalid',
  'connected',array['mail.read','mail.send']::text[],
  '{"communicationCapture":true,"communicationSend":true}'::jsonb,
  '{"validation_fixture":true,"transportClass":"generic_imap_smtp"}'::jsonb
);

insert into atlas.communication_endpoints(
  id,organization_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata
) values (
  '00000000-0000-4000-8000-000000001205'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  'email','fixture-mailbox@example.invalid','fixture-mailbox@example.invalid','Fixture Mailbox','active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.communication_endpoint_source_bindings(
  id,communication_endpoint_id,connected_source_id,binding_role,binding_state,transport_metadata
) values (
  '00000000-0000-4000-8000-000000001206'::uuid,
  '00000000-0000-4000-8000-000000001205'::uuid,
  '00000000-0000-4000-8000-000000001204'::uuid,
  'send_receive','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.institutional_conversations(
  id,organization_id,stable_key,subject,conversation_state,metadata
) values (
  '00000000-0000-4000-8000-000000001207'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  'fixture-outbound-finalizer-conversation','Outbound finalizer fixture','open',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.institutional_conversation_endpoints(
  id,institutional_conversation_id,communication_endpoint_id,endpoint_role
) values (
  '00000000-0000-4000-8000-000000001208'::uuid,
  '00000000-0000-4000-8000-000000001207'::uuid,
  '00000000-0000-4000-8000-000000001205'::uuid,
  'primary'
);

insert into atlas.communication_outbound_operations(
  id,organization_id,communication_endpoint_id,institutional_conversation_id,connected_source_id,
  initiated_by_membership_id,to_recipients,cc_recipients,bcc_recipients,subject,body_text,body_html,
  attachment_refs,idempotency_key,content_sha256,operation_state,lease_owner,lease_expires_at,metadata
) values
(
  '00000000-0000-4000-8000-000000001210'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  '00000000-0000-4000-8000-000000001205'::uuid,
  '00000000-0000-4000-8000-000000001207'::uuid,
  '00000000-0000-4000-8000-000000001204'::uuid,
  '00000000-0000-4000-8000-000000001203'::uuid,
  '[{"address":"to@example.invalid","name":"To Fixture"}]'::jsonb,
  '[{"address":"cc@example.invalid","name":"Cc Fixture"}]'::jsonb,
  '[{"address":"bcc@example.invalid","name":"Bcc Fixture"}]'::jsonb,
  'Accepted fixture','Accepted body',null,'[]'::jsonb,
  'fixture-accepted',repeat('a',64),'leased','fixture-worker',now()+interval '2 hours',
  '{"validation_fixture":true}'::jsonb
),
(
  '00000000-0000-4000-8000-000000001211'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  '00000000-0000-4000-8000-000000001205'::uuid,
  '00000000-0000-4000-8000-000000001207'::uuid,
  '00000000-0000-4000-8000-000000001204'::uuid,
  '00000000-0000-4000-8000-000000001203'::uuid,
  '[{"address":"partial-ok@example.invalid"},{"address":"partial-reject@example.invalid"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Partial fixture','Partial body',null,'[]'::jsonb,
  'fixture-partial',repeat('b',64),'leased','fixture-worker',now()+interval '2 hours',
  '{"validation_fixture":true}'::jsonb
),
(
  '00000000-0000-4000-8000-000000001212'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  '00000000-0000-4000-8000-000000001205'::uuid,
  '00000000-0000-4000-8000-000000001207'::uuid,
  '00000000-0000-4000-8000-000000001204'::uuid,
  '00000000-0000-4000-8000-000000001203'::uuid,
  '[{"address":"deferred@example.invalid"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Failure fixture','Failure body',null,'[]'::jsonb,
  'fixture-failure',repeat('c',64),'leased','fixture-worker',now()+interval '2 hours',
  '{"validation_fixture":true}'::jsonb
),
(
  '00000000-0000-4000-8000-000000001213'::uuid,
  '00000000-0000-4000-8000-000000001202'::uuid,
  '00000000-0000-4000-8000-000000001205'::uuid,
  '00000000-0000-4000-8000-000000001207'::uuid,
  '00000000-0000-4000-8000-000000001204'::uuid,
  '00000000-0000-4000-8000-000000001203'::uuid,
  '[{"address":"uncertain@example.invalid"}]'::jsonb,
  '[]'::jsonb,'[]'::jsonb,
  'Uncertain fixture','Uncertain body',null,'[]'::jsonb,
  'fixture-uncertain',repeat('d',64),'leased','fixture-worker',now()-interval '2 hours',
  '{"validation_fixture":true}'::jsonb
);
