# Atlas Universal Connection Inspection v1 — reviewed source candidate

**Source owner:** `ledger.seats`, `ledger.connections`, `reality.entity_relationships` individually. This candidate adds **no** new entity, connection, client, engagement, permission or event table.

## First shared read seam

The first reusable `connection_inspection_self_api_v1(text,uuid)` presents three existing canonical carriers through the *same* identity/provenance/lifecycle contract. These are *not* three connection systems to be chosen by the user; they are existing source adapters under one presentation/inspect verb.

| Internal source tag | Actual carrier | Current allowed inspection |
| --- | --- | --- |
| `ledger_person_seat` | `ledger.seats` | The authenticated Person's own historic/current Person→Ledger participation |
| `ledger_ledger_connection` | `ledger.connections` | A signed-in Person with active seats on **both** Ledgers; this source is limited to existing `summary_exposure` relations |
| `reality_entity_relationship` | `reality.entity_relationships` | Signed-in Person is a direct canonical endpoint |

Returns `source/target` stable IDs and kinds, `sourceId`, `carrierKind`, original source relationship/state/effective dates, but never personal names, source basis/metadata, clinical facts, relationship evidence, or another person's Ledger seat. **Existence and record disclosure are separate authority questions.** An inspection never grants the right to read a related sensitive record or create/end a connection.

## Authority and uncertainty

- `atlas.reality_access_self_api_v1` binds an actual valid signed-in session and canonical Person; both wrappers are definer functions solely to read protected sources after exact subject checks.
- Only the public wrapper has `authenticated` execution; neither `anon` nor `authenticated` can invoke the internal definer. Missing and unauthorized IDs yield the same `not_visible` response. Unknown carriers are rejected, not guessed.
- `ledger_ledger_connection` requires active seat on both sides; a past seat cannot reveal a second Ledger. `reality_entity_relationship` reveals only relations actually involving the signed-in canonical Person.
- This is **read-only**: no metadata updates, no subject establishment, no code to mint new links, and no medical/therapy-specific permission path.

## Important held work

This candidate alone does not prove a universal `connect/qualify/end` writer or a shared operation authorization evaluator. Future true connection mutation must dispatch to the existing canonical owner (e.g. Ledger–Person seat lifecycle vs Reality relationship proposition/adjudication), preserving each source's authorization and establishment ceremony; do not create a new cross-domain writer or move sources. The generic UI interaction must be in the existing Atlas notebook Semantic Interaction Runtime, not a competing dialog.

## Validation gates

Run disposable clone postconditions, source role/permission diff, negative tests for outsider and no-login, and two signed-in positive/negative cases **before a production release**. Test display of source `observed/disputed/retired` without converting that into established relationships. After release, app consumes this source using one strict validated descriptor; it must continue failing closed when a carrier is unsupported. Do not mount this in practitioner/client history or surface protected health data without record authorization.

An authenticated source read shows the canonical connection **only**. It cannot itself establish whether a session or note may be read.
