-- Disposable clone ONLY: synthetic Atlas persons; never production data.
insert into auth.users(
 id,instance_id,aud,role,email,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
 ('60000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','week-fit-a@example.invalid',now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now()),
 ('60000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','week-fit-b@example.invalid',now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now());

insert into atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
values
 ('60000000-0000-4000-8000-000000000001','clone-week-fit-a','Clone Weekly Fit A','America/Chicago','active','{"origin":"isolated_clone_fixture"}'::jsonb),
 ('60000000-0000-4000-8000-000000000002','clone-week-fit-b','Clone Weekly Fit B','America/Chicago','active','{"origin":"isolated_clone_fixture"}'::jsonb);

-- Establish the actual current Household for each preexisting synthetic Principal.
-- begin_personal_atlas_self_api_v1 treats an existing Principal as established;
-- it does not create a Household for an artificially preseeded Principal.
insert into atlas.households(principal_id,stable_key,name,timezone,status,metadata)
select p.id,'home','Home','America/Chicago','active',
       '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id in (
 '60000000-0000-4000-8000-000000000001',
 '60000000-0000-4000-8000-000000000002'
);

update atlas.principals p
set active_household_id=h.id, updated_at=now()
from atlas.households h
where h.principal_id=p.id and h.stable_key='home'
 and p.user_id in (
  '60000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000002'
 );

insert into atlas.household_members(
 household_id,user_id,display_name,relationship,household_role,active,metadata
)
select p.active_household_id,p.user_id,p.name,'self','principal',true,
       '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id in (
 '60000000-0000-4000-8000-000000000001',
 '60000000-0000-4000-8000-000000000002'
);

insert into atlas.personal_atlas_access_grants(principal_id,grant_kind,state,basis)
select id,'complimentary_testing','active','{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals where user_id in (
'60000000-0000-4000-8000-000000000001',
'60000000-0000-4000-8000-000000000002'
);

insert into atlas.world_kernel_definitions(kernel_key,version,scope_kind,title,definition,active)
values ('household.cleaning',1,'household','House cleaning','{"ordinary":true,"source":"isolated_clone_fixture"}'::jsonb,true);

insert into atlas.world_kernel_models(
 kernel_key,kernel_version,audience_key,model_key,title,summary,configuration,position,active
) values (
 'household.cleaning',1,'general','cleaning_weekly_reset','Weekly reset',
 'Synthetic test source estimate','{"expectedMinutes":30,"usualPattern":"weekly"}'::jsonb,1,true
);
