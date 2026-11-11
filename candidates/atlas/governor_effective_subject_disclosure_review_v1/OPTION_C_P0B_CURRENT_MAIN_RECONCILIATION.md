# Atlas Option C — P0B current-main reconciliation (HELD)

**State:** Current-main-anchored draft source, **not an approved permission**, a database release, or a signed browser acceptance. **Owner:** existing Atlas Effective Disclosure Review lane — Noel #2255 / Atlas #437, old held Noel #2263 (not merged). Keep Atlas PR #550 separate and held.

## Why this exact integration
The October 25–26 40 permissions choices and the November 7 R1–R8 80-choice proposed constitution selected source-owned contextual authority, independently governed Ledgers, concurrent roots, field-level disclosure, recipient non-discoverability, and no implied read permission from a Seat, assignment or role. November constitutional holds H1–H9 remain unresolved.

The old Noel #2263 branch was hundreds of commits behind main and its review referenced a held Work-field decision table not installed in production. **Do not merge that branch wholesale or copy its unreleased Work-field writer into production.**

Current Noel main already owns `atlas.owner_effective_subject_disclosure_review_self_api_v1` with canonical target Seat and a governor-only, legacy two-root source gate. This P0B change stages a **full-function held override of that same source** in `contextual_authority_review_override_HELD.sql`, with matching `contextual_authority_review_postconditions_HELD.sql`. The original `candidate.sql` and `postconditions.sql` are kept **byte-identical to main**, because the universal Work integrated bundle fingerprints them. The override is not a new RPC, permission table, merged migration, or live source change. Existing response, original Work and linked Subject disclosure remain unchanged.

## Exactly what was added

For the existing authorized governor's selected Organization, exact native Ledger and connected canonical Person:

- Resolve **one** active signed-user-linked Principal for the target Person. Missing or multiple active Principals => `unresolved`; do not select one by convenience.
- Require **one** current participation of the exact Ledger in the selected Organization and **one** current compatibility-primary governing Ledger. Missing or multiple => `unresolved`.
- Where unambiguous, check current `root_governing` authority for the *same target Principal* on the selected Ledger and separately on the organization's primary Ledger, with active authority and no ended-at timestamp.
- Report `contextualAuthorityReview` as nonauthorizing source facts: `selectedLedgerRoot`, `organizationPrimaryRoot`, `selectedLedgerIsOrganizationPrimary`, `legacyCompanyWorkDualRootCandidate`. Do not assert effective Work/People access, a current target sign-in, field disclosure, or the propriety of the legacy double-root policy.
- Preserve `company_work_native_ledger_owner_self_v1`, its existing roughly 62 downstream callers, all current signed session/Seat guards, source custody, provider/Org privacy, original canonical Person/Work and current app behavior. No source permission grant or read-path widening.

## Integration fingerprint correction

An initial in-place source edit caused global Database Custody CI's exact-integrated-Work assembler to fail at `integrated SQL candidate differs from exact original sources`. This was a **real dependency introduced by the source edit**, not an unrelated failure. The original candidate and postconditions have since been restored to their exact main Git blobs; a new static test strips only the three additive contextual blocks from the held override and requires byte-exact equality with the bundled original. Re-run exact-head Database Custody CI; never regenerate or modify the universal Work bundle merely to accommodate this held permissions diagnostic.

## Verification boundary

- Static assertion: `scripts/validate-atlas-option-c-contextual-review-source.py`.
- Existing disposable SQL clone postconditions are extended to verify bounded guard shape and original public/private RPC ACL.
- **NOT YET RUN:** actual installation against a protected current production-schema disposable PostgreSQL clone, independent signed GoTrue/PostgREST governor / target / outsider tests, two current roots, target with no account, multiple Principal/participation ambiguity, exact Ledger vs primary denial, Seat/Principal revocation, and other reachable reader leakage. The existing source remains in a draft PR; do not deploy it for testing.
- Even a successful signed source review cannot certify all effective exposure until the legacy elevated readers, Today/Index, search, media, caches and alternate public routes are inventoried and tested.

## Next smallest test

Prepare an **owner-gated protected signed clone** rooted in the exact current main and this exact candidate source; create fictional identities/Seats only in disposable test schema. Prove one signed governor may inspect a connected Person's *source flags* while the target/outsider cannot invoke the governor reviewer, and separately test (1) target root on operating Venue but not primary Elm Farm, (2) both roots on Optical Lift, (3) two independently current root governors, (4) withdrawn root and Seat, (5) ambiguous Principal/participation returning NULL, never green. Compare existing source response unchanged except additive diagnostic. No production dataset, employee seat or provider token fixtures.

After signed proof, preserve the Option C architecture decision and implement proper source-owned operation/field authorities + governed approval/revocation under existing Noel #2255/Atlas #437. Do not fix Marshall with an Elm Farm primary-root grant.
