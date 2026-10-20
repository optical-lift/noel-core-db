create or replace function intelligence.get_noel_medical_lab_context_v1(p_topic text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, draft, intelligence
as $fn$
declare
  q text := lower(btrim(coalesce(p_topic,'')));
  rx text;
begin
  rx := case
    when q ~ 'somat|bodywork|breath|somatic experienc' then 'somat|bodywork|physical healing|function_before_label'
    when q ~ 'trauma|protect|conditioning' then 'trauma|protect|pain|warning'
    when q ~ 'pain|noci|interocep|sensa' then 'pain|sensa|body|interocep|warning'
    when q ~ 'muscle|sway|ideomot|test' then 'muscle|sway|movement|testing|carrier|answer'
    when q ~ 'mind|aware|thought|synthesi|overthink' then 'mind|aware|thought|synthesi|recognition|interpretation'
    when q ~ 'spirit|know|discern|prayer|hearing' then 'spirit|know|discern|hearing|reception'
    when q = '' then null
    else null end;

  return jsonb_build_object(
    'context_version','medical_lab_knowledge_continuity_v1',
    'topic',nullif(q,''),
    'loaded_at',now(),
    'primary_trail_id',23,
    'source_policy',jsonb_build_object(
      'authority','user-approved governance and canon where independently established',
      'historical_messages','first-person dated research history; not empirical verification',
      'external_science','original observations and mechanisms must remain distinct from hypotheses and canonical interpretation',
      'privacy','private research only; person-specific practice remains in its private schema',
      'next_session','Noel first; consult Dropbox only for unimported history or source audit',
      'commits','new governing premises require separate approval'
    ),
    'frameworks',(select coalesce(jsonb_agg(jsonb_build_object('key',spec_key,'version',version_label,'status',status)),'[]'::jsonb)
                  from draft.noel_research_system_specs where spec_key in ('medical_lab_v1','medical_framework_v2','medical_lab_knowledge_continuity_v1')),
    'trail',(select jsonb_build_object('id',trail_id,'key',trail_key,'summary',current_summary,'unresolved',unresolved_question,'next_test',next_test) from draft.research_trails where trail_id=23),
    'premise_count',(select count(*) from draft.research_claims where current_category in ('medical_lab_governing_premises_v2','medical_lab_interospection_premises_v1','medical_lab_interospection_premises_v2')),
    'premise_index',(select coalesce(jsonb_agg(jsonb_build_object('id',c.routing_snapshot->>'premise_id','key',c.claim_key,'title',c.claim_title,'status',c.claim_status) order by c.claim_id),'[]'::jsonb)
                     from draft.research_claims c where c.current_category in ('medical_lab_governing_premises_v2','medical_lab_interospection_premises_v1','medical_lab_interospection_premises_v2')),
    'relevant_premises',(select coalesce(jsonb_agg(jsonb_build_object('id',s.premise_id,'title',s.claim_title,'statement',s.short_claim,'kind',s.claim_kind,'status',s.claim_status,'empirical_status',s.routing_snapshot->>'empirical_status') order by s.claim_id),'[]'::jsonb)
                         from (select c.*,c.routing_snapshot->>'premise_id' as premise_id
                               from draft.research_claims c
                               where c.current_category in ('medical_lab_governing_premises_v2','medical_lab_interospection_premises_v1','medical_lab_interospection_premises_v2')
                                 and (q='' or (rx is not null and (c.claim_title ~* rx or c.short_claim ~* rx))
                                      or (rx is null and (c.claim_title ilike '%'||q||'%' or c.short_claim ilike '%'||q||'%')))
                               order by c.claim_id limit 27) s),
    'historical_trace_count',(select count(*) from draft.research_traces where capture_key like 'medical_history_%'),
    'historical_statements',(select coalesce(jsonb_agg(jsonb_build_object('trace_id',s.trace_id,'title',s.capture_title,'text_as_stated',s.raw_text,'observed_at',s.observed_at,'locator',s.source_reference,'interpretation_note',s.operator_interpretation,'verbatim_excerpt',s.metadata->>'verbatim_excerpt','historical_status','not_empirically_verified') order by s.observed_at,s.trace_id),'[]'::jsonb)
                             from (select t.* from draft.research_traces t where t.capture_key like 'medical_history_%'
                               and (q='' or (rx is not null and (t.capture_title ~* rx or t.raw_text ~* rx or t.metadata->>'topics' ~* rx))
                                    or (rx is null and (t.capture_title ilike '%'||q||'%' or t.raw_text ilike '%'||q||'%')))
                               order by t.observed_at,t.trace_id limit 40) s),
    'revision_links',(select coalesce(jsonb_agg(jsonb_build_object('newer_trace',r.source_object_id,'earlier_trace',r.target_object_id,'relation',r.relation_type,'why',r.rationale) order by r.created_at),'[]'::jsonb)
                      from draft.research_object_relationships r
                      where r.source_object_type='trace' and r.target_object_type='trace'
                        and r.relation_type in ('revises_prior_method_priority','refines_earlier_mind_model','extends_learning_trajectory','reframes_thought_as_body_data','refines_source_carrier_jurisdiction')),
    'scientific_evidence',(select coalesce(jsonb_agg(jsonb_build_object('premise',c.routing_snapshot->>'premise_id','source',e.source_reference,'observation',e.evidence_summary,'evidence_type',e.evidence_type,'support_role',e.support_role) order by e.claim_evidence_id),'[]'::jsonb)
                           from draft.research_claim_evidence e join draft.research_claims c on c.claim_id=e.claim_id
                           where c.current_category in ('medical_lab_governing_premises_v2','medical_lab_interospection_premises_v1','medical_lab_interospection_premises_v2')
                           and (q='' or rx is null or c.claim_title ~* rx or c.short_claim ~* rx)),
    'open_research',(select coalesce(jsonb_agg(jsonb_build_object('key',o.obligation_key,'title',o.obligation_title,'next',o.next_valid_move,'status',o.status) order by o.obligation_id),'[]'::jsonb)
                    from draft.research_obligations o where o.trail_id=23 and o.status in ('open','active','deferred')),
    'adjacent_private_trails',jsonb_build_array(
       jsonb_build_object('trail_id',22,'purpose','historical method-learning in person-specific private practice; do not copy cases into general Medical Lab'),
       jsonb_build_object('trail_id',21,'purpose','historical individual casework; only query when specifically authorized')
    )
  );
end;
$fn$;
revoke all on function intelligence.get_noel_medical_lab_context_v1(text) from public, anon, authenticated;
comment on function intelligence.get_noel_medical_lab_context_v1(text) is 'Private Noel Medical Lab compact startup context. SECURITY INVOKER: authorized research operator only; historical messages are not scientific evidence.';