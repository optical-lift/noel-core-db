# Atlas Work-to-Work prerequisite contract — reviewed source candidate

**Status:** Draft SQL candidate only. **Not a numbered migration, not clone-validated, and not deployed.**

**Logical owner:** Atlas (`atlas_` release lane in `noel-core-db`).  
**Related app PR:** optical-lift/atlas#343 (Living Ink source-only).

## Canonical finding

Production already contains `atlas.work_item_relations` with `depends_on`, `blocks`, `enables`, `part_of`, `alternative_to`, `handoff_to`, and `completion_bundle_member` relation kinds. It has organization-coherent foreign keys, self-link prohibition, and uniqueness by (from Work, to Work, relation kind). `atlas.work_items` remains the original institutional Work identity. Only 2 active completion-bundle relations were observed in the read-only audit; no active `depends_on` rows appeared in that snapshot.

**No second dependency-truth table is appropriate.** `proposals/atlas_work_item_prerequisites_v1_REVIEW_ONLY.sql` proposes server-side functions and one append-only operation history table while retaining this existing canonical graph.

## Interpretation and direction

For an operation of the form “Spray the walkways after the replacement sprayer arrives”:

- **downstream Work** = existing canonical Work for spraying walkways;
- **prerequisite Work** = separately existing canonical Work for acquiring the replacement sprayer;
- **relation** = `depends_on`, **from downstream** to **prerequisite** in `work_item_relations`;
- the text is a candidate only until both exact identities and governing authority are separately proved;
- “sprayer arrives” is **not** proof that purchasing is completed or that a Work result is accepted;
- a newly recorded relationship does **not** automatically change either Work state or place Work onto an individual's day.

## Proposed first authority rule

This first contract intentionally limits relation establishment to **one common, currently evidenced Ledger in one Organization**, with the exact governing principal verified through `atlas.company_work_native_ledger_owner_self_v1`. Both Work IDs must already exist in the same Organization, remain non-retired, and have active `atlas.company_work_native_ledger_relevance` evidence for that very Ledger. Source-verified attribution is reread via `atlas.company_work_native_ledger_exact_source_v1`.

**Ledger seat alone is not authority.** A scope of work, employee title or conversational mention does not grant source mutation. A cross-Ledger or cross-Organization relationship is not granted by this first candidate. A future explicit cross-Ledger bridge must prove both governing authorities and compatibility rather than pretending that shared organization ID settles authority.

## Proposed APIs

- `public.atlas_work_prerequisite_candidates_self_api_v1`: paginated original Work IDs/titles/status **only inside an exact authorized Ledger**.
- `public.atlas_work_prerequisites_self_api_v1`: rereads original incoming `depends_on` edges for authorized downstream Work, with active flag and source state distinct from completion/satisfaction.
- `public.atlas_set_work_prerequisite_self_api_v1`: explicitly establish or withdraw one verified `depends_on` edge using two exact IDs, a meaningful reason and stable action ID. Idempotent replay is checked against the original action fingerprint.
- `atlas.guard_work_item_depends_on_cycle_v1` trigger: cycle protection for **all** writers of `work_item_relations`, including older communication-derived Work code. Organization-scoped advisory locking serializes candidate changes. Depth above 256 fails closed.
- `atlas.work_item_prerequisite_events_v1`: append-only operation history (not independent dependency truth). RLS enabled, no `anon` or `authenticated` direct table rights.

All public entrypoints recheck governing authority server-side and preserve the canonical source; public wrappers are narrow rather than granting direct table access.

## Required clone validation and explicit release gates

1. Generate a versioned canonical `atlas_` migration with the repository's reviewed Supabase CLI workflow. **Do not apply this proposal directly to production.** Source-first in `noel-core-db`, then canonical migration review.
2. Run the official **production-schema clone validation** for this exact migration version and immutable candidate SHA. The harness restores schema/roles to a disposable database; the production credential is read-only for snapshot and never used for candidate SQL.
3. Test original relationships `completion_bundle_member`, `blocks`, `enables` etc. unchanged; `depends_on` trigger must not interfere with unrelated Work.
4. Test two real source Work IDs: same Organization, same proven Ledger, active evidence. Establish one link, verify ID/receipt, reread identical link, repeat source-action ID as idempotent replay, withdraw and reread inactive original record.
5. Test rejection: self-link; missing Work; different Organizations; different Ledgers without shared evidence; connection seat without governing principal; cancelled or superseded Work; stale source verification; unauthorized actor; malformed action/short reason.
6. Test cycle rejection for A→B→C→A and simultaneous A→B/B→A transactions. Exercise an **older communication-derived writer** that can write `depends_on`, to confirm global trigger coverage.
7. Test isolation: the new history table is invisible under direct `anon`/`authenticated` queries; the public wrappers reject unauthorized session and cannot return other Ledger Work titles.
8. Test no-loss: existing Company Work result reporting, standing scope, owner planning, retirement preflight, Work bundle completion, scheduled projection and employee-to-universal-connection paths still work.
9. Run security advisors/lint and validate source and permission diffs. Separate person and Ledger views with live authenticated sessions are needed before any app-side UI action becomes available.
10. Only after source-clone approval, merge via proper lane, schedule **explicitly authorized protected release**. No migration was executed in preparing this branch.

## Deliberate non-goals

- No automatic Work blocking, task status mutation, Day carryforward, proof of satisfaction or deadline inference.
- No parsing an arbitrary sentence into two source IDs without a governed resolution.
- No person/organization authority granted by user-entered text.
- No private tenant rows or founder records committed in SQL fixtures.
- No second independent task registry or direct client-table writes.

## Current proof

Production introspection was **read-only**: table constraints, absence of existing Work relation triggers, current relation kinds, ownership rules, source attribution and available public APIs. No SQL candidate execution or disposable-schema test has yet been performed. Keep the proposal **non-executable by migration tooling** until those gates pass.


## Review refinement — original record readback and synthetic graph proof

The SQL candidate now returns a consistent receipt for first establishment **and** idempotent replay: exact Organization and Ledger, both Work IDs, active state, and the append-only `recordedEventId`. The application adapter refuses a receipt missing any of these or falsely claiming that the relationship created Work or automatically blocked it; it then independently rereads the original relation ID.

The clone validation packet includes two distinct files, neither of which has been executed:

- `atlas_work_item_prerequisites_v1_CLONE_POSTCONDITIONS.sql`: catalog/privilege checks, relation vocabulary preservation, global guard trigger presence, RLS and anonymous restrictions.
- `atlas_work_item_prerequisites_v1_CLONE_GRAPH_TEST.sql`: rollback-only synthetic Organization plus three Work items, A→B→C, prohibition of C→A, deactivation of B→C, safe creation of C→A, rejection of B→C reactivation, plus `blocks` and `completion_bundle_member` untouched.

The test uses only generated fixture IDs and concludes with `ROLLBACK`. It is designed for the disposable full-schema clone, not a production connection.

**Remaining executable tests:** authorized principal vs connected-seat-only sessions, active/withdrawn Ledger evidence, cross-Organization/cross-Ledger denials, concurrent transaction deadlock/cycle protection under two sessions, full idempotency, the older communication-derived `depends_on` writer, existing Work retirement and completion flows. These cannot be certified from static source inspection or a catalog query.

**Build boundary:** This draft remains a `proposals/` source candidate because the pinned Supabase CLI and Docker/PostgreSQL clone runner were unavailable in the execution environment. Do not guess a timestamped migration filename or use direct production SQL as a substitute for `supabase migration new` and the canonical validated release path. Reconcile concurrent `main` changes before creating the numbered migration.


## Build refinement — independent action-event readback

`public.atlas_work_prerequisite_event_self_api_v1` has been added to the **review-only proposal**. It requires exact governing authority and original same-Ledger source evidence for both Work IDs. It returns a specific event by `recordedEventId`, including the original `sourceActionId`, actor Person identity, relation identity, action kind, resulting active state, timestamp and preserved reason.

The companion Atlas app adapter now rejects a purportedly successful change unless **three things** agree: the command receipt, the canonical `work_item_relations` reread and the independently queried append-only event row. No additional authority is inferred from this verification.

The clone postconditions now include the event RPC's anonymous-denial and authenticated entrypoint checks; a separate real-session test must still prove governing-principal-only access despite the public authenticated wrapper.

**Source-level static comparison passed 12/12 architecture checks before the audit readback extension.** This is not a CI/build or Postgres syntax pass. Run the numbered migration and clone tests through the canonical protected workflow before allowing release. Neither candidate repository has been merged or deployed.
