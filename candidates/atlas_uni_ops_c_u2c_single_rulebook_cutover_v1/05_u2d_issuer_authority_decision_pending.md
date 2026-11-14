# UNI-OPS-01 — U2D issuance authority decision record (PENDING PRINCIPAL)

> **Supersession notice (November 13, 2026):** The three issuer/campaign decisions below are historical *pre-November-4* questions, not pending owner choices. Binding choices U2E **1C / 2C / 3C** and Actual-first **6A** are recorded in [06_binding_u2e_actual_first_owner_decisions_20261113.md](06_binding_u2e_actual_first_owner_decisions_20261113.md). They do **not** confer a registered carrier, signed mandate or automatic next issuance. Retain this older evidence unchanged below.


**Source-only architecture proposal.** NOT an authorization, migration, table, active delegate, scheduled task, or Work writer.

**Owned by:** Noel's source-governed Work and Ledger authority. Consumer: Atlas's `issuer-authority-proposal.mjs` inert parser in held draft #535. Existing accepted-offer path stays held as implemented in Noel draft #2485.

## One bound operation

**Purpose:** after a real native source candidate has been offered and one actual connected Person has **signed acceptance** of that one candidate, establish **at most one** canonical original Work with the correct Result contract and explicit service day. A source clock, acceptance of a standing Person scope, or passing a static test cannot be substituted for the candidate-level acceptance.

**Protected:** separate canonical Requirement and Subject, Foundry U1A, native U1B, actual Work/Result, recipient disclosure, Person consent, three-open-original ceiling, named seasons and physical condition, Household and Event sources, production credentials, and past history.

**Acceptance evidence:** the native `governed_prework_candidate_offers_v1` row must be accepted by the exact signed worker, still source-current, with frozen property and effective Rulebook versions, no conflicting historical direct Work, and a planned day chosen from root-approved ISO weekdays. The current source Writer must recheck all of those *atomically*. Receipt cannot itself upgrade authority.

## Three decisions requiring Principal judgment

1. **Issuer after independent candidate acceptance:** (A) current native signed governor personally finalizes every accepted candidate (existing U2B), (B) the accepting worker's signed transaction invokes a *source-governed* original writer under a separately preapproved, revocable, narrowly bounded standing governor mandate, or (C) a separately registered automated carrier later finalizes after acceptance under independently established authority. **No option is automatically adopted**. Mode B does not impersonate the root and is a distinct native writer requiring its own signed-worker, mandate and source tests; B is the simplest event-driven carrier if authorized.
2. **Mandate duration:** one 7-day operating window, one 30-day bounded campaign, or one preapproved maximum-120-day season, always with explicit expiration and immediate prospective revocation. Neither the existing `valid_until` standing Person relationship nor a general farm entitlement is enough by itself.
3. **Continuation after an accepted Actual:** source may offer the next candidate automatically after the Result is accepted (still requiring that next candidate's worker acceptance), or it may remain in a root-selected review queue. A due clock NEVER becomes observed physical condition. Every original remains distinct with one accepted responsibility.

## Invariants independent of choices

- Source: `continuing_care_actual_v1` / first actual **mowing standing** adapter only.
- Actor root and worker remain separate identities and cannot be inferred from prior sessions; no `service_role` public browser secret, root-role spoof, user metadata grant, or surrogate employee Seat.
- No Original Work before explicit one-candidate recipient acceptance. No skipped capacity, duplicate serving, missing or stale disclosure, physical condition inferred from time, invalid named season, unapproved off-day, changed Rulebook authority, or claimant alteration of source IDs.
- Each operation checks exact current revocation, payload fingerprint, source-custody lock, and signed actor. A recorded permission does not create a new technical Principal on its own.
- **Maximum three** concurrently open original Work per accepted worker under the previously approved pilot; real atomic capacity must cover other original Work writers before any live use.
- A successful first original is not consent for an automatically issued next Work; the next candidate must be separately offered and accepted.
- Results and failed releases are accurately recorded; errors return to the Principal. No unsolicited Owner Clock item is inferred from an operator miss.
- Authoring, release, CI, Supabase schema and production deployment remain independent authorities.

## Engineering after Principal selection

For mode B, create a **native owner-signed, revocable authority instrument** that names one existing root/organization/Ledger/farm/source rule/worker standing scope, duration, weekdays, operation set, 3-open cap, disclosure, allowed source condition and one canonical Result. A worker-signed acceptance writer must require the recorded instrument, recheck current owner authority and Subject/Need, and create exactly one original using the protected native Work source. It cannot call a function which requires the owner's *current* authenticated identity unless a separately controlled internal source path with its own actor-proof replaces that check. Distinct `SECURITY DEFINER` code needs an exact principal/caller/revocation/RLS audit, not assumed trust.

For mode C, the automated carrier must be separately registered, eligible and revocable under Atlas Delegated Agent Governance; scheduler identity or technical credentials alone are not authority. Mode A can use existing U2B, with the requirement that every human root sign-in is current.

For continuation, do not issue the next original from completion automatically; first establish current source Need after signed Actual, retrieve the next candidate through the chosen adapter, and require fresh worker consent.

## Current status and verification

- An inert validation contract + declaration in Atlas draft #535 rejects principal impersonation, inflated capacity, excess duration and hidden permissions; 15/15 isolated V8 pure-contract checks passed. **An authored Node test is NOT executed.**
- No owner-signed authority instrument exists in U2C, no actor registered, no user choice stored, no new table/RPC grants and no unattended worker/scheduler enabled.
- No source is installed or signed-tested in a disposable full-schema clone. U2C and earlier U1A/B/U2 source drafts remain release-held.

**Stop:** Await explicit choices. Do not choose the real issuer by assumption or fabricate a Principal authorization.
