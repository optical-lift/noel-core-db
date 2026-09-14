# Atlas Effective Person↔Institution Responsibility Read v1

## Status

Architecture contract only. No schema, migration, RPC, function, view, production mutation, browser permission, or application behavior is created in this tranche.

This contract refines `atlas-canonical-person-institution-responsibility-realization-v1.md` into the read semantics a future executable implementation must preserve.

## Purpose

Define one canonical answer to:

> At time T, what bounded institutional responsibility does Person P effectively carry, and what evidence makes that conclusion true?

The answer must compose existing Atlas source facts without inventing a new generic relationship ontology and without treating current rows as sufficient historical evidence after their meaning becomes mutable.

## Governing law

**Effective Person↔institution responsibility is a derived current/historical position over source facts and lawful uptake history. It is not a permission grant, not a seat entitlement, not a title, and not an allocation shortcut.**

Conceptually:

```text
canonical Person
+ institution affiliation
+ effective position appointment
+ effective position responsibility definition
+ effective responsibility Scope
+ sufficient Person uptake / establishment basis
+ effective institutional custody/context
+ no material unresolved conflict
        ↓
canonical effective Person↔institution responsibility
```

Every downstream consumer that needs durable institutional responsibility should read this same effective authority rather than reconstruct its own join/filter logic.

## 1. Source facts remain source facts

The effective read is derived from source evidence including, where applicable:

- `atlas.people`;
- `atlas.organization_memberships`;
- `atlas.identity_subjects` and governed Person binding where needed;
- `atlas.organization_position_appointments`;
- `atlas.organization_positions`;
- `atlas.organization_position_responsibilities`;
- `atlas.organization_responsibilities`;
- `atlas.organization_responsibility_scopes`;
- future responsibility-offer / acceptance / standing-intake evidence;
- future definition events or equivalent historical position-definition evidence;
- claims/evidence/adjudication where a relation is disputed;
- effective institutional custody when physical/historical organization carriers differ from current institutional treatment.

The projection does not become the source merely because it is the canonical read authority.

## 2. Current effective relation

For a position-based durable responsibility to be **established current** at evaluation time T, Atlas must be able to establish all material dimensions below.

### 2.1 Canonical Person

The institutional relationship must resolve to one canonical `Person` when the consumer is asking a Person-level question.

An auth user, Organization Membership, employee seat, or institution-local identity subject is not enough by itself.

If the institutional subject cannot be resolved to canonical Person and Person identity is material to the requested consequence:

```text
result = indeterminate
```

not:

```text
result = some guessed Person
```

### 2.2 Institution affiliation

The Organization Membership must be sufficiently established for the relevant time/context.

Current compatibility fields such as `active`, `eligibility_begins_on`, and `eligibility_ends_on` may participate in current resolution.

They are not automatically complete historical event history.

### 2.3 Effective appointment

The Person/institutional subject must occupy the relevant position at T.

For current reads, the existing appointment source can support this when:

```text
appointment begins_at <= T
and appointment has not ended before T
and current appointment state does not contradict occupancy
and organization / membership / identity / position agree
```

For historical reads, an ended appointment may still prove past occupancy when its begin/end window and preserved state truthfully establish that history.

A current `status='ended'` must not erase the fact that the appointment existed before `ends_at`.

Conversely, an `active` row with a future `begins_at` does not establish present occupancy.

### 2.4 Effective position definition

The position must itself be the position that existed/effectively applied at T.

Display title is descriptive organization language. It is not the carried responsibility.

### 2.5 Effective position↔responsibility definition

The relevant responsibility must have belonged to the position at T.

Today `organization_position_responsibilities` is a static present link with `created_at` but no append-only lifecycle.

Therefore:

- the existing seeded/current row can establish the current static definition;
- `created_at` can establish that the row did not exist before its creation;
- absence of an ending event cannot establish that the relation remained continuously effective through arbitrary future edits;
- deleting or overwriting the row in the future would destroy historical meaning unless definition history is preserved elsewhere.

Before broad live mutation is enabled, Atlas must add append-only definition history or another equally reconstructable authority and make this effective read consume it.

### 2.6 Effective responsibility

The responsibility concept itself must be applicable at T.

Current `status` is useful current-state evidence, but once responsibility definitions can be retired/reactivated/revised, historical reads require preserved transition history rather than today's status projected backward.

### 2.7 Effective responsibility Scope

The responsibility's bounded institutional/domain reality must be established at T.

Today `organization_responsibility_scopes` is likewise a present/static link with `created_at` and no ending/supersession event history.

A future Scope widening, narrowing, replacement, or removal must be represented as historical definition change rather than destructive mutation if historical Person responsibility depends on it.

### 2.8 Person uptake / establishment basis

Structural definition does not by itself make the Person carry every later version of that definition.

Atlas must establish why this Person took up the position/responsibility bundle effective at T.

Valid bases may include:

- explicit acceptance;
- bounded standing intake already assented to by the Person;
- governed reconstruction of an already-existing real-world relationship;
- adjudicated existing responsibility;
- another future basis expressly admitted by the generic responsibility architecture.

For existing Anna seed data, the universal-organization-structure migration is reconstruction provenance for a relationship Atlas was already modeling operationally. It is not precedent for unilateral generic assignment.

### 2.9 Conflict / adjudication state

If material evidence conflicts over identity, appointment, definition, Scope, uptake, release, or custody, the effective read must preserve the conflict and fail closed for consequences requiring certainty.

It must not resolve conflict by hidden precedence such as:

```text
newest row wins
owner claim wins
employee seat wins
position title wins
work allocation wins
```

unless a narrower governed adjudication rule explicitly establishes that result.

## 3. Canonical resolution states

The effective read should distinguish at least three semantic outcomes.

### `established_current`

Atlas has sufficient governed evidence that Person P carries responsibility R over bounded reality S at T.

### `established_not_current`

Atlas has affirmative governed evidence that the relation is not current at T.

Examples may include:

- appointment had ended before T;
- a responsibility relation was explicitly released/completed where that lifecycle applies;
- a historical position-definition event had already removed/superseded that responsibility;
- the relevant Scope definition had been lawfully replaced so the queried reality was no longer included;
- adjudication established that the Person did not carry the relation.

**Mere absence of a row is not always sufficient evidence for `established_not_current`.**

### `indeterminate`

The source evidence is materially insufficient or conflicting.

Examples:

- institution-local identity does not resolve to Person;
- historical membership state cannot be reconstructed;
- current position link exists but historical definition at T is unknown;
- responsibility Scope membership at T is unresolved;
- Person uptake basis for a newly widened position is unknown;
- conflicting acceptance/release evidence exists;
- effective institutional custody is unresolved.

Consumers requiring certainty must fail closed locally on `indeterminate`.

These names are semantic architecture states, not a required database enum.

## 4. Absence and non-responsibility are not identical

Atlas must not turn every missing relationship into a strong negative assertion.

There are three different questions:

```text
Do we have evidence P carries R?
Do we have evidence P does not carry R?
Do we simply lack sufficient evidence either way?
```

The effective read must preserve the distinction where downstream consequences depend on it.

For ordinary UI enumeration, a consumer may list only `established_current` responsibilities while separately surfacing unresolved relationship conditions where operationally relevant.

For institutional effect uptake, source attribution, triage, or other high-consequence resolution, `indeterminate` must not be silently treated as either current or not-current.

## 5. Time semantics

The read authority must accept or internally preserve an `as_of` time/context rather than defining responsibility only as `now()`.

Conceptually:

```text
effective_person_institution_responsibility(
  person,
  institution,
  responsibility,
  affected reality / scope,
  as_of
)
```

Historical resolution uses evidence effective at `as_of`, not current rows projected backward.

Current resolution is simply historical resolution at the present evaluation time.

## 6. Existing schema can prove current Anna more strongly than arbitrary history

For Anna today, production contains a coherent static chain:

```text
Person Anna
+ active Feast Guild membership
+ active primary Farm Steward appointment
+ active Farm Steward position in Elm
+ five position-responsibility links
+ five active responsibilities
+ five Elm organization-unit responsibility-scope links
+ reconstruction provenance from universal organization structure
```

That is sufficient architectural evidence for the current durable relation while the seeded position definition remains static and uncontested.

It does **not** mean Atlas can already answer every arbitrary historical query about future edits.

The first executable read may therefore safely provide truthful current effective responsibility over the static seeded definition while refusing to claim stronger historical reconstruction than the source model actually preserves.

## 7. Definition evolution requires separate Person uptake

Suppose at T1 Anna is established as carrying:

```text
Farm Steward
  Production stewardship
  Harvest execution
```

At T2 Elm changes the position definition by adding:

```text
Treasury stewardship
```

The position definition event may become institutionally effective at T2.

That alone does not prove Anna's Person responsibility expanded at T2.

Atlas must separately resolve Person uptake:

```text
position definition changed
        ↓
new responsibility consequence for current appointee proposed
        ↓
explicit acceptance / standing intake / reconstruction / other governed basis
        ↓
Person responsibility becomes current
```

The same applies to material Scope widening.

This prevents mutable job descriptions from becoming hidden assignment machinery.

## 8. Definition narrowing and release are also distinct

If an institution removes a responsibility from a position, that structural change is strong evidence that future position incumbents should not receive the old responsibility through that position.

For a current Person who already carries the responsibility, Atlas must still preserve what actually ends the Person's relation.

Depending on the governing effect, position-definition removal may itself be sufficient release evidence or may trigger a required release/transfer process.

The generic architecture does not silently assume either answer for every responsibility class.

The effective read therefore needs both:

```text
position definition effective at T
Person responsibility lifecycle effective at T
```

rather than treating them as one object.

## 9. Exact Company Work responsibility remains independent

`atlas.work_allocations` answers responsibility for an exact Company Work item.

The effective durable responsibility read may correlate an allocation with a durable responsibility when Atlas can prove that the work lies inside the bounded responsibility reality.

Such correlation can support explanation such as:

```text
Anna carries Harvest execution over Elm.
This exact Harvest Stems work item is also allocated to Anna.
The work is inside that durable field.
```

But correlation is not creation.

### Durable responsibility must not auto-create exact allocation

```text
Anna carries Harvest execution
```

does not imply:

```text
all current/future harvest work items are allocated to Anna
```

A work item still needs its own responsibility uptake/allocation truth.

### Exact allocation must not manufacture durable responsibility

```text
one Harvest Stems work item is allocated to Anna
```

does not imply:

```text
Anna permanently carries Elm Harvest execution
```

The allocation may be exceptional, temporary, delegated, shared, or otherwise narrower than the durable field.

## 10. Work correlation states

A future projection may find it useful to distinguish explanatory correlation such as:

```text
inside_durable_responsibility
outside_known_durable_responsibility
unresolved_against_durable_responsibility
```

These are not allocation states and must not change work ownership automatically.

`outside_known_durable_responsibility` does not automatically mean the allocation is invalid. The Person may have explicitly accepted exceptional work.

It is simply a useful institutional fact for explainability, planning, and anomaly review.

## 11. Seat and credential are read-entry gates only

Self-service APIs may lawfully require an active credential/employee seat before returning private employee projections.

That is an access check:

```text
may this credential receive this projection?
```

It is not part of the semantic formula:

```text
what responsibility does Person P carry?
```

Therefore the canonical internal effective-responsibility authority must not require a paid seat merely to conclude that real institutional responsibility exists.

An outward employee self API may wrap that internal authority with seat/credential checks.

This is the clean separation needed for future noncommercial, suspended, pre-provisioned, historical, and cross-Ledger contexts.

## 12. Farm Membership is an execution-carrier adapter

Existing Worker Day functions commonly require `farm_membership_id` because farm execution was built before the newer organization structure.

That remains useful compatibility machinery.

The canonical direction is:

```text
Person/institution exact or durable responsibility
        ↓
execution adapter resolves appropriate farm/domain membership
        ↓
Worker Day delivery
```

not:

```text
farm membership / task assignment
        ↓
infer institutional responsibility
```

Current Company Work production-carrier synchronization already preserves this direction by marking carrier assignment as not itself responsibility evidence.

## 13. `/anna` read composition

A future `/anna` page should not need one giant query that turns every layer into one status.

It should compose canonical projections:

```text
identity / connection context
+ effective institutional placement
+ effective durable responsibilities
+ exact current Company Work responsibilities
+ pending responsibility offers
+ standing intake agreements
+ independent visibility/aperture
+ execution readiness / Worker Day
+ activity and result history
```

The durable-responsibility projection supplies institutional context.

The exact-work projection supplies concrete commitments.

Worker Day supplies execution timing/readiness.

Visibility governs what can be exposed.

None replaces the others.

## 14. Minimum future projection output

A future canonical read should be capable of explaining each effective durable responsibility with fields conceptually equivalent to:

```text
personId
institutionId / organizationId
organizationUnitId
membershipId
identitySubjectId
appointmentId
positionId
positionKey
positionTitle
responsibilityId
responsibilityKey
responsibilityKind
positionResponsibilityRelationshipKind
scopeKind / scope identity / relation kind
asOf
effectiveState
establishmentBasis
establishmentProvenance
definitionProvenance
scopeProvenance
conflict / indeterminate reasons
```

Exact names and SQL shape remain implementation-owned.

The projection should prefer stable canonical identifiers and expose human-language title/name only as labels.

## 15. Explainability contract

For any `established_current` result, Atlas must be able to answer:

1. Which Person?
2. Which institution/Organization Unit?
3. Which position appointment?
4. Which institutional responsibility?
5. What bounded Scope/reality?
6. What position-definition evidence put that responsibility there?
7. What Person uptake/establishment basis made the responsibility attach to this Person?
8. What time is being evaluated?
9. What conflicting evidence, if any, was considered?
10. What later event released/completed/superseded it, if evaluating history after the relation ended?

If those questions cannot be answered sufficiently for the consequence at stake, the relation must not be promoted to `established_current` merely because a join happens to return a row.

## 16. Current limitations that the executable tranche must not hide

The production audit establishes these limitations:

- Organization Membership uses present `active` plus eligibility dates, not a complete append-only membership lifecycle;
- Position Appointment has begin/end semantics but no generic appointment event stream;
- Position↔Responsibility is currently a static link with `created_at` and no end/supersession history;
- Responsibility Scope is currently a static link with `created_at` and no end/supersession history;
- current employee self-context is seat/credential-gated;
- current Company Work responsibility writer can directly set an assignee membership under owner compatibility authority without generic receiver-consent semantics;
- generic responsibility offer/relation/standing-intake persistence is not executable yet.

The first implementation must state which of these it resolves and which remain compatibility boundaries. It must not imply stronger historical or consent semantics than actually exist.

## 17. Minimal executable sequence implied

The safest implementation order is:

1. create a side-effect-free current effective durable responsibility read over existing static source facts, canonical Person, appointment, position, responsibility, and Scope;
2. record it in the architecture truth-authority catalog as the canonical current durable-responsibility read;
3. add tests proving seat/credential is not part of internal responsibility truth;
4. adapt employee self-context to consume the canonical read behind its existing access gate;
5. expose durable responsibility to `/anna` separately from exact Company Work responsibility;
6. before allowing position-definition mutation, add historical definition events/effective-definition read authority;
7. before generic cross-Person responsibility writes, add responsibility-offer/acceptance/standing-intake establishment basis;
8. only then allow dynamic position changes to propagate through effect-specific uptake rather than direct mutable joins.

## 18. Verification contract

The future executable seam must prove at minimum:

- Anna resolves to one canonical Person;
- the current Farm Steward appointment resolves independently of employee seat semantics;
- all five current Elm durable responsibilities resolve from position definition and Scope;
- the internal durable-responsibility authority still describes the relation if product access is hypothetically absent/suspended, without granting the suspended credential access to read it;
- a future-dated appointment does not resolve current;
- an ended appointment does not resolve current but can remain historical evidence for its active window;
- a responsibility created after the queried `as_of` cannot appear historically before creation;
- a Scope link created after `as_of` cannot appear historically before creation;
- lack of sufficient historical definition evidence yields indeterminate rather than fabricated continuity;
- exact Company Work allocation does not create durable position responsibility;
- durable position responsibility does not auto-create work allocation;
- unresolved Person identity, material Scope conflict, or uptake conflict fails closed;
- current self APIs remain access-gated even though internal truth is not seat-created;
- no browser privilege is widened by introducing the canonical internal read.

## Resulting law

> Atlas must derive one canonical effective Person↔institution responsibility read from canonical Person, institution affiliation, effective appointment, historically effective position responsibility definition, historically effective responsibility Scope, Person uptake/establishment basis, and conflict/custody evidence. The read distinguishes established current, established not-current, and indeterminate rather than treating row presence or absence as universal truth. Employee seats control delivery, not responsibility existence. Farm memberships deliver domain execution, not institutional ontology. Exact Company Work allocations and durable institutional responsibilities remain separate but explainably correlatable. Historical claims may be only as strong as the preserved source history; Atlas must never project today's mutable definition backward merely because the current join is convenient.