# Shared Intelligence Custody Cleanup v1

## Status

Implemented in production on 2026-09-24.

This package repairs a mixed-custody legacy path in which universal external-world intelligence and one Atlas Organization's proposed uses of that intelligence were stored in the same Local Intel table.

The governing law is now:

> Canonical external-world truth belongs to Shared Intelligence. An Atlas Organization's idea, use, priority, pursuit, campaign, or relationship state belongs to that Organization.

## 1. The retired mixed carrier

`local_intel.outreach_targets` contained 69 rows that mixed two different authorities:

- 46 rows were actually universal research/acquisition work, such as availability refresh, source acquisition, and fact verification;
- 23 rows were Elm-specific concepts, such as event-host candidates, audience-host candidates, market partners, referral sources, and distribution partners.

The table also copied names, phone numbers, and email addresses alongside canonical entity/person/contact-point references.

That shape made Organization intent look like canonical external-world truth.

## 2. Historical preservation

The 69 legacy rows were copied intact to:

`local_intel.legacy_outreach_targets_archive_v1`

The archive exists only for provenance and reconciliation. It is not a live directory, contact, research, or action authority.

Each archived row has exactly one custody receipt in:

`atlas.legacy_local_intel_outreach_target_mappings`

Allowed dispositions are:

- `shared_intelligence_enrichment`
- `organization_purpose_context`

Production proof after migration:

- archived rows: 69
- custody receipts: 69
- Shared Intelligence research receipts: 46
- Organization-private concept receipts: 23

## 3. Universal research destination

Universal questions formerly represented as outreach were reclassified into:

`local_intel.entity_enrichment_targets`

New supported research kinds are:

- `availability_refresh`
- `source_acquisition`
- `fact_verification`

Legacy rationale, source hints, and provenance remain attached to the enrichment work. Raw copied contact coordinates were not promoted forward.

Universal research means:

> Atlas needs to learn or verify something about the external entity.

It does not mean:

> Elm, Feast Guild, or another Organization intends to contact or pursue this entity.

## 4. Organization-private concept membrane

Atlas now exposes:

`atlas.record_entity_purpose_concept_service_v1`

and authenticated wrapper:

`atlas.record_entity_purpose_concept_self_api_v1`

The service accepts one canonical Shared Intelligence entity and records an Organization-owned purpose/context membership.

The sequence is:

canonical Shared Intelligence entity
→ Organization-private external relationship
→ Organization-private purpose context
→ Organization-private concept payload and provenance

The service may establish a prospective external relationship because the Organization now has a concrete reason to care about that entity.

It does not write the concept payload into:

- `local_intel.entities`;
- Shared Intelligence evidence claims;
- Shared Intelligence market attributes;
- universal role/authority facts;
- universal contact points.

Examples of lawful private concepts include:

- host candidate;
- vendor candidate;
- referral source;
- partnership candidate;
- outreach set membership;
- campaign membership;
- internal priority;
- private rationale;
- suggested action or timing.

The same canonical entity may participate in different private contexts for different Atlas Organizations without cloning identity.

## 5. Canonical identity bridge

The canonical Shared Intelligence ↔ Atlas Organization seam remains:

`atlas.identity_subject_external_identifiers`

with:

- `provider_key='local_intel'`
- `identifier_type='entity_id'`
- `identifier_normalized=<local_intel.entities.id>`

One bounded legacy identity collision was encountered during the cleanup: Marshfield Community Theatre.

The existing Elm Identity Subject already matched the official-verified canonical entity by exact organization name, exact legacy relationship key, and Marshfield relationship location. The migration bound that existing subject to the canonical entity rather than creating a duplicate.

No generic identity-resolution threshold was weakened.

## 6. Shared Intelligence language

The universal question catalog no longer says that Elm is the knower of Shared Intelligence.

Statements such as "If Elm knows..." were neutralized, and `outreach_target` was removed from universal object scopes.

The distinction is now:

- Shared Intelligence asks what Atlas can establish about external reality;
- an Organization overlay records why one Organization cares about that reality.

## 7. Live-carrier retirement

After all 69 archived rows had one lawful destination, the live `local_intel.outreach_targets` rows were removed.

The table remains only as an empty compatibility shell and is protected by:

`local_intel.reject_retired_outreach_target_write_v1`

and trigger:

`outreach_targets_retired_write_guard_v1`

INSERT, UPDATE, and DELETE attempts now fail closed.

The legacy outreach-resolution view therefore returns zero rows, and legacy outreach intent can no longer influence Shared Intelligence person-discovery priority.

## 8. Contact/entity claim frontier

This cleanup deliberately does not turn a claimant into the owner of all canonical evidence.

The preferred future model is evidence-first:

verified Atlas Person
→ independently verified authority to represent/control a real-world organization
→ bounded publisher/controller standing for that canonical entity
→ first-party evidence submissions

A verified claimant should be able to:

- publish current first-party name, contact, location, hours, offerings, people/roles, policies, and other supported facts;
- mark the intended disclosure/contactability posture of information they publish;
- supersede or retract their own first-party assertions;
- challenge third-party evidence and request adjudication;
- distribute approved first-party data through Atlas read membranes.

A claimant should not silently erase:

- source-backed historical observations;
- another source's evidence;
- another Atlas Organization's private relationship data;
- provenance needed to explain how canonical state changed.

The canonical profile should therefore be a survivorship result, not a mutable business card row.

Owner/controller-verified evidence should normally receive the strongest first-party source class and survivorship priority appropriate to the claim type, while contradictory/historical evidence remains preserved underneath.

## 9. Remaining cleanup frontier

This package does not yet retire the inherited `local_intel.entities.local_context_id` compatibility pointer.

The next custody package must inventory and transition all readers, writers, uniqueness rules, and resolution guards that still treat `local_context_id` as an identity boundary. Only then should automatic Elm Local stamping be removed.

Subsequent work also includes:

1. normalize entity phone/email values into governed contact-point evidence;
2. make entity-level contact columns compatibility/current-state projections rather than independent authority;
3. backfill remaining Atlas external relationships to canonical Shared Intelligence entities through governed identity resolution;
4. implement business controller/representative verification and claimed-entity publishing authority;
5. expose Smart Contacts through governed read/write membranes rather than direct Local Intel table access.

## 10. Acceptance proof

The release is acceptable only while all of the following remain true:

1. `local_intel.outreach_targets` has zero live rows.
2. The historical archive has 69 rows.
3. The mapping table has exactly 69 receipts.
4. Receipt split remains 23 Organization concepts + 46 universal research rows.
5. No active Shared Intelligence question family contains Elm ownership wording or `outreach_target` scope.
6. Legacy outreach contribution to person discovery is zero.
7. The retired-write trigger exists for INSERT, UPDATE, and DELETE.
8. Feast Guild has no relationship merely because these entities exist in Shared Intelligence.
9. Organization-private concept payloads do not appear in canonical Shared Intelligence entity/evidence tables.

## Core sentence

> The world is shared; purpose is private. Atlas stores one canonical external entity, then lets each Organization record its own relationship, concepts, plans, and history without converting those private meanings into universal truth.
