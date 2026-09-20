# Personal Reality → Household Claim Route v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This tranche closes the next Laundry loop gap:

> A spontaneous statement can already be captured as raw first-party testimony and human-confirmed as an interpreted Claim proposal, but the existing Personal Reality application route writes all `claim` effects into **person scope**.

That is correct for person-owned claims and wrong for Household Laundry state.

## Target scenario

The Household Laundry instance already exists.

The person says:

> Laundry is piling up.

Personal Reality Capture preserves that sentence once as unresolved first-party Evidence in person custody.

An interpreter resolves it against the known Laundry instance and proposes, for example:

```json
{
  "effectKind": "claim",
  "proposal": {
    "subject": {
      "domain": "household.laundry",
      "kind": "kernel_instance",
      "id": "<laundry instance uuid>"
    },
    "claim": {
      "claimType": "present_state",
      "lifecycleState": "observed",
      "value": {
        "state": "accumulating",
        "pressure": "backlog"
      }
    }
  }
}
```

The proposal remains only a proposal until the existing human-confirmation membrane confirms it.

After confirmation, this tranche provides the correct Household application route.

## Custody problem

The universal Claim/Evidence constitution requires:

- a Claim's primary Evidence to have the same custody scope and subject;
- Claim/Evidence links to remain inside one custody scope.

The raw testimony Evidence is intentionally in **person** scope because the human supplied it before Atlas knew what it meant.

Therefore a Household Claim may not directly use or link that raw Evidence as its primary Evidence.

The correct transition is:

`person-scoped raw testimony Evidence`
→ human-confirmed interpretation
→ `household-scoped interpretation Evidence`
→ `household-scoped Claim`

The Household interpretation Evidence does **not** copy the testimony text. Its provenance references the original Evidence id, proposal id, and human decision receipt.

This preserves the source while respecting custody boundaries.

## New authority

### Internal Household promotion writer

`atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)`

It:

- derives actor from `auth.uid()`;
- derives Household from the active Principal;
- verifies the source Evidence belongs to the signed-in person;
- verifies a consumed human-confirmation receipt for the exact proposal;
- restricts destination subjects to `household` / `household.*`;
- creates a Household-scoped interpretation Evidence record;
- creates the Household-scoped Claim against that Evidence;
- preserves correction/supersession inside the same Household and subject;
- references the raw person Evidence only through provenance because cross-scope links are prohibited.

It is internal and not directly executable by authenticated clients.

### Specialized application route

`atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)`

It consumes an already-confirmed ordinary Personal Reality `claim` proposal whose subject is Household-scoped, applies it through the Household promotion writer, updates proposal route state, preserves destination identity, and handles same-subject Household claim correction transactionally.

No new effect kind is required.

## Fail-closed protection on the old route

The existing generic Personal Reality apply function routes every `claim` through the person Claim writer.

This candidate adds a narrow table guard:

> A `personal_reality_claim` may not be written in person scope when its subject domain is `household` or `household.*`.

Therefore accidentally calling the old generic apply route for a Household proposal fails transactionally instead of creating a person-scoped “household” claim.

This guard does not prohibit other person-scoped Claims that happen to discuss household matters through other governed sources. It targets only the Personal Reality claim route that is known to have the wrong custody behavior for Household subjects.

Production currently contains zero `personal_reality_claim` rows and zero known wrong-scope Personal Reality Household Claims, so no data repair is required before this guard can be validated.

## What this does not do

This tranche does not:

- infer that testimony is about Laundry;
- auto-confirm an AI interpretation;
- create a task;
- create a Household Rhythm;
- create a Person Life Consequence;
- select a responsibility carrier;
- decide Clock placement;
- copy the raw testimony into Household custody;
- permit cross-scope Claim/Evidence links.

It only gives a human-confirmed Household interpretation a truthful destination.

## Correction law

A Household claim proposal may supersede a prior proposal only when the prior applied destination is also a Household Claim in the same current Household and the same subject.

Changing subject is not silently treated as a correction.

## Stack

This candidate is stacked after:

1. current-Household Claim/Evidence membrane;
2. progressive Laundry instance truth.

It also relies on the already-released Personal Reality Capture / proposal / confirmation membrane.

## Validation target

Before promotion, clone validation must prove:

1. raw testimony remains person-scoped;
2. Household interpretation Evidence is separately created in Household scope;
3. raw testimony text is not copied into Household interpretation Evidence;
4. provenance contains the raw person Evidence id, proposal id, and confirmation receipt id;
5. no cross-scope Claim/Evidence link is inserted;
6. the Household Claim primary Evidence is the Household interpretation Evidence;
7. only `household` / `household.*` subjects are accepted by the Household route;
8. old generic Personal Reality apply fails closed for Household-subject `claim` proposals;
9. person-domain Personal Reality claim application continues to work;
10. specialized Household apply requires the existing human-confirmation receipt;
11. same proposal replay is idempotent;
12. correction requires same-Household, same-subject prior applied Claim;
13. superseded Household Claim history remains readable;
14. proposal/event/capture workflow state remains consistent;
15. no task, Rhythm, consequence, carrier, capacity, or Clock row is created;
16. authenticated clients cannot directly execute the internal promotion writer;
17. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
18. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI and run Production Schema Clone Validation before merge. Production release remains a separate authority.
