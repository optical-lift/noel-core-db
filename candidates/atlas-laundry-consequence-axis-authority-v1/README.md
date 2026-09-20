# Laundry Consequence Axis Authority v1

Status: **source-complete stacked candidate; inert, not migration-identified, not clone-validated, not released**.

This tranche binds two independently sourced Household truths to the Person Life consequence without collapsing them into the consequence policy:

- **who carries the ordinary Laundry cycle**;
- **whether the required Laundry action is currently executable**.

It also prevents later consequence re-evaluation from erasing those independently authorized axes.

## Why this is necessary

The existing Person Life consequence evaluator owns requirement creation. Its upsert currently writes:

- `carrier_ref`;
- `carrier_state`;
- `execution_readiness`;
- `placement_state`

from the consequence policy result on every evaluation.

For the Laundry policy built in the prior tranche, those values correctly begin as:

- carrier unresolved;
- readiness not evaluated;
- placement unresolved.

But once later Household evidence establishes carrier or readiness, another Laundry observation must not erase that truth merely because the requirement policy itself still does not own those axes.

Therefore this tranche keeps:

> **requirement authority ≠ carrier authority ≠ execution-readiness authority ≠ placement authority**

and protects those boundaries at persistence time.

## Carrier source

The accepted Laundry instance fact:

```text
claimType = ordinary_responsibility
value.mode = self
```

is sufficient to resolve the ordinary Laundry consequence carrier to:

```text
carrier_ref   = principal:<current principal id>
carrier_state = established
```

Other supported responsibility modes do not silently choose a carrier:

- shared;
- other_household_member;
- outside_household;
- service;
- unresolved;
- other.

Those modes reconcile the consequence carrier to unresolved until a later relationship authority can identify an actual carrier.

This is intentional. “Shared” does not mean Principal.

## Execution-readiness source

Execution readiness comes from a separate Household Claim on the same Laundry instance:

```text
claimType = execution_readiness
lifecycle = observed | accepted
value.state = ready | blocked | unknown
```

V1 maps:

- `ready` → `execution_readiness = ready`;
- `blocked` → `execution_readiness = blocked`;
- `unknown` → `execution_readiness = not_evaluated`.

A requirement can therefore remain real while execution is blocked.

Ordinary Personal Reality can produce this Claim through the Household Claim route. No special Laundry task or setup object is required.

## Persistence protection

A new BEFORE UPDATE guard protects Laundry consequence axes.

If an update attempts to change carrier or readiness:

- a valid source Claim must be named in the consequence Evidence envelope; or
- if the update is merely a later requirement re-evaluation that omitted the already-valid axis authority, the guard restores the prior authorized axis and provenance.

This means:

```text
new Laundry observation
→ consequence requirement refresh
≠ erase known carrier
≠ erase known readiness
```

If a later authorized responsibility/readiness Claim deliberately changes the axis, the reconciliation API supplies that Claim and the guard permits the change.

## Reconciliation endpoint

`atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)`

accepts:

```json
{
  "responsibilityClaimId": "<optional uuid>",
  "readinessClaimId": "<optional uuid>"
}
```

At least one must be supplied.

The endpoint:

1. verifies the open consequence belongs to the signed-in user;
2. verifies its definition targets `household.laundry`;
3. resolves each supplied Claim under current Household custody;
4. updates only the authorized consequence axis/axes;
5. preserves requirement and placement state;
6. returns the updated consequence plus current Clock-admission blockers.

## Placement remains untouched

This tranche deliberately never changes `placement_state`.

Clock characterization and Clock candidate admission remain later authorities.

## Validation target

Before promotion, clone validation must prove:

1. responsibility Claim must be current Household / same Laundry instance / accepted;
2. `self` resolves carrier to the active Principal;
3. shared/other responsibility does not select the Principal;
4. readiness Claim must be current Household / same Laundry instance;
5. ready maps only to ready;
6. blocked maps only to blocked;
7. unknown maps only to not_evaluated;
8. caller cannot supply carrier/ref/readiness values directly;
9. source Claim ids are preserved in consequence evidence;
10. later Laundry consequence re-evaluation cannot erase authorized carrier;
11. later re-evaluation cannot erase authorized readiness;
12. a newer authorized responsibility Claim may intentionally clear/change carrier;
13. a newer authorized readiness Claim may intentionally change readiness;
14. placement_state is unchanged by reconciliation;
15. no task, Rhythm, Clock candidate, or Clock placement is created;
16. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
17. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI and run Production Schema Clone Validation before merge.
