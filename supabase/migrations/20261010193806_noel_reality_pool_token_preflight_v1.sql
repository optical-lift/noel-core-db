
CREATE OR REPLACE FUNCTION draft.get_noel_reality_tokens_v1(
 p_lookup text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_witness_key text DEFAULT NULL
)
RETURNS TABLE (
 witness_key text, canonical_book_code text, chapter integer, verse integer,
 token_position integer, source_token_id text, surface_text text,
 lemma_raw text, morph_raw text, strong_id text, mapping_role text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $f$
WITH lookup AS (
 SELECT CASE WHEN upper(btrim(p_lookup)) ~ '^[HG]0*[0-9]+$'
 THEN substring(upper(btrim(p_lookup)) FROM 1 FOR 1)
      || lpad((substring(upper(btrim(p_lookup)) FROM 2)::integer)::text,4,'0')
 ELSE (SELECT alias_value FROM draft.noel_reality_aliases
       WHERE node_id=btrim(p_lookup) AND alias_kind='strongs' LIMIT 1)
 END AS strong_key
),
ids AS (
 SELECT strong_key, substring(strong_key FROM 1 FOR 1)||
  coalesce(nullif(ltrim(substring(strong_key FROM 2),'0'),''),'0') AS short_key
 FROM lookup WHERE strong_key IS NOT NULL
)
SELECT v.witness_key,v.canonical_book_code,v.chapter,v.verse,v.token_position,
 v.source_token_id,v.surface_text,v.lemma_raw,v.morph_raw,v.strong_id,v.mapping_role
FROM intelligence.v_canon_text_token_spine v CROSS JOIN ids
WHERE v.strong_id IN (ids.strong_key,ids.short_key)
 AND (p_witness_key IS NULL OR v.witness_key=p_witness_key)
 AND ((ids.strong_key LIKE 'H%' AND v.witness_key='mt_noel_current')
      OR (ids.strong_key LIKE 'G%' AND v.witness_key IN ('lxx_catss_tf_v1','nt_n1904_centerblc_planned')))
ORDER BY v.canonical_order,v.chapter,v.verse,v.token_position,v.witness_key
LIMIT least(greatest(coalesce(p_limit,50),1),200)
OFFSET greatest(coalesce(p_offset,0),0);
$f$;
REVOKE ALL ON FUNCTION draft.get_noel_reality_tokens_v1(text,integer,integer,text)
 FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION draft.get_noel_reality_preflight_v1(
 p_lookup text,p_max_depth integer DEFAULT 4,p_token_limit integer DEFAULT 25
)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $f$
SELECT coalesce(draft.get_noel_reality_context_v1(p_lookup,p_max_depth),'{}'::jsonb)
 || jsonb_build_object('live_source_tokens',
   coalesce((SELECT jsonb_agg(to_jsonb(tok) ORDER BY tok.canonical_book_code,tok.chapter,tok.verse,tok.token_position)
      FROM draft.get_noel_reality_tokens_v1(p_lookup,p_token_limit,0,NULL) tok),'[]'::jsonb),
   'token_scope','Page of source-corpus occurrences; not a replacement for the full occurrence field. Use get_noel_reality_tokens_v1 with offset to continue.');
$f$;
REVOKE ALL ON FUNCTION draft.get_noel_reality_preflight_v1(text,integer,integer)
 FROM PUBLIC, anon, authenticated;
