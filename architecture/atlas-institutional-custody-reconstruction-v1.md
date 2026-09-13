# Atlas Institutional Custody Reconstruction v1

## Purpose

Correct the historical mixed `feast_guild` production container now that Ledger Graph v1 is live, without deleting historical evidence or manufacturing false Feast Guild history.

This tranche establishes fresh canonical Elm Farm and Feast Guild institutions, establishes separate Elm Farm and Elm Venue Ledgers, archives Waiting Room test scope and owner-level portfolio work in the legacy portfolio container, and records explicit adjudication evidence before canonical custody changes.

## Governing laws

1. **Historical container is not canonical owner.** A legacy `organization_id` proves where Atlas stored a row at the time; it does not override stronger institutional evidence.
2. **Canonical custody must be evidence-backed and independently queryable.** When a preserved row is rehomed, Atlas first records historical custody in an immutable adjudication.
3. **Storage proximity is not evidence.** Sharing the legacy mixed Organization does not make a row Elm or Feast Guild. Generic composition, Noel, Local, or other cross-cutting records remain portfolio history unless stronger evidence proves custody.
4. **Evidence propagates through real relationships, not naming conventions.** Direct Elm evidence may move a row; dependent Organization custody may then propagate through actual foreign-key relationships from already-proven Elm rows. Table-name families and domain-name guesses are not evidence.
5. **A Ledger is a governing boundary, not an Organization synonym.** Elm Farm and Elm Venue are separate Ledgers even when the same Elm Farm Organization participates in both.
6. **Names are labels, never identity.** New Organization and Ledger stable identifiers are opaque random alphanumeric values.
7. **Authority is direct Principal -> Ledger authority.** Lex governs Elm Farm, Elm Venue, and Feast Guild through explicit root authority; legacy `principals.organization_id` remains compatibility/history only.
8. **Feast Guild starts empty.** No historical Elm, Waiting Room, customer, supplier, task, work, communication, order, farm, employee, position, responsibility, identity, composition, route, or Local state is inherited into the new Feast Guild institution.
9. **Anna is the sole Elm employee.** Her existing membership, identity subject, employee seat, credential, Farm Steward position, and appointment IDs are preserved while canonical Organization custody changes to Elm. Lex may hold a non-employee compatibility owner membership solely for existing Organization-owner read surfaces; that membership is not Ledger authority truth.
10. **Waiting Room remains test history only.** Its farm/unit and directly associated work are archived in the legacy portfolio scope and are not promoted into a new institution.
11. **Owner-level projects remain portfolio history only.** Nathan/Camp Duffel and rehabilitation-house work are archived in the legacy portfolio scope and are not assigned to Elm or Feast Guild.
12. **No destructive deletion.** Existing IDs, timestamps, event revisions, source provenance, and explicit historical-custody evidence remain preserved.
13. **Transport behavior is outside custody adjudication.** Moving Elm communication custody must not enable capture/send, change authorization state, alter granted scopes, change last-sync state, or revoke/activate a source.

## Known production evidence

Historical container Organization:

- ID `818b9a23-65e9-4198-b86c-9496ba548642`
- current label `Feast Guild`
- current legacy mixed Ledger `6dab72b7-cb2f-43eb-855e-c0c99756e0d6`
- scope marker `legacy_mixed_pending_adjudication`

Lex Principal:

- Principal `e99e759c-1a65-4ddc-ba41-91f72c5981d8`
- Person `59e9fd9d-e7fd-48ca-91e0-ee271c05148e`

Elm historical anchors:

- Organization Unit `1b65ac99-0f00-4ca2-9488-e8539cae2a1b`
- Farm `6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f`
- Anna Membership `4bda9631-07a6-43ae-9f51-4cb63d78c803`
- Anna Person `998e6116-6d9d-4ee5-9d48-6c239d58507b`
- Anna institutional Identity Subject `0b87334c-56e0-44c2-a7d7-57d6df60f705`
- Employee Seat `74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0`
- Member Credential `385673ab-cf4e-4dbe-8c1d-11cb244143f2`
- Farm Steward Position `badd2192-28a7-4913-aa90-e7076cb419f5`
- Position Appointment `1baf1031-cbe3-4520-9b5d-485bb5c9a59c`

Waiting Room historical anchors:

- Organization Unit `999569f3-8ae5-4bd0-b74d-f586b6b39d8d`
- Farm `f6592422-cf2b-4375-ba8f-f00828a05c18`

Evidence established in production:

- 1,287 / 1,295 historical tasks explicitly reference Elm Farm.
- 27 / 30 historical projects explicitly reference Elm Farm.
- 1 historical project explicitly references Waiting Room Farm.
- 8 root tasks and 2 root projects are owner-level / cross-farm portfolio work, not Elm or Feast Guild.
- all 96 Company Work items are explicitly Elm Unit scoped.
- all 139 external relationships are explicitly Elm Unit scoped.
- all 18 institutional conversations are explicitly Elm Unit scoped.
- all 7 commercial orders are explicitly Elm Unit scoped.
- all 6 existing Organization Ledger entries are explicitly Elm Unit production events.
- 139 of 140 institutional identity subjects are referenced by the 139 Elm external relationships; the remaining subject is Anna.
- 7,012 work-execution components explicitly reference Elm Farm.
- 4,609 work-execution relations explicitly reference Elm Farm.
- all 5 current operational routes carry the Elm Farm UUID in their own `metadata.farmId`.
- generic composition runs and a Noel recommendation lens also live under the old mixed Organization, but that storage fact alone does **not** establish Elm custody.

## Canonical institution shape after this tranche

```text
Lex Principal
  ├── root_governing -> Elm Farm Ledger
  ├── root_governing -> Elm Venue Ledger
  └── root_governing -> Feast Guild Ledger

Elm Farm Organization
  ├── participates in Elm Farm Ledger [compatibility primary]
  └── participates in Elm Venue Ledger [operating]

Feast Guild Organization
  └── participates in Feast Guild Ledger [compatibility primary]

Legacy Principal Portfolio Organization [archived]
  └── Legacy Mixed Ledger [retired]
```

## Canonical custody model

Introduce an append-only adjudication relation:

`atlas.institutional_custody_adjudications`

Each adjudication records:

- subject schema/table/key;
- historical Organization / Ledger when known;
- canonical Organization and optional canonical Ledger;
- disposition: `reassigned`, `archived`, or `unresolved`;
- evidence basis and evidence payload;
- adjudicated timestamp and metadata.

When a row is rehomed, its adjudication preserves the old mixed container as historical custody. The row ID and domain identity remain unchanged.

### Direct Elm evidence

A historical row is directly Elm when one of these is true:

- `farm_id = 6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f`;
- `organization_unit_id = 1b65ac99-0f00-4ca2-9488-e8539cae2a1b`;
- a custom custody column names that same Elm Unit, such as `connected_sources.custodian_organization_unit_id`;
- an operational route's own `metadata.farmId` names Elm Farm;
- the row is Anna's known institutional membership/identity chain;
- an identity subject is directly referenced by an external relationship already proven Elm;
- a responsibility scope explicitly names the Elm Unit;
- a known historical Organization Ledger entry explicitly names the Elm Unit.

### Relationship-derived Elm evidence

Once a parent row is directly proven Elm, Organization custody may propagate to dependent rows only through actual foreign-key relationships that bind those rows to the already-proven parent. This allows, for example, dependent identity identifiers, work allocations, communication children, route children, and commercial-profile children to follow their proven parent without declaring their entire table family Elm.

A special upstream rule applies to `identity_source_records`: a source record may move only after a moved `identity_source_subject_assertions` row proves that source record belongs to an Elm identity.

### Explicit negative controls

These remain in the archived legacy portfolio unless future evidence adjudicates them separately:

- generic `atlas.composition_runs` that have no direct Elm anchor;
- `local_intel.recommendation_lenses` whose only connection is the old mixed Organization;
- any other row whose sole evidence is `organization_id = 818b9a23-65e9-4198-b86c-9496ba548642`.

The migration itself captures pre-move counts for composition runs and recommendation lenses and aborts if they are silently promoted to Elm or Feast Guild.

### Ledger assignment

Organization custody and Ledger governance are distinct. A row may be proven Elm without enough evidence to choose Elm Farm versus Elm Venue Ledger.

- production, crop, harvest, growing, seed, flower, field, propagation, postharvest, and farm-care evidence may be adjudicated to Elm Farm Ledger;
- explicit venue preparation may be adjudicated to Elm Venue Ledger;
- cross-cutting Elm records remain Organization-adjudicated with Ledger unresolved when evidence does not justify a stronger choice.

### Archive rule

Waiting Room and owner-level portfolio work remain under the archived legacy portfolio Organization as historical evidence. Their adjudication disposition is `archived`, not reassigned to Elm or Feast Guild.

## Atomic integrity strategy

The existing schema contains many composite foreign keys that include Organization custody. The migration therefore temporarily makes only composite foreign keys that explicitly map child `organization_id` to parent `organization_id` deferrable for the transaction, moves the proven graph atomically, forces all constraints immediate, and restores those constraints to their original non-deferrable state before commit.

This must not alter unrelated foreign-key behavior. In particular, the preexisting `atlas.planned_work_occurrences_released_task_id_fkey` remains deferrable and initially deferred.

## Legacy container treatment

The historical Organization is relabeled/reclassified as `Legacy Principal Portfolio` and archived. Its previous label and stable key are preserved in metadata. Its mixed Ledger is renamed `Legacy Principal Portfolio Ledger`, retired, and its active compatibility-primary participation and root authority are ended.

The Lex Principal's legacy `organization_id` continues to point to this archived portfolio container for compatibility/history; it is not authority truth.

## Elm people / structure

The canonical Elm Farm Organization has:

- Lex root authority over Elm Farm Ledger and Elm Venue Ledger;
- Lex as a non-employee compatibility owner membership only where current Organization-owner read contracts still require membership;
- Anna as the only active employee seat;
- Anna's existing membership / identity subject / seat / credential IDs preserved and rehomed to Elm;
- Farm Steward position/appointment and the five responsibilities preserved by ID and rehomed to Elm;
- venue preparation adjudicated to Elm Venue Ledger; farm/production responsibilities adjudicated to Elm Farm Ledger;
- no Katie or Marshall active membership added to Elm.

## Feast Guild clean-room rule

The new Feast Guild Organization and Ledger contain only:

- opaque Organization identity;
- opaque Ledger identity;
- Organization <-> Ledger participation;
- Lex root authority.

No membership, employee seat, farm, unit, identity subject, external relationship, communication, order, position, responsibility, task, project, route, composition state, Local recommendation state, work item, or legacy Ledger entry is copied into Feast Guild.

## Validation requirements

A production-schema clone must prove:

1. historical row identities and fixed Ledger revisions are preserved;
2. legacy mixed Organization is archived and relabeled;
3. legacy mixed Ledger is retired and its participation/authority ended;
4. fresh Elm Farm and Feast Guild Organizations have opaque stable keys unrelated to their names;
5. Elm Farm, Elm Venue, and Feast Guild Ledgers have opaque stable keys;
6. Lex has active root authority across all three new Ledgers;
7. Elm Farm Organization actively participates in both Elm Ledgers;
8. Feast Guild Organization participates only in Feast Guild Ledger and inherits no operating reality;
9. Anna remains the sole active Elm employee seat, while Lex is not made an employee;
10. Waiting Room and owner-level project/task evidence remains historical and is adjudicated archived;
11. direct Elm evidence moves to canonical Elm without changing source row IDs;
12. dependent Organization custody moves only through proven foreign-key relationships;
13. generic composition runs and the generic recommendation lens remain in the legacy portfolio and receive no false Elm adjudication;
14. all six historical Organization Ledger entries preserve identity/revision and move to Elm Farm Ledger;
15. direct browser access to custody adjudications remains denied and adjudications are append-only;
16. no existing communication capture/send/authorization/scopes/sync/revocation state changes as a side effect;
17. temporary Organization-composite FK deferral does not remain in durable schema;
18. unrelated preexisting FK deferrability remains unchanged.

## Explicitly out of scope

This tranche does not invent Feast Guild customers/suppliers/orders, does not enable email capture or sending, does not delete historical test data, does not infer Elm custody from table names, and does not force uncertain cross-cutting Elm records into Farm versus Venue Ledger when the evidence is insufficient.
