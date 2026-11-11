#!/usr/bin/env python3
"""Static Option C P0B review. NOT a signed session, SQL compile, or release."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "candidates/atlas/governor_effective_subject_disclosure_review_v1"
baseline = (BASE / "candidate.sql").read_text(encoding="utf-8")
source = (BASE / "contextual_authority_review_override_HELD.sql").read_text(encoding="utf-8")
postconditions = (BASE / "contextual_authority_review_postconditions_HELD.sql").read_text(encoding="utf-8")

def require(condition: bool, reason: str) -> None:
    if not condition:
        raise AssertionError(reason)

# Exact byte identity: the canonical bundled reviewer must remain unchanged.
# Overlay may add the three P0B blocks and two bounded P1A review packets,
# never change the canonical Work bundle or create permission writers.
restored = source
for start, end in (
    ("\n -- Review-only Option C jurisdiction facts;", " v_context_status text:='unresolved';"),
    (" -- A current root on a selected operating Ledger", "   v_context_status:='source_root_flags_only';\n END IF;\n"),
    ("   'contextualAuthorityReview',jsonb_build_object(", "     'notAnEffectivePermissionCertificate',true),\n"),
):
    require(restored.count(start)==1 and restored.count(end)==1,
            f"held additive source block ambiguous: {start}")
    before, after = restored.split(start, 1)
    block_end, suffix = after.split(end, 1)
    restored = before + suffix
# P1A field annotations must be the only change to original subject facts.
field_source = ("'conditionDecisionCurrentlyGrants',"
    "atlas.has_current_subject_disclosure_v1(p_ledger_id,p_target_person_id,"
    "'spatial','growing_object',s.subject_id,'condition')")
field_start = field_source + ",\n     -- P1A governor-only field observations."
field_end = "'doesNotDiscloseFieldToTarget',true)\n     )"
require(restored.count(field_start)==1 and restored.count(field_end)==1,
        "P1A field packet is missing/ambiguous")
before, after = restored.split(field_start,1)
_, suffix = after.split(field_end,1)
restored = before + field_source + suffix

operation_start = "   -- P1A typed operation observation."
operation_end = ("   'targetActiveNativeLedgerConnectionConfirmed',true,")
require(restored.count(operation_start)==1 and restored.count(operation_end)==1,
        "P1A operation packet is missing/ambiguous")
before, after = restored.split(operation_start,1)
_, suffix = after.split(operation_end,1)
restored = before + operation_end + suffix

require(restored == baseline,
        "held override changed existing source rather than adding bounded review facts")

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
# Typed packets are bounded to existing governor review and cannot certify
# effective rights before independently checked granting chains and signed routes.
for claim in (
    "'contextualOperationObservations',jsonb_build_array(",
    "'dimension','governing','operation','company_work.manage'",
    "'recordKind','native_ledger','fieldPath',NULL",
    "'selectedLedgerRootSource',v_exact_root",
    "'effectivePermission','verification_incomplete'",
    "'sourceWriterRecheckRequired',true",
    "'doesNotAuthorizeAnyOperation',true",
    "'contextualFieldObservations',jsonb_build_array(",
    "'dimension','knowledge','operation','subject.read'",
    "'recordKind','spatial.growing_object','fieldPath','identity'",
    "'recordKind','spatial.growing_object','fieldPath','condition'",
    "'grantChainCoverage','legacy_last_decision_only'",
    "'doesNotDiscloseFieldToTarget',true",
):
    require(claim in source, f"typed source observation invariant missing: {claim}")
require(source.count("'contextualFieldObservations',jsonb_build_array(")==1,
        "field observation may occur only inside original governor Work subject")
require(source.count("'contextualOperationObservations',jsonb_build_array(")==1,
        "operation observation must remain singular and governor-only")
require(source.count("'effectivePermission','verification_incomplete'")==3,
        "no field or operation may be promoted to executable permission")
print("PASS P1A typed contextual governor-only field and operation packets (STATIC ONLY)")
print("PASS P0B current-main contextual governor source guards (STATIC ONLY)")
