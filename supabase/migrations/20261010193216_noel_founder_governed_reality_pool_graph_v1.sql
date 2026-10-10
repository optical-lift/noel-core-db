
CREATE TABLE IF NOT EXISTS draft.noel_reality_nodes (
 node_id text PRIMARY KEY,
 node_kind text NOT NULL CHECK (node_kind IN ('lexical_pool','function_pool','role_pool','component','reality_category')),
 parent_node_id text REFERENCES draft.noel_reality_nodes(node_id),
 display_name text NOT NULL,
 original_definition text,
 operative_definition text,
 authority_state text NOT NULL,
 authority_basis text NOT NULL,
 notes text,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT components_need_parent CHECK (node_kind <> 'component' OR parent_node_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS noel_reality_nodes_parent_idx ON draft.noel_reality_nodes(parent_node_id);
CREATE INDEX IF NOT EXISTS noel_reality_nodes_kind_idx ON draft.noel_reality_nodes(node_kind,authority_state);
CREATE TABLE IF NOT EXISTS draft.noel_reality_aliases(
 alias_kind text NOT NULL,
 alias_value text NOT NULL,
 node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
 PRIMARY KEY(alias_kind,alias_value)
);
CREATE INDEX IF NOT EXISTS noel_reality_aliases_node_idx ON draft.noel_reality_aliases(node_id);
CREATE TABLE IF NOT EXISTS draft.noel_reality_edges (
 edge_id text PRIMARY KEY,
 from_node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
 to_node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
 relation_type text NOT NULL,
 authority_state text NOT NULL,
 authority_basis text NOT NULL,
 propagates_realm boolean NOT NULL DEFAULT false,
 scope_note text,
 evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (from_node_id <> to_node_id)
);
CREATE INDEX IF NOT EXISTS noel_reality_edges_from_idx ON draft.noel_reality_edges(from_node_id,is_active);
CREATE INDEX IF NOT EXISTS noel_reality_edges_to_idx ON draft.noel_reality_edges(to_node_id,is_active);
CREATE TABLE IF NOT EXISTS draft.noel_reality_token_anchors (
 node_id text NOT NULL REFERENCES draft.noel_reality_nodes(node_id),
 witness_key text NOT NULL,
 source_token_id text NOT NULL,
 token_role text NOT NULL,
 canonical_ref text,
 raw_surface text,
 strong_id_in_witness text,
 verification_status text NOT NULL DEFAULT 'source_spine_verified',
 notes text,
 PRIMARY KEY(node_id,witness_key,source_token_id,token_role)
);
CREATE INDEX IF NOT EXISTS noel_reality_anchors_token_idx ON draft.noel_reality_token_anchors(witness_key,source_token_id);
CREATE TABLE IF NOT EXISTS draft.noel_reality_decisions (
 decision_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 subject_kind text NOT NULL CHECK (subject_kind IN ('node','edge')),
 subject_id text NOT NULL,
 action text NOT NULL,
 prior_state text,
 resulting_state text NOT NULL,
 decision_basis text NOT NULL,
 actor_label text NOT NULL DEFAULT 'project_steward',
 recorded_at timestamptz NOT NULL DEFAULT now(),
 extra jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE TABLE IF NOT EXISTS draft.noel_reality_verse_compositions (
 composition_key text PRIMARY KEY,
 canonical_ref text NOT NULL,
 witness_key text NOT NULL,
 composition_statement text NOT NULL,
 token_roles jsonb NOT NULL DEFAULT '[]'::jsonb,
 source_basis text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now()
);
DO $r$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['noel_reality_nodes','noel_reality_aliases','noel_reality_edges','noel_reality_token_anchors','noel_reality_decisions','noel_reality_verse_compositions']
 LOOP
  EXECUTE format('ALTER TABLE draft.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE draft.%I FROM PUBLIC, anon, authenticated',t);
 END LOOP;
END
$r$;
CREATE OR REPLACE FUNCTION draft.get_noel_reality_context_v1(p_lookup text, p_max_depth integer DEFAULT 4)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $f$
WITH RECURSIVE
params AS (
 SELECT CASE WHEN upper(btrim(p_lookup)) ~ '^[HG]0*[0-9]+$'
 THEN substring(upper(btrim(p_lookup)) from 1 for 1)
      || lpad((substring(upper(btrim(p_lookup)) from 2)::integer)::text,4,'0')
 ELSE btrim(p_lookup) END lookup,
 greatest(0,least(coalesce(p_max_depth,4),7)) cap
),
seed AS (
 SELECT n.node_id FROM draft.noel_reality_nodes n,params p
 WHERE n.is_active AND n.node_id=p.lookup
 UNION
 SELECT a.node_id FROM draft.noel_reality_aliases a JOIN draft.noel_reality_nodes n ON n.node_id=a.node_id,params p
 WHERE n.is_active AND a.alias_value=p.lookup AND a.alias_kind='strongs'
),
walk(node_id,depth,path) AS (
 SELECT s.node_id,0,ARRAY[s.node_id]::text[] FROM seed s
 UNION ALL
 SELECT e.to_node_id,w.depth+1,w.path||e.to_node_id
 FROM walk w
 JOIN draft.noel_reality_edges e ON e.from_node_id=w.node_id
 JOIN draft.noel_reality_nodes n ON n.node_id=e.to_node_id
 CROSS JOIN params p
 WHERE e.is_active AND e.propagates_realm AND e.authority_state <> 'illustrative'
 AND n.is_active AND n.authority_state <> 'illustrative'
 AND w.depth < p.cap AND NOT (e.to_node_id=ANY(w.path))
),
best AS (
 SELECT DISTINCT ON (node_id) node_id,depth,path FROM walk ORDER BY node_id,depth
),
seed_info AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'node_id',n.node_id,'name',n.display_name,'operative_definition',n.operative_definition,
 'original_definition',n.original_definition,'authority_state',n.authority_state) ORDER BY n.node_id),'[]'::jsonb) j
 FROM seed s JOIN draft.noel_reality_nodes n ON n.node_id=s.node_id
),
resolved AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'node_id',n.node_id,'kind',n.node_kind,'name',n.display_name,'operative_definition',n.operative_definition,
 'authority_state',n.authority_state,'depth',b.depth,'path',b.path
 ) ORDER BY b.depth,n.node_id),'[]'::jsonb) j
 FROM best b JOIN draft.noel_reality_nodes n ON n.node_id=b.node_id
),
categories AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'category_id',n.node_id,'name',n.display_name,'via_path',b.path,'steps',b.depth
 ) ORDER BY b.depth,n.node_id),'[]'::jsonb) j
 FROM best b JOIN draft.noel_reality_nodes n ON n.node_id=b.node_id WHERE n.node_kind='reality_category'
),
related_edges AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'edge_id',e.edge_id,'from',e.from_node_id,'relation',e.relation_type,'to',e.to_node_id,
 'authority_state',e.authority_state,'propagates_realm',e.propagates_realm,
 'scope',e.scope_note,'evidence',e.evidence) ORDER BY e.edge_id),'[]'::jsonb) j
 FROM draft.noel_reality_edges e WHERE e.is_active AND e.from_node_id IN (SELECT node_id FROM best)
 AND e.authority_state <> 'illustrative'
),
token_evidence AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'node_id',a.node_id,'witness_key',a.witness_key,'source_token_id',a.source_token_id,
 'canonical_ref',a.canonical_ref,'surface',a.raw_surface,'token_role',a.token_role)
 ORDER BY a.node_id,a.canonical_ref,a.source_token_id),'[]'::jsonb) j
 FROM draft.noel_reality_token_anchors a WHERE a.node_id IN (SELECT node_id FROM best)
)
SELECT jsonb_build_object(
 'lookup',p_lookup,'governing_seed',s.j,'reached_nodes',r.j,
 'mandatory_reality_categories',c.j,'typed_edges',e.j,'source_token_examples',t.j,
 'inheritance_contract','Only active, non-illustrative, realm-propagating typed edges produce mandatory category context. Other active edges remain inspectable; relatedness does not establish lexical identity or a successful outcome.'
)
FROM seed_info s CROSS JOIN resolved r CROSS JOIN categories c CROSS JOIN related_edges e CROSS JOIN token_evidence t;
$f$;
REVOKE ALL ON FUNCTION draft.get_noel_reality_context_v1(text,integer) FROM PUBLIC, anon, authenticated;
