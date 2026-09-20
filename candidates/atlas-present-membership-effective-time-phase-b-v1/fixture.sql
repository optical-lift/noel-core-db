-- Data-only fixture for Present Organization Membership Effective Time Phase B.
-- Apply to a disposable production-schema clone after Phase A is present and before candidate.sql.

insert into auth.users(id) values
  ('eb100000-0000-4000-8000-000000000001'::uuid),
  ('eb200000-0000-4000-8000-000000000001'::uuid),
  ('eb300000-0000-4000-8000-000000000001'::uuid),
  ('eb400000-0000-4000-8000-000000000001'::uuid),
  ('eb500000-0000-4000-8000-000000000001'::uuid),
  ('eb600000-0000-4000-8000-000000000001'::uuid),
  ('eb700000-0000-4000-8000-000000000001'::uuid);

insert into atlas.people(id,display_name,status,metadata) values
  ('eb100000-0000-4000-8000-000000000011'::uuid,'Phase B Current Member','active','{"validation_fixture":true}'::jsonb),
  ('eb200000-0000-4000-8000-000000000011'::uuid,'Phase B Current Owner','active','{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000011'::uuid,'Phase B Future Root Owner','active','{"validation_fixture":true}'::jsonb),
  ('eb400000-0000-4000-8000-000000000011'::uuid,'Phase B Expired Member','active','{"validation_fixture":true}'::jsonb),
  ('eb500000-0000-4000-8000-000000000011'::uuid,'Phase B Unbounded No Context','active','{"validation_fixture":true}'::jsonb),
  ('eb700000-0000-4000-8000-000000000011'::uuid,'Phase B Bounded No Context','active','{"validation_fixture":true}'::jsonb);

insert into atlas.person_auth_credentials(
  id,person_id,credential_kind,auth_user_id,status,bound_at,provenance
) values
  ('eb100000-0000-4000-8000-000000000021'::uuid,'eb100000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','eb100000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('eb200000-0000-4000-8000-000000000021'::uuid,'eb200000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','eb200000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000021'::uuid,'eb300000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','eb300000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('eb400000-0000-4000-8000-000000000021'::uuid,'eb400000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','eb400000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('eb500000-0000-4000-8000-000000000021'::uuid,'eb500000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','eb500000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb),
  ('eb700000-0000-4000-8000-000000000021'::uuid,'eb700000-0000-4000-8000-000000000011'::uuid,'supabase_auth_user','eb700000-0000-4000-8000-000000000001'::uuid,'active',now(),'{"validation_fixture":true}'::jsonb);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values
  ('eb010000-0000-4000-8000-000000000001'::uuid,'elm_farm','Phase B Elm Shape','active','{"validation_fixture":true}'::jsonb,'ready'),
  ('eb020000-0000-4000-8000-000000000001'::uuid,'phase_b_no_calendar_org','Phase B No Calendar Org','active','{"validation_fixture":true}'::jsonb,'ready');

insert into atlas.organization_membership_calendar_contexts(
  id,organization_id,timezone_name,context_state,basis_kind,authority_evidence,metadata
) values (
  'eb010000-0000-4000-8000-000000000901'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'America/Chicago','active','current_state_compatibility_adjudication',
  '{"authorityKind":"validation_fixture"}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.identity_subjects(
  id,organization_id,state,created_by_user_id,creation_basis
) values
  ('eb100000-0000-4000-8000-000000000041'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'active','eb100000-0000-4000-8000-000000000001'::uuid,'{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000041'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'active','eb300000-0000-4000-8000-000000000001'::uuid,'{"validation_fixture":true}'::jsonb);

-- Begin unbounded so current production Endpoint grant guards can establish exact grants.
insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,permissions,identity_subject_id,person_id
) values
  ('eb100000-0000-4000-8000-000000000031'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb100000-0000-4000-8000-000000000001'::uuid,'member',true,'{}'::jsonb,'eb100000-0000-4000-8000-000000000041'::uuid,'eb100000-0000-4000-8000-000000000011'::uuid),
  ('eb200000-0000-4000-8000-000000000031'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb200000-0000-4000-8000-000000000001'::uuid,'owner',true,'{}'::jsonb,null,'eb200000-0000-4000-8000-000000000011'::uuid),
  ('eb300000-0000-4000-8000-000000000031'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb300000-0000-4000-8000-000000000001'::uuid,'owner',true,'{}'::jsonb,'eb300000-0000-4000-8000-000000000041'::uuid,'eb300000-0000-4000-8000-000000000011'::uuid),
  ('eb400000-0000-4000-8000-000000000031'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb400000-0000-4000-8000-000000000001'::uuid,'member',true,'{}'::jsonb,null,'eb400000-0000-4000-8000-000000000011'::uuid),
  ('eb500000-0000-4000-8000-000000000031'::uuid,'eb020000-0000-4000-8000-000000000001'::uuid,'eb500000-0000-4000-8000-000000000001'::uuid,'member',true,'{}'::jsonb,null,'eb500000-0000-4000-8000-000000000011'::uuid),
  ('eb700000-0000-4000-8000-000000000031'::uuid,'eb020000-0000-4000-8000-000000000001'::uuid,'eb700000-0000-4000-8000-000000000001'::uuid,'member',true,'{}'::jsonb,null,'eb700000-0000-4000-8000-000000000011'::uuid);

insert into atlas.organization_onboarding_actors(
  organization_id,human_user_id,actor_kind,active,metadata
) values (
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'eb600000-0000-4000-8000-000000000001'::uuid,
  'setup_actor',true,'{"validation_fixture":true}'::jsonb
);

insert into atlas.principals(
  id,user_id,organization_id,stable_key,name,home_timezone,status,metadata,person_id
) values (
  'eb300000-0000-4000-8000-000000000051'::uuid,
  'eb300000-0000-4000-8000-000000000001'::uuid,
  null,'phase_b_future_root_principal','Phase B Future Root Owner',
  'Pacific/Honolulu','active','{"validation_fixture":true}'::jsonb,
  'eb300000-0000-4000-8000-000000000011'::uuid
);

insert into atlas.ledgers(
  id,stable_key,name,organization_id,ledger_kind,status,metadata
) values (
  'eb300000-0000-4000-8000-000000000061'::uuid,
  'phasebeffectivetimerootledger0001','Phase B Root Ledger',
  null,'governed_reality','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.principal_ledger_authorities(
  id,principal_id,ledger_id,authority_kind,status,basis,metadata
) values (
  'eb300000-0000-4000-8000-000000000071'::uuid,
  'eb300000-0000-4000-8000-000000000051'::uuid,
  'eb300000-0000-4000-8000-000000000061'::uuid,
  'root_governing','active','phase_b_effective_time_validation',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.ledger_organization_participations(
  id,ledger_id,organization_id,participation_kind,is_compatibility_primary,status,basis,metadata
) values (
  'eb300000-0000-4000-8000-000000000081'::uuid,
  'eb300000-0000-4000-8000-000000000061'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'governing',true,'active',
  '{"source":"phase_b_effective_time_validation"}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.communication_endpoints(
  id,organization_id,organization_unit_id,endpoint_kind,address,address_normalized,
  display_name,endpoint_state,metadata
) values (
  'eb010000-0000-4000-8000-000000000801'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  null,'email','phase-b@example.test','phase-b@example.test',
  'Phase B Endpoint','active','{"validation_fixture":true}'::jsonb
);

insert into atlas.communication_endpoint_member_grants(
  id,communication_endpoint_id,membership_id,capability,grant_state,
  granted_by_membership_id,grant_basis_kind,metadata
) values
  ('eb100000-0000-4000-8000-000000000801'::uuid,'eb010000-0000-4000-8000-000000000801'::uuid,'eb100000-0000-4000-8000-000000000031'::uuid,'view','active','eb200000-0000-4000-8000-000000000031'::uuid,'explicit_owner_grant','{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000801'::uuid,'eb010000-0000-4000-8000-000000000801'::uuid,'eb300000-0000-4000-8000-000000000031'::uuid,'view','active','eb200000-0000-4000-8000-000000000031'::uuid,'explicit_owner_grant','{"validation_fixture":true}'::jsonb),
  ('eb400000-0000-4000-8000-000000000801'::uuid,'eb010000-0000-4000-8000-000000000801'::uuid,'eb400000-0000-4000-8000-000000000031'::uuid,'view','active','eb200000-0000-4000-8000-000000000031'::uuid,'explicit_owner_grant','{"validation_fixture":true}'::jsonb);

insert into atlas.connected_sources(
  id,custodian_organization_id,provider_key,provider_account_key,display_label,
  authorization_state,granted_scopes,capabilities,metadata
) values (
  'eb010000-0000-4000-8000-000000000701'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'phase_b_provider','phase_b_account','Phase B Organization Source',
  'connected',array['read']::text[],'{"sync":true}'::jsonb,
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_units(
  id,organization_id,stable_key,name,unit_kind,status,metadata
) values (
  'eb010000-0000-4000-8000-000000000601'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'phase_b_unit','Phase B Unit','operating_unit','active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_positions(
  id,organization_id,organization_unit_id,stable_key,display_title,position_kind,status,metadata
) values (
  'eb010000-0000-4000-8000-000000000611'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'eb010000-0000-4000-8000-000000000601'::uuid,
  'phase_b_staff','Phase B Staff','staff','active',
  '{"validation_fixture":true}'::jsonb
);

insert into atlas.organization_employee_seats(
  id,organization_id,organization_membership_id,identity_subject_id,
  seat_class,status,billing_state,billing_unit_price_cents,metadata
) values
  ('eb100000-0000-4000-8000-000000000051'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb100000-0000-4000-8000-000000000031'::uuid,'eb100000-0000-4000-8000-000000000041'::uuid,'employee','active','active',700,'{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000051'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb300000-0000-4000-8000-000000000031'::uuid,'eb300000-0000-4000-8000-000000000041'::uuid,'employee','active','active',700,'{"validation_fixture":true}'::jsonb);

insert into atlas.organization_member_credentials(
  id,organization_id,organization_membership_id,employee_seat_id,identity_subject_id,
  credential_kind,auth_user_id,status,issued_by_organization_id,provenance
) values
  ('eb100000-0000-4000-8000-000000000061'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb100000-0000-4000-8000-000000000031'::uuid,'eb100000-0000-4000-8000-000000000051'::uuid,'eb100000-0000-4000-8000-000000000041'::uuid,'auth_user','eb100000-0000-4000-8000-000000000001'::uuid,'active','eb010000-0000-4000-8000-000000000001'::uuid,'{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000061'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb300000-0000-4000-8000-000000000031'::uuid,'eb300000-0000-4000-8000-000000000051'::uuid,'eb300000-0000-4000-8000-000000000041'::uuid,'auth_user','eb300000-0000-4000-8000-000000000001'::uuid,'active','eb010000-0000-4000-8000-000000000001'::uuid,'{"validation_fixture":true}'::jsonb);

insert into atlas.organization_position_appointments(
  id,organization_id,position_id,identity_subject_id,organization_membership_id,
  appointment_kind,status,begins_at,metadata
) values
  ('eb100000-0000-4000-8000-000000000071'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb010000-0000-4000-8000-000000000611'::uuid,'eb100000-0000-4000-8000-000000000041'::uuid,'eb100000-0000-4000-8000-000000000031'::uuid,'primary','active',now()-interval '1 day','{"validation_fixture":true}'::jsonb),
  ('eb300000-0000-4000-8000-000000000071'::uuid,'eb010000-0000-4000-8000-000000000001'::uuid,'eb010000-0000-4000-8000-000000000611'::uuid,'eb300000-0000-4000-8000-000000000041'::uuid,'eb300000-0000-4000-8000-000000000031'::uuid,'primary','active',now()-interval '1 day','{"validation_fixture":true}'::jsonb);

insert into atlas.work_items(
  id,organization_id,title,work_state,metadata,stable_key
) values (
  'eb010000-0000-4000-8000-000000000501'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'Phase B Work Item','open','{"validation_fixture":true}'::jsonb,
  'phase_b_work_item'
);

insert into atlas.work_allocations(
  id,organization_id,work_item_id,assignee_membership_id,assigned_by_membership_id,
  allocation_role,state,allocated_at,completed_at,metadata
) values (
  'eb010000-0000-4000-8000-000000000511'::uuid,
  'eb010000-0000-4000-8000-000000000001'::uuid,
  'eb010000-0000-4000-8000-000000000501'::uuid,
  'eb400000-0000-4000-8000-000000000031'::uuid,
  'eb200000-0000-4000-8000-000000000031'::uuid,
  'responsible','completed',now()-interval '2 days',now()-interval '1 day',
  '{"validation_fixture":true,"historical_truth":true}'::jsonb
);

-- Introduce Effective-Time boundaries only after current production guards have created
-- the exact Endpoint grant and employee/access fixtures.
update atlas.organization_memberships
set eligibility_begins_on=current_date-30,
    eligibility_ends_on=current_date+30
where id in (
  'eb100000-0000-4000-8000-000000000031'::uuid,
  'eb200000-0000-4000-8000-000000000031'::uuid
);

update atlas.organization_memberships
set eligibility_begins_on=current_date+30,
    eligibility_ends_on=current_date+60
where id='eb300000-0000-4000-8000-000000000031'::uuid;

update atlas.organization_memberships
set eligibility_begins_on=current_date-60,
    eligibility_ends_on=current_date-30
where id='eb400000-0000-4000-8000-000000000031'::uuid;

update atlas.organization_memberships
set eligibility_begins_on=current_date-30,
    eligibility_ends_on=current_date+30
where id='eb700000-0000-4000-8000-000000000031'::uuid;
