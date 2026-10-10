
CREATE TABLE IF NOT EXISTS draft.noel_reality_english_routes(
 term text NOT NULL,
 node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
 route_basis text NOT NULL,
 PRIMARY KEY(term,node_id),
 CHECK (term=lower(btrim(term)))
);
ALTER TABLE draft.noel_reality_english_routes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE draft.noel_reality_english_routes FROM PUBLIC,anon,authenticated;
INSERT INTO draft.noel_reality_english_routes(term,node_id,route_basis)
VALUES
('eat','founding-pool-0018','governed lookup'),
('eating','founding-pool-0018','governed lookup'),
('bless','founding-pool-0043','governed lookup'),
('blessing','founding-pool-0043','governed lookup'),
('bread','founding-pool-0093','founder definition'),
('grain','lexeme:H1715','attested grain lexeme'),
('grain','lexeme:H1250','attested grain lexeme'),
('atonement','function:atonement','governed functional node'),
('atonement','lexeme:H3722','attested source-language root'),
('holiness','function:holiness','governed reality function'),
('healing','reality:healing_holiness_restoration','steward realm'),
('restoration','reality:healing_holiness_restoration','steward realm')
ON CONFLICT(term,node_id) DO NOTHING;
CREATE OR REPLACE FUNCTION draft.lookup_noel_reality_term_v1(
 p_term text,p_max_depth integer DEFAULT 4,p_token_limit integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $f$
WITH matches AS (
 SELECT r.node_id,r.route_basis
 FROM draft.noel_reality_english_routes r
 JOIN draft.noel_reality_nodes n ON n.node_id=r.node_id AND n.is_active
 WHERE r.term=lower(btrim(p_term))
 UNION
 SELECT a.node_id, 'Strong ID lookup'::text
 FROM draft.noel_reality_aliases a
 JOIN draft.noel_reality_nodes n ON n.node_id=a.node_id AND n.is_active
 WHERE a.alias_kind='strongs' AND a.alias_value=upper(btrim(p_term))
),
results AS (
 SELECT m.node_id,m.route_basis,
 draft.get_noel_reality_preflight_v1(m.node_id,p_max_depth,p_token_limit) result
 FROM matches m
)
SELECT jsonb_build_object(
 'search_term',p_term,
 'matched_pools',coalesce(jsonb_agg(jsonb_build_object('node_id',node_id,'basis',route_basis,'context',result)
 ORDER BY node_id),'[]'::jsonb),
 'matching_scope','Explicit English route or exact Strong ID; free-text semantic search is a separate operation.')
FROM results;
$f$;
REVOKE ALL ON FUNCTION draft.lookup_noel_reality_term_v1(text,integer,integer)
 FROM PUBLIC, anon, authenticated;
