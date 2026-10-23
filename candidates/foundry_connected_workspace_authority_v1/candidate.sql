-- SOURCE CANDIDATE ONLY: no production release, migration history or data writes.
-- Foundry Connected Workspace Gate 1, reviewed against Noel main
-- 6ebde9a810152be9c5e51c674229df9f1483b004.
-- Keep existing foundry.events and foundry.snapshots, including all five
-- historical workspace streams, untouched. Legacy workspaces are not backfilled.
--
-- This is a private authority registry, NOT a second Person/Principal or
-- agent/delegation system. Delegated agent credentials and command authority
-- remain in atlas.delegated_agent_*.
BEGIN;

CREATE TABLE foundry.workspace_authority_registry_v1 (
  workspace_id text PRIMARY KEY
    CHECK (length(btrim(workspace_id)) BETWEEN 1 AND 180),
  creation_request_id uuid NOT NULL,
  owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  protocol_version text NOT NULL DEFAULT '0.1'
    CHECK (protocol_version='0.1'),
  provisional_subject_label text NOT NULL
    CHECK (length(btrim(provisional_subject_label)) BETWEEN 1 AND 500),
  provisional_field text NOT NULL
    CHECK (length(btrim(provisional_field)) BETWEEN 1 AND 2000),
  -- A subject label never establishes or merges a canonical Person.
  -- A verified Person link needs a separate owning-domain identity command.
  subject_identity_state text NOT NULL DEFAULT 'unresolved'
    CHECK (subject_identity_state IN ('unresolved','provisional')),
  custody_scope_kind text NOT NULL
    CHECK (custody_scope_kind IN ('verified_self','documented_external')),
  -- The initial source-custody decision is explicitly pending. It is NOT
  -- authorized merely because the operator knows a name or has an AI transcript.
  custody_review_state text NOT NULL DEFAULT 'pending'
    CHECK (custody_review_state IN ('pending','reviewed','suspended','revoked')),
  custody_basis_refs text[] NOT NULL DEFAULT '{}'::text[],
  custody_reviewed_by_principal_id uuid REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  custody_reviewed_at timestamptz,
  custody_review_method text
    CHECK (custody_review_method IS NULL
      OR custody_review_method IN ('canonical_self','reviewed_source_authorization')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  suspended_at timestamptz,
  revoked_at timestamptz,
  CHECK (
    (custody_review_state='reviewed'
     AND cardinality(custody_basis_refs)>0
     AND custody_reviewed_by_principal_id IS NOT NULL
     AND custody_reviewed_at IS NOT NULL
     AND custody_review_method IS NOT NULL)
    OR
    (custody_review_state<>'reviewed')
  ),
  CHECK (
    (custody_scope_kind='verified_self'
      AND (custody_review_method IS NULL OR custody_review_method='canonical_self'))
    OR
    (custody_scope_kind='documented_external'
      AND (custody_review_method IS NULL OR custody_review_method='reviewed_source_authorization'))
  ),
  UNIQUE (owner_principal_id, creation_request_id),
  CHECK (custody_review_state<>'revoked' OR revoked_at IS NOT NULL),
  CHECK (custody_review_state<>'suspended' OR suspended_at IS NOT NULL)
);

-- Guarding private data at the table boundary is defense in depth.
-- NO direct client grants, public views, AI-written ownership or subject claims.
ALTER TABLE foundry.workspace_authority_registry_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON foundry.workspace_authority_registry_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- Deliberately no INSERT/UPDATE/DELETE public or service RPC, no policies,
-- no command catalog entries, no snapshot rewrites, no workspace backfill,
-- no delegated-agent scope expansion and no Atlas canonical Reality changes.
--
-- Before a guarded registrar/review command may be introduced, source must
-- prove canonical authenticated Principal derivation, subject custody proof,
-- exact workspace target authorization, revocation and safe event append.
COMMIT;
