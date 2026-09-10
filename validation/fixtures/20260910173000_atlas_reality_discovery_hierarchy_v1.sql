-- Validation-only fixture for the schema-only disposable production clone.
-- Production already contains these base Reality Discovery question rows from
-- 20260910150000_atlas_reality_discovery_graph_v1. The production-schema clone
-- restores schema but intentionally not table data, so this fixture recreates
-- only the prerequisite catalog rows that 173000 extends with additional edges.

insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,answer_kind,options,
  base_score,friction,consequence_value,information_gain,
  resolved_signal_key,reason_text,metadata,active
) values
('children.school_calendar','people','Do any of the kids use a school, preschool, or daycare calendar?','yes_no',
 '[{"key":"yes","label":"yes"},{"key":"no","label":"no"}]'::jsonb,
 45,1,65,75,'children.school_calendar','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true),
('grounds.responsibility','home','Are you responsible for any yard or land where you live?','single_choice',
 '[{"key":"yes","label":"yes"},{"key":"shared","label":"shared"},{"key":"service","label":"someone else handles it"},{"key":"none","label":"no"}]'::jsonb,
 40,1,55,75,'grounds.responsibility','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true),
('grounds.mowing_method','home','How does mowing usually get handled?','single_choice',
 '[{"key":"push","label":"push mower"},{"key":"riding","label":"riding mower"},{"key":"tractor","label":"tractor"},{"key":"service","label":"lawn service"},{"key":"other","label":"something else"},{"key":"none","label":"we do not mow"}]'::jsonb,
 30,1,45,70,'grounds.mowing_method','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true),
('equipment.riding_mower_identity','home','What riding mower is it?','single_choice',
 '[{"key":"john_deere","label":"John Deere"},{"key":"cub_cadet","label":"Cub Cadet"},{"key":"husqvarna","label":"Husqvarna"},{"key":"other","label":"other"},{"key":"not_sure","label":"not sure"}]'::jsonb,
 20,1,45,55,'equipment.riding_mower_brand','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true),
('transport.vehicle_count','transport','Are you responsible for any vehicles?','single_choice',
 '[{"key":"none","label":"none"},{"key":"one","label":"one"},{"key":"two_plus","label":"two or more"},{"key":"other","label":"something else"}]'::jsonb,
 65,1,85,90,'transport.vehicle_count','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true),
('animals.responsibility','animals','Are there animals you are responsible for?','single_choice',
 '[{"key":"none","label":"none"},{"key":"dog","label":"dog"},{"key":"cat","label":"cat"},{"key":"livestock","label":"livestock"},{"key":"other","label":"other"}]'::jsonb,
 35,1,45,60,'animals.responsibility','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true),
('laundry.location','home','How does laundry work where you live?','single_choice',
 '[{"key":"home","label":"machines in my home"},{"key":"building","label":"shared building machines"},{"key":"laundromat","label":"laundromat"},{"key":"service","label":"service / someone else"},{"key":"other","label":"other"}]'::jsonb,
 25,1,35,55,'laundry.location','Validation fixture for the already-live base Discovery catalog.','{}'::jsonb,true);
