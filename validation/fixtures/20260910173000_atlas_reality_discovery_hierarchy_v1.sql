-- Validation-only prerequisite rows for the schema-only production clone.
-- The real rows already exist in production from 20260910150000; this fixture
-- supplies only their foreign-key identities for local candidate validation.

insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,answer_kind,options,
  base_score,friction,consequence_value,information_gain,
  resolved_signal_key,reason_text,metadata,active
) values
('children.school_calendar','people','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true),
('grounds.responsibility','home','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true),
('grounds.mowing_method','home','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true),
('equipment.riding_mower_identity','home','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true),
('transport.vehicle_count','transport','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true),
('animals.responsibility','animals','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true),
('laundry.location','home','Fixture','yes_no','[]'::jsonb,0,1,0,0,null,'Fixture','{}'::jsonb,true);
