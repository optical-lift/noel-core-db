# Atlas Reality Sentence Establishment v1

**Status:** executable architecture candidate — not a migration, not releasable  
**Established:** September 21, 2026  
**Depends on:** merged source for `20260921150000_atlas_institutional_person_record_v1.sql`; production release of that prerequisite before any dependent application promotion  
**Product authority:** `optical-lift/atlas/docs/product-map/IMPLEMENTATION-REALITY-AUTHORING-CONTRACT.md` (PMD-025)

## 1. Purpose

Establish the first reusable database/kernel tranche behind Atlas Reality Sentence authoring and the Implementation Workbench.

The first proof is deliberately narrow:

- Organization;
- Organization Unit;
- Person;
- Institutional Person Record;
- Organization Position;
- Organization Responsibility;
- Position ↔ Responsibility;
- Person ↔ Position Appointment.

The proving sentence family is the ordinary institutional reality a practitioner must be able to teach Atlas without SQL:

- “Anna is known to Elm.”
- “Elm has the Production unit.”
- “Farm Steward exists in Production.”
- “Production stewardship is a responsibility of Elm.”
- “Farm Steward carries Production stewardship.”
- “Anna occupies Farm Steward.”

Elm is a proving corpus, not a schema vocabulary source. The same operations must fit an unrelated organization without code changes.

## 2. Governing laws

This tranche implements the existing product law:

> Atlas must be teachable by a human without hand-coding database rows and without granting an AI direct truth authority.

> Implementation may propose reality. Only the owning domain may establish reality.

> A sentence is a human interface to governed commands, not a new truth store.

And the governing shorthand:

> Teach Atlas the customer's reality. Do not teach the codebase a new customer.

Reality Sentence authoring therefore does **not** create a generic fact/EAV database and does **not** make sentence text canonical truth.

The path is:

~~~text
evidence / testimony
→ implementation establishment item
→ structured Reality Sentence candidate
→ identity + custody resolution
→ establishment capability resolution
→ consequence preview
→ practitioner decision
→ owning domain command
→ canonical consequence
→ canonical projection / rerender
~~~

The original sentence remains provenance after establishment. The canonical domain consequence becomes truth authority.

## 3. Why Organization Unit is in the first executable grammar

The selected product proof names Organization, Person, Position, Responsibility, their relations, and appointment.

Current canonical structure has an additional hard dependency: an Organization Position requires an `organization_unit_id`.

Therefore a greenfield Position cannot lawfully be established without Organization Unit reality.

Do not hide this by:

- inventing a default unit;
- using the Organization id as a fake unit id;
- manufacturing an “Elm” unit from a Position title;
- embedding a farm-specific unit assumption in the workbench.

The first Establishment Registry must include:

`Organization has Organization Unit → Organization structure command`

For an existing organization such as the current Elm corpus, the sentence may bind to an already-established Organization Unit. For a greenfield organization, the practitioner must be able to establish the Unit through the same governed command universe.

## 4. Reuse the existing Implementation Case substrate

Do not create an unrelated Reality Sentence candidate store.

Use `atlas.implementation_establishment_items` as the durable candidate shell and evolve it with a dedicated `reality_sentence` category plus structured columns.

Current generic establishment items already preserve:

- implementation case custody;
- human author;
- title/detail;
- proposed / established / unresolved / superseded lifecycle;
- basis/provenance.

Reality Sentence adds only the semantics required to resolve a lawful domain command and prove a canonical consequence.

Proposed additive columns:

| Column | Meaning |
| --- | --- |
| `source_finding_id` | optional originating `implementation_finding`; machine/plain-language findings can converge into the same authoring path |
| `reality_operation_key` | versioned Establishment Registry operation key |
| `semantic_bindings` | structured candidate arguments/identity bindings; never canonical truth by itself |
| `resolution_state` | current command-resolution state |
| `canonical_consequence` | command receipt / canonical identifiers after successful establishment |
| `established_by_user_id` | practitioner who invoked the governed establishment |
| `established_at` | successful canonical establishment time |

For `category='reality_sentence'`:

- `title` is the preserved authored sentence shown to the human;
- `detail` may hold explanatory practitioner context;
- `basis` preserves construction mode and evidence provenance;
- `status='established'` is permitted only when the owning command has succeeded and a canonical receipt is present.

The existing generic `save_implementation_establishment_item_self_api_v1` must **not** gain permission to create or mark `reality_sentence` rows established. Dedicated APIs own this category so a workflow label cannot masquerade as domain truth.

## 5. Construction modes converge

A Reality Sentence candidate records `basis.constructionMode` as one of:

- `manual_structured`
- `manual_plain_language`
- `machine_proposed`
- `source_derived`

These are provenance distinctions only. They do not change truth authority.

### Manual structured

The practitioner explicitly selects semantic parts.

Example:

`Anna → occupies → Farm Steward → in Production`

### Manual plain language

The practitioner types ordinary language. Interpretation may propose `reality_operation_key` and bindings. The original text remains evidence.

### Machine proposed

An existing accepted `implementation_finding` can become the source of a Reality Sentence candidate. Acceptance of the finding does not establish the domain consequence.

### Source derived

Connected-source evidence can produce a candidate, but source trust does not bypass identity, custody, or owning-domain command resolution.

## 6. Establishment Registry v1

The Registry is a versioned kernel contract, not an English-verb ontology and not customer vocabulary.

The first entries are:

| Operation key | Render grammar | Owning consequence |
| --- | --- | --- |
| `organization.establish.v1` | `{Organization} exists.` | existing Principal-owned Organization + governing Ledger establishment |
| `organization_unit.establish.v1` | `{Organization} has {Organization Unit}.` | Organization Unit |
| `institutional_person.establish.v1` | `{Person} is known to {Organization}.` | Canonical Person + Institutional Person Record, or existing Person + Institutional Person Record |
| `organization_position.establish.v1` | `{Position} exists in {Organization Unit}.` | Organization Position |
| `organization_responsibility.establish.v1` | `{Responsibility} is a responsibility of {Organization}.` | Organization Responsibility |
| `position_responsibility.establish.v1` | `{Position} carries {Responsibility}.` | Position ↔ Responsibility relation |
| `position_appointment.establish.v1` | `{Person} occupies {Position}.` | Institutional Person Record ↔ Position Appointment |

The registry descriptor must identify:

- operation key + version;
- allowed semantic kinds;
- required bindings;
- owning domain;
- execution class;
- authority requirement;
- identity-resolution requirement;
- canonical command key;
- consequence kind;
- preview/rerender contract.

The Registry must be reusable later by ordinary semantic interaction. Do not create a second onboarding-only verb map.

## 7. Organization birth is intentionally different

A practitioner assignment does not create Principal authority.

Current canonical Organization birth is already governed by:

`atlas.establish_organization_ledger_self_api_v1(...)`

That command resolves the signed-in Canonical Person and active Principal, establishes the Organization and governing Ledger, and creates root Principal → Ledger authority.

Reality Sentence must reuse that authority instead of inventing practitioner ownership.

Therefore `organization.establish.v1` is present in the Registry but its execution class is `principal_self`.

In the practitioner workbench, a proposed “Acme exists” candidate may preview as:

`requires_principal_self_establishment`

until the setup sponsor / Principal establishes the Organization through the owning command.

A later explicit delegation design could add another lawful path. This tranche does not infer one.

## 8. Practitioner implementation scope

For all practitioner-executable organization-structure operations, the command resolver must prove the current user is:

1. an active Atlas implementation practitioner;
2. the active `practitioner` participant on the exact Implementation Case;
3. operating against the Organization/Ledger already bound to that case;
4. within any narrower Organization Unit scope of the active binding, if present.

The Implementation Case does not itself confer ownership of the Organization.

Commercial entitlement also does not manufacture institutional authority. It is only the existing bounded implementation relationship connecting the practitioner to a preexisting governed Ledger scope.

The first resolver may use the current active `ledger_entitlement_bindings` relationship as the exact implementation scope seam.

If the case has no active Ledger binding, structure-establishment preview must remain blocked rather than falling back to an arbitrary Organization id supplied by the browser.

## 9. Identity law for Person establishment

Names are not identity.

`institutional_person.establish.v1` supports exactly two explicit identity modes:

### Existing Person

Required:

- explicit canonical `personId`;
- target Organization in implementation scope.

Result:

- establish/reuse exactly one active Institutional Person Record for that Organization + Person.

### New Person

Required:

- explicit `displayName`;
- explicit practitioner decision that this is a new human identity;
- target Organization in implementation scope.

Result in one governed transaction:

1. create one Canonical Person;
2. create one Institutional Person Record for the target Organization;
3. return both canonical ids.

The command must **not** search `atlas.people.display_name` and silently reuse a same-named Person.

The command must **not** create:

- `auth.users`;
- Person Auth Credential;
- Organization Membership;
- employee seat;
- access/delivery;
- Position;
- Responsibility;
- Work allocation;
- Personal Atlas.

Those are separate relations and consequences.

## 10. Organization Unit establishment law

`organization_unit.establish.v1` requires:

- exact implementation-scoped Organization;
- nonblank display name;
- explicit `unitKind`;
- optional explicit parent Organization Unit already in the same Organization;
- either an explicit stable key or a deterministic candidate key accepted by the operator.

Stable key collisions fail closed unless the candidate explicitly binds to the already-existing Unit.

A same display name is not sufficient evidence that two Units are identical.

## 11. Position establishment law

`organization_position.establish.v1` requires:

- target Organization in implementation scope;
- exact active Organization Unit in that Organization;
- nonblank display title;
- explicit `positionKind`;
- stable identity decision.

A title such as “Farm Steward,” “Executive Director,” “Shop Manager,” or “Treasurer” is organization data. It does not create an Atlas platform type.

Position establishment creates no occupant, employee seat, authority, permission, or Company Work allocation.

## 12. Responsibility establishment law

`organization_responsibility.establish.v1` requires:

- exact implementation-scoped Organization;
- nonblank name;
- explicit `responsibilityKind`;
- stable identity decision.

Responsibility text describes durable institutional stewardship/function. Domain-specific scope is linked separately.

Creating a Responsibility does not assign it to a Person and does not manufacture Company Work.

## 13. Position ↔ Responsibility law

`position_responsibility.establish.v1` requires:

- active Position;
- active Responsibility;
- both in the exact same Organization;
- explicit relationship kind.

The first ordinary relationship kind is `accountable`, but the database contract remains data-driven/nonblank rather than customer-specific.

The operation is idempotent for the same Position + Responsibility relation.

## 14. Person ↔ Position Appointment law

This operation depends on Institutional Person Record source becoming live.

`position_appointment.establish.v1` requires:

- active Institutional Person Record in the target Organization;
- active Position in the same Organization;
- explicit appointment kind;
- effective begin time;
- optional end time.

It must target the Institutional Person Record as the canonical institutional human relation.

It must not require:

- auth credential;
- Organization Membership;
- employee seat;
- Personal Atlas.

Existing authenticated carriers may remain linked as compatibility evidence where present.

Appointment means occupancy of Position. It does not automatically create Decision Authority, generic permission, employee product access, or Company Work allocation.

## 15. Candidate resolution states

The first command resolver uses explicit states rather than booleans:

- `draft`
- `ready`
- `unresolved_identity`
- `unsupported_operation`
- `missing_required_binding`
- `requires_principal_self_establishment`
- `implementation_scope_unbound`
- `outside_implementation_scope`
- `canonical_conflict`
- `prerequisite_not_live`
- `established`
- `superseded`

A blocked candidate remains durable. It is not discarded or stuffed into Notes/Tasks.

## 16. Preview is mandatory

Before an establishment write, the workbench must be able to receive a deterministic preview including:

- rendered sentence;
- operation key;
- normalized semantic bindings;
- existing canonical identities that will be reused;
- canonical identities that would be created;
- owning domain command;
- authority/scope result;
- conflict/unresolved conditions;
- consequence summary;
- rerender/read contract.

Preview must not create canonical domain reality.

The preview output becomes the basis for the explicit practitioner action.

## 17. Canonical command receipt

On successful establishment, the owning domain command returns an operation-specific receipt.

The Reality Sentence orchestration stores a bounded receipt such as:

~~~json
{
  "operationKey": "position_appointment.establish.v1",
  "consequenceKind": "organization_position_appointment",
  "organizationId": "...",
  "institutionalPersonRecordId": "...",
  "positionId": "...",
  "appointmentId": "...",
  "projectionContract": "organization_reality_sentence_projection_v1"
}
~~~

The receipt is provenance, not a second copy of the domain row.

A Reality Sentence may become `status='established'` only inside the same transaction that obtains a successful canonical receipt.

## 18. Canonical rerender

After establishment the workbench stops treating the authored text as the truth source.

It asks the owning projection to rerender the consequence.

Examples:

- Person + Institutional Person Record → “Anna is known to Elm.”
- Position + Responsibility relation → “Farm Steward carries Production stewardship.”
- Appointment → “Anna occupies Farm Steward.”

If the underlying canonical relation later changes, the rendered Reality Entry changes even though the original authored statement remains preserved as provenance/history.

## 19. Workbench read shape

The first case-scoped Reality Sentence read should return two explicit sets:

### Candidates

- establishment item id;
- original sentence;
- construction mode;
- operation key;
- resolution state;
- semantic bindings safe for practitioner display;
- preview;
- source finding/evidence references;
- candidate status.

### Established Reality Entries

- establishment item/provenance id;
- canonical consequence ids;
- canonical rerendered sentence;
- semantic target descriptors;
- current canonical state;
- provenance/evidence references.

The established list must be built from canonical read projection plus establishment provenance, not from `implementation_establishment_items.title` alone.

## 20. First UI behavior

The Implementation Workbench should become an Implementation Spread rather than a permanent CRUD admin screen.

The first authoring control can be compact and deliberate:

~~~text
Tell Atlas something true

[Anna] [occupies] [Farm Steward] [in Production]

Preview
Anna occupies Farm Steward.
Existing: Anna (Person), Production (Unit), Farm Steward (Position)
Will create: Position Appointment
Authority: Implementation Case / Elm Ledger
[Establish]
~~~

For a new identity:

~~~text
[New person: Sarah] [occupies] [Executive Director] [in Organization]

Identity decision required:
○ Sarah is an existing Person [choose]
● This is a new Person

[Preview]
~~~

The UI never exposes table names as the user’s mental model.

## 21. Existing machine-artifact path convergence

Current artifact review promotes an accepted machine extraction to an `implementation_finding` or `implementation_request`.

Keep that behavior.

Add a later explicit transition:

`accepted implementation_finding → Reality Sentence candidate`

The finding remains evidence. The Reality Sentence candidate owns structured command resolution. The domain owns truth establishment.

AI therefore gains no new authority from being the source of the proposal.

## 22. Security posture

Follow current Supabase/API governance:

- all canonical tables remain unavailable for direct browser mutation;
- internal domain command functions live in `atlas`;
- browser-facing wrappers are narrow and explicit;
- no new function is executable by `anon`;
- every authenticated Reality Sentence write rechecks practitioner + exact case scope;
- do not trust Organization/Unit ids merely because the browser supplied them;
- `SECURITY DEFINER` functions must validate all authority and scope internally;
- do not broaden generic table grants to make the workbench easier to implement.

Existing unrelated historical RPC grant problems are outside this tranche unless a new function would depend on them.

## 23. Production/release boundary

This architecture candidate is deliberately **not** placed in `supabase/migrations/`.

Reasons:

1. the dependent Institutional Person Record migration is merged in source but not yet released to production;
2. repository policy requires canonical migration identities to be generated through the pinned Supabase CLI workflow;
3. a chat-authored filename must not become canonical migration identity;
4. production mutation is separate authority and is not granted by implementation work.

When prerequisites are satisfied, the executable SQL candidate should be converted through:

`supabase migration new atlas_reality_sentence_establishment_v1`

Then the exact generated migration must receive:

- matching validation migration;
- production-shaped DML fixture if needed;
- rollback-only postconditions;
- Database Custody CI;
- fresh protected production-schema clone validation;
- separate governed production release.

## 24. Acceptance proof

The first executable proof is successful only when all of these hold:

1. A practitioner can create a manual structured Reality Sentence candidate without AI.
2. An accepted machine finding can converge into the same candidate path.
3. Candidate creation writes no domain truth.
4. Preview exposes the exact owning operation and consequence.
5. An accountless new human can become Canonical Person + Institutional Person Record without `auth.users`.
6. Organization Unit can be established generically.
7. Position can be established under an exact Organization Unit.
8. Responsibility can be established generically.
9. Position ↔ Responsibility can be established.
10. An accountless Institutional Person can be appointed to a Position.
11. None of those operations creates access, employee seat, Personal Atlas, Company Work, or generic authority as a side effect.
12. Same-name Person ambiguity never auto-merges.
13. Cross-Organization ids fail closed.
14. A practitioner cannot write outside the Ledger scope bound to the Implementation Case.
15. An unbound Implementation Case cannot establish organization reality.
16. A Reality Sentence cannot be marked established without a canonical command receipt.
17. After establishment, display is rerendered from canonical reality rather than authored sentence text.
18. The same registry/commands work for an unrelated synthetic organization with unrelated titles and names.
19. No customer-specific title becomes a platform type.
20. No production mutation or application deployment is implied by source acceptance.

## 25. Sequence from here

### Tranche A — source candidate

- this architecture contract;
- exact SQL candidate outside migration authority;
- rollback-only validation specification.

### Tranche B — prerequisite release

- release/verify Institutional Person Record through its own governed path.

### Tranche C — canonical DB migration

- generate migration identity with pinned Supabase CLI;
- replay reviewed candidate from current `main`;
- pass custody + clone validation;
- merge;
- separately release and verify.

### Tranche D — Workbench application slice

After the database contract is live:

- add Reality Sentence composer to the Implementation Case;
- read Registry + case-scoped candidates;
- preview through database resolver;
- establish only through the governed command;
- rerender canonical Reality Entries;
- preserve existing conversation/artifact surfaces as evidence intake.

### Tranche E — broader onboarding

Use the proved command universe to move organization onboarding away from one-off setup forms and toward durable Implementation Spread reality.

Do not add domain families faster than Atlas has lawful owning commands.
