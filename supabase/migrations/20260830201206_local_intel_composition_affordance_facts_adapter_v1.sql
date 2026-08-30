create or replace function local_intel.get_composition_affordance_facts_v1(
  p_shadow_run_id uuid
) returns jsonb
language sql
stable
set search_path = pg_catalog
as $$
with run as (
  select r.id,r.query_text,r.query_state,r.retrieval_function,r.retrieval_parameters,r.retrieval_count,r.status,r.created_at
  from local_intel.recommendation_shadow_runs r
  where r.id=p_shadow_run_id
),
raw_candidates as (
  select a.object_type,a.object_id,a.stable_key,a.discovery_position,a.baseline_live_position,
         a.retrieval_terms,a.retrieval_term_ranks,a.candidate_origin,a.candidate_snapshot,
         coalesce(a.candidate_snapshot->>'entity_id', case when a.object_type='entity' then a.object_id::text else null end)::uuid as entity_id
  from local_intel.recommendation_shadow_candidate_adjudications a
  where a.run_id=p_shadow_run_id
),
attributes as (
  select s.entity_id,
         jsonb_agg(jsonb_build_object(
           'attribute_key',s.attribute_key,
           'value_text',s.value_text,
           'value_json',s.value_json,
           'state_confidence',s.state_confidence,
           'conflict_state',s.conflict_state,
           'decision_state',s.decision_state,
           'valid_from',s.valid_from,
           'evaluated_at',s.evaluated_at,
           'survivorship_policy_key',s.survivorship_policy_key,
           'survivorship_strategy',s.survivorship_strategy,
           'winning_claim_id',s.winning_claim_id
         ) order by s.attribute_key) as attrs
  from local_intel.v_entity_attribute_current_state_v1 s
  where s.entity_id in (select entity_id from raw_candidates where entity_id is not null)
  group by s.entity_id
),
availability as (
  select v.entity_id,
         jsonb_build_object(
           'availability_freshness',v.availability_freshness,
           'current_availability',v.current_availability,
           'latest_current_observation_at',v.latest_current_observation_at,
           'next_current_expiry_at',v.next_current_expiry_at,
           'last_availability_expired_at',v.last_availability_expired_at
         ) as availability_state
  from local_intel.v_entity_availability_summary v
  where v.entity_id in (select entity_id from raw_candidates where entity_id is not null)
),
candidate_rows as (
  select rc.*,
         coalesce(at.attrs,'[]'::jsonb) as current_attributes,
         av.availability_state,
         case
           when jsonb_array_length(coalesce(at.attrs,'[]'::jsonb))=0 then 'missing'
           else 'partial_or_present'
         end as affordance_evidence_state
  from raw_candidates rc
  left join attributes at on at.entity_id=rc.entity_id
  left join availability av on av.entity_id=rc.entity_id
),
packet_candidates as (
  select jsonb_agg(jsonb_build_object(
    'carrier_ref',c.object_type||':'||c.object_id::text,
    'object_type',c.object_type,
    'object_id',c.object_id,
    'entity_id',c.entity_id,
    'stable_key',c.stable_key,
    'candidate_origin',c.candidate_origin,
    'retrieval_terms',c.retrieval_terms,
    'retrieval_term_ranks',c.retrieval_term_ranks,
    'discovery_position',c.discovery_position,
    'baseline_live_position',c.baseline_live_position,
    'factual_snapshot',c.candidate_snapshot,
    'current_attributes',c.current_attributes,
    'current_availability',coalesce(c.availability_state,'null'::jsonb),
    'affordance_evidence_state',c.affordance_evidence_state,
    'explicit_unknowns',case when c.affordance_evidence_state='missing'
      then jsonb_build_array('no resolved current human-use attribute state for this entity in v_entity_attribute_current_state_v1')
      else '[]'::jsonb end
  ) order by c.discovery_position nulls last,c.baseline_live_position nulls last,c.stable_key) as value
  from candidate_rows c
),
stats as (
  select count(*)::integer candidate_count,
         count(*) filter(where affordance_evidence_state='missing')::integer missing_affordance_state_count,
         count(*) filter(where affordance_evidence_state='partial_or_present')::integer candidates_with_resolved_attributes,
         count(*) filter(where object_type='occurrence')::integer occurrence_count,
         count(*) filter(where object_type='entity')::integer entity_count,
         count(*) filter(where object_type='offering')::integer offering_count
  from candidate_rows
)
select jsonb_build_object(
  'adapter_version','local_composition_affordance_facts_v1',
  'adapter_role','candidate_truth_and_affordance_projection_only_no_journey_selection',
  'source_shadow_run_id',r.id,
  'query_text',r.query_text,
  'query_state',r.query_state,
  'retrieval_provenance',jsonb_build_object(
    'function',r.retrieval_function,
    'parameters',r.retrieval_parameters,
    'retrieval_count',r.retrieval_count,
    'run_status',r.status,
    'created_at',r.created_at
  ),
  'candidate_stats',jsonb_build_object(
    'candidate_count',s.candidate_count,
    'entities',s.entity_count,
    'offerings',s.offering_count,
    'occurrences',s.occurrence_count,
    'candidates_with_resolved_attributes',s.candidates_with_resolved_attributes,
    'missing_affordance_state_count',s.missing_affordance_state_count
  ),
  'candidate_affordance_carriers',coalesce(pc.value,'[]'::jsonb),
  'epistemic_contract',jsonb_build_object(
    'prior_shadow_verdicts_not_inherited',true,
    'prior_shadow_rationales_not_inherited',true,
    'category_is_not_affordance',true,
    'family_friendly_label_is_not_complete_family_fit',true,
    'missing_attribute_state_is_unknown_not_negative',true,
    'occurrence_time_is_factual_gate_not_moral_rank',true,
    'adapter_does_not_select_fruit_operations_sequence_or_branches',true
  )
)
from run r cross join stats s cross join packet_candidates pc;
$$;

revoke all on function local_intel.get_composition_affordance_facts_v1(uuid) from public;