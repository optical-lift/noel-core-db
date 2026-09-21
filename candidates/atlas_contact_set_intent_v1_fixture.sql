-- Clone-only DML fixture for Atlas Contact-Set Intent v1.
insert into atlas.organizations(id,stable_key,name,status,onboarding_state,metadata)
values(
  'f1000000-0000-4000-8000-000000000101'::uuid,
  'validation-contact-set-intent-org-v1',
  'Validation Contact Intent Organization',
  'active',
  'new',
  '{"validationFixture":true}'::jsonb
);

insert into atlas.contact_set_intent_requests(
  id,organization_id,requested_by_user_id,source_action_id,source_surface,literal_request,capture_context
) values
(
  'f1000000-0000-4000-8000-000000000102'::uuid,
  'f1000000-0000-4000-8000-000000000101'::uuid,
  'f1000000-0000-4000-8000-000000000103'::uuid,
  'validation-ready',
  'validation',
  'Go find emails for bank people in those towns.',
  '{"conversationRefs":["town-set:marshfield-lebanon-springfield"]}'::jsonb
),
(
  'f1000000-0000-4000-8000-000000000104'::uuid,
  'f1000000-0000-4000-8000-000000000101'::uuid,
  'f1000000-0000-4000-8000-000000000103'::uuid,
  'validation-clarify',
  'validation',
  'Go find emails for bank people in those towns.',
  '{}'::jsonb
);
