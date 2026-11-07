-- HELD Nov 4 6A source: exact live seed inventory RESULT handler
-- pg_get_functiondef MD5 cc55c1af98ca682486f282759da33445. One operation replaced:
-- automatic downstream task creation from physical Result, not the
-- independent seed-event, inventory state, old task Done, or Journal.
-- Direct service_role sync_seed_inventory_dependency_tasks_v1 is
-- independently source-governed and remains under separate approval.
-- DO NOT install without human owner acceptance and collected tests.
BEGIN;
DO $source$
BEGIN
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p
     JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='atlas' AND p.proname='record_seed_inventory_result_core_v1')
    IS DISTINCT FROM 'cc55c1af98ca682486f282759da33445' THEN
   RAISE EXCEPTION 'Seed inventory Result source drift, stop';
 END IF;
END;
$source$;
CREATE OR REPLACE FUNCTION atlas.record_seed_inventory_result_core_v1(p_task_id uuid, p_effective_membership_id uuid, p_effective_role text, p_outcome text, p_observed_quantity numeric, p_quantity_added numeric, p_source text, p_problem_kind text, p_next_check_date date, p_note text, p_idempotency_key text, p_operator_mode boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_task atlas.tasks%rowtype;
  v_membership atlas.farm_memberships%rowtype;
  v_state atlas.rhythm_state%rowtype;
  v_rule atlas.rhythm_rules%rowtype;
  v_binding atlas.rhythm_bindings%rowtype;
  v_lot atlas.seed_lots%rowtype;
  v_position atlas.seed_inventory_position_v1%rowtype;
  v_existing atlas.seed_inventory_events%rowtype;
  v_event_id uuid;
  v_satisfaction_id uuid;
  v_owner_membership_id uuid;
  v_transition jsonb;
  v_clock jsonb;
  v_dependency jsonb;
  v_current_position atlas.seed_inventory_position_v1%rowtype;
  v_shortfall_quantity numeric:=0;
  v_uncovered_count integer:=0;
  v_owner_attention_id uuid;
  v_role text:=lower(coalesce(p_effective_role,''));
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  v_source text:=nullif(btrim(coalesce(p_source,'')),'');
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_now timestamptz:=now();
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_expected numeric;
  v_status text;
  v_transition_id uuid;
  v_journal_id uuid;
begin
  if p_task_id is null or p_effective_membership_id is null or v_key is null or length(v_key)>160 then
    raise exception 'Task, active membership, and idempotency key are required.' using errcode='22023';
  end if;
  if p_outcome not in ('count_confirmed','count_corrected','restocked','depleted','unable_to_verify','problem_found','retired') then
    raise exception 'Choose a valid seed inventory result.' using errcode='22023';
  end if;
  if v_note is not null and length(v_note)>4000 then raise exception 'Note must be 4000 characters or fewer.' using errcode='22023'; end if;
  if p_outcome in ('count_confirmed','count_corrected','restocked') and (p_observed_quantity is null or p_observed_quantity<=0) then
    raise exception 'Record the positive physical quantity currently on hand.' using errcode='22023';
  end if;
  if p_outcome='depleted' and coalesce(p_observed_quantity,0)<>0 then raise exception 'Depleted inventory must be recorded as zero.' using errcode='22023'; end if;
  if p_outcome='restocked' and (p_quantity_added is null or p_quantity_added<=0 or v_source is null) then
    raise exception 'Restock requires the quantity added and its source.' using errcode='22023';
  end if;
  if p_outcome='unable_to_verify' and (p_next_check_date is null or p_next_check_date<=v_today or v_note is null) then
    raise exception 'Unable to verify requires a future recount date and note.' using errcode='22023';
  end if;
  if p_outcome='problem_found' and (p_problem_kind not in ('damaged','mislabeled','missing','contaminated','storage_problem','other') or v_note is null) then
    raise exception 'Choose the inventory problem and describe what was observed.' using errcode='22023';
  end if;
  if p_outcome='retired' and (v_role<>'owner' or v_note is null) then
    raise exception 'Only the farm Owner may retire a seed lot, with a recorded reason.' using errcode='42501';
  end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Seed inventory task was not found.' using errcode='P0002'; end if;
  if v_task.status not in ('open','blocked') or v_task.task_type<>'seed_inventory_recount'
     or coalesce(v_task.metadata->>'task_style','')<>'seed_inventory_recount' then
    raise exception 'This task is not an open Clock-governed seed recount.' using errcode='22023';
  end if;

  select * into v_membership from atlas.farm_memberships where id=p_effective_membership_id and active;
  if v_membership.id is null or v_membership.farm_id<>v_task.farm_id then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  if not p_operator_mode and (auth.uid() is null or v_membership.user_id<>auth.uid()) then
    raise exception 'This membership does not belong to the signed-in player.' using errcode='42501';
  end if;
  if v_role not in ('owner','manager') and not (
    v_role='farm_hand' and v_task.visibility_scope='assigned_worker' and v_task.assigned_membership_id=v_membership.id
  ) then
    raise exception 'This seed recount is outside the active player context.' using errcode='42501';
  end if;

  select rs.* into v_state from atlas.rhythm_state rs
  where rs.id=atlas.rhythm_safe_uuid_v1(v_task.metadata->>'rhythm_state_id')
    and rs.farm_id=v_task.farm_id and rs.rhythm_key='seed_inventory_freshness' and rs.subject_kind='seed_lot'
  for update;
  if v_state.id is null then raise exception 'Seed inventory Clock state was not found.' using errcode='P0002'; end if;
  select * into v_rule from atlas.rhythm_rules where id=v_state.rhythm_rule_id;
  select * into v_binding from atlas.rhythm_bindings where id=v_state.rhythm_binding_id for update;
  select * into v_lot from atlas.seed_lots where id=v_state.subject_id and farm_id=v_task.farm_id for update;
  if v_lot.id is null then raise exception 'Seed lot was not found.' using errcode='P0002'; end if;
  select * into v_position from atlas.seed_inventory_position_v1 where seed_lot_id=v_lot.id;
  v_expected:=coalesce(v_position.projected_on_hand_quantity,v_position.recorded_receipt_quantity);

  if p_outcome='count_confirmed' and p_observed_quantity is distinct from v_expected then
    raise exception 'The physical count differs from Atlas. Use Count corrected and record the observed quantity.' using errcode='22023';
  end if;
  if p_outcome='count_corrected' and p_observed_quantity is not distinct from v_expected then
    raise exception 'The physical count matches Atlas. Use Count confirmed.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_task.farm_id::text||':seed-inventory:'||v_key,0));
  select * into v_existing from atlas.seed_inventory_events where farm_id=v_task.farm_id and event_key=v_key;
  if v_existing.id is not null then
    return jsonb_build_object('eventId',v_existing.id,'taskId',v_existing.task_id,'outcome',v_existing.outcome,'deduplicated',true);
  end if;

  insert into atlas.seed_inventory_events(
    organization_id,farm_id,seed_lot_id,task_id,rhythm_state_id,event_key,outcome,observed_at,
    observed_quantity,quantity_added,unit,source,problem_kind,next_check_date,note,
    created_by_user_id,effective_membership_id,metadata
  ) values(
    v_state.organization_id,v_task.farm_id,v_lot.id,v_task.id,v_state.id,v_key,p_outcome,v_now,
    case when p_outcome='depleted' then 0 else p_observed_quantity end,p_quantity_added,v_lot.quantity_unit,
    v_source,p_problem_kind,p_next_check_date,v_note,auth.uid(),v_membership.id,
    jsonb_build_object(
      'operatorMode',coalesce(p_operator_mode,false),'expectedBeforeObservation',v_expected,
      'recordedReceiptQuantity',v_lot.received_quantity,'timeClaimsInventoryQuantity',false
    )
  ) returning id into v_event_id;

  v_status:=case p_outcome
    when 'count_confirmed' then 'verified'
    when 'count_corrected' then 'verified'
    when 'restocked' then 'verified'
    when 'depleted' then 'depleted'
    when 'unable_to_verify' then 'uncertain'
    when 'problem_found' then 'problem'
    else 'retired' end;

  insert into atlas.seed_inventory_state(
    seed_lot_id,organization_id,farm_id,status,verified_on_hand_quantity,unit,
    last_verified_at,last_observed_at,source_event_id,current_task_id,next_check_date,note,metadata
  ) values(
    v_lot.id,v_state.organization_id,v_task.farm_id,v_status,
    case when p_outcome in ('count_confirmed','count_corrected','restocked') then p_observed_quantity
         when p_outcome='depleted' then 0 else v_position.verified_on_hand_quantity end,
    v_lot.quantity_unit,
    case when p_outcome in ('count_confirmed','count_corrected','restocked','depleted') then v_now else v_position.last_verified_at end,
    v_now,v_event_id,
    case when p_outcome in ('unable_to_verify','problem_found') then v_task.id end,
    p_next_check_date,v_note,
    coalesce(v_position.state_metadata,'{}'::jsonb)||jsonb_build_object('lastOutcome',p_outcome,'lastTaskId',v_task.id)
  ) on conflict(seed_lot_id) do update set
    status=excluded.status,
    verified_on_hand_quantity=excluded.verified_on_hand_quantity,
    unit=excluded.unit,
    last_verified_at=excluded.last_verified_at,
    last_observed_at=excluded.last_observed_at,
    source_event_id=excluded.source_event_id,
    current_task_id=excluded.current_task_id,
    next_check_date=excluded.next_check_date,
    note=excluded.note,
    metadata=atlas.seed_inventory_state.metadata||excluded.metadata,
    updated_at=v_now;

  if p_outcome in ('count_confirmed','count_corrected','restocked','depleted') then
    update atlas.seed_lots set
      status=case when p_outcome='depleted' then 'depleted' else 'available' end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'last_seed_inventory_event_id',v_event_id,'last_physical_count_at',v_now,
        'current_inventory_status',v_status
      ),updated_at=v_now
    where id=v_lot.id;

    insert into atlas.rhythm_satisfactions(
      organization_id,farm_id,rhythm_state_id,rhythm_binding_id,rhythm_rule_id,rhythm_key,
      subject_kind,subject_id,satisfaction_key,satisfaction_kind,satisfied_at,renewal_interval_seconds,
      source_kind,source_id,source_event,source_task_id,policy_match,evidence,created_by_user_id
    ) values(
      v_state.organization_id,v_state.farm_id,v_state.id,v_state.rhythm_binding_id,v_state.rhythm_rule_id,
      'seed_inventory_freshness','seed_lot',v_lot.id,'seed-inventory:'||v_event_id::text,'full',v_now,null,
      'seed_inventory',v_event_id,p_outcome,v_task.id,
      jsonb_build_object('matchKind','structured_physical_seed_count','ruleKey',v_rule.rule_key),
      jsonb_build_object('seedInventoryEventId',v_event_id,'taskId',v_task.id,'seedLotId',v_lot.id,'observedQuantity',case when p_outcome='depleted' then 0 else p_observed_quantity end),
      auth.uid()
    ) returning id into v_satisfaction_id;

    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'done','seed-inventory:'||v_key||':done',null,
      coalesce(v_note,case p_outcome
        when 'count_confirmed' then 'Physical seed count confirmed.'
        when 'count_corrected' then 'Physical seed count corrected.'
        when 'restocked' then 'Seed inventory restocked and physically counted.'
        else 'Seed inventory physically counted at zero.' end),
      null,'seed_inventory',p_outcome,
      jsonb_build_object('seed_inventory_event_id',v_event_id,'seed_lot_id',v_lot.id,'observed_quantity',case when p_outcome='depleted' then 0 else p_observed_quantity end),null
    );
    update atlas.rhythm_state set
      last_qualifying_satisfaction_id=v_satisfaction_id,current_task_id=null,current_occurrence_id=null,
      recovery_started_at=null,updated_at=v_now
    where id=v_state.id;
    v_clock:=atlas.evaluate_rhythm_binding_v1(v_state.id,v_now,'seed_inventory_verified');

  elsif p_outcome='unable_to_verify' then
    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'rescheduled','seed-inventory:'||v_key||':unable',p_next_check_date,
      v_note,'Physical quantity remains unverified.','seed_inventory','unable_to_verify',
      jsonb_build_object('seed_inventory_event_id',v_event_id,'seed_lot_id',v_lot.id,'next_check_date',p_next_check_date),null
    );
    if v_state.state<>'recovering' then
      v_transition_id:=atlas.record_rhythm_transition_v1(
        v_state.id,'seed-inventory:'||v_event_id::text||':recovering','recovering',v_state.state,'recovering',
        'partial_result',v_now,v_now,null,v_task.id,v_task.planned_occurrence_id,
        jsonb_build_object('seedInventoryEventId',v_event_id,'outcome',p_outcome)
      );
    end if;
    update atlas.rhythm_state set
      state='recovering',recovery_started_at=coalesce(recovery_started_at,v_now),
      current_task_id=v_task.id,current_occurrence_id=v_task.planned_occurrence_id,
      state_reason=jsonb_build_object('source','seed_inventory_result','eventId',v_event_id,'outcome',p_outcome,'nextCheckDate',p_next_check_date),
      updated_at=v_now
    where id=v_state.id;
    v_clock:=jsonb_build_object('state','recovering','reason','physical_count_unverified');

  elsif p_outcome='problem_found' then
    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'blocked','seed-inventory:'||v_key||':problem',null,
      v_note,v_note,'seed_inventory','owner_handoff',
      jsonb_build_object('seed_inventory_event_id',v_event_id,'seed_lot_id',v_lot.id,'problem_kind',p_problem_kind),null
    );
    if v_role<>'owner' then
      select id into v_owner_membership_id from atlas.farm_memberships
      where farm_id=v_task.farm_id and role='owner' and active order by created_at limit 1;
      if v_owner_membership_id is not null then
        update atlas.tasks set
          assigned_membership_id=v_owner_membership_id,visibility_scope='assigned_worker',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'assignee_key','owner','seed_inventory_owner_handoff',true,
            'seed_inventory_event_id',v_event_id,'seed_inventory_issue',v_note
          ),updated_at=v_now
        where id=v_task.id;
      end if;
    end if;
    if v_state.state<>'recovering' then
      v_transition_id:=atlas.record_rhythm_transition_v1(
        v_state.id,'seed-inventory:'||v_event_id::text||':recovering','recovering',v_state.state,'recovering',
        'partial_result',v_now,v_now,null,v_task.id,v_task.planned_occurrence_id,
        jsonb_build_object('seedInventoryEventId',v_event_id,'outcome',p_outcome,'problemKind',p_problem_kind)
      );
    end if;
    update atlas.rhythm_state set
      state='recovering',recovery_started_at=coalesce(recovery_started_at,v_now),
      current_task_id=v_task.id,current_occurrence_id=v_task.planned_occurrence_id,
      state_reason=jsonb_build_object('source','seed_inventory_result','eventId',v_event_id,'outcome',p_outcome,'problemKind',p_problem_kind),
      updated_at=v_now
    where id=v_state.id;
    v_clock:=jsonb_build_object('state','recovering','reason','inventory_problem');

  else
    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'changed_plan','seed-inventory:'||v_key||':retired',null,
      v_note,'Seed lot retired.','seed_inventory','retired',
      jsonb_build_object('seed_inventory_event_id',v_event_id,'seed_lot_id',v_lot.id),null
    );
    update atlas.seed_lots set status='closed',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'retired_seed_inventory_event_id',v_event_id,'retired_at',v_now,'retired_reason',v_note
    ),updated_at=v_now where id=v_lot.id;
    update atlas.rhythm_bindings set
      active=false,active_until=greatest(v_now,active_from+interval '1 second'),
      owner_reason=v_note,updated_at=v_now
    where id=v_binding.id;
    update atlas.rhythm_state set
      state='paused',current_task_id=null,current_occurrence_id=null,
      state_reason=jsonb_build_object('source','seed_inventory_result','eventId',v_event_id,'outcome','retired'),
      last_evaluated_at=v_now,last_transition_at=v_now,updated_at=v_now
    where id=v_state.id;
    v_clock:=jsonb_build_object('state','paused','reason','seed_lot_retired');
  end if;

  -- Nov 4 6A: a trusted inventory Result is evidence of a physical
  -- shortfall, not permission to issue the next dependency Task.
  -- Preserve true inventory event, current source state, rhythm, linked
  -- existing task closeout, and owner-facing seed Journal.
  -- A separately source-authorized issuer may consider later Work.
  -- Re-evaluate trusted position AFTER this true inventory Result/state
  -- was recorded. A mere "problem_found" or "depleted" label alone is
  -- not a source-qualified uncovered production commitment.
  select * into v_current_position
  from atlas.seed_inventory_position_v1 p
  where p.seed_lot_id=v_lot.id;
  if coalesce(v_current_position.count_trusted,false) then
    select greatest(coalesce(sum(c.outstanding_quantity),0)-
                      coalesce(v_current_position.projected_on_hand_quantity,0),0),
           count(*) filter(where not c.covered_by_trusted_inventory)::integer
    into v_shortfall_quantity,v_uncovered_count
    from atlas.seed_allocation_coverage_v1 c
    where c.seed_lot_id=v_lot.id;
  end if;
  v_dependency:=jsonb_build_object(
    'action','seed_result_source_qualified_no_auto_work',
    'seedInventoryEventId',v_event_id,
    'seedLotId',v_lot.id,
    'observedOutcome',p_outcome,
    'countTrusted',coalesce(v_current_position.count_trusted,false),
    'verifiedUncoveredQuantity',v_shortfall_quantity,
    'uncoveredDependencyCount',v_uncovered_count,
    'shortfallMustBeAdjudicatedIndependently',
        coalesce(v_current_position.count_trusted,false) and v_shortfall_quantity>0,
    'autoTaskOrOccurrenceIssued',false,
    'requiresSeparateNewWorkDecision',
        coalesce(v_current_position.count_trusted,false) and v_shortfall_quantity>0);

  if coalesce(v_current_position.count_trusted,false)
      and v_shortfall_quantity>0 then
    -- One source-keyed owner-only attention for the current seed Lot,
    -- not a Work offer, purchase order, roster or agent assignment.
    -- Reader must re-evaluate actual current coverage because a later
    -- count/restock may resolve the shortfall.
    v_owner_attention_id:=atlas.upsert_journal_event_v1(
      p_organization_id=>v_state.organization_id,
      p_farm_id=>v_state.farm_id,
      p_event_key=>'seed-shortfall-needs-owner-decision:'||v_lot.id::text,
      p_event_kind=>'owner_decision',
      p_source_kind=>'seed_lot',
      p_source_id=>v_lot.id,
      p_source_event=>'verified_shortfall',
      p_occurred_at=>v_now,
      p_journal_date=>v_today,
      p_title=>'Review verified seed shortfall',
      p_detail=>'A trusted current physical count does not cover committed production needs. Independent owner direction and accepted Work are required.',
      p_visibility_scope=>'owner',
      p_importance=>'attention',
      p_actor_user_id=>auth.uid(),
      p_assigned_user_id=>null,
      p_task_id=>null,
      p_payload=>jsonb_build_object(
        'contractVersion','seed_shortfall_owner_attention_6a_v1',
        'seedInventoryEventId',v_event_id,
        'seedLotId',v_lot.id,
        'trustedUncoveredQuantity',v_shortfall_quantity,
        'unit',v_lot.quantity_unit,
        'uncoveredDependencyCount',v_uncovered_count,
        'ownerDecisionStillRequired',true,
        'operationalOwnerReviewOnly',true,
        'principalEscalationQualified',false,
        'principalClockCandidateCreated',false,
        'purchaseOrOtherWorkAuthorized',false,
        'newTaskCreated',false
      ),
      p_provenance=>jsonb_build_object(
        'sourceTable','atlas.seed_inventory_events',
        'sourceEventId',v_event_id,
        'originalTaskId',v_task.id,
        'physicalResultRecordedAt',v_now,
        'truthBoundary','trusted_shortfall_is_not_purchase_work_authority',
        'noAutomaticSuccessorWork',true
      )
    );
    if v_owner_attention_id is null then
      raise exception 'Seed shortfall owner attention missing true source'
        using errcode='23514';
    end if;
  end if;

  v_journal_id:=atlas.upsert_journal_event_v1(
    p_organization_id=>v_state.organization_id,
    p_farm_id=>v_state.farm_id,
    p_event_key=>'seed-inventory:'||v_event_id::text,
    p_event_kind=>case when p_outcome='problem_found' then 'problem' else 'state_change' end,
    p_source_kind=>'seed_inventory_event',
    p_source_id=>v_event_id,
    p_source_event=>p_outcome,
    p_occurred_at=>v_now,
    p_journal_date=>v_today,
    p_title=>'Seed inventory observed — '||v_lot.lot_label,
    p_detail=>coalesce(v_note,replace(p_outcome,'_',' ')),
    p_visibility_scope=>'farm_shared',
    p_importance=>case when p_outcome='problem_found' then 'attention' when p_outcome in ('count_corrected','restocked','depleted') then 'normal' else 'quiet' end,
    p_assigned_user_id=>null,
    p_task_id=>v_task.id,
    p_object_id=>null,
    p_crop_cycle_id=>null,
    p_project_id=>null,
    p_payload=>jsonb_build_object(
      'seedInventoryEventId',v_event_id,'seedLotId',v_lot.id,'outcome',p_outcome,
      'observedQuantity',case when p_outcome='depleted' then 0 else p_observed_quantity end,
      'quantityAdded',p_quantity_added,'unit',v_lot.quantity_unit,'problemKind',p_problem_kind,
      'nextCheckDate',p_next_check_date,'dependencyEffect',v_dependency
    ),
    p_provenance=>jsonb_build_object('adapter','seed_inventory_freshness_v1','source_table','atlas.seed_inventory_events','event_id',v_event_id)
  );

  return jsonb_build_object(
    'contractVersion','seed_inventory_result_v1','eventId',v_event_id,'taskId',v_task.id,
    'seedLotId',v_lot.id,'outcome',p_outcome,'expectedBeforeObservation',v_expected,
    'observedQuantity',case when p_outcome='depleted' then 0 else p_observed_quantity end,
    'journalEventId',v_journal_id,'ownerAttentionId',v_owner_attention_id,'clock',v_clock,'dependencyEffect',v_dependency,'deduplicated',false
  );
end;
$function$;

COMMIT;
