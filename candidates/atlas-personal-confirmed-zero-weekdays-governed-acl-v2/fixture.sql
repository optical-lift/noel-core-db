-- Disposable production-schema clone ONLY, not founder/user data.
insert into auth.users(
 id,instance_id,aud,role,email,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
('62000000-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','policy-reader-a@example.invalid',now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now()),
('62000000-0000-4000-8000-000000000002',
 '00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','policy-reader-b@example.invalid',now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now());

insert into atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
values
('62000000-0000-4000-8000-000000000001','ci-capacity-membrane-a',
 'Synthetic Capacity Principal A','America/Chicago','active',
 '{"origin":"isolated_clone_fixture"}'::jsonb),
('62000000-0000-4000-8000-000000000002','ci-capacity-membrane-b',
 'Synthetic Capacity Principal B','America/Chicago','active',
 '{"origin":"isolated_clone_fixture"}'::jsonb);

insert into atlas.households(principal_id,stable_key,name,timezone,status,metadata)
select p.id,'home','Synthetic Home','America/Chicago','active',
 '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id in (
 '62000000-0000-4000-8000-000000000001',
 '62000000-0000-4000-8000-000000000002'
);
update atlas.principals p
set active_household_id=h.id,updated_at=now()
from atlas.households h
where h.principal_id=p.id and h.stable_key='home'
 and p.user_id in (
 '62000000-0000-4000-8000-000000000001',
 '62000000-0000-4000-8000-000000000002'
);
insert into atlas.household_members(
 household_id,user_id,display_name,relationship,household_role,active,metadata
)
select p.active_household_id,p.user_id,p.name,'self','principal',true,
 '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id in (
 '62000000-0000-4000-8000-000000000001',
 '62000000-0000-4000-8000-000000000002'
);

-- Existing synthetic Principals need an active Personal access grant so the
-- real already-established enrollment path can canonically admit their Person.
-- This is disposable-clone DML, not a production entitlement.
insert into atlas.personal_atlas_access_grants(principal_id,grant_kind,state,basis)
select p.id,'complimentary_testing','active',
       '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id in (
 '62000000-0000-4000-8000-000000000001',
 '62000000-0000-4000-8000-000000000002'
);

-- A genuine kernel source model makes weekly-fit positive proof meaningful.
insert into atlas.world_kernel_definitions(kernel_key,version,scope_kind,title,definition,active)
values ('household.cleaning',1,'household','House cleaning',
        '{"ordinary":true,"source":"isolated_clone_fixture"}'::jsonb,true);
insert into atlas.world_kernel_models(
  kernel_key,kernel_version,audience_key,model_key,title,summary,configuration,position,active
) values ('household.cleaning',1,'general','clone-cleaning-estimate','Weekly home care',
 'Synthetic known estimate','{"expectedMinutes":30,"usualPattern":"weekly"}'::jsonb,1,true);
