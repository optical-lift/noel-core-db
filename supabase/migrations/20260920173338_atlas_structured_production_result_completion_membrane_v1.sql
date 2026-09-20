-- Structured Production Result Completion Membrane v1 candidate.
-- Candidate source only. Promote through the governed Supabase CLI migration generator.

begin;

create or replace function atlas.record_task_transition_v1(
  p_task_id uuid,
  p_transition text,
  p_idempotency_key text,
  p_target_date date default null,
  p_note text default null,
  p_reason text default null,
  p_lane_key text default null,
  p_work_key text default null,
  p_payload jsonb default '{}'::jsonb,
  p_existing_field_log_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_scoped_key text;
  v_bed_readiness jsonb;
begin
  if p_task_id is null then
    raise exception 'Task id is required.' using errcode='22023';
  end if;

  if p_transition in ('done','checklist_done')
     and exists (
       select 1
       from atlas.production_lot_tasks plt
       where plt.task_id=p_task_id
     )
     and atlas.worker_task_requires_structured_result_v1(p_task_id)
  then
    raise exception 'This Production work requires its governed result contract before completion.'
      using errcode='23514';
  end if;

  if p_transition in ('done','checklist_done') then
    v_bed_readiness:=atlas.task_bed_weeding_readiness_v1(p_task_id);
    if coalesce((v_bed_readiness->>'applicable')::boolean,false)
       and not coalesce((v_bed_readiness->>'ready')::boolean,false)
    then
      raise exception '%',coalesce(
        nullif(v_bed_readiness->>'waitingText',''),
        'Weed the destination bed before transplanting.'
      ) using errcode='23514';
    end if;
  end if;

  v_scoped_key:=p_task_id::text||':'||md5(coalesce(p_idempotency_key,''));
  return atlas.record_task_transition_v1_internal(
    p_task_id,
    p_transition,
    v_scoped_key,
    p_target_date,
    p_note,
    p_reason,
    p_lane_key,
    p_work_key,
    coalesce(p_payload,'{}'::jsonb),
    p_existing_field_log_id
  );
end;
$function$;

comment on function atlas.record_task_transition_v1(
  uuid,text,text,date,text,text,text,text,jsonb,uuid
) is
'Generic task transition membrane. Production-linked work that requires a structured result may not be generically completed; its governed Production result adapter must write canonical reality and then complete through the internal transition path.';

create or replace view atlas.production_structured_completion_audit_v1 as
select
  t.id as task_id,
  t.farm_id,
  plt.production_lot_id,
  pl.stable_key as production_lot_key,
  pl.lot_label,
  plt.link_role,
  t.title,
  t.task_type,
  t.action_key,
  t.status,
  t.completed_at,
  t.completed_by,
  true as structured_result_required,
  count(ple.id)::integer as production_event_count,
  'structured_production_result_missing'::text as issue_key,
  'Historical task completion is evidence that the task was closed, not proof of the missing biological result. Recover from current observation or separately supported historical evidence; do not infer event facts from completed_at.'::text as recovery_boundary
from atlas.tasks t
join atlas.production_lot_tasks plt
  on plt.task_id=t.id
join atlas.production_lots pl
  on pl.id=plt.production_lot_id
left join atlas.production_lot_events ple
  on ple.task_id=t.id
where t.status='done'
  and atlas.worker_task_requires_structured_result_v1(t.id)
group by
  t.id,t.farm_id,plt.production_lot_id,pl.stable_key,pl.lot_label,
  plt.link_role,t.title,t.task_type,t.action_key,t.status,
  t.completed_at,t.completed_by
having count(ple.id)=0;

revoke all on atlas.production_structured_completion_audit_v1
from public,anon,authenticated;
grant select on atlas.production_structured_completion_audit_v1
to service_role;

comment on view atlas.production_structured_completion_audit_v1 is
'Internal audit of completed Production-linked tasks whose governed structured Production result is absent. This surface diagnoses historical completion/evidence divergence; it does not backfill biological facts.';

do $verification$
begin
  if pg_get_functiondef(
       'atlas.record_task_transition_v1(uuid,text,text,date,text,text,text,text,jsonb,uuid)'::regprocedure
     ) not ilike '%production_lot_tasks%'
     or pg_get_functiondef(
       'atlas.record_task_transition_v1(uuid,text,text,date,text,text,text,text,jsonb,uuid)'::regprocedure
     ) not ilike '%worker_task_requires_structured_result_v1%'
  then
    raise exception 'Generic Production completion membrane was not installed.';
  end if;

  if has_table_privilege(
       'authenticated',
       'atlas.production_structured_completion_audit_v1',
       'SELECT'
     )
     or has_table_privilege(
       'anon',
       'atlas.production_structured_completion_audit_v1',
       'SELECT'
     )
  then
    raise exception 'Production structured-completion audit leaked to browser roles.';
  end if;

  if not has_table_privilege(
       'service_role',
       'atlas.production_structured_completion_audit_v1',
       'SELECT'
     )
  then
    raise exception 'Production structured-completion audit is unavailable to service_role.';
  end if;
end;
$verification$;

commit;
