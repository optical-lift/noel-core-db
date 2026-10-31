# Carry Build 1 — v3 database-enforced adoption: acceptance contract

Status: **held source only**. Existing Us Carry v1 (`20261027204404`) and
dated-event v2 (`20261027222504`) are unreleased. No production SQL,
Atlas objects, new identities, or private financial data are involved.

## Bounded outcome

After v3, the private service role MUST be unable to create financial
expectation revisions or lines independently or call
`us.carry_append_event_v1` directly to seal a preassembled draft.
One owner-scoped, narrow event-derived adoption function must reconstruct
the exact dated candidate from an attested adopted baseline and the current
immutable Carry event cutoff in a single transaction.

The tested Python writer in Us PR #1 **does not meet this database privilege
postcondition yet**, even though its separate-connection adoption race passed
on RiverSong. Do not substitute a Python lock or a session-settable GUC for
the database privilege boundary.

## Existing authority to preserve

- Supabase Auth `get_user(token)` verified at the trusted Us server;
  no request-supplied owner ID and no user_metadata ownership.
- Only the private Us database schema; all direct `anon` /
  `authenticated` table and function exposure remains revoked.
- Existing adopted revision remains append-only and unchanged.
- Existing financial source/case stream identity and history remain intact.
- Candidate is uniquely keyed by `(period_month, line_key)`, with
  plan-window, scope, exact-decimal and evidence-class constraints.

## SQL postconditions for v3

1. `service_role` lacks INSERT on both
   `us.financial_expectation_revisions` and
   `us.financial_expectation_lines`.
2. `service_role` lacks direct EXECUTE on the legacy unrestricted
   `us.carry_append_event_v1` entrypoint. Its replacement ordinary
   private event append path cannot accept `REVISION_SEALED`.
3. A dedicated narrow v3 function is the only service-executable
   writer for adoption. It checks exact owner and stream, locks the
   stream/plan, recomputes the original baseline fingerprint, reads
   every dated financial event in order through the expected cutoff,
   materializes all affected AND unaffected monthly lines, and seals
   the new revision atomically. No caller-supplied line array or digest
   counts as authorization.
4. Same approval idempotency key and exact event cutoff replay the
   same adopted receipt; a changed cutoff or payload is denied.
5. A competing new action with stale cutoff is denied, and two
   simultaneous valid approvals create at most one new revision.
6. Failure anywhere rolls back the draft revision, lines, and seal
   together. Direct inserts after adoption remain impossible.
7. Baseline/source provenance and the prior revision's history remain
   byte-equivalent after adoption. Non-additive balances are not summed.
8. A usable authenticated Us reader and reviewer must show the exact
   forecast line values that match the signed preview digest before
   allowing an approval. The server rechecks digest under lock.
9. Genuine signed independent GoTrue owner/outsider sessions must
   demonstrate authorized use and unauthorized non-discovery through
   the Us HTTP endpoint, not merely mocked tokens or SQL role grants.
10. No migration release without dependency-complete disposable clone
    tests, source custody CI, and separate protected authorization.

## Release / source order

1. Original private finance (already live).
2. Carry v1 (generated and source-merged, **not live**).
3. Dated-event v2 (generated draft PR #2345, **not live**).
4. New v3 (not yet generated or tested) — only when complete.

An attempted broad v3 database-function source submission was blocked by
the connected code-hosting safety check. That is not a passing SQL build.
Keep this acceptance gate explicitly open; do not weaken permissions or
invent a positive test receipt to close it.

## Verified precursor

- RiverSong automatic run #41216770910:
  55 Python tests and independent PostgreSQL approval race, unchanged
  adopted baseline, owner-denied candidate and full cleanup.
- Further Us HTTP/preview-digest work is on the active Us draft branch
  and must be verified against its latest SHA before being called green.
