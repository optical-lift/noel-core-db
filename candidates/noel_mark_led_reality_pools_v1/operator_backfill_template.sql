-- Noel mark-first MT source backfill. NOT a migration. Privileged PRIVATE OPERATOR ONLY.
-- Run AFTER reviewed registry migration; book at a time; psql \set book_code 'Gen'.
-- This transaction does not create Reality Pools, form/pool links, or Strong's routes.
-- Source and founder-definition snapshots must be taken independently first.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL noel.book_code = :'book_code';

-- 1. Immutable exact Unicode source surface (NMF)
INSERT INTO draft.noel_mark_forms
 (script_code, representation_rank, representation_contract_key, exact_surface)
SELECT DISTINCT 'Hebr','R2','mt_noel_current_exact_surface_v1', s.surface_text
FROM intelligence.v_canon_source_text_spine s
WHERE s.witness_key='mt_noel_current' AND s.language_code='hbo'
  AND s.provenance_status='verified'
  AND s.canonical_book_code=current_setting('noel.book_code')
ON CONFLICT (form_id) DO NOTHING;

-- 2. Independently numbered attested source occurrences (not form IDs)
INSERT INTO draft.noel_mark_occurrence_bindings
 (witness_key,source_token_id,representation_rank,representation_contract_key,
  form_id,source_surface,source_provenance_status)
SELECT s.witness_key,s.source_token_id,'R2','mt_noel_current_exact_surface_v1',
 draft.noel_mark_form_id_v1('Hebr','R2','mt_noel_current_exact_surface_v1',s.surface_text),
 s.surface_text,s.provenance_status
FROM intelligence.v_canon_source_text_spine s
WHERE s.witness_key='mt_noel_current' AND s.language_code='hbo'
  AND s.provenance_status='verified'
  AND s.canonical_book_code=current_setting('noel.book_code')
ON CONFLICT (witness_key,source_token_id,representation_rank,representation_contract_key)
DO NOTHING;

-- 3. Versioned R2 comparison identity (NMI): strips ONLY explicitly listed
-- Hebrew combining marks and editorial '/', preserving all exact NMF evidence.
INSERT INTO draft.noel_mark_identities
 (script_code,representation_rank,identity_contract_key,projected_surface)
SELECT DISTINCT 'Hebr','R2','mt_noel_current_consonantal_projection_v1',
 draft.noel_mark_mt_consonantal_projection_v1(s.surface_text)
FROM intelligence.v_canon_source_text_spine s
WHERE s.witness_key='mt_noel_current' AND s.language_code='hbo'
  AND s.provenance_status='verified'
  AND s.canonical_book_code=current_setting('noel.book_code')
ON CONFLICT (identity_id) DO NOTHING;

-- 4. Each source exact form belongs to one projected identity under v1.
INSERT INTO draft.noel_mark_identity_forms
 (identity_id,form_id,exact_surface,projected_surface,identity_contract_key)
SELECT DISTINCT
 draft.noel_mark_identity_id_v1('Hebr','R2',
   'mt_noel_current_consonantal_projection_v1',
   draft.noel_mark_mt_consonantal_projection_v1(s.surface_text)),
 draft.noel_mark_form_id_v1('Hebr','R2','mt_noel_current_exact_surface_v1',s.surface_text),
 s.surface_text, draft.noel_mark_mt_consonantal_projection_v1(s.surface_text),
 'mt_noel_current_consonantal_projection_v1'
FROM intelligence.v_canon_source_text_spine s
WHERE s.witness_key='mt_noel_current' AND s.language_code='hbo'
  AND s.provenance_status='verified'
  AND s.canonical_book_code=current_setting('noel.book_code')
ON CONFLICT (form_id,identity_contract_key) DO NOTHING;

-- 5. Reconcile *every* occurrence against both layers, preventing silent
-- ON CONFLICT skipping of stale or contrary source evidence.
DO $check$
DECLARE v_missing bigint; v_unverified bigint;
BEGIN
 SELECT count(*) INTO v_unverified
 FROM intelligence.v_canon_source_text_spine s
 WHERE s.witness_key='mt_noel_current' AND s.language_code='hbo'
   AND s.canonical_book_code=current_setting('noel.book_code')
   AND (s.provenance_status IS DISTINCT FROM 'verified'
        OR s.source_token_id IS NULL OR s.surface_text IS NULL);
 IF v_unverified > 0 THEN
   RAISE EXCEPTION 'Unverified/missing MT source tokens in batch: %',v_unverified;
 END IF;
 SELECT count(*) INTO v_missing
 FROM intelligence.v_canon_source_text_spine s
 LEFT JOIN draft.noel_mark_occurrence_bindings b
   ON b.witness_key=s.witness_key AND b.source_token_id=s.source_token_id
  AND b.representation_rank='R2' AND b.representation_contract_key='mt_noel_current_exact_surface_v1'
  AND b.source_surface=s.surface_text
 LEFT JOIN draft.noel_mark_identity_forms f
   ON f.form_id=b.form_id AND f.exact_surface=s.surface_text
  AND f.identity_contract_key='mt_noel_current_consonantal_projection_v1'
 LEFT JOIN draft.noel_mark_identities i
   ON i.identity_id=f.identity_id AND i.projected_surface=f.projected_surface
 WHERE s.witness_key='mt_noel_current' AND s.language_code='hbo'
   AND s.canonical_book_code=current_setting('noel.book_code')
   AND (b.form_id IS NULL OR i.identity_id IS NULL);
 IF v_missing > 0 THEN
   RAISE EXCEPTION 'Missing/stale form or identity binding in batch: %',v_missing;
 END IF;
END;
$check$;
COMMIT;
-- Idempotency: repeat a book and assert unchanged counts and keys.
-- No automatic authority promotions, dictionary label routing, or legacy pool merges.
