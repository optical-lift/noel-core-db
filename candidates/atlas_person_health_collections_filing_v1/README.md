# Atlas Build 1 — Canonical Person Health Collection and verified filing

Status: SOURCE-ONLY REVIEW CANDIDATE. This source has NOT been merged,
generated as a migration, applied to production, tested with signed sessions,
or deployed to Atlas. Owning repository: noel-core-db; Atlas release lane.
Governing issue: https://github.com/optical-lift/noel-core-db/issues/2106
Consumer: https://github.com/optical-lift/atlas/pull/382

## Canonical truth reused

- atlas.notebook_spread_instances; public.atlas_notebook_index_self_api_v1
- atlas.personal_reality_captures (original testimony, untouched)
- atlas.notebook_spread_source_bindings (typed relation, not copied note)
- atlas.require_active_task_principal_v1 and auth.uid (two distinct identities)
- Existing weight rule version 1 and signed permission; no new classifier

## Actual source change

- Existing and future active user-bound principals get one private
  personal.health Spread; collision of wrong semantic identity raises an error.
- One immutable events table records each original capture ID, route event,
  actor, source binding, target/from Spread, time, mode and rule version.
- Four authenticated public RPC wrappers implement Collection list, explicit
  or previously approved deterministic filing, signed source readback and
  Today movement receipt. All private inner APIs and tables remain ungranted.
- Moves retire old current route, preserve source/binding history and add an
  immutable receipt. Retrying a successful route returns the prior receipt.
- No automatic filing for unmatched, revoked, unapproved or preapproval text.
  The phrase "Weighed in at 194lbs" remains unmatched in v1 until Build 2.
- No extra note table, clinical assertion, new Work, Ledger access or
  inferred onset/measurement time. Today receipt never copies the text.

## Validation and release obligations

1. Review candidate SQL against latest main and repeat read-only schema audit.
2. Generate migration from an approved source-candidate commit on main through
   .github/workflows/migration-source-generation.yml; source-first custody.
3. Run fixture.sql and validation.sql on disposable production-schema clone.
4. Execute TWO truly separate signed GoTrue/PostgREST sessions: both see
   canonical Index Health, A file/readback/retry/move, foreign User B cannot
   read or route A's source, no anon calls, cross-Collection denial, race
   serialization, revoked recognition, original source/evidence unchanged.
   SQL request.jwt settings are NOT real authentication proof.
5. Run owning Atlas release-lane checks, lint delta, registry contract,
   migration receipt and protected-production release review.
6. Merge/validate #382 on exact DB contract, run genuine browser Index to
   Collection to original source and Today receipt, then verify live signed
   readback. Explicit independent release authorization still required.
7. Mark Build 1 closed only after actual DB + app released end-to-end proof.

Known limits: This candidate has not been SQL-executed, validated on a clone,
or proven with signed sessions. Verification is pending. No production change
has been made. Do NOT skip any protection or release gate.
