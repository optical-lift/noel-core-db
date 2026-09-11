-- Validation-only rows for the schema-only production clone.
-- This fixture creates one disposable Principal whose only unanswered Discovery
-- question is the deliberately over-scored riding-mower specialization.

insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous)
values('11111111-1111-4111-8111-111111111111','authenticated','authenticated','encounter-admission-fixture@example.invalid',now(),now(),false,false);

insert into atlas.principals(id,user_id,stable_key,name,status,metadata)
values('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','fixture-encounter-admission','Encounter Admission Fixture','active','{}'::jsonb);

insert into atlas.households(id,principal_id,stable_key,name,status,metadata)
values('33333333-3333-4333-8333-333333333333','22222222-2222-4222-8222-222222222222','fixture-home','Fixture Home','active','{}'::jsonb);

update atlas.principals
set active_household_id='33333333-3333-4333-8333-333333333333'
where id='22222222-2222-4222-8222-222222222222';

insert into atlas.household_members(household_id,user_id,display_name,relationship,household_role,active,metadata)
values('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','Fixture Principal','self','principal',true,'{}'::jsonb);

insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,answer_kind,options,
  base_score,friction,consequence_value,information_gain,
  resolved_signal_key,reason_text,metadata,active
) values
('home.confirm_purchase_address','home','Fixture address','yes_no','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('household.people_shape','people','Fixture household','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('home.tenure','home','Fixture tenure','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('home.major_repairs','home','Fixture repairs','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('home.setting','home','Fixture setting','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('home.dwelling_kind','home','Fixture dwelling','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('grounds.responsibility','home','Fixture grounds','yes_no','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('transport.vehicle_count','transport','Fixture vehicles','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('household.child_count','people','Fixture children','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('children.school_calendar','people','Fixture school','yes_no','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('animals.responsibility','animals','Fixture animals','yes_no','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('life.weekday_anchor','life','Fixture weekday','short_text','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('laundry.location','home','Fixture laundry','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('grounds.scale','home','Fixture grounds scale','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('grounds.mowing_method','home','Fixture mowing','single_select','[]'::jsonb,100,1,0,0,null,'Fixture','{}'::jsonb,true),
('equipment.riding_mower_identity','home','Fixture mower identity','short_text','[]'::jsonb,10000,0,10000,10000,null,'Fixture highest-ranked specialization','{}'::jsonb,true);

insert into atlas.reality_discovery_answer_events(
  principal_id,owner_user_id,question_key,source_action_id,answer_value,metadata
) values
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','home.confirm_purchase_address','fixture-01','"no"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','household.people_shape','fixture-02','"one_person"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','home.tenure','fixture-03','"own"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','home.major_repairs','fixture-04','"me"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','home.setting','fixture-05','"rural"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','home.dwelling_kind','fixture-06','"house"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','grounds.responsibility','fixture-07','"yes"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','transport.vehicle_count','fixture-08','"1"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','household.child_count','fixture-09','"0"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','children.school_calendar','fixture-10','"no"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','animals.responsibility','fixture-11','"no"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','life.weekday_anchor','fixture-12','"workdays"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','laundry.location','fixture-13','"home"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','grounds.scale','fixture-14','"acreage"'::jsonb,'{}'::jsonb),
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','grounds.mowing_method','fixture-15','"riding"'::jsonb,'{}'::jsonb);
