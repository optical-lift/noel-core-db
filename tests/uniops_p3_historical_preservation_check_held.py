#!/usr/bin/env python3
"""HELD / SOURCE ONLY: no-issuer conservation after independently signed historic cancellation.

This checks the already-signed U4/P3 first-mowing source BEFORE and AFTER a
separate, governor-reviewed historical retirement of ONE fictional obsolete
legacy_task_slice Work in the same isolated organization. A real physical
mowing Result is never treated as a cancellation, and a historical review is
never treated as a Result.

The source SQL snapshot is the exact previously signed P3 read-only snapshot.
Both captures must come from that snapshot via real disposable PostgreSQL; this
comparison NEVER simulates a signed session or executes an API/SQL call.

IMPORTANT: the separate retired Work is a generic legacy slice. This is NOT
proof of cancellation of a prior mowing-original or that nonempty old mowing
Tasks/occurrences were preserved. That requires a further physical fixture.
"""
from collections.abc import Mapping

SNAPSHOT_CONTRACT="uni_ops_p3_signed_result_snapshot_v1"
NO_MUTATION=(
    "originalWorkState","rhythmState","qualifyingSatisfactionId",
    "nextEligibleAt","observedPhysicalCondition",
    "sourceWorkTotal","legacyTaskTotal","plannedOccurrenceTotal",
    "legacyReleasedTaskIds","eligibleOrReleasedOccurrenceIds",
    "releasedOccurrenceIds","governedOfferTotal","workPlanTotal",
    "workResultTotal","originalResultTotal","originalAcceptanceTotal",
    "physicalCareResultTotal","physicalCareObservationTotal",
    "satisfactionTotal","principalObligationTotal",
    "campaignTableAbsent","campaignOfferTableAbsent"
)
RETIRED_FIXTURE_DELTA={"workTotal":1,"workAllocationTotal":1}

class PreservationRefusal(AssertionError):
    """Safe fixed refusal: never carry private row, UUID, actor or SQL data."""

def require_preserved(before, after):
    """Return true only when the signed P3 original/Need survives cancellation."""
    for record in (before,after):
        if (not isinstance(record,Mapping)
                or record.get("contract")!=SNAPSHOT_CONTRACT
                or record.get("phase")!="replay"
                or record.get("validExactOriginal") is not True
                or record.get("validRhythmState") is not True
                or record.get("campaignTableAbsent") is not True
                or record.get("campaignOfferTableAbsent") is not True):
            raise PreservationRefusal("Exact signed P3 snapshot custody missing")
        if (record.get("originalWorkState")!="completed"
                or record.get("rhythmState")!="resting"
                or record.get("sourceWorkTotal")!=1
                or record.get("originalResultTotal")!=1
                or record.get("originalAcceptanceTotal")!=1
                or record.get("physicalCareResultTotal")!=1
                or record.get("physicalCareObservationTotal")!=1
                or record.get("satisfactionTotal")!=1
                or not record.get("qualifyingSatisfactionId")
                or not record.get("nextEligibleAt")
                or not record.get("observedPhysicalCondition")):
            raise PreservationRefusal("First mowing Result/Need was not already proven")
    for field in NO_MUTATION:
        if (field not in before or field not in after
                or before[field]!=after[field]):
            raise PreservationRefusal("Historical retirement changed P3 protected state")
    for field,increment in RETIRED_FIXTURE_DELTA.items():
        if (type(before.get(field)) is not int
                or type(after.get(field)) is not int
                or after[field]!=before[field]+increment):
            raise PreservationRefusal("Historical retirement fixture census not exact")
    # Prior released Task/eligible occurrence identities are compared above,
    # but no synthetic historical mowing Task is asserted to exist in this test.
    for field in ("legacyReleasedTaskIds","eligibleOrReleasedOccurrenceIds",
                  "releasedOccurrenceIds"):
        if not isinstance(before[field],list):
            raise PreservationRefusal("Historical carrier identity set is unavailable")
    return True
