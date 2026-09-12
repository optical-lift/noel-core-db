-- Data-only prerequisite fixture for the disposable production-schema clone.
-- Feast Guild / Elm / hello@elmfarm.co mirror current production identities.
insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values
('818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'feast_guild','Feast Guild','active','{"validation_fixture":true}'::jsonb,'ready'),
('11111111-1111-4111-8111-111111111111'::uuid,'addressability_claim_fixture','Addressability Claim Fixture','active','{"validation_fixture":true}'::jsonb,'ready');

insert into atlas.organization_units(id,organization_id,parent_unit_id,stable_key,name,unit_kind,status,metadata) values
('1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null,'elm','Elm','operating_business','active','{"validation_fixture":true}'::jsonb),
('22222222-2222-4222-8222-222222222222'::uuid,'11111111-1111-4111-8111-111111111111'::uuid,null,'external_claim_target','External Claim Target','operating_unit','active','{"validation_fixture":true}'::jsonb);

insert into atlas.communication_endpoints(id,organization_id,organization_unit_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata) values
('7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,'email','hello@elmfarm.co','hello@elmfarm.co','Elm Farm','active','{"validation_fixture":true}'::jsonb);
