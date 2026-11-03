-- B2B: structural consistency of THREE independent source evidence receipts.
-- NOT a released reviewer mandate, issuance operation, or access-control grant.
-- This source does NOT touch B2A's permanently closed writer gate.
BEGIN;

CREATE TABLE titus.formation_review_edition_evidence_v1 (
  teaching_release_ref uuid PRIMARY KEY,
  program_id uuid NOT NULL REFERENCES titus.programs(program_id) ON DELETE RESTRICT,
  curriculum_version_id uuid NOT NULL REFERENCES titus.curriculum_versions(curriculum_version_id) ON DELETE RESTRICT,
  formation_unit_id uuid NOT NULL REFERENCES titus.formation_units(formation_unit_id) ON DELETE RESTRICT,
  learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  edition_fingerprint text NOT NULL CHECK (edition_fingerprint ~ '^[0-9a-f]{64}$'),
  educational_review_source_ref uuid NOT NULL,
  source_rights_source_ref uuid NOT NULL,
  release_decision_source_ref uuid NOT NULL,
  issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  effective_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  withdrawn_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > effective_at),
  CHECK (withdrawn_at IS NULL OR withdrawn_at >= effective_at),
  UNIQUE(teaching_release_ref,formation_unit_id,learner_person_entity_id)
);
COMMENT ON TABLE titus.formation_review_edition_evidence_v1 IS
 'B2B SOURCE CANDIDATE: asserted external educational, source-rights, release references; cannot certify issuer/source rights or create access by insertion. No issuance API.';
 
CREATE TABLE titus.formation_review_disclosure_evidence_v1 (
  disclosure_evidence_id uuid PRIMARY KEY,
  teaching_release_ref uuid NOT NULL
    REFERENCES titus.formation_review_edition_evidence_v1(teaching_release_ref) ON DELETE RESTRICT,
  formation_response_id uuid NOT NULL
    REFERENCES titus.formation_responses(formation_response_id) ON DELETE RESTRICT,
  learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  reviewer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  consent_source_ref uuid NOT NULL,
  consent_issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  effective_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  withdrawn_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (learner_person_entity_id <> reviewer_person_entity_id),
  CHECK (consent_issuer_person_entity_id = learner_person_entity_id),
  CHECK (expires_at > effective_at),
  CHECK (withdrawn_at IS NULL OR withdrawn_at >= effective_at),
  UNIQUE(teaching_release_ref,formation_response_id,reviewer_person_entity_id,consent_source_ref)
);
COMMENT ON TABLE titus.formation_review_disclosure_evidence_v1 IS
 'B2B SOURCE CANDIDATE: exact-response learner consent evidence reference, not self-declared consent and not issuer-certified without future governed source operation.';

CREATE TABLE titus.formation_review_mandate_evidence_v1 (
  mandate_evidence_id uuid PRIMARY KEY,
  teaching_release_ref uuid NOT NULL
    REFERENCES titus.formation_review_edition_evidence_v1(teaching_release_ref) ON DELETE RESTRICT,
  formation_unit_id uuid NOT NULL REFERENCES titus.formation_units(formation_unit_id) ON DELETE RESTRICT,
  learner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  reviewer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  mandate_source_ref uuid NOT NULL,
  issuer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  mandate_operation text NOT NULL CHECK (mandate_operation = 'review_learner_response'),
  effective_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (learner_person_entity_id <> reviewer_person_entity_id),
  CHECK (expires_at > effective_at),
  CHECK (revoked_at IS NULL OR revoked_at >= effective_at),
  UNIQUE(teaching_release_ref,formation_unit_id,learner_person_entity_id,
    reviewer_person_entity_id,mandate_source_ref)
);
COMMENT ON TABLE titus.formation_review_mandate_evidence_v1 IS
 'B2B SOURCE CANDIDATE: reviewer-specific mandate citation, distinct from learner consent or educational/source-rights release. Not a generic teacher grant.';

-- Private source-only candidate: no browser reads, no browser writes, no
-- public API, and no direct role grants even if these were mistakenly deployed.
ALTER TABLE titus.formation_review_edition_evidence_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.formation_review_disclosure_evidence_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE titus.formation_review_mandate_evidence_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON titus.formation_review_edition_evidence_v1,
  titus.formation_review_disclosure_evidence_v1,
  titus.formation_review_mandate_evidence_v1 FROM PUBLIC;
DO $block$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON titus.formation_review_edition_evidence_v1,titus.formation_review_disclosure_evidence_v1,titus.formation_review_mandate_evidence_v1 FROM anon';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON titus.formation_review_edition_evidence_v1,titus.formation_review_disclosure_evidence_v1,titus.formation_review_mandate_evidence_v1 FROM authenticated';
  END IF;
END;
$block$;

-- This is an INTERNAL consistency probe for proposed records. It is NOT
-- reviewer authorization: receipt REFERENCES are NOT verified against a
-- source-owned issuer; no real issuer/consent/release writer exists.
-- A future canonical writer must verify these sources, lock revocation and
-- recheck at the actual write boundary, not trust this probe as a permit.
-- The exact Person comes from the existing live-session resolver, NEVER
-- from a p_reviewer_person_id client argument.
CREATE OR REPLACE FUNCTION titus.formation_review_evidence_match_v1(
  p_formation_response_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM titus.formation_responses r
    JOIN titus.formation_units u ON u.formation_unit_id=r.formation_unit_id
      AND u.teacher_id=r.teacher_id
      AND u.review_state='current'
      AND u.formation_state IN (
        'learner_ready','encountered','teachback_pending',
        'teachback_received','teachback_reviewed',
        'transfer_pending','transfer_reviewed','integrated'
      )
    JOIN titus.teacher_person_bindings learner
      ON learner.teacher_id=u.teacher_id
      AND learner.binding_state='active'
      AND learner.retired_at IS NULL
    JOIN titus.formation_review_edition_evidence_v1 e
      ON e.formation_unit_id=u.formation_unit_id
      AND e.program_id=u.program_id
      AND e.learner_person_entity_id=learner.person_entity_id
      AND e.effective_at<=now() AND now()<e.expires_at
      AND e.withdrawn_at IS NULL
    JOIN titus.curriculum_versions cv ON cv.curriculum_version_id=e.curriculum_version_id
      AND cv.program_id=e.program_id
      AND cv.version_status IN ('frozen','published')
    JOIN titus.formation_review_disclosure_evidence_v1 d
      ON d.teaching_release_ref=e.teaching_release_ref
      AND d.formation_response_id=r.formation_response_id
      AND d.learner_person_entity_id=learner.person_entity_id
      AND d.effective_at<=now() AND now()<d.expires_at
      AND d.withdrawn_at IS NULL
    JOIN titus.formation_review_mandate_evidence_v1 m
      ON m.teaching_release_ref=e.teaching_release_ref
      AND m.formation_unit_id=u.formation_unit_id
      AND m.learner_person_entity_id=learner.person_entity_id
      AND m.reviewer_person_entity_id=d.reviewer_person_entity_id
      AND m.mandate_operation='review_learner_response'
      AND m.effective_at<=now() AND now()<m.expires_at
      AND m.revoked_at IS NULL
    WHERE r.formation_response_id=p_formation_response_id
      -- Never retrofit a later release to a response created earlier.
      AND r.created_at>=e.effective_at
      AND r.response_status='submitted'
      AND d.reviewer_person_entity_id <> learner.person_entity_id
      AND d.reviewer_person_entity_id =
        titus.current_authenticated_person_entity_id_v1()
  );
$$;
REVOKE ALL ON FUNCTION titus.formation_review_evidence_match_v1(uuid) FROM PUBLIC;
DO $block$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION titus.formation_review_evidence_match_v1(uuid) FROM anon';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION titus.formation_review_evidence_match_v1(uuid) FROM authenticated';
  END IF;
END;
$block$;

-- The separate B2A writer gate stays FALSE. Never overwrite it here.
COMMIT;
