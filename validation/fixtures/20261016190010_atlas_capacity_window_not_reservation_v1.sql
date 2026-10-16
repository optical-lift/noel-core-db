-- Disposable production-schema clone ONLY. Synthetic identities and no private data.
insert into auth.users(
 id,instance_id,aud,role,email,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
 '61000000-0000-4000-8000-000000000001',
 '00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','capacity-window-guard@example.invalid',now(),
 '{"provider":"email","providers":["email"]}'::jsonb,'{}'::jsonb,now(),now()
);

insert into atlas.principals(user_id,stable_key,name,home_timezone,status,metadata)
values (
 '61000000-0000-4000-8000-000000000001',
 'ci-capacity-window-principal','Capacity Window Test','America/Chicago','active',
 '{"origin":"isolated_clone_fixture"}'::jsonb
);

-- Real production trigger creates the five automatic protected-attention zones.
insert into atlas.households(principal_id,stable_key,name,timezone,status,metadata)
select p.id,'home','Synthetic Home','America/Chicago','active',
 '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id='61000000-0000-4000-8000-000000000001';

update atlas.principals p
set active_household_id=h.id,updated_at=now()
from atlas.households h
where h.principal_id=p.id and h.stable_key='home'
  and p.user_id='61000000-0000-4000-8000-000000000001';

insert into atlas.household_members(
 household_id,user_id,display_name,relationship,household_role,active,metadata
)
select p.active_household_id,p.user_id,p.name,'self','principal',true,
 '{"origin":"isolated_clone_fixture"}'::jsonb
from atlas.principals p
where p.user_id='61000000-0000-4000-8000-000000000001';

insert into atlas.principal_capacity_policies(
 principal_id,stable_key,name,weekdays,local_start,local_end,
 default_discretionary_minutes,maximum_planned_minutes,effective_from,active
)
select p.id,'ci-all-days-policy','Synthetic known daily capacity',
 array[0,1,2,3,4,5,6]::smallint[],
 '08:00'::time,'18:00'::time,120,120,
 ((statement_timestamp() at time zone 'America/Chicago')::date - 7),true
from atlas.principals p
where p.user_id='61000000-0000-4000-8000-000000000001';
