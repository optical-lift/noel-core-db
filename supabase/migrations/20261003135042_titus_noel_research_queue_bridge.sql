create unique index if not exists curriculum_findings_noel_research_request_key_uq
on titus.curriculum_findings(target_key)
where target_type = 'noel_research_request';

create or replace view titus.v_noel_research_queue as
select
  f.finding_id,
  f.target_key as queue_key,
  f.priority,
  f.status,
  f.curriculum_version_id,
  coalesce(f.source_provenance->>'object_type', 'project_research_question') as object_type,
  f.source_provenance->>'object_key' as object_key,
  coalesce(f.source_provenance->>'current_stage', 'canon_research_needed') as current_stage,
  f.source_provenance->>'already_completed' as already_completed,
  f.finding_text as noel_question,
  f.source_provenance->>'next_action' as next_action,
  f.source_provenance->>'writeback_target' as writeback_target,
  f.source_provenance->>'course_slug' as course_slug,
  f.source_provenance->>'slot_key' as slot_key,
  f.source_provenance->>'related_titus_target_type' as related_titus_target_type,
  f.source_provenance->>'related_titus_target_key' as related_titus_target_key,
  f.created_at,
  f.resolved_at
from titus.curriculum_findings f
where f.target_type = 'noel_research_request'
  and f.status in ('open','deferred');

comment on view titus.v_noel_research_queue is
'Titus-owned handoff queue: the Marlene-specific project state stays in Titus; Noel/Song is invoked only to answer the canon/truth question exposed by each row. Results must be written back to Titus rather than mirrored into parallel Marlene research state in Noel.';

revoke all on titus.v_noel_research_queue from public, anon, authenticated;

create or replace function intelligence.get_marlene_noel_queue()
returns table (
  finding_id uuid,
  queue_key text,
  priority text,
  status text,
  curriculum_version_id uuid,
  object_type text,
  object_key text,
  current_stage text,
  already_completed text,
  noel_question text,
  next_action text,
  writeback_target text,
  course_slug text,
  slot_key text,
  related_titus_target_type text,
  related_titus_target_key text,
  created_at timestamptz,
  resolved_at timestamptz
)
language sql
stable
security invoker
set search_path = pg_catalog, titus, intelligence
as $$
  select
    q.finding_id,
    q.queue_key,
    q.priority,
    q.status,
    q.curriculum_version_id,
    q.object_type,
    q.object_key,
    q.current_stage,
    q.already_completed,
    q.noel_question,
    q.next_action,
    q.writeback_target,
    q.course_slug,
    q.slot_key,
    q.related_titus_target_type,
    q.related_titus_target_key,
    q.created_at,
    q.resolved_at
  from titus.v_noel_research_queue q
  order by
    case q.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
    q.created_at,
    q.queue_key;
$$;

revoke all on function intelligence.get_marlene_noel_queue() from public, anon, authenticated;