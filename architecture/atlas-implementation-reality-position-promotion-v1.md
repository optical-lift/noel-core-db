# Atlas Implementation Reality Position Promotion v1

## Purpose

Graduate the next structural Reality Sentence family after Organization Unit:

`Organization Unit has Position`

The canonical owner already exists as `atlas.organization_positions`. A Position is durable institutional structure inside an Organization Unit. It is not an appointment, person, responsibility, billing seat, Initial Scope row, or implementation artifact.

## Canonical truth owner

`atlas.organization_positions` owns:

- `organization_id`;
- `organization_unit_id`;
- `display_title`;
- `position_kind`;
- internal `stable_key`;
- `status`.

The composite foreign key on `(organization_id, organization_unit_id)` keeps Position custody inside the Unit's Organization.

## Reality Sentence grammar

Operation:

`organization_position.establish`

Bindings:

- subject = proposed `organization_position`;
- object = canonical `organization_unit`;
- context = null.

Semantic payload:

- required `positionKind` = nonblank string.

Organization is derived from the canonical Unit. It is not redundantly authored as a context binding.

`stable_key` is an owning-domain implementation identifier and must not be supplied through the Reality Sentence.

## Human rendering

`Unit Name has Position Display Title (positionKind).`

Canonical rerender is generated from `atlas.organization_positions` + `atlas.organization_units`, never copied from literal candidate wording.

## Authority

Readiness requires:

1. open Implementation Case;
2. signed-in assigned practitioner;
3. canonical active Organization Unit;
4. active root Ledger entitlement binding for that Unit's Organization;
5. active Organization participation in that Ledger;
6. verified setup sponsor whose canonical Principal governs that Ledger;
7. proposed Position subject;
8. nonblank `positionKind`.

Initial Scope and Finding adjudication remain separate membranes.

## Identity rule

For v1, a normalized Position display title inside the same Organization Unit is treated as the institutional role identity boundary.

- same title + same kind + active = existing canonical identity;
- same title with conflicting kind/status = canonical conflict.

Appointments may attach multiple people to one Position; repeated people do not require duplicate Position rows.

## Preview boundary

The preview may validate grammar, semantic payload, Unit custody, Ledger authority, and existing canonical identity. It may canonical-rerender already promoted Position truth and dynamically report whether the exact promotion RPC exists.

It may not mutate Position truth, candidate state, appointments, responsibilities, Initial Scope, or Findings.

## Mutation tranche

After preview release, the owning-domain command will add:

`public.promote_implementation_reality_position_self_api_v1(uuid)`

It must rerun preview, generate an internal collision-safe stable key, establish/reuse only lawful Position truth, record the receipt on the candidate, and rerender from canonical Position custody.

## Sequence

`Organization Unit → Position → Responsibility → Position↔Responsibility → Person↔Position appointment`

## Private Atlas Actions boundary

The private `optical-lift/atlas` repository remains untouched while its Actions quota is locked. This database-source tranche uses only public `noel-core-db` custody/release infrastructure.
