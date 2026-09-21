-- Clone-only pre-migration DML fixture for Atlas Contact-Set Execution Preparation v1.
insert into atlas.organizations(id,stable_key,name,status,onboarding_state,metadata)
values(
  'f3000000-0000-4000-8000-000000000101'::uuid,
  'validation-contact-exec-org',
  'Validation Contact Execution Org',
  'active',
  'new',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.local_contexts(id,stable_key,organization_id,name,status,metadata)
values(
  'f3000000-0000-4000-8000-000000000111'::uuid,
  'validation-contact-exec-context',
  'f3000000-0000-4000-8000-000000000101'::uuid,
  'Validation Contact Context',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.entities(
  id,stable_key,entity_type,name,website_url,email,city,state,status,verification_state,metadata,local_context_id
) values
(
  'f3000000-0000-4000-8000-000000000121'::uuid,
  'validation-river-bank',
  'business',
  'Validation River Bank',
  'https://river-bank.example.invalid',
  null,
  'Marshfield',
  'MO',
  'active',
  'source_verified',
  '{"category":"bank","validationFixture":true}'::jsonb,
  'f3000000-0000-4000-8000-000000000111'::uuid
),
(
  'f3000000-0000-4000-8000-000000000122'::uuid,
  'validation-prairie-bank',
  'business',
  'Validation Prairie Bank',
  'https://prairie-bank.example.invalid',
  null,
  'Springfield',
  'MO',
  'active',
  'source_verified',
  '{"category":"bank","validationFixture":true}'::jsonb,
  'f3000000-0000-4000-8000-000000000111'::uuid
),
(
  'f3000000-0000-4000-8000-000000000131'::uuid,
  'validation-avery-reed',
  'person',
  'Avery Reed',
  null,
  null,
  'Marshfield',
  'MO',
  'active',
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'f3000000-0000-4000-8000-000000000111'::uuid
),
(
  'f3000000-0000-4000-8000-000000000132'::uuid,
  'validation-jordan-vale',
  'person',
  'Jordan Vale',
  null,
  null,
  'Marshfield',
  'MO',
  'active',
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'f3000000-0000-4000-8000-000000000111'::uuid
);

insert into local_intel.relationship_definitions(
  relationship_kind,relationship_category,subject_entity_types,object_entity_types,
  is_hierarchical,is_person_organization,description,is_active,metadata
) values (
  'holds_role_at',
  'role',
  array['person']::text[],
  array['business','organization','nonprofit']::text[],
  false,
  true,
  'Validation fixture relationship kind for a person holding a role at an organization.',
  true,
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.entity_relationships(
  id,subject_entity_id,relationship_kind,object_entity_id,role_title,is_current,
  verification_state,metadata,role_function,truth_state,conflict_state
) values
(
  'f3000000-0000-4000-8000-000000000141'::uuid,
  'f3000000-0000-4000-8000-000000000131'::uuid,
  'holds_role_at',
  'f3000000-0000-4000-8000-000000000121'::uuid,
  'Branch Manager',
  true,
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'management',
  'accepted_current',
  'none'
),
(
  'f3000000-0000-4000-8000-000000000142'::uuid,
  'f3000000-0000-4000-8000-000000000132'::uuid,
  'holds_role_at',
  'f3000000-0000-4000-8000-000000000121'::uuid,
  'Community Officer',
  true,
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'community_relations',
  'accepted_current',
  'none'
);

insert into local_intel.contact_points(
  id,entity_id,contact_type,contact_value,normalized_value,is_primary,
  verification_state,deliverability_state,marketing_status,last_checked_at,metadata
) values (
  'f3000000-0000-4000-8000-000000000151'::uuid,
  'f3000000-0000-4000-8000-000000000131'::uuid,
  'email',
  'avery@river-bank.example.invalid',
  'avery@river-bank.example.invalid',
  true,
  'source_verified',
  'unknown',
  'unassessed',
  now(),
  '{"validationFixture":true}'::jsonb
);

insert into atlas.contact_set_intent_requests(
  id,organization_id,requested_by_user_id,source_action_id,source_surface,literal_request,
  capture_context,request_state,interpretation,validation,execution_plan,interpreter_kind,interpreter_ref
) values (
  'f3000000-0000-4000-8000-000000000161'::uuid,
  'f3000000-0000-4000-8000-000000000101'::uuid,
  'f3000000-0000-4000-8000-000000000162'::uuid,
  'validation-contact-exec-request',
  'validation',
  'Find bank people in Marshfield and Springfield and get their emails.',
  '{"places":["Marshfield","Springfield"]}'::jsonb,
  'ready',
  '{
    "intentFamily":"build_target_contact_set",
    "objective":"mixed",
    "target":{
      "description":"bank people",
      "organizationKinds":["bank"],
      "namedOrganizations":[],
      "personFunctions":["decision_adjacent"],
      "titles":[],
      "include":[],
      "exclude":[],
      "similaritySeedEntityIds":[]
    },
    "geography":{
      "mode":"explicit",
      "placeLabels":["Marshfield","Springfield"],
      "basis":"literal request"
    },
    "fields":{
      "required":["email","name","title","organization"],
      "optional":["phone"]
    },
    "population":{
      "desiredCount":3,
      "mode":"exact_if_supported"
    },
    "ledgerEffect":{
      "attachToLedger":true,
      "effortTag":"contact_discovery",
      "roleKey":"contact"
    },
    "resolvedReferences":[],
    "unresolvedReferences":[],
    "clarificationQuestion":null
  }'::jsonb,
  '{"valid":true,"executionReady":true}'::jsonb,
  '{"contractVersion":"contact_set_execution_plan_v1"}'::jsonb,
  'ai',
  'validation-interpreter-v1'
);
