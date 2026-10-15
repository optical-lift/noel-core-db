-- PRIVATE Noel Song mark/LXX evidence population template, not schema migration.
-- Requires released structure and authorized production data-population pass.
-- Replace __BUCKET_0_TO_31__ with one integer 0..31, execute one transaction
-- at a time and verify after each. Re-running any bucket is idempotent.
-- No interpretation/rule/decision is populated here; observed edges only.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='180s';

INSERT INTO draft.noel_mark_lxx_choice_occurrences_v1 (
  identity_id,witness_key,source_token_id,form_id,alignment_segment_id,
  greek_token_id,greek_lexeme_key,greek_surface,
  source_member_order,target_member_order,source_member_role,target_member_role,
  source_segment_count,target_segment_count,mapping_scope,greek_member_function,
  evidence_quality,provenance_note
)
SELECT DISTINCT f.identity_id,o.witness_key,o.source_token_id,o.form_id,
 a.alignment_segment_id,t.source_token_id,g.greek_lex,g.greek_utf8,
 m.member_order,t.member_order,m.member_role,t.member_role,
 a.source_token_count,a.target_token_count,
 CASE WHEN a.source_token_count=1 AND a.target_token_count=1 THEN 'direct_token'
 WHEN a.source_token_count=1 THEN 'one_to_many'
 WHEN a.target_token_count=1 THEN 'many_to_one'
 ELSE 'many_to_many' END,
 'unassessed',
 CASE WHEN coalesce(a.requires_review,true) THEN 'variant_review'
 WHEN a.source_token_count=1 AND a.target_token_count=1 THEN 'direct_unflagged'
 ELSE 'phrase_candidate' END,
 'CATSS Hebrew↔Greek alignment membership. Non-1:1 segments are co-membership evidence, NOT proof that each Greek lexeme independently translates the Hebrew word; connectors/heads require review.'
FROM draft.noel_mark_occurrence_bindings o
JOIN draft.noel_mark_identity_forms f ON f.form_id=o.form_id
 AND f.identity_contract_key='mt_noel_current_consonantal_projection_v1'
JOIN core.alignment_segment_members m ON m.source_token_id=o.source_token_id AND m.side='source'
JOIN core.alignment_segments a ON a.alignment_segment_id=m.alignment_segment_id
JOIN core.alignment_segment_members t ON t.alignment_segment_id=a.alignment_segment_id AND t.side='target'
JOIN draft.lxx_tf_words_resolved_stage g ON g.tf_word_node=substring(t.source_token_id FROM '[0-9]+$')::bigint
WHERE o.witness_key='mt_noel_current'
 AND o.representation_rank='R2'
 AND o.representation_contract_key='mt_noel_current_exact_surface_v1'
 AND mod(abs(hashtext(f.identity_id)::bigint),32)=__BUCKET_0_TO_31__
 AND a.source_token_count>0 AND a.target_token_count>0
 AND t.source_token_id ~ '^catss_lxx_tf:[0-9]+$'
 AND g.greek_lex IS NOT NULL
ON CONFLICT (witness_key,source_token_id,alignment_segment_id,greek_token_id) DO NOTHING;

-- Only original Song source occurrences can establish Song priority.
-- A different Greek lexeme appearing elsewhere is NOT a competing Song anchor.
WITH song AS MATERIALIZED (
 SELECT c.choice_id,c.identity_id,c.source_token_id,
  s.canonical_book_code||' '||s.chapter||':'||s.verse song_ref,
  c.greek_lexeme_key,c.mapping_scope,c.evidence_quality
 FROM draft.noel_mark_lxx_choice_occurrences_v1 c
 JOIN intelligence.v_canon_source_text_spine s
 ON s.witness_key=c.witness_key AND s.source_token_id=c.source_token_id
 WHERE s.canonical_book_code='Sng' AND s.provenance_status='verified'
 AND mod(abs(hashtext(c.identity_id)::bigint),32)=__BUCKET_0_TO_31__
),profile AS (
 SELECT identity_id,
 count(DISTINCT greek_lexeme_key) song_lexeme_count,
 bool_and(mapping_scope='direct_token' AND evidence_quality='direct_unflagged') all_direct
 FROM song GROUP BY identity_id
)
INSERT INTO draft.noel_mark_song_anchor_choices_v1 (
 identity_id,choice_id,song_canonical_ref,song_anchor_state,authority_note
)
SELECT s.identity_id,s.choice_id,s.song_ref,
 CASE WHEN p.song_lexeme_count=1 AND p.all_direct THEN 'sole_direct_song_choice'
 WHEN p.song_lexeme_count>1 THEN 'song_multiple_open'
 ELSE 'attested_song_choice' END,
 'Song Greek translation is attested and traceable. Single direct Song lexeme has interpretive priority under the Song method but does not prove an identical underlying function without canonical testing.'
FROM song s JOIN profile p ON p.identity_id=s.identity_id
ON CONFLICT(choice_id) DO NOTHING;
COMMIT;

-- Post-batch private read-only checks should compare:
--  1. each saved choice against its existing CATSS segment, member orders, witness, Hebrew NMI and Greek lexeme
--  2. each Song anchor against actual Sng token location and Greek word
--  3. Reconcile separately: original 287 strict Song single-choice anchors and 10 strict multi-choice NMIs; adding phrase members necessarily changes *full* Song choice counts, so do not apply the old 287/10 numbers as all-evidence totals
--  4. original 287 founder lexical pools and existing decisions are unchanged
--  5. no 'canon_excluded' constraints without a reviewed decision and proof