# Personal Institutional Implementation Handoff v1

**Status:** source-only candidate; not released  
**Date:** 2026-09-22  
**Parent:** Personal Institutional Destination v1

## Purpose

When a person has explicitly routed a captured sentence to an existing Implementation Case, Atlas needs a lawful way to put that testimony in front of the implementation practitioner.

The signed-in person must not become the practitioner merely because they supplied the testimony.

The existing shared Implementation conversation is the correct receiving membrane.

## Required source state

The handoff accepts only an applied `institutional_destination` proposal whose:

- owner is the signed-in human;
- destination kind is `implementation_case`;
- destination id identifies the case;
- source Institutional Anchor belongs to the same capture and Principal;
- human still has conversation authority for that Implementation Case.

## Write

The handoff:

1. ensures the case has the shared `Atlas intake` conversation thread;
2. inserts the original Personal Reality capture testimony as a text entry;
3. records provenance metadata linking the Personal Reality capture, source Evidence, confirmed Institutional Anchor proposal, and applied Institutional Destination proposal;
4. returns the conversation entry id.

Retry is idempotent by the Institutional Destination proposal id.

## Critical non-authority

The handoff does **not** create:

- an Implementation Reality Candidate;
- an establishment operation;
- Organization truth;
- Ledger truth;
- Commercial Composition truth;
- a task;
- a responsibility;
- practitioner adjudication.

The conversation entry is incoming testimony from an authorized case participant. The practitioner remains responsible for deciding whether the testimony warrants a typed Implementation Reality Candidate and, later, canonical promotion.

## Exact testimony

The conversation entry body is the preserved `personal_reality_captures.testimony`.

The bridge does not paraphrase, classify, or rewrite it.

## Result

```text
Personal testimony
→ human-confirmed institutional anchor
→ human-confirmed existing Implementation destination
→ exact testimony enters shared Implementation conversation
→ practitioner adjudication remains downstream
```
