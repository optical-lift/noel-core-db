# Atlas Institutional Custody Reconstruction v1

## Purpose

Reconstruct canonical Elm Farm and Feast Guild institutional identity after Ledger Graph v1 without rewriting historical truth, bypassing runtime triggers, or pretending the historical mixed `feast_guild` storage container was ever a clean institution.

This tranche is deliberately **additive and staged**. It establishes the correct canonical Organizations/Ledgers and an immutable effective-custody layer while leaving all existing production rows physically where they are. Runtime read/write cutover is a later controlled tranche.

## Governing laws

1. **No trigger bypass.** No production/runtime trigger may be suspended, disabled, skipped, bypassed, or made conditionally inert merely because custody reconstruction is in progress.
2. **Historical storage is evidence, not authority.** A legacy `organization_id` proves where a row was stored, not which institution canonically owns its reality.
3. **Immutable and append-only history stays physically immutable.** Custody is corrected by adjudication, not by rewriting source history.
4. **No false transient contradictions.** Reconstruction may not temporarily violate runtime guards and rely on transaction invisibility as justification.
5. **Canonical custody is explicit.** `atlas.institutional_custody_adjudications` records effective Organization/Ledger custody for preserved source rows.
6. **Compatibility is explicit.** The historical mixed Organization/Ledger is registered as a compatibility carrier until runtime cutover is complete.
7. **A Ledger is a governing boundary, not an Organization synonym.** Elm Farm and Elm Venue remain separate Ledgers under the Elm Farm Organization.
8. **Names are labels, never identity.** New Organization and Ledger stable identifiers are opaque.
9. **Principal authority is direct.** Lex receives root authority over Elm Farm, Elm Venue, and Feast Guild Ledgers. The historical mixed authority may coexist temporarily only as compatibility state until cutover.
10. **Feast Guild starts clean.** No historical Elm, Waiting Room, customer, supplier, task, work, communication, order, farm, employee, position, responsibility, or identity row is physically copied or reassigned into Feast Guild.
11. **Evidence, not table families, drives adjudication.** Elm custody begins from explicit Elm Unit/Farm/Anna/route evidence. Generic composition and Local/Noel state remain portfolio history.
12. **No destructive deletion or retrospective rewriting.** IDs, source timestamps, event revisions, provenance, communication state, and append-only evidence remain untouched.

## Historical compatibility carrier

The current production mixed scope remains physically unchanged during this tranche:

- Organization `818b9a23-65e9-4198-b86c-9496ba548642`
- stable key `feast_guild`
- name `Feast Guild`
- status `active`
- Ledger `6dab72b7-cb2f-43eb-855e-c0c99756e0d6`
- Ledger scope marker `legacy_mixed_pending_adjudication`

It is registered in `atlas.institutional_custody_carriers` as `legacy_mixed_scope`. This is not a statement that it remains canonical authority. It is an explicit acknowledgement that existing runtime rows and immutable history still physically reference it while read/write cutover is pending.

## Canonical forward graph

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

Legacy mixed Organization + Ledger
  └── explicit compatibility carrier [physical rows preserved]
```

## Custody adjudication model

`atlas.institutional_custody_adjudications` is append-only. Each adjudication identifies an existing source row and records:

- source schema/table/key;
- historical Organization/Ledger when known;
- canonical Organization/Ledger when supported;
- disposition: `reassigned`, `archived`, or `unresolved`;
- evidence basis and evidence payload;
- adjudication timestamp.

`reassigned` means canonical custody is known even though the physical row remains in the compatibility carrier.

`archived` means the row remains historical portfolio/test evidence and is not promoted into a canonical institution.

`unresolved` means the historical mixed container is the only reliable evidence and Atlas refuses to guess.

## Effective custody resolver

`atlas.effective_institutional_custody_v1(...)` resolves canonical custody from adjudication. If no adjudication exists, it falls back to the supplied physical Organization/Ledger. Browser roles cannot execute it directly; it is an internal compatibility seam for governed read/write contracts.

This resolver is the forward path for runtime convergence. Existing source rows are not rewritten merely to make old columns look canonical.

## Evidence rules

### Elm Organization evidence

A preserved row is canonically Elm when stronger evidence exists, including:

- `farm_id = 6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f`;
- `organization_unit_id = 1b65ac99-0f00-4ca2-9488-e8539cae2a1b`;
- Anna’s known institutional identity/employment chain;
- an operational route whose own metadata names Elm Farm;
- a responsibility scope that explicitly names the Elm Unit.

### Ledger evidence

- explicit production Ledger entries map to Elm Farm Ledger;
- farm/production/crop/flower/seed/growing/postharvest truth may map to Elm Farm Ledger when the row itself supplies that evidence;
- venue-specific responsibility evidence maps to Elm Venue Ledger;
- cross-cutting Elm Organization truth may remain Organization-adjudicated with Ledger unresolved.

### Archive evidence

Waiting Room and its farm-keyed test records are archived custody.

Owner-level Nathan/Camp Duffel and rehabilitation-house task/project rows remain archived portfolio history.

Generic composition runs and Local/Noel recommendation-lens state remain archived portfolio history even when physically stored in the old mixed Organization.

### Residual evidence

Any remaining old-Organization row with no stronger evidence receives `unresolved`, never an invented Elm or Feast Guild assignment.

## Anna

Anna’s existing durable IDs remain physically unchanged. Their effective custody is adjudicated to canonical Elm:

- Membership `4bda9631-07a6-43ae-9f51-4cb63d78c803`
- Person `998e6116-6d9d-4ee5-9d48-6c239d58507b`
- Identity Subject `0b87334c-56e0-44c2-a7d7-57d6df60f705`
- Employee Seat `74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0`
- Member Credential `385673ab-cf4e-4dbe-8c1d-11cb244143f2`
- Farm Steward Position `badd2192-28a7-4913-aa90-e7076cb419f5`
- Appointment `1baf1031-cbe3-4520-9b5d-485bb5c9a59c`

Lex may receive a new non-employee compatibility owner membership on canonical Elm. This does not replace Principal → Ledger authority.

## Communication boundary

`connected_sources`, communication events, attachments, participants, threads, inbox history, authorization state, scopes, capture/send flags, sync timestamps, and revocation state remain physically unchanged.

Their effective institutional custody may be adjudicated to Elm, but no communication behavior changes in this tranche.

## Feast Guild clean room

The canonical Feast Guild Organization/Ledger contain only new institutional identity, Organization↔Ledger participation, and Lex root authority. No legacy operating rows are copied or mutated into Feast Guild.

## Validation requirements

The production-schema clone must prove:

1. canonical Elm Farm, Elm Venue, and Feast Guild identities exist with opaque stable keys;
2. Lex has root authority over all three canonical Ledgers;
3. Elm participates in Farm and Venue Ledgers;
4. Feast Guild is clean-room;
5. the historical mixed Organization and Ledger remain physically unchanged and active as compatibility carrier state;
6. Elm Unit/Farm source IDs remain physically under the historical carrier while effective custody resolves to canonical Elm;
7. Anna’s preserved IDs remain unchanged while effective custody resolves to Elm;
8. six historical Ledger entry IDs/revisions remain unchanged while effective custody resolves to Elm Farm Ledger;
9. Waiting Room and owner-level portfolio work resolve as archived;
10. generic composition and recommendation-lens state resolve as archived, never Elm;
11. connected-source physical custody/authorization/capabilities/sync state remain unchanged while effective custody resolves to Elm;
12. custody adjudications are append-only and browser-inaccessible;
13. carrier/target relations are browser-inaccessible;
14. no runtime trigger state changes;
15. no FK deferrability changes;
16. unresolved residual mixed-container rows are explicit rather than guessed.

## Runtime cutover boundary

This tranche does **not** repoint existing read/write APIs. The next tranche must adopt `effective_institutional_custody_v1` (or governed projections built on it) so new canonical Organizations/Ledgers become the runtime authority without rewriting historical rows.

Only after all active reads/writes no longer depend on the mixed carrier may a later governed migration end the compatibility carrier and retire its legacy authority.

## Immutable migration identity

`20260914000504_atlas_institutional_custody_reconstruction_v1.sql`

The earlier physical-rehome candidates are superseded and must never be released.