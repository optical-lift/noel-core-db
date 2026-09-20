do $fixture$
declare
  v_org uuid:='96200000-0000-0000-0000-000000000001'::uuid;
  v_other_org uuid:='96200000-0000-0000-0000-000000000002'::uuid;
begin
  insert into auth.users(id,email,created_at,updated_at)
  values
    ('96100000-0000-0000-0000-000000000001'::uuid,'endpoint-owner@example.test',now(),now()),
    ('96100000-0000-0000-0000-000000000002'::uuid,'endpoint-bounded-owner@example.test',now(),now()),
    ('96100000-0000-0000-0000-000000000003'::uuid,'endpoint-member@example.test',now(),now()),
    ('96100000-0000-0000-0000-000000000004'::uuid,'endpoint-other-org@example.test',now(),now()),
    ('96100000-0000-0000-0000-000000000005'::uuid,'endpoint-later-owner@example.test',now(),now());

  insert into atlas.organizations(id,stable_key,name,status)
  values
    (v_org,'endpoint-knowledge-fixture-org','Endpoint Knowledge Fixture','active'),
    (v_other_org,'endpoint-knowledge-fixture-other','Endpoint Knowledge Other','active');

  insert into atlas.organization_memberships(
    id,organization_id,user_id,role,active,permissions,eligibility_begins_on
  )
  values
    ('96300000-0000-0000-0000-000000000001'::uuid,v_org,'96100000-0000-0000-0000-000000000001'::uuid,'owner',true,'{}'::jsonb,null),
    ('96300000-0000-0000-0000-000000000002'::uuid,v_org,'96100000-0000-0000-0000-000000000002'::uuid,'owner',true,'{}'::jsonb,date '2099-01-01'),
    ('96300000-0000-0000-0000-000000000003'::uuid,v_org,'96100000-0000-0000-0000-000000000003'::uuid,'member',true,'{}'::jsonb,null),
    ('96300000-0000-0000-0000-000000000004'::uuid,v_other_org,'96100000-0000-0000-0000-000000000004'::uuid,'member',true,'{}'::jsonb,null);

  insert into atlas.communication_endpoints(
    id,organization_id,endpoint_kind,address,address_normalized,display_name,endpoint_state,metadata
  ) values(
    '96400000-0000-0000-0000-000000000001'::uuid,
    v_org,
    'email',
    'fixture@example.test',
    'fixture@example.test',
    'Fixture inbox',
    'active',
    '{}'::jsonb
  );
end;
$fixture$;
