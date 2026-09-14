-- Data-only fixture for Atlas Teaching Existing Subject Binding v1.
-- Run only in the disposable production-schema clone before the candidate migration.

insert into auth.users(id) values
  ('a2100000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('a2100000-0000-4000-8000-000000000011'::uuid,'Teaching Existing Subject Fixture Root','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values (
  'a2100000-0000-4000-8000-000000000021'::uuid,
  'a2100000-0000-4000-8000-000000000011'::uuid,
  'supabase_auth_user',
  'a2100000-0000-4000-8000-000000000001'::uuid,
  'active',now(),'{"validation_fixture":true}'::jsonb
);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values (
  'a2100000-0000-4000-8000-000000000031'::uuid,
  'a2100000-0000-4000-8000-000000000001'::uuid,
  null,
  'teaching_existing_subject_fixture_root',
  'Teaching Existing Subject Fixture Root',
  'America/Chicago','active','{"validation_fixture":true}'::jsonb,
  'a2100000-0000-4000-8000-000000000011'::uuid
);

insert into atlas.ledgers(id,stable_key,name,organization_id,ledger_kind,status,metadata) values
  (
    'a2200000-0000-4000-8000-000000000001'::uuid,
    'teachingexistingsubjectroot001',
    'Teaching Existing Subject Root Ledger',
    null,'governed_reality','active','{"validation_fixture":true}'::jsonb
  ),
  (
    'a2200000-0000-4000-8000-000000000002'::uuid,
    'teachingexistingsubjectother01',
    'Teaching Existing Subject Other Ledger',
    null,'governed_reality','active','{"validation_fixture":true}'::jsonb
  );

insert into atlas.capability_definitions(capability_key,capability_version,status,eligible_subject_kinds)
values ('teaching',1,'active',array['ledger']::text[]);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values
  (
    'a2300000-0000-4000-8000-000000000001'::uuid,
    'a2100000-0000-4000-8000-000000000031'::uuid,
    'a2200000-0000-4000-8000-000000000001'::uuid,
    'root_governing','active','teaching_existing_subject_validation','{"validation_fixture":true}'::jsonb
  ),
  (
    'a2300000-0000-4000-8000-000000000002'::uuid,
    'a2100000-0000-4000-8000-000000000031'::uuid,
    'a2200000-0000-4000-8000-000000000002'::uuid,
    'root_governing','active','teaching_existing_subject_validation','{"validation_fixture":true}'::jsonb
  );

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values (
  'a2400000-0000-4000-8000-000000000001'::uuid,
  'teaching_existing_subject_fixture_org',
  'Teaching Existing Subject Fixture Organization',
  'active','{"validation_fixture":true}'::jsonb,'ready'
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values
  (
    'a2400000-0000-4000-8000-000000000011'::uuid,
    'a2200000-0000-4000-8000-000000000001'::uuid,
    'a2400000-0000-4000-8000-000000000001'::uuid,
    'governing',false,'active','{"source":"teaching_existing_subject_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
  ),
  (
    'a2400000-0000-4000-8000-000000000012'::uuid,
    'a2200000-0000-4000-8000-000000000002'::uuid,
    'a2400000-0000-4000-8000-000000000001'::uuid,
    'participating',false,'active','{"source":"teaching_existing_subject_validation"}'::jsonb,'{"validation_fixture":true}'::jsonb
  );

insert into atlas.organization_ledger_entries(
  id,organization_id,event_key,source_domain,semantic_type,source_event_key,
  occurred_at,title,detail,truth_status,designation_status,payload,provenance,correlation,ledger_id
) values
  (
    'a2500000-0000-4000-8000-000000000001'::uuid,
    'a2400000-0000-4000-8000-000000000001'::uuid,
    'teaching-source-entry-1','validation','teaching_source','source-1',
    now(),'Existing governed subject one','First same-Ledger subject for Teach this.',
    'established','designated','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb,'{}'::jsonb,
    'a2200000-0000-4000-8000-000000000001'::uuid
  ),
  (
    'a2500000-0000-4000-8000-000000000002'::uuid,
    'a2400000-0000-4000-8000-000000000001'::uuid,
    'teaching-source-entry-2','validation','teaching_source','source-2',
    now(),'Existing governed subject two','Second same-Ledger subject for source-conflict proof.',
    'established','designated','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb,'{}'::jsonb,
    'a2200000-0000-4000-8000-000000000001'::uuid
  ),
  (
    'a2500000-0000-4000-8000-000000000003'::uuid,
    'a2400000-0000-4000-8000-000000000001'::uuid,
    'teaching-source-entry-other','validation','teaching_source','source-other',
    now(),'Other Ledger governed subject','Cross-Ledger negative proof subject.',
    'established','designated','{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb,'{}'::jsonb,
    'a2200000-0000-4000-8000-000000000002'::uuid
  );
