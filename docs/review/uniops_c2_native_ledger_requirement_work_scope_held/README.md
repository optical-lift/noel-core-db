# UNI-OPS C2 — exact native Ledger Work disclosure source adjudication (HELD)

**Date:** 2026-11-09 local / 2026-11-10 UTC. **Owner train:** [Atlas UNI-OPS #532](https://github.com/optical-lift/atlas/issues/532). **Source concern:** [Noel issue #2667](https://github.com/optical-lift/noel-core-db/issues/2667). **Current Atlas consumer:** [held draft #551](https://github.com/optical-lift/atlas/pull/551).

**Disposition:** Stage a **review-only, source-preserving narrow correction** to an existing native Company Ledger owner read; do not create a new generic Case store, Work issuer, right, migration or privileged union. This document is a source-custody recommendation, **not approval to install it**.

## 1. Verified installed source and exact issue

Read-only `pg_get_functiondef` of installed `atlas.operating_requirements_owner_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_limit integer)` in connected project `zirqkouammpwxlqfbsvf` was pinned by MD5 **`ffcf0b1c8ab49b4d456037aa5f1147cf`** (4,401 bytes). Captured as `installed_baseline.sql`; no customer content rows were read.

The existing `STABLE SECURITY DEFINER` function checks `atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id)`. The operating Case/requirement register is scoped to **one exact native Ledger and one Organization**. Yet its nested `canonical_work` subquery filters `atlas.work_requirement_links` by active requirement and Organization only, not by **each linked original Work's** current selected-Ledger relevance.

Consequences are two distinct statements:
- **Observed source omission:** an exact selected-Ledger requirement read can include original Work ID/title/state with no independent, current proof that the original belongs to the selected Ledger. A Company governor may have broader Organization rights elsewhere, but this **Ledger-specific reader does not itself prove broader disclosure entitlement**.
- **Not established:** no production data or real Case was checked for such a mismatched link. This issue does not assert that a breach or unauthorized human disclosure has occurred.

The current [Atlas draft #551](https://github.com/optical-lift/atlas/pull/551) additionally intersects the requirement's Work links with `company_work_accountability_native_ledger_self_api_v1(p_scope='native_ledger')` before presentation. That is a conservative second signed source check. **It cannot repair the raw source RPC contract**; its two sequential reads are not one atomic snapshot.

## 2. Proposed exact correction — original source retained except one predicate

`proposed_function_review_only.sql` is identical to the installed 4,401-byte function **except one inserted `AND EXISTS` block inside the current `canonical_work` Work link WHERE clause**, immediately after existing `l.active`. The added block checks:
1. `company_work_native_ledger_relevance.organization_id = i.organization_id` **and** `work_item_id = i.id` **and** `ledger_id = p_ledger_id`;
2. `attribution_state = 'active'`, not historically withdrawn;
3. `evidence_kind = 'owner_attested'`, **or** `source_verified` with a still-current exact source-object match returned by `atlas.company_work_native_ledger_exact_source_v1(rel.work_item_id,rel.ledger_id)` using all three `source_schema/source_table/source_id` fields.

This mirrors the **installed source's existing distinction** between owner-attested and independently source-verified relevance; it does not upgrade attestation to proof, admit unchecked `source_verified`, assign responsibility, call Work writers, or synthesize a Result. The original function signature, current source-owner gate, `SECURITY DEFINER` semantics, owner-register selection, separate legacy-linked requirement reconciliation, event/Result history and response contract are **unchanged**.

**Important choice:** This correction narrows `canonical_work` returned from a selected Ledger; it intentionally may hide previously visible same-Organization Work that lacks relevance to that Ledger. The owner must affirm this narrower display meaning before a signed source install. It does **not** alter actual `atlas.work_requirement_links` relationships, and it does not delete historical Work.

## 3. Evidence versus acceptance

The no-network Python source contract `tests/test_uniops_c2_native_ledger_case_link_source_held.py` validates the exact frozen installed function MD5, exact one-block replacement (rejects any other SQL/auth change), current native Ledger and source proof predicates, unchanged legacy/owner source and synthetic truth-table denials. **It cannot establish PostgreSQL execution, PostgREST transport or real signed authorization**. The YAML workflow is PR-only; no secrets, protected environment, schema clone, production data access, or SQL execution.

A separately approved **disposable signed follow-on** would reuse the existing four real local GoTrue synthetic identities from `scripts/validate-atlas-c1-signed-http.py` (owner, worker with forged `user_metadata`, other Ledger member, no-seat) and its native owner root/seat/session revocation tests. It would extend that fixture with:
- one existing exact native Ledger `L1` Company operating requirement, one linked canonical Work with current `L1` source relevance, and a second linked same-Organization Work with only `L2` relevance or withdrawn `L1` evidence;
- owner `L1` signed reader **shows only L1 Work**, no foreign Work ID/title/embedded link count; legitimate owner `L2` read still requires an actual L2-scoped register source;
- verified source class coverage: active owner attestation is labelled as such, source-verified requires *current* exact Ledger source proof, revoked source/relevance denies;
- independent actual signed worker, outsider, no-seat, anonymous, wrong Organization/Ledger, revoked root/seat/deleted-session **denials** with no payload leak;
- unchanged counts and IDs for original Work, allocations, outcomes, results/acceptances, Clock and requirement records after all reads;
- Atlas `readOperatingCase` exact one Case/Work lineage comparison, no fake completed history, `historyCompleteness=not_established`, no automatic next Work.

**Do not run a protected clone automatically.** First pin source/workflow/fixture revisions and get a distinct owner authorization for the specific protected diagnostic. The held historical-cancellation [Noel #2665](https://github.com/optical-lift/noel-core-db/pull/2665)/[#2666](https://github.com/optical-lift/noel-core-db/pull/2666) and unarmed #2664 are not part of this source change.

## 4. Release and architectural hold

- **Noel** owns SQL source and source-specific disclosure; this source review remains separate/unmerged until an authorized source-law decision.
- **Atlas** continues to own only the held read-only app projection; do not merge #551 as universally available based only on these tests.
- **Case** remains the logical owner-selected Option C: durable source-governed condition/Need/evidence, with independently authorized original `atlas.work_items`. No new Case tables/permissions or next Work after Done.
- **Next bounded gate:** review exact proposed narrower Ledger disclosure law; then prepare/gate one signed disposable source fixture/driver without production mutation. A genuine multi-actor positive/negative run is not yet accomplished.
