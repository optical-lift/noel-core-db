-- UNIVERSAL NO-PRIVATE-ROWS aggregate source inventory. Read-only SELECT.
-- Execute only through an authorized owner-controlled read-only connection.
-- Never treat counts, claims, aliases, same-ID proximity or metadata as
-- canonical identity or domain-adapter authorization.
WITH
  requirement_families AS (
    SELECT w.source_object_type AS family,
           count(*)::integer AS active_count,
           count(*) FILTER (
             WHERE w.source_object_type='reality_entity'
               AND e.id IS NOT NULL
               AND e.identity_state='canonical'
               AND nullif(btrim(w.metadata->>'needKey'),'') IS NOT NULL
           )::integer AS common_candidates
    FROM atlas.work_requirements w
    LEFT JOIN reality.entities e
      ON w.source_object_type='reality_entity'
     AND e.id=w.source_object_id
    WHERE w.state='active'
    GROUP BY w.source_object_type
  ),
  independent_sources AS (
    SELECT
      (SELECT count(*) FROM atlas.identity_subjects)::integer AS subject_claims,
      (SELECT count(*) FROM atlas.identity_source_subject_assertions)::integer AS assertions,
      (SELECT count(*) FROM atlas.identity_reconciliation_reviews)::integer AS reviews,
      (SELECT count(*) FROM atlas.identity_reconciliation_adjudications)::integer AS adjudications,
      (SELECT count(*) FROM foundry.events
        WHERE event_type='foundry_reality_input_v1')::integer AS original_foundry_inputs,
      (SELECT count(*) FROM foundry.source_custody_review_cases_v1
        WHERE review_state='approved' AND revoked_at IS NULL
          AND (expires_at IS NULL OR expires_at>now()))::integer AS current_approved_reviews
  )
SELECT jsonb_build_object(
 'contract','universal_rulebook_common_source_coverage_v1',
 'sourceFamilies',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'family',family,
      'activeRequirements',active_count,
      'commonCanonicalCandidates',common_candidates
    ) ORDER BY family)
    FROM requirement_families
  ),'[]'::jsonb),
 'identityEvidenceSurfaces',jsonb_build_object(
    'identitySubjects',src.subject_claims,
    'sourceSubjectAssertions',src.assertions,
    'reconciliationReviews',src.reviews,
    'reconciliationAdjudications',src.adjudications
  ),
 'foundryOriginEvidence',jsonb_build_object(
    'originalOperatingInputEvents',src.original_foundry_inputs,
    'currentlyApprovedReviewCases',src.current_approved_reviews
  ),
 'notGranted',jsonb_build_object(
    'domainAdapterAuthority',true,
    'policyAdoptionAuthority',true,
    'workIssuanceAuthority',true
  )
) AS aggregate_only
FROM independent_sources src;
