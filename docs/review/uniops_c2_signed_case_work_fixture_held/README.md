# HELD UNI-OPS C2 — signed Case → original Work test preparation

**Date:** 2026-11-09 local / 2026-11-10 UTC. **State:** TEST SOURCE ONLY; not an executed genuine signed test, release, installation or source-law approval.

**Owner source:** [Noel issue #2667](https://github.com/optical-lift/noel-core-db/issues/2667). **One predicate under separate review:** [Noel draft #2668](https://github.com/optical-lift/noel-core-db/pull/2668), exact held head `2545ed3cdafc811ce6ccb466b6aaa99ab9d5ec17`. **App consumer remains held:** [Atlas draft #551](https://github.com/optical-lift/atlas/pull/551); [Atlas UNI-OPS #532](https://github.com/optical-lift/atlas/issues/532).

## Bounded result

Prepare **one genuine multi-actor signed source disclosure test** that extends the **existing** C1 GoTrue/PostgREST authentication fixture, without changing the C2 SQL proposal or Atlas application. The test must distinguish a registered Case's linked original Work from the narrower set that currently qualifies for disclosure within a selected native Ledger. It is not a new Case store, Work issuer, Ledger governor, agent, or production feature.

Two files and their no-network contract test are proposed:
- `tests/uniops_c2_case_work_disposable_fixture_held.sql` — local-only fictional test data. Requires the current schema, *completed existing C1 signed establish/revise probe*, **separately reviewed #2668 predicate installed only on a disposable clone**, and explicit PG17 + four fictional identities + `uni_ops.disposable_clone=true` guards. It creates **no real user, allocation, Result, Clock, grant, or production migration**.
- `scripts/validate-atlas-c2-case-work-signed-http.py` — loopback-only extension that imports **existing** `scripts/validate-atlas-c1-signed-http.py` functions for actual local GoTrue password sign-in, verified `auth.sessions`, authenticated PostgREST RPC, 42501 denial, and real per-request source authority. It refuses remote database and API addresses.
- `tests/test_uniops_c2_case_work_signed_source_held.py` and PR-only workflow: syntax, fixture/identity/clone/authority safety-contract checks **without running the fixture, SQL, GoTrue, remote requests, or a protected diagnostic**.

This branch is intentionally separate from the one-predicate review #2668. Staging it neither approves the source law nor invokes the protected runner.

## Fictional fixture matrix

| Record | Same Organization | Exact Ledger relevance | Requirement link | Expected raw L1 owner read |
| --- | --- | --- | --- | --- |
| C21 original | Yes | L1 current owner-attested *synthetic evidence* | Active | **Included** |
| C22 foreign original | Yes | L2 only, with actual fictional native L2 + Atlas participation | Active | **Excluded ID, title and embedded count** |
| C23 withdrawn original | Yes | L1 previously attested, already withdrawn with recorded reason | Active | **Excluded** |
| C24 historical original | Yes | L1 current | Inactive historical link | **Excluded**; history completeness NOT established |

The C1 fixture has an L2 native `ledger.ledgers` and other-Ledger seat, but **no Atlas participation for L2**. The C2 fixture deliberately adds only the missing fictional Atlas L2 participation (non-primary, operating), so a foreign original's L2 evidence is valid evidence instead of a fake mismatch.

The common requirement is created by the original **signed** C1 owner API, not by a new fixture-issued Case. The four fictional `atlas.work_items` and persisted relevance rows are expressly **test setup**, not claims that a signed governor issued or attested them. The test is about what an authenticated *reader* exposes from those preexisting synthetic rows.

## Signed positive/negative expectations

The actual raw `operating_requirements_owner_self_api_v1` HTTP response must expose **only C21** in the one C1 register Case. The driver also examines the entire serialized packet for all denied original IDs/titles, rather than trusting a filtered Atlas adapter.

Actual independently signed worker (including forged `user_metadata.is_owner=true`), other-Ledger member, no-seat person, anonymous request, wrong Organization and wrong native Ledger must be denied. After initial positive, withdrawing C21's evidence in the disposable database must change the *same signed owner's* answer to an empty **current qualifying** list; it must not erase historical Work. Then revoke the native principal root, native seat and signed auth session separately, and verify every later signed attempt is denied.

Read-only snapshots of preexisting Atlas Work and Clock table rows are compared before and after the reader and denial probes. Work, allocation, Result, planning, Clock and requirement data are **not** to change. The test's allowed local setup and revocation mutations are explicitly separate from read behavior; withdrawing the relevance row is not an original Work/Result/Clock mutation. No writer, assignment, completion or automatic successor is invoked.

## Not yet proved / mandatory next gate

1. **Source law:** the owner must affirm the exact per-original selected-Ledger relevance rule in #2668. A governor's broader Organization read must not silently broaden this native-Ledger-specific Case endpoint.
2. **Current-schema validation:** review this fixture against the real PG17 clone *without touching production*; confirm required SQL columns, triggers, role/ACL parity, and that every test-row insert is lawful for the fictional database. The static tests do not establish execution.
3. **Source-verified evidence case:** add one separately proven `source_verified` original, then withdraw its exact source object without rewriting original evidence; test that it disappears. Current C21 uses **owner-attested** evidence, which is not equivalent to source verification.
4. **Historical fidelity:** distinguish the inactive link from the withdrawn relevance; an empty `canonical_work` array proves only zero **currently qualifying active** linked Work. It must not be sold as a complete Case history.
5. **Protected signed test controller:** separately review and pin exact main/controller, C1 fixture, proposed function, test script, fixture source, relevant hash and authorization gates in a trusted existing disposable-schema lane. Run the genuine signed job **only after a distinct owner-authored approval**. Never run from this PR or an edit to #2667.
6. **Release:** successful source-only CI or signed clone is not permission to merge #2668 / Atlas #551, install SQL in production, change GRANT/RLS/identity, expose a general Case UI, cancel history, or extend Titus.

**Current evidence accounting:** static source prepared; actual clone fixture/GoTrue execution **NOT RUN**; signed C2 acceptance **NOT ESTABLISHED**; no production or app state changed; historic #2665/#2666 and protected #2664 remain untouched.
