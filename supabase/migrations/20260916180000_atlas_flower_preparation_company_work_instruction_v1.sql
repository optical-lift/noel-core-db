begin;

-- Package 7 / Operating Knowledge execution proof.
--
-- Governing boundary:
--   * Flower Preparation v2 resolves Operating Knowledge exactly once, at Owner
--     direction time, and preserves immutable directive-line provenance.
--   * unchanged Flower Preparation v1 remains the authority for directive birth,
--     Owner-review completion, and release of the waiting Preparation task.
--   * the existing task -> Company Work adoption seam remains the authority for
--     durable work identity and responsibility.
--   * this migration projects the already-established directive/provenance into
--     that existing Company Work item as a frozen instruction snapshot.
--   * Worker Day reads that snapshot; it does not re-run Operating Knowledge and
--     cannot change which rule governed already-released work.
--
-- Forward-only: no existing directive, task, Company Work, Worker Day, or rule
-- rows are backfilled or mutated by the migration itself.

do $preflight$
begin
  if to_regprocedure('atlas.record_flower_preparation_directive_v2(uuid,jsonb,text,text)') is null then
    raise exception 'Flower Preparation v2 authority is missing.';
  end if;
  if to_regprocedure('atlas.company_work_worker_day_self_api_v1(date,integer)') is null then
    raise exception 'Company Work Worker Day read authority is missing.';
  end if;
  if to_regclass('atlas.flower_preparation_directives') is null
     or to_regclass('atlas.flower_preparation_directive_lines') is null
     or to_regclass('atlas.flower_preparation_directive_line_knowledge_provenance') is null
     or to_regclass('atlas.work_execution_adapters') is null
     or to_regclass('atlas.work_items') is null
     or to_regclass('atlas.worker_week_projection_sources') is null then
    raise exception 'Flower Preparation / Company Work projection custody is incomplete.';
  end if;
end
$preflight$;

create or replace function atlas.sync_flower_preparation_company_work_instruction_v1(
  p_directive_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_directive atlas.flower_preparation_directives%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_worker_task_id uuid;
  v_work_item_id uuid;
  v_line_count integer;
  v_provenance_count integer;
  v_lines jsonb := '[]'::jsonb;
  v_instruction text;
  v_snapshot jsonb;
begin
  if p_directive_id is null then
    return jsonb_build_object('state','missing_directive_id');
  end if;

  select * into v_directive
  from atlas.flower_preparation_directives d
  where d.id = p_directive_id;

  if v_directive.id is null then
    return jsonb_build_object('state','missing_directive','directiveId',p_directive_id);
  end if;

  select count(*)::integer into v_line_count
  from atlas.flower_preparation_directive_lines l
  where l.directive_id = v_directive.id;

  select count(*)::integer into v_provenance_count
  from atlas.flower_preparation_directive_line_knowledge_provenance p
  where p.directive_id = v_directive.id;

  -- v2 inserts provenance after unchanged v1 has created all directive lines.
  -- Do nothing until every line has its immutable provenance row.
  if v_line_count < 1 or v_provenance_count <> v_line_count then
    return jsonb_build_object(
      'state','awaiting_complete_provenance',
      'directiveId',v_directive.id,
      'lineCount',v_line_count,
      'provenanceCount',v_provenance_count
    );
  end if;

  select * into v_occurrence
  from atlas.planned_work_occurrences o
  where o.id = v_directive.preparation_occurrence_id;

  if v_occurrence.id is null then
    raise exception 'Flower Preparation directive % lost its governed occurrence.', v_directive.id
      using errcode='P0001';
  end if;

  v_worker_task_id := v_occurrence.released_task_id;
  if v_worker_task_id is null then
    raise exception 'Flower Preparation directive % has no released execution task.', v_directive.id
      using errcode='P0001';
  end if;

  select a.work_item_id into v_work_item_id
  from atlas.work_execution_adapters a
  join atlas.work_items w
    on w.id = a.work_item_id
   and w.organization_id = a.organization_id
  where a.task_id = v_worker_task_id
  order by case when a.state='active' then 0 when a.state='completed' then 1 else 2 end,
           a.created_at desc,
           a.id
  limit 1;

  if v_work_item_id is null then
    raise exception 'Released Flower Preparation task % has no canonical Company Work identity.', v_worker_task_id
      using errcode='P0001';
  end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'lineNumber', l.line_number,
    'cropProfileId', l.crop_profile_id,
    'productLabel', l.product_label,
    'outputKind', l.output_kind,
    'requestedQuantity', l.requested_quantity,
    'stemsPerUnit', l.stems_per_unit,
    'note', l.note,
    'sourceKind', p.source_kind,
    'knowledgeRuleIds', to_jsonb(p.knowledge_rule_ids),
    'resolutionContext', p.resolution_context,
    'resolvedEffect', p.resolved_effect
  )) order by l.line_number), '[]'::jsonb)
  into v_lines
  from atlas.flower_preparation_directive_lines l
  join atlas.flower_preparation_directive_line_knowledge_provenance p
    on p.directive_line_id = l.id
   and p.directive_id = l.directive_id
  where l.directive_id = v_directive.id;

  select string_agg(
    case
      when l.output_kind='bundle' then
        format('%s × %s bundle%s · %s stems each%s',
          l.requested_quantity,
          l.product_label,
          case when l.requested_quantity=1 then '' else 's' end,
          l.stems_per_unit,
          case when l.note is null then '' else ' · ' || l.note end)
      else
        format('%s × %s %s%s',
          l.requested_quantity,
          l.product_label,
          replace(l.output_kind,'_',' '),
          case when l.note is null then '' else ' · ' || l.note end)
    end,
    E'\n' order by l.line_number
  )
  into v_instruction
  from atlas.flower_preparation_directive_lines l
  where l.directive_id = v_directive.id;

  v_instruction := 'Owner Preparation direction:' || E'\n' || coalesce(v_instruction,'');

  v_snapshot := jsonb_build_object(
    'contractVersion','flower_preparation_company_work_instruction_v1',
    'directiveId',v_directive.id,
    'directiveVersion',2,
    'harvestBatchId',v_directive.harvest_batch_id,
    'preparationOccurrenceId',v_directive.preparation_occurrence_id,
    'preparationTaskId',v_worker_task_id,
    'recordedAt',v_directive.created_at,
    'lines',v_lines,
    'truthBoundary','frozen_owner_preparation_direction_with_operating_knowledge_provenance',
    'ruleResolutionOccursUpstream',true,
    'workerDayMayNotReresolve',true
  );

  update atlas.work_items w
  set instructions = v_instruction,
      metadata = coalesce(w.metadata,'{}'::jsonb) || jsonb_build_object(
        'instructionSourceKind','flower_preparation_directive',
        'instructionSourceId',v_directive.id,
        'operatingInstructionSnapshot',v_snapshot
      ),
      updated_at = now()
  where w.id = v_work_item_id;

  if not found then
    raise exception 'Canonical Company Work item % disappeared while projecting Flower Preparation instruction.', v_work_item_id
      using errcode='P0001';
  end if;

  return jsonb_build_object(
    'state','projected',
    'directiveId',v_directive.id,
    'preparationTaskId',v_worker_task_id,
    'workItemId',v_work_item_id,
    'lineCount',v_line_count
  );
end;
$function$;

revoke all on function atlas.sync_flower_preparation_company_work_instruction_v1(uuid)
  from public, anon, authenticated, service_role;

create or replace function atlas.sync_flower_preparation_company_work_instruction_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
begin
  perform atlas.sync_flower_preparation_company_work_instruction_v1(new.directive_id);
  return new;
end;
$function$;

revoke all on function atlas.sync_flower_preparation_company_work_instruction_trigger_v1()
  from public, anon, authenticated, service_role;

create trigger flower_prep_project_company_work_instruction_v1
after insert on atlas.flower_preparation_directive_line_knowledge_provenance
for each row execute function atlas.sync_flower_preparation_company_work_instruction_trigger_v1();

-- Additive Worker Day enrichment. Worker Day consumes the already-frozen Company
-- Work instruction snapshot; it never resolves Company Operating Knowledge itself.
create or replace function atlas.company_work_worker_day_self_api_v1(
  p_start_date date,
  p_days integer default 7
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_items jsonb:='[]'::jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_start_date is null then raise exception 'Worker Day start date required.' using errcode='22023'; end if;
  if coalesce(p_days,0)<1 or p_days>31 then raise exception 'Worker Day range must be between 1 and 31 days.' using errcode='22023'; end if;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'projectionId',wp.id,
    'farmId',wp.farm_id,
    'deliveryMembershipId',wp.membership_id,
    'organizationId',wp.organization_id,
    'organizationMembershipId',wp.organization_membership_id,
    'plannedDate',wp.planned_date,
    'originalPlannedDate',wp.original_planned_date,
    'planOrder',wp.plan_order,
    'title',wp.title,
    'planState',wp.plan_state,
    'environment',wp.environment,
    'expectedActiveMinutes',wp.expected_active_minutes,
    'reason',wp.reason,
    'deliveryKey',wp.delivery_key,
    'deliveryPayload',wp.delivery_payload,
    'requiredWorkItemIds',coalesce((
      select jsonb_agg(s.work_item_id order by s.work_item_id)
      from atlas.worker_week_projection_sources s
      where s.projection_id=wp.id and s.source_role='required'
    ),'[]'::jsonb),
    'requiredWork',coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'workItemId',wi.id,
        'title',wi.title,
        'instructions',wi.instructions,
        'operationClass',wi.operation_class,
        'instructionSourceKind',wi.metadata->>'instructionSourceKind',
        'instructionSourceId',wi.metadata->>'instructionSourceId',
        'operatingInstructionSnapshot',wi.metadata->'operatingInstructionSnapshot'
      )) order by wi.id)
      from atlas.worker_week_projection_sources s
      join atlas.work_items wi on wi.id=s.work_item_id
      where s.projection_id=wp.id and s.source_role='required'
    ),'[]'::jsonb),
    'resultReporting',atlas.company_work_projection_result_reporting_self_v1(wp.id)
  )) order by wp.planned_date,wp.plan_order,wp.created_at,wp.id),'[]'::jsonb)
  into v_items
  from atlas.farm_memberships fm
  join atlas.farms f on f.id=fm.farm_id
  cross join lateral (
    select atlas.organization_employee_worker_context_self_v1(f.id,fm.id) ctx
  ) c
  join atlas.worker_week_projection wp
    on wp.farm_id=f.id
   and wp.membership_id=fm.id
   and wp.organization_id=(c.ctx->>'organizationId')::uuid
   and wp.organization_membership_id=(c.ctx->>'organizationMembershipId')::uuid
  where fm.user_id=v_uid
    and fm.active
    and fm.role='farm_hand'
    and coalesce((c.ctx->>'ok')::boolean,false)
    and wp.planned_date>=p_start_date
    and wp.planned_date<p_start_date+p_days;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','company_work_worker_day_v2',
    'startDate',p_start_date,
    'days',p_days,
    'items',v_items
  );
end;
$function$;

-- CREATE OR REPLACE preserves the existing function ACL and browser membrane.

commit;
