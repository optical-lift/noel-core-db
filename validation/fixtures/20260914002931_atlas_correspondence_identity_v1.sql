-- Data-only prerequisite fixture for Atlas Correspondence Identity v1.
-- Disposable production-schema clone only.

insert into auth.users(id,aud,role,email,created_at,updated_at)
values(
  '33333333-3333-4333-8333-333333333333'::uuid,
  'authenticated','authenticated','correspondence-owner@example.invalid',now(),now()
);

insert into atlas.organizations(id,stable_key,name,status,metadata,onboarding_state) values
('81818181-8181-4181-8181-818181818181'::uuid,'correspondence_identity_fixture','Correspondence Identity Fixture','active','{"validation_fixture":true}'::jsonb,'ready'),
('91919191-9191-4191-8191-919191919191'::uuid,'correspondence_identity_other_fixture','Other Correspondence Fixture','active','{"validation_fixture":true}'::jsonb,'ready');

insert into atlas.organization_units(id,organization_id,parent_unit_id,stable_key,name,unit_kind,status,metadata) values
('82828282-8282-4282-8282-828282828282'::uuid,'81818181-8181-4181-8181-818181818181'::uuid,null,'primary','Primary Endeavor','operating_business','active','{"validation_fixture":true}'::jsonb),
('92929292-9292-4292-8292-929292929292'::uuid,'91919191-9191-4191-8191-919191919191'::uuid,null,'other','Other Endeavor','operating_business','active','{"validation_fixture":true}'::jsonb);

insert into atlas.organization_memberships(id,organization_id,user_id,role,active,permissions) values
('83838383-8383-4383-8383-838383838383'::uuid,'81818181-8181-4181-8181-818181818181'::uuid,'33333333-3333-4333-8333-333333333333'::uuid,'owner',true,'{}'::jsonb),
('93939393-9393-4393-8393-939393939393'::uuid,'91919191-9191-4191-8191-919191919191'::uuid,'33333333-3333-4333-8333-333333333333'::uuid,'owner',true,'{}'::jsonb);

insert into atlas.communication_endpoints(
  id,organization_id,organization_unit_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata
) values
('84848484-8484-4484-8484-848484848484'::uuid,'81818181-8181-4181-8181-818181818181'::uuid,'82828282-8282-4282-8282-828282828282'::uuid,'email','hello@primary.invalid','hello@primary.invalid','Primary Hello','active','{"validation_fixture":true}'::jsonb),
('85858585-8585-4585-8585-858585858585'::uuid,'81818181-8181-4181-8181-818181818181'::uuid,'82828282-8282-4282-8282-828282828282'::uuid,'email','info@primary.invalid','info@primary.invalid','Primary Info','active','{"validation_fixture":true}'::jsonb),
('94949494-9494-4494-8494-949494949494'::uuid,'91919191-9191-4191-8191-919191919191'::uuid,'92929292-9292-4292-8292-929292929292'::uuid,'email','hello@other.invalid','hello@other.invalid','Other Hello','active','{"validation_fixture":true}'::jsonb);
