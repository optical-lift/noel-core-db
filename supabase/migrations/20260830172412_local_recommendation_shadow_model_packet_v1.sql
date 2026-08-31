create or replace function local_intel.get_recommendation_shadow_model_packet_v1(p_run_id uuid)
returns jsonb
language sql
stable
set search_path to 'pg_catalog','local_intel'
as $function$
with run_ctx as (
  select r.*,l.stable_key as lens_key,l.name as lens_name,l.source_system,l.source_ref,l.source_version,l.mode as lens_mode
  from local_intel.recommendation_shadow_runs r
  join local_intel.recommendation_lenses l on l.id=r.lens_id
  where r.id=p_run_id
), candidate_rows as (
  select c.*,
    jsonb_build_object(
      'stable_key',c.stable_key,
      'object_type',c.object_type,
      'title',coalesce(c.candidate_snapshot->>'title',c.candidate_snapshot->>'entity_name'),
      'entity_name',c.candidate_snapshot->>'entity_name',
      'category',c.candidate_snapshot->>'category',
      'candidate_origin',c.candidate_origin,
      'baseline_live_position',c.baseline_live_position,
      'discovery_position',c.discovery_position,
      'verdict',c.verdict,
      'shadow_position_group',c.shadow_position_group,
      'confidence',c.confidence,
      'activated_dimensions',c.activated_dimensions,
      'rationale',c.rationale,
      'missing_evidence',c.missing_evidence,
      'does_not_establish',c.does_not_establish,
      'schedule',c.candidate_snapshot->'schedule',
      'price',c.candidate_snapshot->'price',
      'audience',c.candidate_snapshot->'audience',
      'location',c.candidate_snapshot->'location',
      'current_status',c.candidate_snapshot->>'current_status',
      'public_url',c.candidate_snapshot->>'public_url',
      'last_verified_at',c.candidate_snapshot->>'last_verified_at'
    ) as packet_candidate
  from local_intel.recommendation_shadow_candidate_adjudications c
  where c.run_id=p_run_id
)
select jsonb_build_object(
  'packet_type','ask_elm_governed_recommendation_shadow_v1',
  'run_id',r.id,
  'mode','shadow',
  'production_rank_changed',coalesce((r.shadow_summary->>'production_rank_changed')::boolean,false),
  'lens',jsonb_build_object(
    'key',r.lens_key,
    'name',r.lens_name,
    'source_system',r.source_system,
    'source_ref',r.source_ref,
    'source_version',r.source_version,
    'mode',r.lens_mode
  ),
  'query',jsonb_build_object('text',r.query_text,'state',r.query_state),
  'active_operators',r.active_operator_snapshot,
  'retrieval',jsonb_build_object(
    'function',r.retrieval_function,
    'parameters',r.retrieval_parameters,
    'candidate_count',r.retrieval_count,
    'summary',r.shadow_summary
  ),
  'preferred',coalesce((select jsonb_agg(cr.packet_candidate order by cr.shadow_position_group,cr.discovery_position) from candidate_rows cr where cr.verdict='preferred'),'[]'::jsonb),
  'eligible',coalesce((select jsonb_agg(cr.packet_candidate order by cr.shadow_position_group,cr.discovery_position) from candidate_rows cr where cr.verdict='eligible'),'[]'::jsonb),
  'unresolved',coalesce((select jsonb_agg(cr.packet_candidate order by cr.shadow_position_group,cr.discovery_position) from candidate_rows cr where cr.verdict='unresolved'),'[]'::jsonb),
  'lower_fit',coalesce((select jsonb_agg(cr.packet_candidate order by cr.shadow_position_group,cr.discovery_position) from candidate_rows cr where cr.verdict='lower_fit'),'[]'::jsonb),
  'ineligible',coalesce((select jsonb_agg(cr.packet_candidate order by cr.shadow_position_group,cr.discovery_position) from candidate_rows cr where cr.verdict='ineligible'),'[]'::jsonb),
  'model_contract',jsonb_build_object(
    'speak_from_governed_packet',true,
    'do_not_recalculate_morality',true,
    'do_not_promote_unresolved_to_fact',true,
    'preserve_ties_and_nulls',true,
    'explain_preference_using_activated_dimensions_only',true,
    'do_not_use_prohibited_shortcuts',true
  )
)
from run_ctx r;
$function$;