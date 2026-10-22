# Atlas One Date + Subject: Packet 0 source and authority inventory (initial verified slice)

**Observed:** October 22, 2026, via read-only production catalog and source-identity queries.  
**Status:** Beginning Packet 0; Packet 1 read-only candidate prepared; **not a declaration of complete calendar coverage**.

## Current release facts

The production migration ledger contains:
- `20261022050415`: Ledger/Occurrence ordinary shared Work.
- `20261022053857`: Event Work actions and personal-attention extension.
- `20261022132852`: public authenticated RPC delegates for Event paths.

Live `atlas.work_item_context_links` has 3 relationships, so related Work is no longer universally empty. This does not prove the three-Person browser test. The Atlas application uses an exact `(ledger, canonical occurrence)` URL address and a guarded Event-work reader/writer, but complete date and subject reality is not yet converged.

## Source and permission table

| Source of reality | Canonical identity | Live read seam | Writer owner | Current coverage / boundary |
| --- | --- | --- | --- | --- |
| Shared Occurrence | `local_intel.occurrences.id` | `atlas.canonical_occurrence_temporal_adapter_v1`, `atlas.ledger_occurrence_shared_index_self_api_v1` | Shared Intelligence / canonical occurrence governance | Exact event ID; adapter currently labels all admitted occurrences as `scheduled` irrespective of source status. Requires epistemic tightening. |
| Operational Organization event overlay | `atlas.community_events.id` pointing through `atlas.organization_occurrence_bindings.id` | `atlas.community_event_occurrence_overlay_service_v1` | Organization event domain | Operational title/local schedule/status can disagree with canonical occurrence, and existing overlay adapter omits these differences. Five of 48 current linked overlays are comparison candidates; not five proven false statements. |
| Ledger occurrence relevance | `ledger.occurrence_calendar_bindings.id` | `atlas.ledger_scheduling_temporal_adapter_v1`, Ledger Event Index | Ledger scheduling | Current Ledger/calendar relation is not independent event identity. |
| Ledger occupancy | `ledger.occurrence_resource_claims.id` | `atlas.ledger_scheduling_temporal_adapter_v1` | Ledger resource-claim command | Separate interval, conflict availability and booking semantics. An occupancy is not the event time or a confirmed booking. |
| Organization purpose temporal context | `atlas.organization_purpose_contexts.id` and membership | `atlas.organization_context_temporal_composer_service_v2` | Organization-context commands | Private selection/curation over canonical occurrence or marker. |
| Temporal markers | `local_intel.temporal_markers.id` | `atlas.canonical_temporal_marker_temporal_adapter_v1` | Local Intelligence | Date-bearing meaning, not an event or midnight occurrence. |
| Recurrence expectations | Source-specific recurrence rule / instance | `atlas.recurrence_expectation_temporal_adapter_v1` | Recurrence domain | Expected occurrence is not automatically an established event. |
| Company Work and planned time | `atlas.work_items.id` / `atlas.work_time_contracts.id` | Company Work accountability, planning readers | Company Work and planning commands | Timing is not yet included in the limited Ledger occurrence evidence read, and a Work deadline is not the Event date. |
| Person Life / Principal Clock | Person- and clock-owned identities | Person/Clock authorized readers | Person, Household, Principal | No universal Person-wide cross-Ledger date composer proven in this packet. |
| Communication | `atlas.communication_events.id`, Conversation, outbound operation and attempt | Correspondence/Communication governed readers | Communication/source transport | Sent/accepted/received states and dates must stay source qualified; no communication is an Event merely because it shares words or date. |
| Place/GIS | `reality.entities.id` canonical Place and Place profile, `atlas.spatial_contexts` | Spatial resolvers | Canonical Reality/Geography | No automatic venue-name→Place identity admission. |
| Legacy public calendar projection | `public.elm_local_calendar_events_v1` | Legacy public read | Historical compatibility | Must be inventoried/shadow-compared before cutover, never mistaken for canonical temporal truth. |
| Native Person ↔ Ledger participation | `ledger.seats`; active Ledger/Organization participation | `atlas.current_active_ledger_seat_v1` | Identity / Ledger connection | Seat = relationship, not ownership, paid employee seat or permission for every action. |
| Ledger Event Work and attention | `atlas.work_items.id` with typed context and Event actions | `atlas.ledger_occurrence_work_extension_self_api_v1` and guarded commands | Company Work, Event action writer, personal attention | Three production context links; not full end-to-end UI or proof of performance. |

## Concrete currently demonstrated hole

Existing Ledger Temporal composer is **not** a seat-wide general calendar reader: `atlas.ledger_temporal_composer_self_api_v1` requires `capability_root_authority_context_self_v1`. The source Event Index permits active Ledger People only through a narrower verified exposure. The reconciliation candidate must **not** call the broad root composer for a seat and accidentally expose private booking, resource customer, money, or unrelated institution context.

The new candidate is intentionally narrower: only Ledger-bound Occurrences and specifically linked operational Organization Event assertions, with source qualified timestamps, alias/lifecycle *comparison candidates*, and `wholeTemporalFieldComplete=false`. It is a **date evidence adapter**, not the universal date Encounter.

## Owner-selected behavior preserved

- Index is a governed adaptive composition, not a hardcoded Event module.
- Established subject edges are separate from suggestive/reviewable candidates.
- Ordinary Ledger work is collaborative under specific permission, not exclusive assignee authority.
- A notebook sentence builder should not require a model call.
- Source-accepted Done requires actual outcome evidence; checker is not presumed physical performer.
- Responsibility offers, attention-directed exposure and accepted standing authority remain distinct.
- Compose/send carries an exact subject link; keyword coincidence never proves a relation.
- Date differences remain visible with selective commit-time blocks; absence of evidence is not proof of no more activity.
- Task unlink, governed retirement and mistaken-entry disposition are separate, history-preserving actions.

## New live findings that block broad Event-work completion

**Current Venue connections:** A fresh read now finds **four** active native Ledger Person seats (not the three counted in an earlier snapshot). A Seat alone does not prove that Person has an authenticated Atlas session; signed-person proof remains separate.

**Completion evidence gap:** `atlas.mark_ledger_occurrence_shared_work_done_self_api_v1` currently accepts only Organization, Ledger, Occurrence, Work and a source-action ID. It creates an immediately **accepted** completed result whose stored evidence contains the actor and action ID but no concrete outcome observation. This is faithful about *who checked the box* and does not claim physical performer; however it **does not satisfy the owner's chosen completion law (5D)**: actual completion needs evidence. The existing call must not be described as source-evidenced real-world completion. Before the first subject is declared done, define an ordinary outcome-evidence/verification policy and version the governed completion command; preserve old results as historical assertions, not retroactively proven outcomes. Do not silently require heavy paperwork for all tasks or treat a click alone as enough.

**Same date is not one Event:** The Venue Ledger currently has two independent bound Occurrences whose starts fall on the same October 30 civil day. The date reconciliation reader must preserve both separate canonical IDs; only the Harvest Party's own linked operational assertion is compared with its source record.

## Packet 0 audit still to complete

1. Inventory and mechanically exercise every relevant database date writer, planner, projection and legacy calendar consumer, including task timing, personal day, correspondence and external calendars.
2. Verify each source family's exact provenance, as-of, timezone/DST and coverage semantics; compare past/current/future source versions.
3. Inspect the legacy `elm_local_calendar_events_v1` and all app/agent/date answer paths. Establish a read-parity matrix, not UI-specific truth patches.
4. Prove end-to-end three authenticated Person sessions and denied non-Ledger Person without forged `auth.uid()` values.
5. Audit resolved versus unresolved conflicts under source-specific authority and decide lawful adjudication *without changing the existing source rows just to make the screen agree*.
6. Prove an unrelated Ledger and a second source class; only then call the model reusable across domains.

## Next gated code

1. Review and validate `candidates/atlas-ledger-date-claims-reconciliation-v1/candidate.sql` in the disposable production-schema clone.
2. Release a deliberately narrowed Ledger date evidence reader only through governed migration-generation/release steps.
3. Compose those paired source claims through the existing Universal Temporal Contribution Protocol; do not create a competing canonical `calendar_events` table.
4. Add a counterpart Subject Time reader consuming the same source envelope, then source-coverage contracts for Company Work and permitted personal reality.
5. Add source-owned disposition/correction after authorization and observation-before-mutation proof.
