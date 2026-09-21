# Atlas Contact-Set Execution Preparation v1

## Purpose

Turn a validated `build_target_contact_set` intent into a durable, inspectable execution snapshot before any external acquisition occurs.

This package implements the "existing reality first" half of the Skill:

```text
typed contact-set intent
→ typed Shared Directory search
→ requesting Ledger overlay
→ required-field coverage
→ exact research gaps
→ optional private Ledger attachment
→ durable execution run
```

It does not perform web research. It identifies exactly what research remains.

## Why this exists

The historical Shared Directory search accepts one free-text query. That is useful for a human lookup box but too weak for Atlas Intelligence.

A request such as:

> Find emails for bank people in those towns.

contains separate dimensions:

- subject kind: people;
- organization kind: bank;
- geography: the resolved towns;
- functional meaning: decision-adjacent people;
- required fact: email;
- private consequence: put qualifying contacts in the requesting Ledger.

Those dimensions must remain typed rather than collapsing back into a string search.

## Typed target search

`atlas.shared_directory_target_search_service_v1` accepts:

- the requesting Organization;
- the interpreted target object;
- interpreted geography;
- required fields;
- a bounded result limit.

For person targets it:

1. finds matching canonical organizations in Shared Intelligence;
2. follows current public role/working relationships to canonical people;
3. applies explicit role-function/title constraints when present;
4. treats `decision_adjacent` as a request for current people attached to the qualifying organization rather than as a literal title;
5. composes the requesting Organization's private overlay;
6. reports exactly which required fields are missing.

For organization targets it returns the qualifying canonical organizations directly.

## Gap types

The search emits research targets rather than silently widening the search:

- `entity_field_gap`: canonical subject exists, but one or more required fields are missing;
- `organization_person_gap`: qualifying organization exists, but no qualifying person is known;
- population shortfall is added by execution preparation when the user requested a count and the supported result set is smaller.

These gaps become the input to Acquire Missing Truth.

## Ledger effect

When the interpretation authorizes a Ledger effect, existing qualifying canonical entities are attached through the existing Shared Directory → Atlas relationship membrane.

This creates only Organization-private relationship state. It never clones the Shared Intelligence entity.

Default role key is `contact` unless the interpretation explicitly carries a valid role key.

## Durable run

`atlas.contact_set_execution_runs` stores:

- source intent request;
- Organization / optional Unit;
- execution state;
- immutable-at-preparation directory snapshot;
- exact gap snapshot;
- private Ledger-effect results.

The run is resumable evidence of what Atlas already knew before acquisition.

## Truth boundaries

Preparation must not:

- create or edit Shared Intelligence identities;
- perform external research;
- fabricate missing fields;
- send communication;
- expose another Organization's overlay.

It may create the requesting Organization's private relationship handle when the interpreted Ledger effect authorizes it.

## Acceptance proof

The rollback-only validation world contains:

- two canonical banks in two towns;
- two canonical people at one bank;
- one person with a public email;
- one person missing email;
- the second bank with no known person.

The typed request asks for three bank people and requires email/name/title/organization.

Expected preparation:

- two existing people returned;
- one is complete from existing reality;
- one has an email gap;
- the second bank produces a person gap;
- requested count of three produces a population gap;
- both known people are attached to the validation Organization's Ledger using the same canonical Shared Intelligence UUIDs;
- no Shared Intelligence entity is created.
