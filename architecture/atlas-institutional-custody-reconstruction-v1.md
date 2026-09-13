# Atlas Institutional Custody Reconstruction v1

## Purpose

Correct the historical mixed `feast_guild` production container now that Ledger Graph v1 is live, without rewriting or deleting historical evidence.

This tranche establishes fresh canonical Elm Farm and Feast Guild institutions, establishes separate Elm Farm and Elm Venue Ledgers, archives the Waiting Room test scope and owner-level test/project scope in the legacy portfolio container, and introduces explicit adjudication evidence for historical rows whose original foreign keys must remain as historical custody.

## Governing laws

1. **Historical container is not canonical owner.** A legacy `organization_id` proves where Atlas stored a row at the time; it does not override stronger institutional evidence.
2. **Canonical custody must be explicit and independently queryable.** Historical foreign keys may remain untouched when changing them would rewrite history or create integrity risk.
3. **A Ledger is a governing boundary, not an Organization synonym.** Elm Farm and Elm Venue are separate Ledgers even when the same Elm Farm Organization participates in both.
4. **Names are labels, never identity.** New Organization and Ledger stable identifiers are opaque random alphanumeric values.
5. **Authority is direct Principal -> Ledger authority.** Lex governs Elm Farm, Elm Venue, and Feast Guild through explicit root authority; legacy `principals.organization_id` remains compatibility/history only.
6. **Feast Guild starts empty.** No historical Elm, Waiting Room, customer, supplier, task, work, communication, order, farm, membership, position, responsibility, or identity state is inherited into the new Feast Guild institution.
7. **Anna is the sole active Elm employee.** Her new canonical Elm employment relation is explicit; Lex governs Elm through Ledger authority, not by inheriting the legacy owner membership.
8. **Waiting Room remains test history only.** Its farm/unit and directly associated work are archived in the legacy portfolio scope and are not promoted into a new institution.
9. **Owner-level projects remain portfolio history only.** Nathan/Camp Duffel and rehabilitation-house work are archived in the legacy portfolio scope and are not assigned to Elm or Feast Guild.
10. **No destructive deletion.** Existing IDs, timestamps, event revisions, source provenance, and legacy container references remain preserved.

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
- Farm Steward Position `badd2192-28a7-4913-aa90-e7076cb419f5`
- Position Appointment `1baf1031-cbe3-4520-9b5d-485bb5c9a59c`

Waiting Room historical anchors:

- Organization Unit `999569f3-8ae5-4bd0-b74d-f586b6b39d8d`
- Farm `f6592422-cf2b-4375-ba8f-f00828a05c18`

Evidence already established in production:

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

Introduce an append-only adjudication relation for historical records:

`atlas.institutional_custody_adjudications`

Each adjudication identifies an existing historical subject and records:

- subject schema/table/kind/key;
- historical Organization / Organization Unit / Farm / Ledger when known;
- canonical Organization and optional canonical Ledger;
- disposition: `reassigned`, `archived`, or `unresolved`;
- evidence basis and evidence payload;
- adjudicated timestamp and metadata.

The historical record itself does not need to have its original foreign keys rewritten for Atlas to know its canonical custody.

### Elm evidence rule

A historical row is canonically Elm when direct evidence names the Elm Farm or Elm Unit, including:

- `farm_id = 6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f`, or
- `organization_unit_id = 1b65ac99-0f00-4ca2-9488-e8539cae2a1b`, or
- it is an institutional identity record proven to belong to the 139 Elm external relationships or Anna's institutional identity.

Rows may additionally receive an Elm Farm or Elm Venue Ledger adjudication when the domain itself proves the governing boundary. Lack of sufficient Ledger evidence is not permission to guess.

### Venue evidence rule

Venue-specific records may be assigned to Elm Venue Ledger when their semantic domain proves event/venue operation. Farm production, flower production, crop, harvest, growing, field, postharvest, and farm-care state belong to Elm Farm Ledger. Cross-cutting Elm organization records may remain Organization-adjudicated with Ledger unresolved until stronger evidence exists.

### Archive rule

Waiting Room and owner-level portfolio work remain under the archived legacy portfolio Organization as historical evidence. Their adjudication disposition is `archived`, not reassigned to Elm or Feast Guild.

## Legacy container treatment

The historical Organization is relabeled/reclassified as a legacy Principal/portfolio container and archived. Its previous label and stable key are preserved in metadata. Its mixed Ledger is retired, and its active compatibility-primary participation and root authority are ended.

The Lex Principal's legacy `organization_id` may continue to point to this archived portfolio container for compatibility/history; it is not authority truth.

## Elm people / structure

The new Elm Farm Organization begins with:

- Lex root authority over Elm Farm Ledger and Elm Venue Ledger;
- Anna as the only active Elm member/employee;
- an active employee seat for Anna;
- Farm Steward structure carried forward canonically with preserved historical source references;
- no inherited Katie or Marshall active membership.

Historical membership/seat/position rows remain preserved in the legacy container. New canonical Elm relationship rows are created rather than rewriting old relationship history.

## Feast Guild clean-room rule

The new Feast Guild Organization and Ledger contain only:

- opaque Organization identity;
- opaque Ledger identity;
- Organization <-> Ledger participation;
- Lex root authority.

No membership, employee seat, farm, unit, identity subject, external relationship, communication, order, position, responsibility, task, project, work item, or legacy Ledger entry is copied into Feast Guild.

## Validation requirements

A production-schema clone must prove:

1. historical IDs and row counts are preserved;
2. legacy mixed Organization is archived and relabeled;
3. legacy mixed Ledger is retired and its participation/authority ended;
4. fresh Elm Farm and Feast Guild Organizations have opaque stable keys unrelated to their names;
5. Elm Farm, Elm Venue, and Feast Guild Ledgers have opaque stable keys;
6. Lex has active root authority across all three new Ledgers;
7. Elm Farm Organization actively participates in both Elm Ledgers;
8. Feast Guild Organization participates only in Feast Guild Ledger;
9. Feast Guild has no inherited operational/commercial/institutional rows;
10. Anna is the sole active Elm organization membership and has one active employee seat;
11. Waiting Room and owner-level project/task evidence remains historical and is adjudicated archived;
12. Elm evidence is adjudicated to the Elm Organization without changing historical source IDs;
13. all six historical Organization Ledger entries remain unchanged in identity/revision and are canonically adjudicated to Elm Farm Ledger;
14. direct browser access to custody adjudications remains denied;
15. no existing communication capture/send state is enabled or mutated as a side effect.

## Explicitly out of scope

This tranche does not invent Feast Guild customers/suppliers/orders, does not enable email capture or sending, does not delete historical test data, and does not force uncertain cross-cutting Elm records into Farm versus Venue Ledger when the evidence is insufficient.
