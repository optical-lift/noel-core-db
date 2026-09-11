# Atlas Reality Discovery Encounter Admission v1

## Purpose

Separate **question ranking** from **Encounter admission** in Reality Discovery.

The current Discovery graph answers:

> Which unresolved eligible question ranks highest?

That is not sufficient to decide:

> Has any unresolved question earned the human's attention in this encounter?

V1 therefore adds a second governed step:

`unresolved reality`
→ `eligibility / suppression`
→ `question ranking`
→ **Encounter admission**
→ `highest-ranked admitted question`
→ `human encounter`

Ranking orders questions that are already admissible. It does not itself create a right to ask.

## Canonical boundary

Encounter admission owns only the Discovery-level decision that an otherwise eligible question is appropriate for a named Discovery encounter kind.

It does **not** own:

- Person, Household, Home, Vehicle, Animal, Money, Health, Calendar, Organization, or kernel truth;
- question eligibility signals;
- question ranking weights;
- Clock placement;
- urgency or priority;
- notification/interruption authority outside the active Discovery encounter;
- completion of the person's world model.

An unanswered question may remain true, relevant, and highly ranked while still being deferred from the current encounter.

## Encounter kinds

The existing session kinds remain authoritative:

- `first_day` — unusually favorable initial teaching window, but still bounded by attention entitlement;
- `manual` — the person explicitly opened Discovery and therefore grants broader discovery attention;
- `micro` — a later bounded question justified by a real nearby consequence/kernel need.

This change does not add a new session lifecycle or a universal onboarding-completion flag.

## Admission classes

Each active question receives one semantic admission class:

### `foundation`

Establishes broad world shape or responsibility boundaries and can eliminate or activate substantial downstream branches.

Examples:
- household shape;
- residence tenure;
- residence setting;
- major-repair responsibility;
- vehicle responsibility.

Default first-day disposition: **admit**.

### `near_consequence`

A missing fact is already needed for a real or approaching consequence Atlas is prepared to carry.

Default first-day disposition: **admit only when explicit consequence evidence exists**. V1 does not manufacture that evidence from ranking score.

### `high_leverage`

One answer can materially alter several downstream questions or kernels, without being merely descriptive specialization.

Examples may include school-calendar applicability, animal responsibility, or mowing method once grounds responsibility is established.

Default first-day disposition: **admit**.

### `specialization`

Adds detail to an already-established subject but is not yet needed for an immediate consequence.

Examples:
- exact riding-mower identity after the human has already said a riding mower is used.

Default first-day disposition: **defer**.

### `nice_to_know`

Potentially useful context with no meaningful present consequence or large branch effect.

Default first-day disposition: **defer**.

### `just_in_time`

A question intended primarily for later micro-discovery when a known kernel/consequence reaches the point that one missing material fact blocks useful action.

Default first-day disposition: **defer**.

## V1 policy

The first-day policy is intentionally semantic rather than numeric.

For `first_day`:

- admit `foundation`;
- admit `high_leverage`;
- admit `near_consequence` only when a future governed consequence-evidence predicate is explicitly satisfied;
- defer `specialization`;
- defer `nice_to_know`;
- defer `just_in_time`.

For `manual`:

- admit every eligible class except where a future rule explicitly says otherwise, because the person deliberately requested broader discovery.

For `micro`:

- admit only questions selected through a bounded micro-question path. V1 must not reinterpret an arbitrary high ranking as micro-question warrant.

## Why no score threshold

The existing score remains useful for ordering unresolved questions after prerequisites, suppressions, candidate requirements, and admission are applied.

A score threshold collapses two different judgments:

1. comparative value — which question is best among candidates;
2. attention entitlement — whether asking any candidate is justified now.

Those must remain separate.

A specialization question can rank above another specialization question and still be correctly deferred from first-day Discovery.

## First-day quiet rule

First-day Discovery becomes quiet when:

> no unresolved **admitted** question remains for the `first_day` encounter.

This does not mean:

- Discovery is complete;
- the person's world is mapped;
- deferred questions are false;
- kernels are established;
- future micro-discovery is forbidden.

It means only that Atlas has no further first-day question with sufficient Encounter warrant.

## Initial classification of the current live question catalog

The current questions should be classified conservatively:

| Question | V1 admission class | First-day |
| --- | --- | --- |
| `home.confirm_purchase_address` | `foundation` | admit when candidate exists |
| `household.people_shape` | `foundation` | admit |
| `home.tenure` | `foundation` | admit |
| `home.major_repairs` | `foundation` | admit |
| `home.setting` | `foundation` | admit |
| `home.dwelling_kind` | `foundation` | admit |
| `grounds.responsibility` | `foundation` | admit when eligible |
| `transport.vehicle_count` | `foundation` | admit |
| `household.child_count` | `high_leverage` | admit when eligible |
| `children.school_calendar` | `high_leverage` | admit when eligible |
| `animals.responsibility` | `high_leverage` | admit |
| `life.weekday_anchor` | `foundation` | admit |
| `laundry.location` | `high_leverage` | admit when context materially raises it |
| `grounds.scale` | `high_leverage` | admit when grounds responsibility exists |
| `grounds.mowing_method` | `high_leverage` | admit when grounds responsibility exists |
| `equipment.riding_mower_identity` | `specialization` | defer |

This classification can evolve through governed source changes. It is not inferred from raw score at runtime.

## Backend contract

The eventual canonical migration should:

1. add a private, data-driven admission policy surface or equivalent governed metadata;
2. classify every active Discovery question explicitly;
3. preserve current prerequisite / suppress / candidate logic;
4. preserve current deterministic score calculation;
5. filter ranked questions through encounter admission before selecting the winner;
6. expose admission class and encounter kind in the returned explanation/provenance so the decision is inspectable;
7. return quiet for first-day when eligible unresolved questions exist but all are deferred;
8. leave manual Discovery able to continue into deferred questions when the human explicitly asks to keep mapping;
9. leave micro-question admission closed unless a bounded future micro-question warrant exists;
10. not add a universal completion flag or modify canonical domain truth.

The existing public `reality_discovery_next_question_self_api_v1()` contract should remain compatible for the current first-day client. A lower-level/internal selector may accept an encounter kind, while the public wrapper may resolve that kind from the current active Discovery session.

## Required regression proof

### Rural owner household

After broad facts establish owner/rural/grounds context:

- vehicle, school/calendar, animal, mowing-method, and other admitted broad/high-leverage questions may continue to surface;
- if mowing is answered `riding`, `equipment.riding_mower_identity` becomes eligible in the graph but remains unresolved and **deferred from first-day**;
- manual or later justified micro-discovery may surface mower identity.

### Dense-city single renter

After renter/dense-city/management/no-vehicle context:

- grounds and mower branches remain suppressed by ordinary graph rules;
- apartment-relevant broad/high-leverage questions may remain first-day admitted;
- specialization does not fill the remainder of the session merely because no better questions remain.

### Quiet-with-unresolved proof

A required test must demonstrate a state where:

- at least one active, eligible, unanswered Discovery question still exists;
- every such remaining question is deferred for `first_day`;
- the first-day selector returns `quiet=true`;
- the same deferred question can still be retrieved through an explicitly broader/manual or future warranted encounter.

That is the key proof that admission, not exhaustion, governs first-day stopping.

## Release boundary

This document is architecture source only. It does not authorize production DDL or change live Discovery behavior.

A canonical migration must be generated through the repository's pinned Supabase migration workflow, validated against a production-schema clone, merged through normal custody, and separately released before production behavior changes.
