-- Clone-only pre-migration fixture for Shared Atlas contact-gap acquisition v1.
-- Requires the already-live Atlas contact-set execution preparation package.
insert into atlas.organizations(id,stable_key,name,status,onboarding_state,metadata)
values(
  'f4000000-0000-4000-8000-000000000101'::uuid,
  'validation-gap-acq-org',
  'Validation Gap Research Org',
  'active',
  'new',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.local_contexts(id,stable_key,organization_id,name,status,metadata)
values(
  'f4000000-0000-4000-8000-000000000111'::uuid,
  'validation-gap-origin-context',
  'f4000000-0000-4000-8000-000000000101'::uuid,
  'Validation Origin Context',
  'active',
  '{"validationFixture":true}'::jsonb
);

insert into local_intel.entities(
  id,stable_key,entity_type,name,website_url,email,city,state,status,verification_state,metadata,local_context_id
) values
(
  'f4000000-0000-4000-8000-000000000121'::uuid,
  'validation-gap-river-bank',
  'business',
  'Validation River Bank',
  'https://river-bank-gap.example.invalid',
  null,
  'Marshfield',
  'MO',
  'active',
  'source_verified',
  '{"category":"bank","validationFixture":true}'::jsonb,
  'f4000000-0000-4000-8000-000000000111'::uuid
),
(
  'f4000000-0000-4000-8000-000000000131'::uuid,
  'validation-gap-avery-reed',
  'person',
  'Avery Reed',
  null,
  null,
  'Marshfield',
  'MO',
  'active',
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'f4000000-0000-4000-8000-000000000111'::uuid
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
)
on conflict (relationship_kind) do nothing;

insert into local_intel.entity_relationships(
  id,subject_entity_id,relationship_kind,object_entity_id,role_title,is_current,
  verification_state,metadata,role_function,truth_state,conflict_state
) values (
  'f4000000-0000-4000-8000-000000000141'::uuid,
  'f4000000-0000-4000-8000-000000000131'::uuid,
  'holds_role_at',
  'f4000000-0000-4000-8000-000000000121'::uuid,
  'Branch Director',
  true,
  'source_verified',
  '{"validationFixture":true}'::jsonb,
  'management',
  'accepted_current',
  'none'
);

insert into atlas.contact_set_intent_requests(
  id,organization_id,requested_by_user_id,source_action_id,source_surface,literal_request,
  capture_context,request_state,interpretation,validation,execution_plan,interpreter_kind,interpreter_ref
) values (
  'f4000000-0000-4000-8000-000000000151'::uuid,
  'f4000000-0000-4000-8000-000000000101'::uuid,
  'f4000000-0000-4000-8000-000000000152'::uuid,
  'validation-gap-acq-request',
  'validation',
  'Find the bank contact email in Marshfield.',
  '{"places":["Marshfield"]}'::jsonb,
  'ready',
  '{
    "intentFamily":"build_target_contact_set",
    "objective":"enrich",
    "target":{
      "description":"bank contact",
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
      "placeLabels":["Marshfield"],
      "basis":"literal request"
    },
    "fields":{
      "required":["email","name","title","organization"],
      "optional":[]
    },
    "population":{
      "desiredCount":1,
      "mode":"exact_if_supported"
    },
    "ledgerEffect":{
      "attachToLedger":true,
      "effortTag":"contact_research",
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

insert into atlas.contact_set_execution_runs(
  id,request_id,organization_id,execution_state,required_fields,desired_count,selected_count,
  directory_snapshot,gap_snapshot,ledger_effect_snapshot
) values (
  'f4000000-0000-4000-8000-000000000161'::uuid,
  'f4000000-0000-4000-8000-000000000151'::uuid,
  'f4000000-0000-4000-8000-000000000101'::uuid,
  'needs_acquisition',
  array['email','name','title','organization']::text[],
  1,
  1,
  '{"candidateCount":1}'::jsonb,
  '{
    "contractVersion":"contact_set_gap_snapshot_v1",
    "gapCount":1,
    "populationGap":false,
    "researchTargets":[
      {
        "gapKind":"entity_field_gap",
        "entityId":"f4000000-0000-4000-8000-000000000131",
        "organizationEntityId":"f4000000-0000-4000-8000-000000000121",
        "missingFields":["email"],
        "reason":"Canonical subject exists but required email is missing."
      }
    ]
  }'::jsonb,
  '{"attachToLedger":true,"roleKey":"contact","results":[],"communicationAuthorized":false}'::jsonb
);
