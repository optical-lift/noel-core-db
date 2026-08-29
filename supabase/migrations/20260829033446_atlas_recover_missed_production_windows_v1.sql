create or replace function atlas.author_production_work_occurrence_v1(
  p_farm_id uuid,
  p_work_key text,
  p_occurrence_key text,
  p_title text,
  p_due_date date,
  p_not_before_date date,
  p_source_kind text,
  p_source_id uuid,
  p_task_type text,
  p_action_key text,
  p_work_class text,
  p_priority text,
  p_visibility_scope text,
  p_assigned_membership_id uuid,
  p_assigned_user_id uuid,
  p_organization_id uuid,
  p_note text,
  p_metadata jsonb default '{}'::jsonb,
  p_relation_payload jsonb default '{}'::jsonb,
  p_work_lane text default 'process_continuation',
  p_commitment_kind text default 'dependency',
  p_latest_lawful_date date default null,
  p_miss_consequence jsonb default '{}'::jsonb,
  p_release_if_due boolean default false
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_reconciler_active boolean := coalesce(current_setting('atlas.production_reconciler_active', true),'')='on';
  v_governed boolean;
  v_existing atlas.planned_work_occurrences%rowtype;
  v_effective_latest date:=p_latest_lawful_date;
  v_effective_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_effective_miss jsonb:=coalesce(p_miss_consequence,'{}'::jsonb);
begin
  v_governed := p_work_key in (
    'germination','seedling-care','owner-reseed-decision','owner-lifecycle-gap','owner-pot-up-method','pot-up',
    'hardening','transplant-readiness','owner-seedling-recovery','owner-bed-math',
    'transplant','establishment','field-water','field-weed','owner-field-failure',
    'owner-harvest-rules','harvest-readiness'
  ) or p_work_key like 'field-care-%';

  if v_governed and not v_reconciler_active then
    select * into v_existing from atlas.planned_work_occurrences
    where farm_id=p_farm_id and occurrence_key=p_occurrence_key
    order by created_at desc limit 1;
    if v_existing.id is not null then
      return jsonb_build_object('occurrenceId',v_existing.id,'taskId',v_existing.released_task_id,'state',v_existing.state,'authority','production_reconciler','deduplicated',true);
    end if;
    return jsonb_build_object('occurrenceId',null,'taskId',null,'state','deferred_to_reconciler','authority','production_reconciler','deduplicated',false);
  end if;

  if v_effective_latest is not null and p_due_date is not null and v_effective_latest<p_due_date then
    v_effective_metadata:=v_effective_metadata||jsonb_build_object(
      'recovered_missed_window',true,
      'original_latest_lawful_date',v_effective_latest,
      'recovery_due_date',p_due_date,
      'recovery_authority','production_work_authoring_boundary'
    );
    v_effective_miss:=v_effective_miss||jsonb_build_object(
      'windowMissed',true,
      'originalLatestLawfulDate',v_effective_latest,
      'recoveredOperationalDeadline',p_due_date
    );
    v_effective_latest:=p_due_date;
  end if;

  return atlas.author_production_work_occurrence_internal_v1(
    p_farm_id,p_work_key,p_occurrence_key,p_title,p_due_date,p_not_before_date,p_source_kind,p_source_id,
    p_task_type,p_action_key,p_work_class,p_priority,p_visibility_scope,p_assigned_membership_id,p_assigned_user_id,
    p_organization_id,p_note,v_effective_metadata,p_relation_payload,p_work_lane,p_commitment_kind,v_effective_latest,
    v_effective_miss,p_release_if_due
  );
end;
$function$;

revoke all on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) from public,anon,authenticated;
grant execute on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) to postgres,service_role;

comment on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) is 'Production work authoring boundary. State-derived work is reconciler-only. If an already-missed biological window is recovered, the original deadline is preserved in metadata and the operational recovery deadline is normalized to the authored due date.';