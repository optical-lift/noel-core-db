-- Atlas employer-drawer harvest/event intelligence v1
--
-- First reviewed semantic adapter through the A5 Exposure Envelope.
-- The adapter does not expose worker_week_projection.delivery_payload, work-item
-- instructions, planned-occurrence notes, or arbitrary metadata. It recognizes
-- one canonical structured condition: a worker-projected harvest occurrence whose
-- source contract explicitly says the normal harvest is partial because a bounded
-- number of beds are reserved for attendee harvest at an event.
--
-- Rendering remains downstream. This migration admits only the small semantic
-- facts required to render that condition faithfully.

begin;

insert into atlas.semantic_exposure_policies (
  policy_key,
  audience_kind,
  purpose_key,
  information_class,
  semantic_kind,
  predicate_key,
  adapter_key,
  source_domain,
  source_kind,
  provenance
)
values
  (
    'employer_drawer_event_harvest_exception_active_v1',
    'organization_member',
    'employer_drawer',
    'worker_institutional_intelligence',
    'requirement_state',
    'event_harvest_exception_active',
    'worker_projection_event_harvest_reservation_v1',
    'operations',
    'planned_work_occurrence',
    jsonb_build_object(
      'contractVersion','employer_drawer_harvest_event_intelligence_v1',
      'reason','A projected harvest occurrence may expose that its normal full-harvest contract is intentionally suspended for an event.'
    )
  ),
  (
    'employer_drawer_reserved_flower_beds_minimum_v1',
    'organization_member',
    'employer_drawer',
    'worker_institutional_intelligence',
    'requirement_state',
    'reserved_flower_beds_minimum',
    'worker_projection_event_harvest_reservation_v1',
    'operations',
    'planned_work_occurrence',
    jsonb_build_object(
      'contractVersion','employer_drawer_harvest_event_intelligence_v1',
      'reason','The lower bound is a structured execution constraint, not copied prose.'
    )
  ),
  (
    'employer_drawer_reserved_flower_beds_maximum_v1',
    'organization_member',
    'employer_drawer',
    'worker_institutional_intelligence',
    'requirement_state',
    'reserved_flower_beds_maximum',
    'worker_projection_event_harvest_reservation_v1',
    'operations',
    'planned_work_occurrence',
    jsonb_build_object(
      'contractVersion','employer_drawer_harvest_event_intelligence_v1',
      'reason','The upper bound is a structured execution constraint, not copied prose.'
    )
  ),
  (
    'employer_drawer_event_attendees_harvest_reserved_beds_v1',
    'organization_member',
    'employer_drawer',
    'worker_institutional_intelligence',
    'requirement_state',
    'event_attendees_harvest_reserved_beds',
    'worker_projection_event_harvest_reservation_v1',
    'operations',
    'planned_work_occurrence',
    jsonb_build_object(
      'contractVersion','employer_drawer_harvest_event_intelligence_v1',
      'reason','This structured boolean is the causal link that makes the reservation relevant to the worker.'
    )
  ),
  (
    'employer_drawer_event_harvest_service_date_v1',
    'organization_member',
    'employer_drawer',
    'worker_coordination_context',
    'temporal_contract',
    'event_harvest_service_date',
    'worker_projection_event_harvest_reservation_v1',
    'operations',
    'planned_work_occurrence',
    jsonb_build_object(
      'contractVersion','employer_drawer_harvest_event_intelligence_v1',
      'reason','The service date allows downstream rendering to situate the admitted fact without exposing raw schedule prose.'
    )
  )
on conflict (policy_key) do update set
  audience_kind=excluded.audience_kind,
  purpose_key=excluded.purpose_key,
  information_class=excluded.information_class,
  semantic_kind=excluded.semantic_kind,
  predicate_key=excluded.predicate_key,
  adapter_key=excluded.adapter_key,
  source_domain=excluded.source_domain,
  source_kind=excluded.source_kind,
  allowed_modalities='{}'::text[],
  allowed_adjudication_states='{}'::text[],
  active=true,
  provenance=excluded.provenance,
  updated_at=now();

create or replace function atlas.worker_projection_event_harvest_reservation_v1(
  p_organization_id uuid,
  p_audience_membership_id uuid,
  p_delivery_membership_id uuid,
  p_window_start date,
  p_window_end date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_rec record;
  v_min integer;
  v_max integer;
  v_result jsonb;
  v_facts jsonb := '[]'::jsonb;
  v_admitted jsonb;
  v_candidate jsonb;
  v_fact_count integer := 0;
begin
  if p_organization_id is null
     or p_audience_membership_id is null
     or p_delivery_membership_id is null
     or p_window_start is null
     or p_window_end is null
     or p_window_end < p_window_start
     or p_window_end - p_window_start > 13 then
    return jsonb_build_object(
      'contractVersion','worker_projection_event_harvest_reservation_v1',
      'state','invalid_request',
      'items','[]'::jsonb
    );
  end if;

  for v_rec in
    select distinct on (o.id)
      o.id as occurrence_id,
      o.planned_due_date,
      o.task_payload,
      w.id as projection_id
    from atlas.worker_week_projection w
    join atlas.work_items wi
      on wi.id = w.source_id
     and w.source_kind = 'work_item'
     and wi.organization_id = p_organization_id
     and wi.work_state in ('open','completed')
     and wi.source_object_type = 'planned_work_occurrence'
    join atlas.planned_work_occurrences o
      on o.id = wi.source_object_id
     and o.farm_id = w.farm_id
    join atlas.farms f
      on f.id = w.farm_id
     and f.organization_id = p_organization_id
    where w.membership_id = p_delivery_membership_id
      and w.planned_date between p_window_start and p_window_end
      and w.organization_id = p_organization_id
      and w.plan_state in ('planned','conditional','flexible')
      and o.state not in ('cancelled','completed')
      and coalesce((o.task_payload#>>'{metadata,event_harvest_exception}')::boolean,false) = true
      and coalesce((o.task_payload#>>'{metadata,normal_full_thursday_harvest}')::boolean,true) = false
      and coalesce((o.task_payload#>>'{metadata,event_attendees_harvest_reserved_beds}')::boolean,false) = true
    order by o.id,w.planned_date,w.plan_order,w.id
  loop
    begin
      v_min := nullif(v_rec.task_payload#>>'{metadata,reserved_flower_beds_min}','')::integer;
      v_max := nullif(v_rec.task_payload#>>'{metadata,reserved_flower_beds_max}','')::integer;
    exception when invalid_text_representation or numeric_value_out_of_range then
      v_min := null;
      v_max := null;
    end;

    if v_min is null or v_max is null or v_min < 1 or v_max < v_min or v_max > 20 then
      continue;
    end if;

    v_facts := '[]'::jsonb;
    v_fact_count := 0;

    v_candidate := jsonb_build_object(
      'adapterKey','worker_projection_event_harvest_reservation_v1',
      'informationClass','worker_institutional_intelligence',
      'semanticKind','requirement_state',
      'predicateKey','event_harvest_exception_active',
      'sourceDomain','operations',
      'sourceKind','planned_work_occurrence',
      'sourceId',v_rec.occurrence_id::text,
      'valueKind','boolean',
      'value',true
    );
    v_admitted := atlas.semantic_exposure_envelope_v1(
      p_organization_id,p_audience_membership_id,'employer_drawer',v_candidate
    );
    if coalesce((v_admitted->>'admitted')::boolean,false) then
      v_facts := v_facts || jsonb_build_array(v_admitted->'envelope');
      v_fact_count := v_fact_count + 1;
    end if;

    v_candidate := jsonb_build_object(
      'adapterKey','worker_projection_event_harvest_reservation_v1',
      'informationClass','worker_institutional_intelligence',
      'semanticKind','requirement_state',
      'predicateKey','reserved_flower_beds_minimum',
      'sourceDomain','operations',
      'sourceKind','planned_work_occurrence',
      'sourceId',v_rec.occurrence_id::text,
      'valueKind','number',
      'value',to_jsonb(v_min),
      'valueUnit','beds'
    );
    v_admitted := atlas.semantic_exposure_envelope_v1(
      p_organization_id,p_audience_membership_id,'employer_drawer',v_candidate
    );
    if coalesce((v_admitted->>'admitted')::boolean,false) then
      v_facts := v_facts || jsonb_build_array(v_admitted->'envelope');
      v_fact_count := v_fact_count + 1;
    end if;

    v_candidate := jsonb_build_object(
      'adapterKey','worker_projection_event_harvest_reservation_v1',
      'informationClass','worker_institutional_intelligence',
      'semanticKind','requirement_state',
      'predicateKey','reserved_flower_beds_maximum',
      'sourceDomain','operations',
      'sourceKind','planned_work_occurrence',
      'sourceId',v_rec.occurrence_id::text,
      'valueKind','number',
      'value',to_jsonb(v_max),
      'valueUnit','beds'
    );
    v_admitted := atlas.semantic_exposure_envelope_v1(
      p_organization_id,p_audience_membership_id,'employer_drawer',v_candidate
    );
    if coalesce((v_admitted->>'admitted')::boolean,false) then
      v_facts := v_facts || jsonb_build_array(v_admitted->'envelope');
      v_fact_count := v_fact_count + 1;
    end if;

    v_candidate := jsonb_build_object(
      'adapterKey','worker_projection_event_harvest_reservation_v1',
      'informationClass','worker_institutional_intelligence',
      'semanticKind','requirement_state',
      'predicateKey','event_attendees_harvest_reserved_beds',
      'sourceDomain','operations',
      'sourceKind','planned_work_occurrence',
      'sourceId',v_rec.occurrence_id::text,
      'valueKind','boolean',
      'value',true
    );
    v_admitted := atlas.semantic_exposure_envelope_v1(
      p_organization_id,p_audience_membership_id,'employer_drawer',v_candidate
    );
    if coalesce((v_admitted->>'admitted')::boolean,false) then
      v_facts := v_facts || jsonb_build_array(v_admitted->'envelope');
      v_fact_count := v_fact_count + 1;
    end if;

    v_candidate := jsonb_build_object(
      'adapterKey','worker_projection_event_harvest_reservation_v1',
      'informationClass','worker_coordination_context',
      'semanticKind','temporal_contract',
      'predicateKey','event_harvest_service_date',
      'sourceDomain','operations',
      'sourceKind','planned_work_occurrence',
      'sourceId',v_rec.occurrence_id::text,
      'valueKind','date',
      'value',to_jsonb(v_rec.planned_due_date::text)
    );
    v_admitted := atlas.semantic_exposure_envelope_v1(
      p_organization_id,p_audience_membership_id,'employer_drawer',v_candidate
    );
    if coalesce((v_admitted->>'admitted')::boolean,false) then
      v_facts := v_facts || jsonb_build_array(v_admitted->'envelope');
      v_fact_count := v_fact_count + 1;
    end if;

    -- This item is useful only if every required semantic coordinate crossed the
    -- membrane. Partial admission is suppressed rather than rendered ambiguously.
    if v_fact_count = 5 then
      v_result := jsonb_build_object(
        'sourceProjectionId',v_rec.projection_id,
        'facts',v_facts
      );
      return jsonb_build_object(
        'contractVersion','worker_projection_event_harvest_reservation_v1',
        'state','admitted',
        'items',jsonb_build_array(v_result),
        'truthBoundary',jsonb_build_object(
          'rawProjectionPayloadExposed',false,
          'rawWorkItemInstructionsExposed',false,
          'rawOccurrenceTaskPayloadExposed',false,
          'allRequiredFactsMustBeAdmitted',true
        )
      );
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','worker_projection_event_harvest_reservation_v1',
    'state','none',
    'items','[]'::jsonb
  );
end;
$$;

comment on function atlas.worker_projection_event_harvest_reservation_v1(uuid,uuid,uuid,date,date) is
  'Reviewed employer-drawer adapter for one structured institutional-intelligence fact: projected harvest is intentionally partial because a bounded number of beds are reserved for event-attendee harvest. It returns only A5-admitted normalized envelopes and suppresses raw prose/source payloads.';

revoke all on function atlas.worker_projection_event_harvest_reservation_v1(uuid,uuid,uuid,date,date)
  from public, anon, authenticated;
grant execute on function atlas.worker_projection_event_harvest_reservation_v1(uuid,uuid,uuid,date,date)
  to service_role;

commit;
