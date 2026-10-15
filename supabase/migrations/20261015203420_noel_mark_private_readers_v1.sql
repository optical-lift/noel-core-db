-- Noel mark-first PRIVATE reader candidate v1. Structural source only; no founder data.
-- Governed noel_ migration generation and schema-clone validation required.
-- Does not replace or modify the existing begin_noel_research_v1 reader.
BEGIN;

CREATE FUNCTION draft.get_noel_mark_occurrence_context_v1(
  p_source_token_id text,
  p_form_limit integer DEFAULT 12
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
WITH seed AS MATERIALIZED (
 SELECT o.witness_key,o.source_token_id,o.source_surface,o.form_id,
        f.identity_id,i.projected_surface
 FROM draft.noel_mark_occurrence_bindings o
 JOIN draft.noel_mark_identity_forms f
   ON f.form_id=o.form_id
  AND f.identity_contract_key='mt_noel_current_consonantal_projection_v1'
 JOIN draft.noel_mark_identities i ON i.identity_id=f.identity_id
 WHERE o.witness_key='mt_noel_current'
   AND o.representation_rank='R2'
   AND o.representation_contract_key='mt_noel_current_exact_surface_v1'
   AND o.source_token_id=btrim(p_source_token_id)
)
SELECT coalesce((
 SELECT jsonb_build_object(
  'contract_version','noel_mt_r2_mark_occurrence_context_v1',
  'found',true,
  'witness_key',s.witness_key,
  'representation_rank','R2',
  'source_token_id',s.source_token_id,
  'exact_surface',s.source_surface,
  'form_id',s.form_id,
  'identity_id',s.identity_id,
  'projected_surface',s.projected_surface,
  'source',(
    SELECT jsonb_build_object(
      'book',src.canonical_book_code,
      'chapter',src.chapter,'verse',src.verse,
      'position',src.token_position,
      'provenance_status',src.provenance_status,
      'historical_strongs',src.strong_id,
      'legacy_lemma_annotation',src.lemma_raw,
      'legacy_morph_annotation',src.morph_raw
    ) FROM intelligence.v_canon_source_text_spine src
    WHERE src.witness_key=s.witness_key
      AND src.source_token_id=s.source_token_id
      AND src.surface_text=s.source_surface
    LIMIT 1
  ),
  'exact_form_variants',(
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'form_id',x.form_id,'exact_surface',x.exact_surface
    ) ORDER BY x.form_id),'[]'::jsonb)
    FROM (SELECT f.form_id,f.exact_surface
          FROM draft.noel_mark_identity_forms f
          WHERE f.identity_id=s.identity_id
          ORDER BY f.form_id
          LIMIT least(greatest(coalesce(p_form_limit,12),1),50)) x
  ),
  'recorded_pool_links',(
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'node_id',l.node_id,'display_name',n.display_name,
      'legacy_authority_state',n.authority_state,
      'link_role',l.link_role,'review_state',l.review_state,
      'decision_id',l.decision_id,'evidence_locator',l.evidence_locator
    ) ORDER BY l.link_role,l.node_id),'[]'::jsonb)
    FROM draft.noel_mark_pool_identity_links l
    JOIN draft.noel_reality_nodes n ON n.node_id=l.node_id
    WHERE l.identity_id=s.identity_id
  ),
  'identity_limit',
    'NMI is a versioned R2 consonantal comparison address, not a semantic equivalence or a physical R0/R1 claim. Historic labels and proposed pool links have no ratification authority.',
  'legacy_strongs_required',false
 ) FROM seed s LIMIT 1
),jsonb_build_object(
 'contract_version','noel_mt_r2_mark_occurrence_context_v1',
 'found',false,
 'source_token_id',p_source_token_id,
 'admission_limit','Only an attested source-token ID from mt_noel_current Hebrew R2 is supported. Do not infer absent tokens or remap other witnesses.'
));
$function$;

CREATE FUNCTION draft.get_noel_mark_collision_review_queue_v1(
 p_limit integer DEFAULT 25,
 p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
WITH conflicts AS MATERIALIZED (
 SELECT identity_id,count(DISTINCT node_id)::integer AS pool_count
 FROM draft.noel_mark_pool_identity_links
 WHERE link_role='candidate_legacy_pool' AND review_state='proposed'
 GROUP BY identity_id
 HAVING count(DISTINCT node_id)>1
), slice AS (
 SELECT c.identity_id,c.pool_count,i.projected_surface
 FROM conflicts c JOIN draft.noel_mark_identities i ON i.identity_id=c.identity_id
 ORDER BY c.identity_id
 LIMIT least(greatest(coalesce(p_limit,25),1),100)
 OFFSET greatest(coalesce(p_offset,0),0)
)
SELECT jsonb_build_object(
 'contract_version','noel_mark_legacy_pool_review_v1',
 'total_collision_nmis',(SELECT count(*) FROM conflicts),
 'offset',greatest(coalesce(p_offset,0),0),
 'results',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
      'identity_id',s.identity_id,
      'projected_surface',s.projected_surface,
      'candidate_pool_count',s.pool_count,
      'historical_pool_candidates',(
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'node_id',l.node_id,'display_name',n.display_name,
          'legacy_authority_state',n.authority_state,
          'review_state',l.review_state,
          'evidence_locator',l.evidence_locator
        ) ORDER BY l.node_id),'[]'::jsonb)
        FROM draft.noel_mark_pool_identity_links l
        JOIN draft.noel_reality_nodes n ON n.node_id=l.node_id
        WHERE l.identity_id=s.identity_id
          AND l.link_role='candidate_legacy_pool'
          AND l.review_state='proposed'
      )
   ) ORDER BY s.identity_id) FROM slice s
 ),'[]'::jsonb),
 'interpretation','These are unratified historical alias intersections, not proven semantic conflicts. The queue creates no decisions, primary pools, or mergers.'
);
$function$;

REVOKE ALL ON FUNCTION draft.get_noel_mark_occurrence_context_v1(text,integer),
  draft.get_noel_mark_collision_review_queue_v1(integer,integer)
  FROM PUBLIC,anon,authenticated;
COMMIT;
