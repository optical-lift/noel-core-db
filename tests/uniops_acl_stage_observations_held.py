#!/usr/bin/env python3
"""HELD pure stage-classifier and catalog-only SQL for UNI-OPS function ACL.

NO database connection, production controller, correction, authorization, or
entrypoint is provided here. A future separately approved protected inspector
could use these fixed SELECTs against its disposable localhost clone.
Current/default ACL compatibility is NOT historical grant provenance.
"""
from dataclasses import dataclass
import re

import reconcile_uniops_native_governor_acl_local_held as acl

# Local clone ONLY. These fixed statements return bounded aggregate counts,
# never an ACL array, raw grant, role identity, SQL body or user record.
DEFAULTS_SQL = """
SELECT
 count(*) FILTER (WHERE d.defaclnamespace=0),
 count(*) FILTER (WHERE d.defaclnamespace='public'::regnamespace),
 count(*) FILTER (WHERE a.is_grantable)
FROM pg_catalog.pg_default_acl d,
     LATERAL pg_catalog.aclexplode(d.defaclacl) a
WHERE d.defaclrole='postgres'::regrole
  AND d.defaclobjtype='f'
  AND d.defaclnamespace IN (0,'public'::regnamespace)
  AND a.privilege_type='EXECUTE'
  AND a.grantee NOT IN ('postgres'::regrole,'service_role'::regrole)
""".strip()

# Not evidence of the statement that *originally* granted a permission.
# Each "matches_default" means a current postgres default ACL contains the
# same grantee as an actual extra explicit function EXECUTE grant.
EXTRAS_SQL = """
SELECT
 count(*) FILTER (WHERE a.grantee NOT IN (p.proowner,'service_role'::regrole)),
 count(*) FILTER (WHERE a.grantee NOT IN (p.proowner,'service_role'::regrole)
    AND EXISTS (
       SELECT 1 FROM pg_catalog.pg_default_acl d,
            LATERAL pg_catalog.aclexplode(d.defaclacl) x
       WHERE d.defaclrole='postgres'::regrole
         AND d.defaclobjtype='f'
         AND d.defaclnamespace IN (0,p.pronamespace)
         AND x.privilege_type='EXECUTE' AND x.grantee=a.grantee
         AND NOT x.is_grantable)),
 count(*) FILTER (WHERE a.grantee NOT IN (p.proowner,'service_role'::regrole)
    AND NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_default_acl d,
            LATERAL pg_catalog.aclexplode(d.defaclacl) x
       WHERE d.defaclrole='postgres'::regrole
         AND d.defaclobjtype='f'
         AND d.defaclnamespace IN (0,p.pronamespace)
         AND x.privilege_type='EXECUTE' AND x.grantee=a.grantee
         AND NOT x.is_grantable)),
 count(*) FILTER (WHERE a.grantee NOT IN (p.proowner,'service_role'::regrole)
    AND a.is_grantable),
 count(*) FILTER (WHERE a.grantee='service_role'::regrole AND a.is_grantable)
FROM pg_catalog.pg_proc p,
     LATERAL pg_catalog.aclexplode(p.proacl) a
WHERE p.oid=to_regprocedure('public.grant_personal_atlas_access_v1(uuid,text,jsonb)')
  AND a.privilege_type='EXECUTE'
""".strip()

BOOL_FIELDS = ("default_acl","anon_exec","authenticated_exec",
               "postgres_exec","service_exec","explicit_grantees_confined")
VERDICTS = frozenset({
    "stage_canonical_match",
    "stage_default_compatible_not_provenance",
    "stage_default_drift_ambiguous",
    "stage_extra_unknown_refused",
    "stage_delegable_refused",
    "stage_other_mismatch_refused",
    "stage_source_unverified",
    "stage_preexisting_target_refused",
    "stage_target_missing_refused",
    "stage_metadata_refused",
})
_COUNT_RE = re.compile(r"(?:0|[1-9][0-9]{0,2})")
_DIGEST_RE = re.compile(r"[0-9a-f]{32}")


def parse_counts(raw, size):
    """Finite, small catalog metadata only; refuse null, negative or overflow."""
    if not isinstance(raw, str):
        raise ValueError("stage_metadata_refused")
    cells = raw.strip().split("|")
    if len(cells) != size or any(not _COUNT_RE.fullmatch(c) for c in cells):
        raise ValueError("stage_metadata_refused")
    return tuple(int(x) for x in cells)


@dataclass(frozen=True)
class StageDecision:
    verdict: str
    mismatch_fields: tuple
    role_defaults_changed: bool
    schema_defaults_changed: bool

    def __post_init__(self):
        if self.verdict not in VERDICTS or any(x not in BOOL_FIELDS for x in self.mismatch_fields):
            raise ValueError("stage_metadata_refused")

    def safe_line(self):
        """Only allowlisted categories and Boolean field NAMES leave the test."""
        return (
            "UNI_OPS_STAGE_VERDICT=" + self.verdict +
            ";DIFF=" + (",".join(self.mismatch_fields) or "none") +
            ";ROLE_DEFAULT_CHANGE=" + str(self.role_defaults_changed).lower() +
            ";SCHEMA_DEFAULT_CHANGE=" + str(self.schema_defaults_changed).lower()
        )


def classify_stages(
    source, before_target, after_roles_target, after_schema_target,
    before_defaults, after_roles_defaults, after_schema_defaults,
    final_extras, digest,
):
    """Classify staged metadata; do not infer causal or historical provenance.

    The supplied nine-field ACL observations are private in-memory values.
    Blank target observation indicates the function does not yet exist.
    All database reads are deliberately outside this pure helper.
    """
    invalid = StageDecision("stage_metadata_refused", (), False, False)
    if not isinstance(digest,str) or not _DIGEST_RE.fullmatch(digest):
        return invalid
    try:
        db = parse_counts(before_defaults, 3)
        dr = parse_counts(after_roles_defaults, 3)
        ds = parse_counts(after_schema_defaults, 3)
        extra, compatible, unexplained, delegable, service_option = parse_counts(final_extras, 5)
    except ValueError:
        return invalid
    role_changed = db != dr
    schema_changed = dr != ds

    def decision(code, differences=()):
        return StageDecision(code, tuple(differences), role_changed, schema_changed)

    if not acl._verified_acl_observation(source,digest) or acl.classify(source,digest)!="protected":
        return decision("stage_source_unverified")
    if before_target != "" or after_roles_target != "":
        return decision("stage_preexisting_target_refused")
    if not acl._verified_acl_observation(after_schema_target,digest):
        if after_schema_target == "":
            return decision("stage_target_missing_refused")
        return decision("stage_source_unverified")
    src, dst = source.split("|"), after_schema_target.split("|")
    differences = tuple(BOOL_FIELDS[i] for i in range(6) if src[i+3] != dst[i+3])

    if compatible + unexplained != extra or delegable > extra or service_option > 1:
        return decision("stage_metadata_refused")
    if service_option or delegable:
        return decision("stage_delegable_refused", differences)
    if unexplained:
        return decision("stage_extra_unknown_refused", differences)
    if src == dst:
        # Full parity only; there must be no extra grants left over.
        if extra:
            return decision("stage_metadata_refused")
        return decision("stage_canonical_match")
    if not extra:
        return decision("stage_other_mismatch_refused", differences)
    if schema_changed:
        return decision("stage_default_drift_ambiguous", differences)
    if compatible == extra and differences:
        return decision("stage_default_compatible_not_provenance", differences)
    return decision("stage_other_mismatch_refused", differences)


if __name__ == "__main__":
    raise SystemExit("HELD pure classifier: no protected or standalone execution")
