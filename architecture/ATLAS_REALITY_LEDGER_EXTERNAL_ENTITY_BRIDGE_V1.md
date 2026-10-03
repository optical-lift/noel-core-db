# Atlas Reality / Ledger External Entity Bridge v1

Status: governing implementation architecture  
Date: 2026-09-25

## Purpose

Atlas needs one clean path from external-world discovery into an institution's operational memory without creating a second CRM identity plane.

The bridge must let Atlas:

1. discover or re-find a business/person through Shared Intelligence;
2. preserve exactly one canonical identity for that real-world referent;
3. attach that canonical Entity to a specific Ledger for an institution-specific purpose;
4. record contact, follow-up, response, selection, rejection, conversion, or other actions in that Ledger;
5. later recover both the universal Entity and the institution-private history.

The bridge must not revive `atlas.organizations`, Organization Membership, Principal Ledger Authority, or the legacy `atlas.external_relationships` identity model as the authority foundation.

## Governing distinction

Three different truths remain separate:

```text
Shared Intelligence
  = acquisition + evidence + identity resolution

Reality
  = canonical real-world Entity

Ledger
  = one institution's private action/context history around that Entity
```

A source result is not a new Entity.

A Ledger prospect is not a new Entity.

An outreach action is not a canonical attribute of the target Entity.

## 1. Admission preserves identity

The admission adapter is:

`atlas.admit_shared_intelligence_entity_to_reality_service_v1`

It accepts only an active, already-resolved `local_intel.entities` row.

When that referent is not yet present in Reality, Atlas inserts it into `reality.entities` using the same UUID.

When the UUID is already present in Reality, Atlas reuses it.

When the Shared Intelligence stable key would collide with a different Reality UUID, the adapter stops for adjudication rather than minting or silently merging another identity.

Therefore:

```text
Shared Intelligence Entity UUID
          =
Reality Entity UUID
```

for admitted external referents.

The adapter lives in `atlas`, not `ledger`, so the Ledger core does not depend directly on Shared Intelligence.

## 2. Contact routes follow the admitted Entity

Admission also carries governed Shared Intelligence contact points into `reality.contact_routes`.

The source verification state, visibility, deliverability state, marketing state, and source IDs remain preserved as evidence.

A public Shared Intelligence route may be marked `public_disclosure=true`.

A source-observed route remains non-public.

Suppressed or hard-bounced source routes enter Reality suppressed and are not silently reactivated by later admission calls.

## 3. Ledger-private Entity context

`ledger.entity_contexts` is the institution-private overlay.

It answers:

> Why does this Ledger currently care about this canonical Entity?

Examples include:

- `prospect`
- `customer`
- `supplier`
- `candidate`
- `participant`
- another future bounded context kind

A Ledger Entity context does not establish:

- a second identity;
- a universal real-world relationship;
- ownership;
- representation;
- Ledger access;
- authority;
- a claim that another Ledger must share.

If Elm Venue marks a business as a `prospect`, that is Elm Venue's operating context, not a canonical fact about the business.

## 4. Entity-targeted Ledger actions

`ledger.actions.object_entity_id` adds a first-class foreign key from a Ledger action to the canonical Reality Entity that is the object/counterparty of that action.

Example:

```text
Elm Farm Venue Ledger
  -> outreach_attempted
  -> object_entity_id = Smith Financial Planning
  -> performed_by_entity_id = Katie
  -> occurred_at = ...
  -> payload = { channel, outcome, follow-up, notes }
```

The UUID is not hidden only inside JSON.

`ledger.record_entity_action_service_v1` requires the target Entity to already have an active Ledger context. This preserves the explicit boundary:

```text
known universal Entity
  -> explicit Ledger context
  -> Ledger action history
```

## 5. Bridge composition

The service-level composition is:

`atlas.attach_shared_intelligence_entity_to_ledger_service_v1`

It performs:

```text
resolved Shared Intelligence Entity
  -> admit/reuse same UUID in Reality
  -> establish Ledger-private Entity context
  -> append entity_context_established Ledger action
```

Repeated attachment is idempotent for the same Ledger + Entity + context kind.

Search alone does not call this bridge. Search discovery and institutional selection remain separate acts.

## 6. Human write authority

Authenticated writes use explicit Reality responsibility:

`institutional_external_entity_engagement`

The responsibility is jurisdiction-bound to the subject Entity of the Ledger and scope-bound to exact Ledger IDs.

Permitted operations in v1:

- `ledger_entity_attach`
- `ledger_entity_action`

An active Seat does not grant these writes.

A generic role does not grant these writes.

Organization Membership and Principal Ledger Authority are not consulted.

Elm v1 receives this responsibility for the Elm Farm Venue Ledger only.

## 7. Read authority

`atlas.ledger_entity_contexts_self_api_v1` is read through active Ledger Seat participation, consistent with the current Reality/Ledger read-access membrane.

The read returns:

- canonical Reality Entity identity;
- Ledger-private context;
- public current contact routes;
- latest Entity-targeted Ledger action;
- context basis and metadata.

Private source-observed routes are not exposed through this projection merely because they exist in Reality custody.

## 8. Elm Venue use

The immediate intended flow is:

```text
Springfield/Webster County research
  -> Shared Intelligence resolves Company X
  -> Company X remains one universal Entity
  -> operator selects Company X for Elm Venue prospecting
  -> Company X is admitted/reused in Reality
  -> Elm Venue gains context_kind=prospect
  -> calls/emails/meetings/follow-ups append to Elm Venue Ledger
```

Another Ledger may later care about Company X for an entirely different reason without creating Company X again.

## 9. Legacy boundary

The new bridge must not write a new durable prospect set into:

- `atlas.external_relationships`;
- `atlas.external_relationship_interactions`;
- legacy buyer relationship tables;
- legacy campaign/outreach identity carriers;
- Organization-owned duplicate contact tables.

Those remain compatibility/history until deliberately migrated.

## 10. Governing acceptance

The bridge is accepted only when:

1. a resolved Shared Intelligence Entity enters Reality with the same UUID;
2. repeated admission does not duplicate it;
3. stable-key conflict stops rather than silently merging;
4. Ledger context is private to the target Ledger;
5. an Entity-targeted action carries an FK to `reality.entities`;
6. write authority is exact Reality responsibility, not Seat or role;
7. read authority is Ledger Seat participation;
8. Elm Venue authority does not leak into another Elm Ledger;
9. Ledger core services do not directly depend on `local_intel`;
10. legacy Organization authority structures are absent from the new write path.

## Core sentence

> One real-world thing gets one canonical Entity; each Ledger may hold its own context and action history around that Entity without owning, cloning, or redefining it.


## Production release checkpoint — 2026-09-25

GitHub migration package `20260925194500_atlas_reality_ledger_external_entity_bridge_v1.sql` is live in production. Supabase recorded the production application as version `20260925195307` with migration name `atlas_reality_ledger_external_entity_bridge_v1`.

Production verification established:

- `ledger.entity_contexts` exists with RLS enabled and no direct authenticated table access;
- `ledger.actions.object_entity_id` is a real FK path to `reality.entities`;
- Lex has exactly one active `institutional_external_entity_engagement` responsibility for Elm;
- that responsibility is scope-bound to `Elm Farm Venue Ledger` and does not resolve for `Elm Farm Flower Ledger`;
- a real active Shared Intelligence Entity can be admitted with its existing UUID, attached to the Venue Ledger as `prospect`, and receive an Entity-targeted Ledger action;
- the production proof ran inside a rollback transaction, so no test prospect or outreach action remained afterward;
- production contained zero persisted `ledger.entity_contexts` immediately after release.

Supabase advisor findings on the new objects were reviewed. The RLS-without-policy information finding is intentional because the table is private and exposed only through governed functions. The authenticated `SECURITY DEFINER` warnings correspond to the three intentional authenticated membranes whose bodies enforce exact Reality responsibility or Ledger Seat checks. Newly created indexes are expected to report unused until real Entity-context traffic begins.
