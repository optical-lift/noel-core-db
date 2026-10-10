BEGIN;

-- Noel governed research entry v1. Ratified definitions and inherited realms
-- precede legacy discovery. This is a private, security-invoker read seam.
INSERT INTO draft.noel_reality_english_routes(term, node_id, route_basis)
VALUES
('eaten','founding-pool-0018','English eat form'),
('ate','founding-pool-0018','English eat form'),
('eats','founding-pool-0018','English eat form'),
('blessed','founding-pool-0043','English bless form'),
('blesses','founding-pool-0043','English bless form')
ON CONFLICT (term,node_id) DO NOTHING;

CREATE OR REPLACE FUNCTION intelligence.begin_noel_research_v1(
 p_question text,
 p_depth integer DEFAULT 4,
 p_token_limit integer DEFAULT 8,
 p_candidate_limit integer DEFAULT 8
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $body$
WITH
 question_terms AS MATERIALIZED (
  SELECT DISTINCT
   CASE WHEN w.term ~ '^[hg][0-9]{1,5}$'
    THEN upper(left(w.term,1))||lpad((substring(w.term FROM 2)::integer)::text,4,'0')
    ELSE w.term END AS term
  FROM regexp_split_to_table(lower(coalesce(p_question,'')),'[^[:alnum:]]+') AS w(term)
  WHERE w.term <> ''
 ),
 routes AS MATERIALIZED (
  SELECT DISTINCT q.term,r.node_id,r.route_basis
  FROM question_terms q
  JOIN draft.noel_reality_english_routes r ON r.term=q.term
  JOIN draft.noel_reality_nodes n ON n.node_id=r.node_id AND n.is_active
  UNION
  SELECT DISTINCT q.term,a.node_id,'exact_source_lexical_identity'::text
  FROM question_terms q
  JOIN draft.noel_reality_aliases a ON a.alias_value=q.term AND a.alias_kind='strongs'
  JOIN draft.noel_reality_nodes n ON n.node_id=a.node_id AND n.is_active
 ),
 pool_preflights AS MATERIALIZED (
  SELECT r.term,r.node_id,r.route_basis,
   draft.get_noel_reality_preflight_v1(r.node_id,
    least(greatest(coalesce(p_depth,4),1),7),
    least(greatest(coalesce(p_token_limit,8),1),50)) AS pool_context
  FROM routes r
 ),
 governed AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'matched_term',term,'pool_id',node_id,'route_basis',route_basis,
    'governed_context',pool_context) ORDER BY term,node_id),'[]'::jsonb) AS payload,
    count(*) AS route_count
  FROM pool_preflights
 ),
 discovered AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
   'matched_term',qt.term,'objects',coalesce(s.results,'[]'::jsonb))
   ORDER BY qt.term),'[]'::jsonb) AS payload
  FROM (SELECT DISTINCT term FROM routes) qt
  CROSS JOIN LATERAL (
   SELECT coalesce(jsonb_agg(to_jsonb(search_result) ORDER BY search_result.score DESC),
    '[]'::jsonb) AS results
   FROM intelligence.search_noel_research_objects_v4(qt.term,
    least(greatest(coalesce(p_candidate_limit,8),1),20)) search_result
  ) s
 ),
 full_question_search AS (
  SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.score DESC),'[]'::jsonb) AS payload
  FROM intelligence.search_noel_research_objects_v4(p_question,
    least(greatest(coalesce(p_candidate_limit,8),1),20)) s
 )
SELECT jsonb_build_object(
 'contract_version','noel_research_preflight_v1',
 'question',p_question,
 'preflight_complete',true,
 'recognized_pool_count',g.route_count,
 'requires_lexical_disambiguation',g.route_count=0,
 'governing_pool_contexts',g.payload,
 'legacy_discovery_by_recognized_term',d.payload,
 'legacy_discovery_by_full_question',f.payload,
 'authority_rule',
 'Steward-ratified meanings and typed relationships remain operative until steward revision. Coverage and legacy ranking do not demote them. Governed reality categories are required context, not identity or a guaranteed successful outcome. Preserve witness-specific source tokens.',
 'research_next_step',
  CASE WHEN g.route_count=0
   THEN 'No lexical pool route recognized: discover candidates without pretending inherited English is a steward-ratified meaning.'
   ELSE 'Reason from the governing pools before synthesis. Track syntax, source, carrier, receiver, authorization, direction, incoming/outgoing state, and inherited reality categories.' END
)
FROM governed g CROSS JOIN discovered d CROSS JOIN full_question_search f;
$body$;

REVOKE ALL ON FUNCTION intelligence.begin_noel_research_v1(text,integer,integer,integer)
 FROM PUBLIC,anon,authenticated;

COMMIT;
