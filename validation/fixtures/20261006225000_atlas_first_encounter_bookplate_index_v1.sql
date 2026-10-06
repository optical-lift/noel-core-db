delete from atlas.reality_discovery_edges
where question_key='family.children_stage';

delete from atlas.reality_discovery_questions
where question_key='family.children_stage';

insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,
  base_score,friction,consequence_value,information_gain,resolved_signal_key,
  reason_text,active,metadata
) values (
  'family.children_stage','people','Children?',null,'single_choice',
  '[{"key":"minor","label":"minor"},{"key":"adult","label":"adult"},{"key":"both","label":"both"}]'::jsonb,
  88,1,78,98,'family.children_stage',
  'A parent relationship persists across the child life course, while child age stage is distinct from current household topology.',
  true,
  '{"encounterCluster":"family","orientationScaleKeys":["children","household"],"encounterClusterLabel":"FAMILY","orientationWorldDomains":["family"],"orientationPositionPairs":["family:parent"]}'::jsonb
);

insert into atlas.reality_discovery_edges(
  question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text
) values
(
  'family.children_stage','orientation.family_parent','eq','true'::jsonb,'require',0,
  'Ask child life stage only after the human explicitly identifies as a parent.'
),
(
  'family.children_stage','identity.age_band','in','["midlife","older_adult"]'::jsonb,'boost',35,
  'Later chronology raises the information value of distinguishing grown children from children at home.'
);
