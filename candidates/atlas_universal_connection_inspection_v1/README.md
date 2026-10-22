# Atlas Universal Connection Inspection v1 — Source Candidate

**Authority:** existing source rows in ledger.seats and ledger.connections only. No new relationship, account, grant, patient, client or permission store.

## First supported carriers

1. ledger_person_seat: the authenticated, currently verified Person may inspect their OWN canonical Person-to-Ledger seat (including original active/paused/ended source state and historical dates).
2. ledger_ledger_connection: one canonical cross-Ledger summary-exposure connection may be inspected only by a Person who currently has ACTIVE seats on BOTH Ledgers. It preserves the source connection state/dates, without granting access to either Ledger's private content.

Both return the same canonical source, target, source record identity, relationship meaning and lifecycle shape. The public API is a guarded authenticated-only wrapper; internal source reader is not directly callable by anon/authenticated. Invalid source kinds are rejected; missing and unauthorized IDs return the same not-visible shape. No names, evidence, metadata or sensitive underlying records are returned.

## Explicit safety hold

The third contemplated carrier, reality.entity_relationships, is NOT included in this version. Its RLS policy surface is not established for a normal signed-in Person and some canonical relationships could be sensitive. A Person appearing as an endpoint is not enough to prove disclosure permission. Add it only with a separately reviewed universal record-visibility policy and signed-in cross-actor tests, not a medical-specific bypass.

This is an inspected-source projection ONLY. Connect, qualify/change and end still belong to original governed source commands. This project has not established a generic mutation authorizer or a universal every-object connector.

## Required release

Review source and exact role grants, generate migration via protected workflow, validate on disposable production-schema clone, confirm sessionless/foreign-person/one-sided-Ledger denial and cross-domain positive cases with real test accounts, then separately authorize DB release. The application must remain unlaunched until that proof exists.

No personal records, private research, client health data or test users are embedded here.
