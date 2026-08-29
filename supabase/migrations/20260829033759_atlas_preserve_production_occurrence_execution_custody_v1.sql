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
  v_existing_visibility text;
  v_existing_membership uuid;
  v_existing_user uuid;
  v_existing_org uuid;
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

  select * into v_existing
  from atlas.planned_work_occurrences
  where farm_id=p_farm_id and occurrence_key=p_occurrence_key
  order by created_at desc limit 1;

  if v_governed and not v_reconciler_active then
    if v_existing.id is not null then
      return jsonb_build_object('occurrenceId',v_existing.id,'taskId',v_existing.released_task_id,'state',v_existing.state,'authority','production_reconciler','deduplicated',true);
    end if;
    return jsonb_build_object('occurrenceId',null,'taskId',null,'state','deferred_to_reconciler','authority','production_reconciler','deduplicated',false);
  end if;

  if v_existing.id is not null then
    v_existing_visibility:=nullif(v_existing.task_payload->>'visibility_scope','');
    begin v_existing_membership:=nullif(v_existing.task_payload->>'assigned_membership_id','')::uuid; exception when others then v_existing_membership:=null; end;
    begin v_existing_user:=nullif(v_existing.task_payload->>'assigned_user_id','')::uuid; exception when others then v_existing_user:=null; end;
    begin v_existing_org:=nullif(v_existing.task_payload->>'organization_id','')::uuid; exception when others then v_existing_org:=null; end;

    if v_existing_membership is not null or v_existing_user is not null then
      p_visibility_scope:=coalesce(v_existing_visibility,p_visibility_scope,'assigned_worker');
      p_assigned_membership_id:=coalesce(v_existing_membership,p_assigned_membership_id);
      p_assigned_user_id:=coalesce(v_existing_user,p_assigned_user_id);
      p_organization_id:=coalesce(v_existing_org,p_organization_id);
      v_effective_metadata:=v_effective_metadata||jsonb_build_object('execution_custody_preserved',true,'execution_custody_source_occurrence_id',v_existing.id);
    end if;
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

with elm as (
  select id,organization_id from atlas.farms where stable_key='elm_farm' limit 1
), anna as (
  select fm.id as membership_id,fm.user_id,fm.farm_id
  from atlas.farm_memberships fm join elm e on e.id=fm.farm_id
  where fm.worker_key='anna' and fm.active
  order by fm.updated_at desc limit 1
), target as (
  select pwo.id,a.membership_id,a.user_id,e.organization_id
  from atlas.planned_work_occurrences pwo
  join elm e on e.id=pwo.farm_id
  cross join anna a
  where pwo.occurrence_key like 'production:hardening:%'
    and pwo.state='planned'
    and pwo.task_payload->'metadata'->>'production_lot_key' in (
      'snapdragon_rocket_overwinter_2026_live',
      'snapdragon_potomac_overwinter_2026_live',
      'snapdragon_first_lady_overwinter_2026_live',
      'snapdragon_chantilly_overwinter_2026_live'
    )
)
update atlas.planned_work_occurrences pwo
set task_payload=jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(pwo.task_payload,'{}'::jsonb),
            '{visibility_scope}','"assigned_worker"'::jsonb,true
          ),
          '{assigned_membership_id}',to_jsonb(t.membership_id::text),true
        ),
        '{assigned_user_id}',to_jsonb(t.user_id::text),true
      ),
      '{organization_id}',to_jsonb(t.organization_id::text),true
    ) || jsonb_build_object(
      'metadata',coalesce(pwo.task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
        'assigned_to','Anna','assignee_key','anna','executor_worker_key','anna',
        'executor_membership_id',t.membership_id,'execution_custody_restored_by','production_reconciler_v1'
      )
    ),
    metadata=coalesce(pwo.metadata,'{}'::jsonb)||jsonb_build_object(
      'execution_custody_restored_by','production_reconciler_v1',
      'assigned_membership_id',t.membership_id,
      'assigned_user_id',t.user_id
    ),
    updated_at=now()
from target t where pwo.id=t.id;

comment on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) is 'Production work authoring boundary. State-derived work is reconciler-only. Existing non-null worker execution custody is preserved across reconciliation unless a separate governed reassignment changes the occurrence.';