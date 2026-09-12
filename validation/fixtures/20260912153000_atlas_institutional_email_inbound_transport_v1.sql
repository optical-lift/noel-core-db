-- Synthetic rows only, for disposable production-structure clone testing.
insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state)
values(
  '00000000-0000-4000-8000-000000002202'::uuid,
  'fixture_inbound_email_org','Inbound Email Validation Organization','active',
  '{"validation_fixture":true}'::jsonb,'ready'
);

insert into atlas.connected_sources(
  id,custodian_organization_id,provider_key,provider_account_key,display_label,account_hint,
  authorization_state,granted_scopes,capabilities,metadata
) values (
  '00000000-0000-4000-8000-000000002204'::uuid,
  '00000000-0000-4000-8000-000000002202'::uuid,
  'imap_smtp_email','fixture-inbound@example.invalid','Inbound Fixture Mailbox','fixture-inbound@example.invalid',
  'connected',array['mail.read','mail.send']::text[],
  '{"communicationCapture":true,"communicationSend":true}'::jsonb,
  '{"validation_fixture":true,"transportClass":"generic_imap_smtp"}'::jsonb
);

insert into atlas.communication_endpoints(
  id,organization_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata
) values (
  '00000000-0000-4000-8000-000000002205'::uuid,
  '00000000-0000-4000-8000-000000002202'::uuid,
  'email','fixture-inbound@example.invalid','fixture-inbound@example.invalid','Inbound Fixture Mailbox','active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.communication_endpoint_source_bindings(
  id,communication_endpoint_id,connected_source_id,binding_role,binding_state,transport_metadata
) values (
  '00000000-0000-4000-8000-000000002206'::uuid,
  '00000000-0000-4000-8000-000000002205'::uuid,
  '00000000-0000-4000-8000-000000002204'::uuid,
  'send_receive','active','{"validation_fixture":true}'::jsonb
);
