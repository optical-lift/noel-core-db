# Reporting Core v1

## Purpose

Reporting Core is the private, source-custodied memory layer for Marshall's municipal reporting workflow. It is designed to power three products from one truth model:

1. permanent municipal memory across people, organizations, government bodies, projects, properties, contracts and recurring issues;
2. meeting change detection that compares new records with prior source versions and reporting history;
3. source-to-reporting packets that assemble actions, money, quotes, chronology, conflicts and follow-up questions without writing the article.

Reporting Core does not treat AI output as a source and does not flatten source authority. Agenda proposals, adopted minutes, interviews, published reporting, reporter observations and machine-derived OCR/transcripts remain distinguishable.

## Storage and privacy boundary

The live data belongs in a private `reporting` schema inside the existing `noel-core` Supabase project. The schema is not an exposed Data API schema and grants no access to `anon` or `authenticated` roles in v1. Unpublished Otter transcripts, interviews and reporter notes must never be committed to a public Git repository. The public `noel-core-db` repository may contain only schema/migration code and non-sensitive architecture documentation.

## Source custody

A source is append/version oriented. `source_family_key` identifies the continuing source identity; `source_version_key` identifies one captured version. Changed content becomes a new source row rather than silently overwriting the earlier evidence. Durable locators store stable IDs and public canonical URLs only; expiring signed download URLs are not durable source identity.

Derived text such as OCR and automatic transcripts remains linked to a parent source and is marked as machine-derived at passage level. Source passages preserve page/segment locators so claims and quotes can resolve to the precise evidence surface.

## Newsroom objects

`reporting.objects` owns reporting-specific identity for people, organizations, government bodies, projects, properties, places, contracts and similar durable subjects. A reporting object may optionally bind to a `local_intel.entities` identity, but that binding is explicit and has its own verification state. Local marketing intelligence never automatically becomes newsroom truth.

Relationships are represented as claims whose value is another object, so relationship facts use the same evidence and conflict machinery as every other claim.

## Claims and evidence

A claim separates three independent questions:

- **phase:** proposed/requested/estimated/approved/adopted/actual/reported/observed;
- **claim state:** candidate/source-backed/verified/disputed/superseded/rejected;
- **conflict state:** none/unresolved/resolved.

A non-candidate claim cannot exist without evidence. The database enforces this at transaction commit. Evidence always identifies a source and may identify a precise passage from that same source.

A verified claim also requires an explicit verification method and timestamp. Machine-derived claims remain labeled as such even when the underlying source is authoritative.

## Money facts

Money is a specialization of a source-backed claim rather than a free-floating amount. Roles intentionally distinguish request, proposed budget, estimated expense/revenue, award, estimate, bid, contract award, appropriation, reimbursement and actual expense/revenue. This prevents an application request from silently becoming an award or an estimated referee budget from silently becoming an actual expense.

## Events, actions, votes and quotes

Events represent meetings, interviews, hearings, incidents, tours and other reporting moments. Sources attach to events by explicit roles such as agenda, minutes, transcript or interview audio.

Government/public actions belong to events and carry finality. Individual votes attach to actions.

Quotes attach to precise source passages and preserve raw speaker labels, resolved speaker identity when known, verification state and machine-derived confidence. A machine transcript can therefore be searchable without pretending that it has been audio-verified.

## Topics and story state

Topics are the continuing story/issue layer. They move through workflow states such as `watching`, `upcoming`, `occurred`, `follow_up`, `packet_ready`, `published`, `continuing` and `archived`. Topics can link to objects, events, sources and claims, allowing yesterday's published story and today's meeting packet to remain part of the same continuing issue.

## Search

V1 uses PostgreSQL full-text indexes on source passages, object names/descriptions, claim text and topic text. Semantic embeddings can be added later without changing custody or authority semantics.

## Architectural laws

1. No source flattening.
2. No reportable orphan facts.
3. Proposed, approved and actual are different states.
4. Machine-derived text stays visibly machine-derived.
5. Source versions are additive; changed evidence is not silently overwritten.
6. Reporter-private material never enters public repositories.
7. Local-intelligence identity may assist resolution but cannot decide reporting truth.
8. Every quote resolves to a source passage.
9. Every money fact resolves to an evidenced claim.
10. Meeting-change and reporting-packet products must read this shared model rather than maintaining parallel truth stores.
