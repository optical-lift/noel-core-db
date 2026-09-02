-- Remove redundant anonymous SELECT grants from Atlas operational relations.
-- All listed relations have RLS enabled and no anon/PUBLIC row policy.
-- Authenticated and service-role privileges are unchanged.

revoke select on table
  atlas.action_requirement_templates,
  atlas.crop_profiles,
  atlas.farms,
  atlas.field_log_objects,
  atlas.field_logs,
  atlas.growing_objects,
  atlas.object_contents,
  atlas.object_state,
  atlas.planting_claim_objects,
  atlas.planting_claims,
  atlas.project_goals,
  atlas.project_steps,
  atlas.projects,
  atlas.resources,
  atlas.task_objects,
  atlas.task_resource_requirements,
  atlas.zones
from anon;