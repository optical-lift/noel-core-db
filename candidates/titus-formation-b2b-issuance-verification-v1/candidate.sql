-- Titus B2B next bounded increment: a private, source-issued authority
-- verification seam. SOURCE ONLY; do not deploy/merge as an access grant.
--
-- Live source audit (2026-11-03): Titus' historical teacher/profile and
-- curriculum records, draft.reality_source_rights and Atlas Course/Enrollment
-- do not provide a verified, edition/learner/response/reviewer-specific
-- issuer decision. The B2B evidence tables contain ASSERTED source_ref UUIDs.
-- There is no legitimate issuer/receipt verifier to call yet.
--
-- This function is intentionally permanently FALSE in this candidate.
-- It cannot be made true by inserted B2B fixture rows, a client-supplied
-- Person, a role, a source_ref, a frozen version, or service_role transport.
-- A future change requires its own source-owned issuer proof and review.
BEGIN;

CREATE OR REPLACE FUNCTION titus.formation_review_source_issuance_verified_v1(
  p_formation_response_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO pg_catalog
AS $closed$
  SELECT false;
$closed$;

COMMENT ON FUNCTION titus.formation_review_source_issuance_verified_v1(uuid) IS
 'B2B private issuance boundary: always false until separately governed '
 'author/rightsholder/review/release, learner consent and reviewer mandate '
 'issuers and their current revocation checks are actually proven. '
 'B2B evidence_match is structural ONLY; never use it as authorization.';

REVOKE ALL ON FUNCTION
  titus.formation_review_source_issuance_verified_v1(uuid) FROM PUBLIC;

DO $roles$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION titus.formation_review_source_issuance_verified_v1(uuid) FROM anon';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION titus.formation_review_source_issuance_verified_v1(uuid) FROM authenticated';
  END IF;
END;
$roles$;

-- Leave B2A's hard-false feedback writer unchanged; no public RPC, data
-- migration, person binding, issuance carrier, grants or other schema change.
COMMIT;
