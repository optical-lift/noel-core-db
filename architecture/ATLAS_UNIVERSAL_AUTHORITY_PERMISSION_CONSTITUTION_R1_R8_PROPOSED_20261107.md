# Atlas / Noel — Universal Authority & Permission Constitution
## Decision record, Rounds 1–8 — reviewable DRAFT, 2026-11-07

**Status: PROPOSED HUMAN DESIGN, NOT ADOPTED SOURCE LAW.**
**Owners:** human constitutional decisions in the conversation; source custody and executable authority remain in \`optical-lift/noel-core-db\`; \`optical-lift/atlas\` composes released readers/commands.
**Existing design lane:** Noel [draft #2254](https://github.com/optical-lift/noel-core-db/pull/2254); related first exact-Ledger Flower grant [issue #2255](https://github.com/optical-lift/noel-core-db/issues/2255), held source-audit [draft #2263](https://github.com/optical-lift/noel-core-db/pull/2263), Atlas connected-Person notebook [#437](https://github.com/optical-lift/atlas/issues/437).
**Boundary:** This new document changes neither the earlier candidate \`architecture/ATLAS_NATIVE_LEDGER_RELATIONSHIP_DERIVED_ACCESS_V1.md\` nor \`atlas.features.yaml\`, the Atlas Authority Graph, delegated-agent rules, security checks, database grants, real user permissions, migrations, or production. Where the human selections contradict those sources, they are deliberately marked **REQUIRES GOVERNANCE ADJUDICATION**. This is not a release request or permission to bypass current checks.

## A. Decision interpretation and precedence

The eight rounds are **80 source design answers**, not 80 independently consistent executable rules. A later explicit answer revises an earlier answer **only for the same question**. Where two answers concern distinct layers (record custody versus permission; creation versus transfer; administrative display versus durable evidence), preserve both distinctions. Where they genuinely cannot coexist, preserve the conflict rather than manufacture consensus.

The final ten answers were supplied as free text:
- **71 — “Like a google doc.”** A *single original Bed identity* can be jointly governed/collaboratively edited by multiple authorized Ledger participants, with access/edits attributable to each actor. This is a *collaborative-editing analogy*, not a request to use Google Docs, nor a grant of unrestricted editor rights to every connected Ledger.
- **72 — custody transfer versus usability.** Two different operations: move the **custody/authority** of the original, or establish a **bounded use/reference** from another Ledger. Example: Venue tags a Flower Bed and creates Venue Work associated with it **without owning the Bed**. Do not infer custody transfer from referencing or attaching Work. Whether an actual custody transfer can be caused by a Zone move remains **unresolved** against earlier 69B.
- **73B — imported copy.** The receiving Ledger may govern local storage; reading and redistribution of its contents stay bounded by original disclosure rights.
- **74A — position activation.** Acceptance of an institutional position is proposed to activate its associated operations **and information access**, with visible source-backed checkboxes allowing authorized revision of that permission. This is a material **proposed exception to the existing no-role-as-content-grant law**, not currently executable.
- **75 — simultaneous roots.** Multiple independent root governors **may coexist concurrently** over one Ledger; never presume exactly one. This supersedes prior question wording presuming a lone root governor. Succession/absence/replacement must evaluate the actual current set of governing authorities.
- **76A — upstream chain lost.** Dependent powers become ineffective immediately, while the chain remains recorded until explicitly closed.
- **77D — vacancy assertion.** A connected Person's declaration is effective to establish the relevant governor vacancy **only after confirmation by another distinct connected Person**; whether such a declaration can change authority without additional source evidence is a major unresolved security issue.
- **78C — emergency governor.** An independently established emergency auditor receives temporary root authority **until the named successor takes office**. This is not necessarily a full-Ledger vacancy when another active root governor already exists.
- **79D — compaction/deletion.** Permission decisions are periodically summarized, reviewed, then their original events erased. This conflicts with current append-only/provenance and immutable-decision protections; **no deletion mechanism is authorized or proposed for implementation** until a reviewed source- and legal-retention-safe replacement proves provenance, dispute resolution, and required audit can remain truthful.
- **80C — any independent allow.** At least one valid active granting chain can authorize access despite a denial from another chain. This **revises 40A** (blanket denial wins) and qualifies **46D** (denial local to its own chain). It cannot on its own expand original source custody, defeat separate confidentiality law, or turn an invalid grant into a valid one. Whether absolute source-level prohibitions can override the union of grants remains **unresolved**.

## B. Proposed general structure

### B1. Authority is not one ranking

Preserve distinct domains of:
1. **Identity / relationship:** who a Person/Principal is, connected to which exact Ledger and Organization.
2. **Original governance:** Ledger founding and concurrent current root governing authority.
3. **Information authority:** which source fields and subject records can be disclosed.
4. **Operational authority:** source-defined permitted operations on real subjects.
5. **Decision / approval authority:** authority to accept, adjudicate, and issue specified consequences.
6. **Granting / delegation authority:** which permissions one may confer to whom, within which chain.
7. **Responsibility:** durable institutional position responsibility and exact original Work allocation; neither is an execution warrant.
8. **Current execution authority:** whether a Work operation is presently fitting and source-permitted.
9. **Custody / source jurisdiction:** which source owns original record identity and transition; distinct from another Ledger's ability to refer, observe, or make its own Work.
10. **History/retention authority:** access to prior outcomes and decision evidence, separate from current field disclosure.

Existing authorizing source functions and source-owned command law govern **today**. Do not create a global catch-all permission table, reinterpret a role name as effective authority, or make the application the security owner merely to implement this draft.

### B2. Founding, roots, and successor

- **Creation (11A/21A/31A):** intended initial Ledger creator receives original root governance and may propose/select what enters their Ledger.
- **Multiple roots (75):** one Ledger may have multiple concurrently effective, independently attributable root governors; none is implied to be the sole root. An action requiring “root governor” means a source-verified currently effective root with sufficient jurisdiction for that action, not an arbitrary root recorded in app state.
- **Existing subject admission (41D→61C; 43D; 73B):** choosing to include, reference, copy, or request transfer does not magically seize another source's original. A local copy can have its own custody while retaining provenance and disclosure limits. Explicitly distinguish original record transfer, immutable reference, lawful copy, and relationship/use.
- **Root information (22A):** selected design would give a root governor all information properly *belonging* to that Ledger. This must not be used to acquire data merely by labeling it as belonging, nor to bypass the original source's retained disclosure constraints on copies. **REQUIRES GOVERNANCE ADJUDICATION** versus current independent knowledge authority.
- **Succession (32D, 47A, 53A, 58B, 75, 78C):** root changes are source events and may preserve valid grants; succession order should be pre-established. Model departure of one root separately from absence of all roots; do not trigger global emergency succession if another root is governing. Draft 53A says previous grants survive regardless of conditions, conflicting with 8D/76A; see hold H3.
- **Vacancy (56B→77D):** two *distinct currently connected* Persons' attestations would be required under the user's chosen direction, with an original unverified report distinguishable from the second confirmation. **Do not implement authority transfer based solely on these assertions until the exact source, challenge/recovery and co-governor semantics are adjudicated.**
- **Emergency auditor (38D/48D/57D→78C):** independent beforehand authority may allow bounded audit; proposed emergency root elevation lasts only until a named successor is active. No ordinary auditor becomes root from merely viewing a history screen.

### B3. Position, assignment, information, and grant review

- **Position acceptance (51C→74A):** the accepted appointment is intended to activate a defined package of operations *and information* permissions, with governor-controlled revision checkboxes. Every checkbox must correspond to a released source-owned operation, field, scope, effective condition, and real authorized writer. Unreleased capabilities show unavailable, not a fake grant.
- This **revises Round 1's general principle that a responsibility only proposes information access**. It does *not* rewrite the currently released \`effective_person_organization_responsibilities_current_v1\` semantics, native Ledger Seats, existing Work identity, or execution gates. Explicitly review appointment lifecycle, operator consent, decision provenance and source eligibility before promotion.
- **Exact Work (3D/23D/45C/67B):** assignment alone does not reveal private Work title/details. Zone permission may yield a **limited associated Work title** only when the title itself is lawfully discoverable; instructions are not inherited. If the title reveals an undisclosed Person or activity, hide the Work entirely. The coexistence of a genuinely assigned Work and no disclosed instructions must have a truthful blocked/ready path, not a fake Work card or leaked text.
- **Proposals (5D/16A):** source-known responsibility, Person-initiated broad requests, and governor review can each propose capability changes, but do not enumerate hidden subject identities to unauthorized requesters.
- **Grant inspection (14A/25A):** delegating granting authority is intended to permit inspection of the information the delegate can grant, within the actual granted jurisdiction. This is a material exception to presently separate knowledge and grant authority, and requires its own explicit source-law review.
- **Permission interface (74A):** checkboxes display current source-effective rights and approved change operations, not synthetic front-end claims. Multiple roots may each act only when their exact authority is valid; concurrent conflicting approvals need source-level serialization and provenance.

### B4. Shared physical subjects: the Google Doc analogy

**Stable physical original:** A real Bed has one enduring canonical Bed identity and a source-accountable history. Multiple Ledgers can have **concurrent governed participation** in it, analogous to collaborators using the same Google document rather than maintaining incompatible duplicate originals.

**Different relationships, different powers:**

| Relationship | Flower example | Venue example | Not automatically conferred |
|---|---|---|---|
| Original Bed custody | Authoritative biological/physical Bed maintenance, as established by source | None merely because Venue uses it | Custody from tags, references or Work links |
| Permitted use/reference | Reads/acts within Flower authority | May tag/locate the Bed in a Venue plan | Editing original Bed data |
| Source-specific Work | Flower Work with original identity, allocation, result | Venue Work whose context references the *same* Bed | Ownership of Flower Work or original Bed |
| Collaborator edits | Explicit source-approved edits to Bed attributes | Only if additionally granted | Blanket full editing from shared visibility |
| Visibility | Zone/crop fields subject to Flower permission | Source-approved permitted operational fields | Finance, personal notes, sensitive titles or instructions |

**Two independent source relations are essential:** (a) \`acts_on\` / \`references\` / \`uses\` a subject; and (b) **custody transfer** of that original. Neither should infer the other.

**Shared edit collisions:** At least two governors/editors may initiate overlapping edits. Use existing source concurrency/version and attribution rules. Two Ledgers must not independently rewrite two incompatible copies of the same original. A single Bed's current custody, operating scope and exact source permission for each field remain adjudicable.

**Zone inheritance (26A/27A/36A/59A/65D/66C/67B/68C):** source-confirmed current membership can dynamically bring a Bed into permitted operational categories; new Bed members inherit the authorized categories, subject to original source jurisdiction. A move out removes that Zone-derived current access. Source-separated sensitive information is not pulled in merely because it references the Bed. Work instructions remain separately governed; even titles disappear when protected existence would otherwise be disclosed.

**Movement and custody (69B→72 free text):** the earlier selected answer treated moving Beds between Ledgers' Zones as immediately transferring original custody. The user has now clarified that moving or tagging for Venue use is *not necessarily custody transfer*. Mark 69B as **NOT UNIVERSAL**. An actual custody transfer has distinct source conditions still to be established; do not infer it from geometry, tags or use relationships.

### B5. Permission truth and end conditions

- **Proposed evaluated envelope:** \`signed Person + current Ledger identity + establishment source + authority chain + exact operation + subject/source scope + information field + effective conditions + current source facts + revocation state\`. Present lawful Work execution is evaluated independently from mere access.
- **Independent grants (46D/52B/80C):** multiple chains may carry the same permission. If one chain is revoked, its dependents are ineffective, yet another independent valid allowance can remain. A denial tied to one chain alone does not eliminate the other. An expressly source-owned mandatory prohibition might still stop access across all chains: **unresolved** under literal 80C, not silently assumed.
- **Dependency loss (37A/54B→76A):** upstream revocation/expiry makes dependent powers ineffective immediately, while recorded chain metadata stays until formal closure. The current root governor's exclusive **formal whole-chain termination** authority (54B) is distinct from current-power invalidation.
- **Expiry (8D/24D/28A/50D):** active conditions are rechecked at request time. When a permission ends, new protected reads and commands fail even on a previously signed-in session. Previously delivered information is a separate governed custody/retention question.
- **Denial history and compaction (60A/79D):** chosen design wishes to retain a periodic reviewed summary and erase original decision events. This is **in direct conflict with current append-only and preserve-provenance source governance**, and with the independent-auditor and chain-proof expectations. The intended result is faithfully recorded here; **no event erasure, truncation, migration, deletion command, or altered audit policy is approved**. A future separately reviewed retention proposal must prove how disputes, stale decisions, governance transfers, revoked grants and legal retention remain accurately reconstructible. If it cannot, this particular choice cannot be safely adopted.
- **Universal field grammar (12B/30A/39A/49A→70B):** every exposed subject uses a standard field grammar. Empty presentation slots are permitted, but an unknown, absent, withheld, missing, or not-applicable original fact must remain separately truthful in the underlying source; do not fabricate source facts. Candidate standard field families: identity/title, instructions, location, attachments, history, status, and source/domain extensions. The precise canonical field registry is **not yet approved**.

## C. Canonical conflicts: explicit holds, not silent reinterpretation

| Hold | Proposed user design | Existing source/governance conflict | Required decision/proof before executable change |
|---|---|---|---|
| H1 — ledger founding and imported jurisdiction | 21A/22A/31A, revised 61C/73B | Source custody and knowledge authority cannot be acquired merely by copying or creating a Ledger | Define truthful founding/entry/participation/transfer and what root can read, with independent Flower and Venue examples |
| H2 — appointment powers | 51C/74A accepted position grants operations and information | Current \`atlas.features.yaml\` and Noel #2254 treat responsibility/position as distinct from permission | Admit exact versioned preauthorization and checkboxes without implicit role wildcard or a separate permission engine |
| H3 — inherited grants and expiry | 47A/53A all grants survive succession; 76A and 8D stop ineffective powers | Unconditional survival conflicts with current validity/expiry and revocation | Distinguish survival of grant record from survival of effective permission; clarify multiple-root changeover |
| H4 — emergency succession | 75 multiple roots; 77D two-person vacancy confirmation; 78C auditor temporary root; 58B named automatic successor | Existing root source/Principal authority and delegation must not be replaced by unverified claims; co-roots affect what vacancy means | Source-defined per-governor vacancy, abuse resistance, distinct authenticated confirmations, successor eligibility and exact emergency period |
| H5 — decision history compaction | 60A/79D erase originals after reviewed summary | Current durable provenance, append-only decision protections, audit and security history | Prove lawful retention, replay/verification/audit equivalence before any archival/deletion design; do not erase existing events |
| H6 — dynamic shared-Bed custody | 64B and 71 collaborative original; 69B move transfers custody; 72 distinguishes use from transfer | Exact source and Ledger custody cannot be inferred from moving geometry, or from ordinary context links | Versioned shared-subject collaboration, source original owner/custodian, bounded Venue use, explicit governed custody transfer independent of tagging |
| H7 — independent allow | 80C active allow wins over unrelated chain denial | Other source confidentiality/custody and mandatory deny policies may have higher-order jurisdiction | Distinguish valid independent grants from source-owned overriding prohibition and deny-by-default |
| H8 — root read-all and delegated-grant read | 22A/25A joins governance/grant with knowledge | Current dimensions and source-local disclosure prevent automatic read broadening | Review exact owned fields, external copies, third-party privacy, independently signed governor/worker/outsider negative tests |
| H9 — standard universal fields | 39A/49A/70B universal field and empty display | Current sources do not all have identical fields or semantics | Define optional semantic mapping with truthful unknown/withheld distinction and no synthetic content |

**Do not use a green code/static check as permission to implement any H1–H9 change.** Existing released functions and RLS remain authoritative pending separately reviewed, domain-owned revisions.

## D. Design boundary and bounded next implementation train (NO IMPLEMENTATION AUTHORIZED HERE)

1. **Owner review of this proposed constitution:** Record the 80 human decisions and the free-text final answers, plus H1–H9 as *unresolved constitutional change requests*. No further multiple-choice round is required to prepare the draft; future questions can be specific to blocking proofs.
2. **One narrow source-proof specification:** Existing Noel issue #2255 first Flower proof; one real Bed, one Flower root, a Venue root/participant, two distinct governed Ledger participations; Flower retains original Bed custody while Venue may read the permitted identity, reference it, and establish original Venue Work context. Test that Venue cannot edit Flower crop/Bed state or see financial/private data without its own lawful grant. Do not copy the Bed or make a second original.
3. **Position-authority candidate separately:** Define the precise preauthorized checkbox envelope of an accepted appointment and the difference between direct authority, information disclosure, Work allocation and execution warrant. Avoid shipping a generalized role-as-admin path.
4. **Co-root and succession proof separately:** Two concurrent real root governors with distinct signed sessions and a common Ledger; conflicting decisions, revocation, individual-root vacancy, both-roots unavailable, independent auditor, successor interval. No trigger based solely on a UI's report.
5. **Gate 0 actual carrier proof:** Continue existing held Noel #2263 rather than creating competing permissions. Test already-live My Work, Today, dated Work, Worker Day, Farm SQL readers and current Atlas Index/Event/media caches with genuine independent signed GoTrue/PostgREST accounts on disposable full-schema clone, including valid worker-positive Work/Done/history.
6. **Only then** source-specific held grant writer and field reader review, protected clone, signed negative/positive receipts, exact authorized migration, separate governed release, and the existing Atlas Ledger → Connections → Person notebook UI. No new production source or grant is inferred from this design document.

### Acceptance example — Elm Farm Flower / Elm Farm Venue

> Flower's source-governed physical Bed B is a single enduring original. Venue can, when authorized, reference B and attach its own original Work “prepare a photo station adjacent to B” to that Bed. Flower and Venue may both have current governors and legitimate overlapping participation in B without cloning the Bed. Venue's reference/Work does not transfer custody or automatically reveal Flower planting operations, prices, another Person's Work details, or instructions. A separately authorized custody transfer changes who governs the original; a location move or tag by itself does not. The same actor, operation, subject, and exact field are checked against the current source facts at read/write time.

**Source/provenance note:** Existing Atlas Authority Graph and \`atlas.features.yaml\`, Noel native Ledger permissions draft #2254, held Gate 0 draft #2263, current farm custody release, and the attached Atlas delegated-agent governance are **current prior sources**; Rounds 1–8 are **human proposed choices**. No proposed choice retroactively authorizes a prior action, overwrites completed source history, or removes current source checks. This text is not a status certificate for SQL or runtime.


## E. Verified 2026-11-07 source gap — Venue use of Flower Bed (read-only catalog)

This section distinguishes verified **present production source** from proposed human architecture. These are SELECT-only function definitions, column names and index definitions; no writes, signed user tests, or migrations.

1. Released `atlas.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)` and its public wrapper exist. The function inserts an original Work's `spatial/growing_object/acts_on` context link with `confersAccess:false` and `createsWork:false`, after signed governor and source checks.
2. The active `atlas.guard_work_growing_object_context_v1()` trigger on `atlas.work_item_context_links` checks **all** `spatial/growing_object` links, regardless of relation name, and requires the provided exact Ledger to match `atlas.farm_crop_ledger_custody_v1` for the Bed's Farm. It additionally requires real legacy Work/task source, same farm/Zone and Organization Unit, native Ledger participation, active Work allocation, signed governor and reviewed identity. **Relabeling Venue's link or passing Flower's Ledger ID while using Venue Work would not establish lawful Venue use, and must not be used to evade these requirements.**
3. Active index `farm_crop_ledger_custody_one_active_v1` is unique per Farm for active custody. This carrier cannot represent two active crop-custodian Ledgers for Elm Farm. Google Doc-like collaboration must represent different authorized relations to **one original**, not a second Farm custodian.
4. `atlas.work_item_context_links` is unique by exact `work_item_id, subject_domain, subject_kind, subject_id, relation_kind`, so distinct original Works can refer to one Bed **if** each relation has an approved source establishment contract. Uniqueness alone provides no right to read, link, or edit.
5. `atlas.principal_ledger_authorities_active_uq` is unique per `(principal_id,ledger_id,authority_kind)`, **not** per Ledger. This catalog shape does not impose a one-root-per-Ledger restriction, consistent with concurrent multiple roots. Actual co-governor authorization and conflicting-write behavior require independent signed proof.

**Exact bounded next source outcome:** Preserve original Flower custody and existing `acts_on` trigger. Design a separate source-owned Venue `references`/`uses` authority **and** corresponding Venue Work-context establishment whose signed governor/Person is actually authorized for the Venue Ledger, the original Venue Work, and the particular Bed, without Flower custody or crop financial details. No new public RPC or grant is authorized by this design.

**Acceptance prior to release:** Flower original Bed unchanged; Venue real original Work may link only a permitted existing Bed; success creates neither custody nor duplicate Bed; exact Venue/Flower source proof; other Bed/Zone, unrelated Ledger/Organization and forged Flower principal denied; worker cannot self-authorize; revoked Venue relationship denies subsequent reads/actions; Flower `acts_on` and worker Work/Done still function; co-root actions attributable; hidden Work titles/instructions, finance and personal fields remain hidden; same JWT after genuine session revoke denied; independent real GoTrue/PostgREST signed tests on protected disposable full-schema clone. Only separately approved source migration and Atlas notebook release could change production.

**Current reality:** Venue use of Flower's Bed through the current custody command is **not implemented**. The constraint is a source guard to preserve, not bypass. The previously signed-live Flower Bed 3/4 associations remain unchanged.


## F. 2026-11-07 HELD Venue Bed-use source implementation candidate

The owner explicitly authorized moving from design to a bounded source build. On this **same** Noel design draft branch, a held and unreleased source candidate was added at:
- `candidates/atlas/venue_bed_shared_use_v1/HELD_source_candidate.sql`
- `candidates/atlas/venue_bed_shared_use_v1/README.md`
- `candidates/atlas/venue_bed_shared_use_v1/postconditions_DISPOSABLE_CLONE_ONLY.sql`
- `scripts/validate-atlas-venue-bed-shared-use-source.py`
- `.github/workflows/atlas-venue-bed-shared-use-source.yml`

The source implements two non-public, RLS-protected source relations and four distinct held internal operations: exact Flower governor offer, exact Venue governor acceptance, authorized original Venue Work → original Flower Bed use-reference, and withdrawal. A composite FK requires each Work reference to point to the **same Bed and Venue Ledger** as the accepted use. It reuses `atlas.reality_access_self_api_v1()` for current live-session checks, per-Ledger root authority and native Seats; current Flower Farm crop custody; and existing exact Venue Work-to-Ledger relevance. It does **not** create/copy Work or Beds; modify the original Flower Work-context trigger; grant crop content reads; change RLS of existing tables; release a migration; or expose public/internal functions to authenticated browser users.

**Different current source semantics:** A Venue-use reference remains in its narrow Venue source-owned relation. It has **not yet converged with the released universal `work_item_context_links` Work reader**; that integration is an explicit next proof gate, not license to weaken original Flower source guards. Current Venue Work relevance can be source-verified or lawful attested (source vocabulary); the new candidate does not magically upgrade attestation to direct source proof.

The unprivileged static safety test is evidence of source containment only. The clone-only structural checks fingerprint unchanged original Flower `guard_work_growing_object_context_v1()` (MD5 `2c7de5ef8fa2519a5afec4feecf28f4a`) and original Flower link writer (MD5 `d430424f04b3e27a09be3bae00f7d821`). Those are **read-only production catalog baselines**, not signed proof or evidence of a clone execution.

**Required before executable release:** protected disposable *full-schema* clone, Postgres SQL syntax/ACL check, exact signed Flower/Venue/root/worker/outsider/ended Seat/revoked-session tests, dynamic source withdrawal, concurrent root and action-ID replay, original Flower Work/Done and Event Work positive parity, information-field leakage audit, source-reviewed production migration and explicitly authorized deployment. The nine constitutional holds remain unpromoted. The single existing Atlas completion register is on draft Atlas PR #543.
