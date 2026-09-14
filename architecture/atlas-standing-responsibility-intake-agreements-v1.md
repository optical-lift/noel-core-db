# Atlas Standing Responsibility Intake Agreements v1

## Status

Architecture contract only. No executable standing-intake schema or runtime exists in this tranche.

## Purpose

Define how a Person may decide **in advance** to accept bounded classes of future responsibility offers without turning employment, membership, title, seat, or sender power into unilateral assignment.

This contract extends the already-settled cross-Atlas responsibility model:

- delivery of a responsibility offer is not assignment;
- the receiver ultimately determines whether responsibility is accepted;
- offer lifecycle and responsibility lifecycle are separate;
- accepted offers may produce different responsibility effects;
- visibility, responsibility, action authority, custody, compensation, and product delivery remain independent dimensions.

## Governing principle

A receiver may accept responsibility either:

1. **item-by-item**, after a particular offer arrives; or
2. **in advance**, through a standing responsibility-intake agreement that precisely defines what future offers the receiver has already agreed to take on.

A standing agreement is therefore not a sender-side assignment privilege. It is durable evidence of the receiver's prior consent.

The agreement may be proposed or authored by another party. What matters is that the receiver has assented to its bounded terms.

Conceptually:

```text
Person P assents to standing intake agreement A
A admits future offers from source S
A is bounded to governed Scope/category/effect/time/context

future offer O arrives
        + A is active
        + O satisfies every required boundary of A
        + source/custody/target resolution is sufficiently determinate
        -> O may become accepted on the basis of A
        -> resulting Responsibility Relation is created/current
```

If Atlas cannot prove that the offer satisfies the standing agreement, the offer remains an ordinary pending offer. Ambiguity must fail closed rather than expanding the agreement.

## Generic, not employment-only

The primitive is **standing responsibility intake**, not `employment assignment`.

Examples include:

- an employee agreeing to carry a bounded class of work from an employer;
- a spouse saying, "send me anything about household bills";
- one collaborator agreeing in advance to handle all photography requests for a project;
- a vendor agreeing to receive and fulfill a defined class of service requests;
- a friend agreeing to handle a recurring category of errands;
- a volunteer agreeing to take responsibility for a bounded community function.

Employment is one compensated relationship context in which standing intake is common and operationally important.

## Employment meaning

Employment does not mean:

> the employer can make any proposition or task the employee's responsibility by sending it.

Employment means, in this architecture:

> the Person has entered a compensated standing relationship in which they may pre-accept bounded classes of responsibility sent from a specified institutional source under agreed conditions.

The compensation/employment relationship may also establish expectations, schedules, escalation consequences, capacity assumptions, and remedies for refusal or non-performance. Those consequences are separate institutional facts from whether a particular responsibility was accepted.

A seat, membership, appointment, title, or position may support the evidence/basis for the standing agreement. None of those objects is itself the standing acceptance.

## Minimum semantic boundaries of a standing agreement

A future executable agreement must be able to identify at least:

- **receiver Person** — the Person whose assent creates the advance acceptance;
- **accepted source** — the Person, Organization, Ledger, governed relationship, or other source class from which qualifying offers may originate;
- **governed target boundary** — exact subject, Governed Scope, semantic category, predicate envelope, or another sufficiently bounded description of the responsibility reality that may be admitted;
- **admitted responsibility effect(s)** — for example carrier transfer, delegated child responsibility, shared participation, or new requested responsibility;
- **effective window** — when the standing agreement is active;
- **basis/provenance** — why the agreement exists and how the Person expressed assent;
- **status/lifecycle** — enough to establish when the agreement is active, revised, suspended, ended, or superseded;
- **optional delivery/context conditions** — where necessary, constraints such as channel, schedule, geography, work class, capacity, or other governed predicates.

These dimensions are conceptual requirements, not a commitment to a specific table shape.

## Receiver consent remains primary

The standing agreement is effective because the receiver assented to it.

The source cannot unilaterally enlarge it.

For example, if Anna has pre-accepted:

```text
source: Elm Farm
scope: routine farm production work
allowed effect: carrier responsibility / delegated child responsibility
active: during employment window
```

then an Elm offer that clearly falls inside that boundary may be accepted immediately on the basis of Anna's standing agreement.

But an offer concerning a different business, private household matter, materially broader management responsibility, or another Scope outside the standing boundary remains pending for Anna's explicit decision.

## No wildcard-by-title rule

The following are not sufficient generic standing acceptance evidence by themselves:

- `employee` seat;
- Organization membership;
- position title;
- appointment;
- role label;
- payroll relationship;
- supervisor label;
- `Farm Steward` or similar human-language title;
- being physically scheduled for work.

Those facts may explain or corroborate a standing agreement. They cannot silently manufacture its scope.

## Delivery under a standing agreement

When a qualifying offer arrives under an active standing agreement, Atlas should preserve both facts:

1. a responsibility offer crossed the receiver's Atlas boundary; and
2. it was accepted under a specific standing agreement.

The system should not erase the offer layer merely because acceptance was automatic under prior consent.

Conceptually:

```text
Offer O
  status: accepted
  acceptance_basis: standing_agreement A

Responsibility Relation R
  person: receiver P
  target: governed subject/scope
  state: current
  source_offer: O
  basis: A
```

This preserves explainability: Atlas can answer not only **what is this Person responsible for?** but also **why did this become their responsibility without a fresh click?**

## Standing intake does not grant visibility

A standing agreement does not itself create semantic visibility.

It is valid for Atlas to have:

```text
Person P has pre-accepted responsibility class C
qualifying offer O arrives
Responsibility Relation becomes current
P still lacks broader live visibility into the source Ledger
```

The intentionally disclosed offer payload may be visible because it was sent to P. Any further source visibility must come from the independent visibility system.

If the Person needs more information to execute responsibly, Atlas may surface that as a missing-visibility or insufficient-context condition. It must not silently expand visibility because responsibility exists.

## Standing intake does not move custody

Acceptance under a standing agreement does not move the governed subject into the receiver's Ledger.

Elm work accepted by Anna remains Elm-governed if Elm is the effective custodian of that reality. A household obligation may remain household-governed. A genuinely new personal responsibility may be person-governed. Custody follows the reality, not the acceptance mechanism.

## Standing intake and effect resolution

A standing agreement may admit only specified responsibility effects.

Examples:

- an employee may pre-accept **carrier responsibility** for routine Company Work;
- a specialist may pre-accept only **delegated child responsibilities** beneath a broader owner's responsibility;
- a collaborator may pre-accept **shared participation** but not transfer;
- a service provider may pre-accept creation of a **new requested responsibility** under defined commercial terms.

If an incoming offer's effect cannot be resolved within the standing agreement's allowed effects, acceptance must not be inferred. The offer remains pending or otherwise unresolved until clarified.

## Revocation and ending

A receiver may end or revise a standing agreement prospectively, subject to whatever separate contractual/employment consequences govern that relationship.

Ending the standing agreement means:

> future offers no longer qualify for advance acceptance.

It does **not** mean:

> all already-current responsibilities disappear.

Current Responsibility Relations must still reach `completed` or `released` through their own lifecycle.

Similarly, an employer ending employment may terminate future standing intake while leaving already-existing responsibilities to be explicitly released, transferred, completed, or otherwise resolved.

## Item-level refusal after standing acceptance

Once a qualifying offer has been accepted under a valid standing agreement, Atlas should not rewrite history and pretend the Person never accepted it merely because they later object.

The Person may instead:

- request or effect release where the governing relationship permits it;
- return/reroute the responsibility through a valid handoff process;
- raise a dispute claim that the offer never actually matched the standing agreement;
- claim that the standing agreement had already ended or was narrower than Atlas resolved;
- invoke whatever refusal, safety, capacity, contractual, or employment mechanism applies.

A later assertion that the work was outside the agreement is a claim/evidence question. If the match is genuinely disputed, effective responsibility may become indeterminate until resolved under the claims/evidence/adjudication layer.

## Capacity and overload

A standing agreement does not imply infinite capacity.

Future executable intake may include capacity predicates or separate capacity governance. If the agreement says only what class of responsibility is admitted but no capacity ceiling is established, Atlas must not invent one.

Likewise, exceeding expected workload may create planning/escalation reality without automatically proving that already-accepted responsibility never existed.

## Source validity

The source boundary matters.

A standing agreement to accept Elm Farm production work does not mean any Person can label an offer `Elm Farm` and force acceptance. Atlas must resolve the actual source/custody/relationship basis sufficiently to establish that the offer originated through the admitted source boundary.

False source claims remain claims. They do not satisfy the agreement merely because they are asserted.

## Scope/category resolution

When an agreement refers to a Governed Scope or semantic category, the incoming target must resolve inside that boundary under the same fail-closed Scope membership rules already established for Atlas.

Unresolved Scope membership cannot be used to auto-accept an offer.

Thus:

```text
standing agreement admits Scope S
incoming target T
membership(T, S) = unresolved

=> no automatic acceptance
=> offer remains pending/unresolved
```

## Relationship evidence versus acceptance evidence

Existing organization machinery may provide important context:

- `organization_employee_seats` — product/billing delivery;
- `organization_memberships` — current organization identity/access compatibility;
- `organization_positions` — persistent institutional positions;
- `organization_position_appointments` — who currently holds a position;
- `organization_responsibilities` — standing institutional responsibility concepts;
- `organization_position_responsibilities` — relation between positions and those concepts;
- `organization_responsibility_scopes` — legacy/local scoped responsibility language.

These are not promoted into the generic standing-intake primitive.

A future migration may correlate or derive compatibility evidence from them, but the generic contract must preserve the distinction:

```text
employment/position evidence
          !=
receiver's standing advance acceptance
```

## Auditability

For every responsibility admitted through standing intake, Atlas must be able to explain at least:

- who the receiver was;
- what offer arrived;
- who/what the source was;
- which active standing agreement admitted it;
- which target boundary matched;
- what responsibility effect was applied;
- what governed subject/scope became the responsibility target;
- where custody remained;
- when the acceptance became effective;
- whether later release/completion/dispute events occurred.

## Historical reconstruction

Standing agreements must be reconstructable historically.

If an agreement was active on September 10 and ended September 12, an offer delivered September 11 may have been validly accepted under the agreement even though the agreement is inactive today. Current state cannot be used to rewrite historical responsibility.

Future executable design therefore needs durable event history or equivalent temporal provenance.

## No hidden hierarchy

Standing intake does not establish rank.

An employee may have a standing intake agreement from a business without becoming a lower ontological class of Person. A spouse may have a broad household intake agreement. A contractor may have a narrower vendor intake agreement. These are bounded relationship facts, not a universal hierarchy.

Broader triage rights still depend on independently resolved visibility + responsibility containment under the aperture rules already established.

## Deliberately not included yet

This architecture tranche creates no:

- standing-intake agreement table;
- agreement event table;
- automatic-acceptance trigger;
- employment contract table;
- payroll/compensation schema;
- capacity model;
- refusal consequence model;
- release/return RPC;
- generic offer table;
- generic responsibility relation table;
- visibility grant;
- authority grant;
- roster relation;
- UI;
- Worker Day migration.

## Resulting law

The settled law is:

> Responsibility always originates in the receiver's consent. That consent may be expressed after an individual offer arrives or in advance through a bounded standing responsibility-intake agreement. Employment commonly supplies the compensated relationship in which such advance consent is established, but employment labels, seats, positions, and memberships do not themselves create acceptance. A qualifying future offer may become accepted immediately only when Atlas can prove that it falls inside the receiver-assented standing agreement. Ambiguous or out-of-bound offers remain pending. Ending the standing agreement stops future automatic acceptance but does not erase already-current responsibility.
