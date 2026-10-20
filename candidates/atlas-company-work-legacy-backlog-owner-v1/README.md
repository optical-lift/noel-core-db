# Atlas Build 5 — Venue-first archived Company Work recovery

Release lane: `atlas`. Candidate name: `atlas_company_work_legacy_backlog_owner_v1`.

## Audited production starting point (2026-10-20)

- Elm organization: `fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2`.
- Elm Venue Ledger: `8df18008-28ef-48e9-babd-1eb0e0dd7e3c`.
- Canonical Marshall: `da09e489-4bc7-47e6-9ba1-12e1db60906d`; historical Elm person `3105e113-d73f-4f9f-b7e1-c112eb26e87b` has an active owner-approved identity reconciliation.
- 37 historical tasks bearing Marshall association were not in a completed status. 34 archived sources had **no** canonical Work link; 1 blocked had no Work link; 2 open tasks were **already linked to canonical Work**.
- 8 archived records were explicitly tagged `metadata.collection_zone=Venue`, `metadata.executor_label=Marshall`, with no canonical Work link at audit time. This is the **first recovery batch**. Private House, attic, basement, farm and outdoor candidates are deliberately not relabeled as Venue.

## Behavioral contract

1. Only authenticated current owner with both governing roots and a native Ledger seat can read or decide.
2. UI and RPC read archived original `atlas.tasks` for evidence. No task status, due date, assignee, title, metadata or original pull pool state is modified. Archived means **no recorded completion**, not proof of incomplete physical work.
3. Each Owner has three explicit decisions: **needed and distinct** (one new unassigned open `atlas.work_items`), **already covered** (bind reviewed legacy evidence to an existing exact canonical Work), or **not current** (no Work). Every decision is captured with original task title/status/metadata/note snapshots, decision reason, native Ledger and canonical owner.
4. A unique canonical legacy-source index plus transaction advisory lock and unique review decision key prevent source duplication. Exact active-title duplicates are blocked and must be matched rather than re-created. Semantic equivalence remains an Owner judgment, explicitly attested with reasons.
5. Original executor label is shown as historical evidence; canonical Person ID is presented only if there is a real former user-membership link through `organization_person_canonical_reality_v1`. Text matching in the People UI is merely a visible *review filter*, never binding proof.
6. No automated assignment, `work_allocations`, employee seat, plan, Worker Day projection, Today placement, or task completion. When owner confirms Work belongs to selected Ledger, the owner-attested Ledger relevance is separately recorded. Existing Work can then be offered under the current universal connection protocol.
7. The first view focuses on the existing `Venue` source zone; both RPCs are parametrized by source zone so future batches can reuse the same governed mechanism without person-specific exceptions.

## Release and validation

1. Review this candidate in noel-core-db, merge to `main`.
2. Create OWNER issue titled `Migration generation request: Atlas atlas_company_work_legacy_backlog_owner_v1` with `release_lane: atlas`, `migration_name: atlas_company_work_legacy_backlog_owner_v1`, exact candidate SHA on main, `candidate_path: candidates/atlas-company-work-legacy-backlog-owner-v1/candidate.sql`, `fixture_path: none`, `validation_path: candidates/atlas-company-work-legacy-backlog-owner-v1/postconditions.sql`.
3. Review generated migration PR and production-clone validation, merge only with green gates.
4. Manually run governed Production Database Release on main for that migration. **Do not paste candidate SQL directly into production.**
5. Only then merge/deploy the Atlas app PR using its regular protected production release. Verify original 8 Venue candidates appear after selecting Marshall / original executor label, and no canonical Work appears until an actual owner decision.
6. Record owner outcomes on two test cases: `not_current` creates no Work; `recovered_new_work` creates exactly one Work, survives reload and preserves original source unchanged; re-try must not create another. Test `matched_existing_work` reuses exact current Work. Ensure no auto allocation or Today delivery.

## Not in scope

- Bulk activation of 34 archived sources, automatic Marshall assignment, relocation of Private House/outdoor work to Venue, Task resurrection or use of the old Finish Elm `pull to Today` RPCs.
- Future recovery of farm/outdoor/house sources can use the same generic RPCs but needs its own source-zone and owner review.
