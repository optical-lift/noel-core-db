#!/usr/bin/env python3
"""Static Option C P0B review. NOT a signed session, SQL compile, or release."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "candidates/atlas/governor_effective_subject_disclosure_review_v1"
source = (BASE / "candidate.sql").read_text(encoding="utf-8")
postconditions = (BASE / "postconditions.sql").read_text(encoding="utf-8")

def require(condition: bool, reason: str) -> None:
    if not condition:
        raise AssertionError(reason)

# Must continue the CURRENT source-reviewed governor endpoint, not invent a
# competing Person/Work/permission engine or grant to an ordinary worker.
require(source.count("CREATE OR REPLACE FUNCTION") == 2,
        "unexpected extra RPC or replacement")
require(source.count("GRANT EXECUTE ON FUNCTION") == 1,
        "unexpected executable privilege expansion")
for old in (
    "atlas.owner_effective_subject_disclosure_review_self_api_v1(",
    "public.owner_effective_subject_disclosure_review_self_api_v1(",
    "atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id)",
    "ledger.seats s",
    "s.seat_state='active'",
    "linkedSubjectDisclosure",
    "has_current_subject_disclosure_v1",
    "subject_disclosure_decision_events_v1",
    "'governorOnly',true,'isSignedTargetAccessProof',false",
    "signedAlternativeReaderCoverageComplete',false",
    "directSignedOwnerWorkerOutsiderAndAnonymousTestsRequired',true",
):
    require(old in source, f"original boundary lost: {old}")

# Independent exact selected Ledger and governing primary claims must be
# evaluated only when the same current Principal and source scope are unique.
for check in (
    "contextualAuthorityReview",
    "v_target_principal_count=1",
    "v_exact_participation_count=1",
    "v_primary_candidate_count=1",
    "p.person_id=p_target_person_id",
    "p.user_id IS NOT NULL",
    "lop.ledger_id=p_ledger_id AND lop.organization_id=p_organization_id",
    "lop.participation_kind IN ('governing','operating')",
    "lop.participation_kind='governing'",
    "lop.is_compatibility_primary IS TRUE",
    "a.principal_id=v_target_principal AND a.ledger_id=p_ledger_id",
    "a.principal_id=v_target_principal AND a.ledger_id=v_primary_candidate",
    "a.authority_kind='root_governing' AND a.status='active'",
    "a.ended_at IS NULL",
    "source_root_flags_only",
    "legacyCompanyWorkDualRootCandidate",
    "legacyDualRootIsNotUniversalAuthorityLaw',true",
    "doesNotAuthorizeAnyOperation',true",
    "notAFieldDisclosure',true",
    "notASignedTargetSessionProof',true",
    "notAnEffectivePermissionCertificate',true",
):
    require(check in source, f"bounded contextual fact missing: {check}")

require(source.count("v_context_status:='source_root_flags_only'") == 1,
        "only resolved source facts may be reported")
require(source.count("v_context_status text:='unresolved'") == 1,
        "ambiguous inputs must be unknown, not granted or denied")
require("THEN v_exact_root AND v_primary_root ELSE NULL END" in source,
        "dual-root explanation must use the same Principal and never imply a grant")
require("CASE WHEN v_context_status='source_root_flags_only'" in source,
        "ambiguous response may not present fabricated root authority")
require("'notAnEffectivePermissionCertificate'" in postconditions and
        "'authenticated'" in postconditions and "'anon'" in postconditions,
        "protected-clone invariants or ACL negative control missing")
print("PASS P0B current-main contextual governor source guards (STATIC ONLY)")
