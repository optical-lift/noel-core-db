# Atlas connected-Person prerequisite reader — review-only candidate

## Purpose

The canonical Work prerequisite **writer** is installed in production (migration `20261022182439`). Genuine signed GoTrue + PostgREST testing passed on the disposable clone in run [#39872823272](https://github.com/optical-lift/noel-core-db/actions/runs/39872823272). The owner-only candidate and original-relation APIs do **not** authorize connected people simply because they have a native Ledger seat.

The missing integration is a **read-only** projection of original prerequisites to a Person who is currently responsible for the specific downstream Work. No second relationship store or worker permission to establish/withdraw dependencies is required.

## Proposed source contracts

- `atlas.connected_person_work_prerequisites_self_api_v1(org,ledger,downstreamWork)`: stable private database function requiring live session (`reality_access_self_api_v1.state = ready`), canonical Person, current participating Ledger connection, a current original *responsible* Person-native Work allocation to the exact downstream Work and current Work-to-Ledger relevance.
- `public.connected_person_work_prerequisites_self_api_v1`: authenticated-only entrypoint. Anonymous denied; direct authenticated execution of the private function denied.
- The original `atlas.work_item_relations` remains truth. Only `active = true`, `relation_kind = depends_on`, same Organization and presently evidenced same Ledger prerequisite relations are projected, with original relation ID, prerequisite Work ID/title/state and original `satisfied_at`. Recorded `satisfied_at` is **not** a computed satisfaction or completion claim.
- An unauthorized Work or Person returns an error (`42501`), *not* an empty collection. A verified authorized downstream Work with no active prerequisites returns `relations: []`.
- The governing-owner APIs and existing Company Work/Person authorization remain **unchanged**. A seat alone is insufficient. No employee-seat concept is used.
- Scope: active responsible allocation to open Work, or completed responsible allocation to completed Work. Person-native establishment kinds only: receiver uptake, accepted standing-scope delegation or direct Ledger connection assignment.

## Source exposure boundary

The assigned Person can see a prerequisite's title **only** when a currently active canonical dependency edge exists from their assigned Work, and the prerequisite has independent active relevance to the *same* Ledger. They cannot search the Ledger's other Work, read private audit-event authors, list other allocations, or establish/change relationships. This is derived from **work-specific responsibility**, not broad Ledger connection ownership.

No automatic blocking, completion, status change, or new Work records. Historical inactive links are excluded from this worker-current view; the owner retains the governed original history reader.

## Mandatory verification before generation/release

1. Review source-only SQL and clone-catalog assertions in `proposals/`; never run proposal SQL directly in production.
2. Construct a **source-admitted** disposable fixture that uses four local GoTrue identities (owner, connected recipient, other-Ledger participant, and no-seat). Create a real governed `ledger_connection_direct_assignment` using the existing authenticated `connected_ledger_direct_assign_self_api_v1` command, rather than falsifying the provenance required by `guard_work_allocation_responsibility_establishment_v2`.
3. Have the genuine signed owner link that original downstream Work to another evidenced Work on the same Ledger. Verify the recipient reads the exact original relation and title, cannot use owner-only APIs, and cannot read another Work for which they lack an allocation. Verify outsider/other-Ledger/anonymous/invalid session/revoked seat denials and honest empty results after withdrawal.
4. Verify no new/worsened database advisor findings, original Work read parity, non-leaking records, and unchanged `depends_on` cycle/event guards.
5. Stage reviewed SQL under `candidates/atlas/` and use the canonical owner-gated CLI generator to produce a numbered migration; run protected production-schema clone with the signed fixture, receive successful artifacts, and use protected release. Do not invent migration timestamps.
6. App adapter in draft Atlas PR #358 is **unmounted** until backend release and the remaining Today/no-loss + real notebook tests are demonstrated.

### Why the fixture remains unresolved in this review-only proposal

The existing `atlas.work_allocations` guard rejects fabricated bare allocations. A synthetic row lacking the actual governed establishment evidence would create a misleading green test and must not be used. Use the existing source command to create the assignment on the disposable local server before verifying the proposed reader. The proposal is **not deployable** until that end-to-end test is in place.
