# Atlas Implementation Reality Position Responsibility Definition v1

## Status

Source candidate only. Not released to production as of 2026-10-02.

Branch:

`architecture/implementation-reality-position-responsibility-definition-v1`

## Why this is the next command

`position_responsibility_definition.establish` is already admitted by the live Reality Candidate v2 grammar, but has no promotion command.

Unlike `organization.establish` or `person.establish`, this operation does not need to mint a new identity. It joins three identities that must already exist canonically:

- Organization Position;
- Organization Responsibility;
- governing Organization.

Production already carries this truth in `atlas.organization_position_responsibilities`. Existing rows use `relationship_kind = accountable`. Positions and Responsibilities are not presently canonical `reality.entities`, so this command intentionally stays on the governed Atlas institutional carrier instead of manufacturing Reality Entity identities solely to use the generic relationship substrate.

## Operation meaning

For v1:

`Position carries Responsibility`

means:

`the Position is accountable for the Responsibility`.

The operation does not expose a free-form relationship kind. Its semantics are fixed by the command contract to `accountable`.

If future institutional grammar needs advisory, supporting, consulted, delegated, or other relationship kinds, those require separately governed operation semantics rather than overloading this command.

## Preview requirements

Promotion is available only when all of the following are true:

1. candidate operation is exactly `position_responsibility_definition.establish`;
2. subject is a canonical active Organization Position;
3. object is a canonical active Organization Responsibility;
4. context is a canonical active Organization;
5. Position, Responsibility, and context all belong to the same Organization;
6. semantic payload is empty — this command has no free-form semantic fields;
7. establishment basis is explicit and of an already admitted basis kind;
8. the Organization has a current root Ledger entitlement binding for the Implementation Case;
9. the Organization actively participates in that Ledger;
10. a verified setup sponsor exists;
11. the setup sponsor resolves to an active Principal with authority over that Ledger;
12. the canonical Position/Responsibility pair does not already conflict.

If the exact accountable pair already exists, preview returns `canonical_relation_exists` and performs no mutation.

## Canonical consequence

The canonical write is one idempotent row in:

`atlas.organization_position_responsibilities`

with:

`relationship_kind = accountable`.

Because the carrier has a composite primary key and no independent row UUID, the Reality Candidate consequence reference uses the stable pair:

`<position_uuid>|<responsibility_uuid>`

The candidate remains the durable provenance carrier for establishment basis, evidence references, actor, Implementation Case, preview scope, and promotion receipt.

## Authority boundary

The assigned practitioner may compose and submit the candidate but does not gain canonical mutation authority merely by doing so.

Promotion still requires the verified setup sponsor Principal to govern the bound Ledger, matching the current Position and Responsibility establishment membranes.

## Data API boundary

Internal preview, promotion, establishment, and renderer functions are not executable by `anon`, `authenticated`, or `service_role` directly.

The public Data API exposes authenticated-only wrappers:

- `preview_implementation_reality_position_responsibility_definition_self_api_v1`
- `promote_implementation_reality_position_responsibility_definition_self_api_v1`

## Release order

1. validate in a disposable production-schema clone;
2. prove ACL and authority behavior;
3. release the database command deliberately;
4. prove a real or fixture candidate reaches `ready`, promotes once, and becomes idempotently `already_promoted` / existing relation thereafter;
5. only then change Atlas from recognized-not-admitted to executable and make the browser route deployment-eligible.

No production database change is authorized by this source candidate.
