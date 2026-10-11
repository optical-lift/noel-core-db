BEGIN;
CREATE OR REPLACE FUNCTION public.titus_constellation_private_snapshot_v1()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $f$
WITH
pn AS (
  SELECT 'pool:'||n.node_id id, n.node_id origin_id, 'pool'::text kind,
         n.display_name label,n.node_kind||' · '||n.authority_state subtitle,
         n.authority_state authority,
         coalesce(n.operative_definition,n.original_definition,n.notes,'') detail,
         coalesce((SELECT jsonb_agg(a.alias_value ORDER BY a.alias_value)
                   FROM draft.noel_reality_aliases a WHERE a.node_id=n.node_id),'[]'::jsonb) aliases,
         'draft.noel_reality_nodes'::text source,
         coalesce((SELECT jsonb_agg(jsonb_build_object(
           'ref',t.canonical_ref,'witness',t.witness_key,'surface',t.raw_surface,
           'sourceTokenId',t.source_token_id) ORDER BY t.canonical_ref,t.source_token_id)
           FROM (SELECT canonical_ref,witness_key,raw_surface,source_token_id
                 FROM draft.noel_reality_token_anchors WHERE node_id=n.node_id
                 ORDER BY canonical_ref,source_token_id LIMIT 16) t),'[]'::jsonb) token_examples,
         '[]'::jsonb lane_tags
  FROM draft.noel_reality_nodes n WHERE n.is_active
),
sn AS (
  SELECT 'song:'||s.song_object_id::text,s.song_object_id::text,'song'::text,
         s.object_name,coalesce(s.object_type,'Song object'),
         coalesce(s.object_status,'unclassified'),
         coalesce(s.one_sentence_claim,s.provisional_function_lane,s.notes,''),
         '[]'::jsonb,'draft.song_objects'::text,'[]'::jsonb,
         coalesce((SELECT jsonb_agg(DISTINCT coalesce(t.mini_lane_label,t.tag_role))
                   FROM draft.song_lane_tags t WHERE t.song_object_id=s.song_object_id
                   AND coalesce(t.mini_lane_label,t.tag_role) IS NOT NULL),'[]'::jsonb)
  FROM draft.song_objects s
),
pt AS (
  SELECT 'pattern:'||p.pattern_id,p.pattern_id,'pattern'::text,
         p.pattern_name,coalesce(p.plain_language_caption,'Registered pattern'),
         coalesce(p.authority_level,p.pattern_status,'unclassified'),
         coalesce(p.core_claim,p.notes,''),
         '[]'::jsonb,'draft.pattern_registry'::text,'[]'::jsonb,'[]'::jsonb
  FROM draft.pattern_registry p
),
nodes AS (SELECT * FROM pn UNION ALL SELECT * FROM sn UNION ALL SELECT * FROM pt),
edges_all AS (
  SELECT 'pool-edge:'||e.edge_id id,'pool:'||e.from_node_id src,'pool:'||e.to_node_id dst,
         e.relation_type relation,e.authority_state authority,
         'draft.noel_reality_edges'::text source,
         coalesce(e.scope_note,e.authority_basis,'') note,
         e.propagates_realm inherits
  FROM draft.noel_reality_edges e WHERE e.is_active
  UNION ALL
  SELECT 'pattern-edge:'||r.pattern_relationship_id::text,
         'pattern:'||r.source_pattern_id,'pattern:'||r.target_pattern_id,
         r.relationship_type,coalesce(r.status,'unclassified'),
         'draft.pattern_relationships',coalesce(r.relationship_claim,r.evidence_note,''),false
  FROM draft.pattern_relationships r
  UNION ALL
  SELECT 'pattern-song:'||l.pattern_song_object_link_id::text,
         'pattern:'||l.pattern_id,'song:'||l.song_object_id::text,
         coalesce(l.link_role,l.object_role,'associated_song_object'),
         coalesce(l.status,'unclassified'),'draft.pattern_song_object_links',
         coalesce(l.evidence_note,l.note,''),false
  FROM draft.pattern_song_object_links l
),
edges AS (
 SELECT e.* FROM edges_all e
 JOIN nodes a ON a.id=e.src JOIN nodes b ON b.id=e.dst
),
an AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'originId',origin_id,'kind',kind,'label',label,'subtitle',subtitle,
  'authority',authority,'detail',detail,'aliases',aliases,'source',source,
  'tokenExamples',token_examples,'laneTags',lane_tags) ORDER BY kind,id),'[]'::jsonb) v
 FROM nodes
),
ae AS (
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'from',src,'to',dst,'relation',relation,'authority',authority,
  'source',source,'note',note,'inheritsRealm',inherits) ORDER BY id),'[]'::jsonb) v
 FROM edges
)
SELECT jsonb_build_object(
 'nodes',an.v,'edges',ae.v,'sourceMode','live',
 'asOf',statement_timestamp()::text,
 'omissions',jsonb_build_array(
  (SELECT format('%s relationship(s) excluded because their endpoints are missing or inactive.',
                 (SELECT count(*) FROM edges_all)-(SELECT count(*) FROM edges))),
  'Scope: live Reality Pools, Song objects, registered patterns and their explicit edges; other canon and research families are not yet in this projection.'
 )
)
FROM an CROSS JOIN ae;
$f$;
REVOKE ALL ON FUNCTION public.titus_constellation_private_snapshot_v1()
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.titus_constellation_private_snapshot_v1()
TO service_role;
COMMIT;
