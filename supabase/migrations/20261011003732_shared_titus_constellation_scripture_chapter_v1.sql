BEGIN;

-- Private source-witness reading surface for Titus. No founder note bodies or new interpretation.
-- Service-role transport is not viewer authorization: the Titus route must remain gated independently.
CREATE OR REPLACE FUNCTION public.titus_constellation_private_chapter_v1(
  p_book text, p_chapter integer
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $f$
WITH
request AS (
  SELECT p_book AS book, p_chapter AS chapter
  WHERE p_book ~ '^[1-3]?[A-Z][a-z]{1,2}$'
    AND p_chapter BETWEEN 1 AND 150
),
kjv_verse_tokens AS (
  SELECT t.verse,
         jsonb_agg(jsonb_build_object(
           'sourceTokenId',t.source_token_id,
           'position',t.position,
           'surface',t.kjv_surface,
           'strongId',t.strong_id,
           'poolIds','[]'::jsonb
         ) ORDER BY t.position,t.id) AS tokens
  FROM draft.token_occurrences t
  JOIN request r ON r.book=t.book AND r.chapter=t.chapter
  WHERE t.kjv_surface IS NOT NULL
  GROUP BY t.verse
),
hebrew_tokens AS (
  SELECT t.id,t.verse,t.position,t.source_token_id,t.strong_id,t.hebrew_surface,
         coalesce((
           SELECT jsonb_agg(DISTINCT 'pool:'||a.node_id)
           FROM draft.noel_reality_token_anchors a
           JOIN draft.noel_reality_nodes n ON n.node_id=a.node_id AND n.is_active
           WHERE a.witness_key='mt_noel_current'
             AND a.source_token_id=t.source_token_id
             AND a.verification_status IN ('source_spine_verified','verified_source_spine')
         ), '[]'::jsonb) AS pool_ids
  FROM draft.ot_canonical_tokens_stage t
  JOIN request r ON r.book=t.book AND r.chapter=t.chapter
  WHERE t.hebrew_surface IS NOT NULL
),
hebrew_verse_tokens AS (
  SELECT verse,
         jsonb_agg(jsonb_build_object(
           'sourceTokenId',source_token_id,
           'position',position,
           'surface',hebrew_surface,
           'strongId',strong_id,
           'poolIds',pool_ids
         ) ORDER BY position,id) AS tokens
  FROM hebrew_tokens
  GROUP BY verse
)
SELECT jsonb_build_object(
 'book',r.book,'chapter',r.chapter,
 'name',CASE r.book
   WHEN 'Psa' THEN 'Psalms' WHEN 'Gen' THEN 'Genesis'
   WHEN 'Exo' THEN 'Exodus' WHEN 'Lev' THEN 'Leviticus'
   WHEN 'Num' THEN 'Numbers' WHEN 'Deu' THEN 'Deuteronomy'
   WHEN 'Pro' THEN 'Proverbs' WHEN 'Isa' THEN 'Isaiah'
   WHEN 'Jer' THEN 'Jeremiah' WHEN 'Eze' THEN 'Ezekiel'
   WHEN 'Mat' THEN 'Matthew' WHEN '1Co' THEN '1 Corinthians'
   ELSE r.book END,
 'englishWitness','CrossWire KJV OSIS tagged occurrences',
 'originalWitness','Noel WLC / OSHB-derived Hebrew tokens',
 'english',coalesce((
   SELECT jsonb_agg(jsonb_build_object('verse',v.verse,'tokens',v.tokens) ORDER BY v.verse)
   FROM kjv_verse_tokens v
 ), '[]'::jsonb),
 'original',coalesce((
   SELECT jsonb_agg(jsonb_build_object('verse',v.verse,'tokens',v.tokens) ORDER BY v.verse)
   FROM hebrew_verse_tokens v
 ), '[]'::jsonb),
 'note','English witness is the source-tagged KJV token sequence, not a reconstructed punctuated edition. Hebrew words are separately ordered by their own canonical source. Only exact verified MT token IDs create research-pool highlights. KJV Strong numbers do not establish one-to-one translation alignment.'
)
FROM request r;
$f$;

REVOKE ALL ON FUNCTION public.titus_constellation_private_chapter_v1(text,integer)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.titus_constellation_private_chapter_v1(text,integer)
TO service_role;

COMMIT;
