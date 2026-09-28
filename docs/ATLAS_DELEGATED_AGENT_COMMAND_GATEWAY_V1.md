# Atlas Delegated Agent Command Gateway v1

**Status:** governed architecture / initial implementation

## Purpose

Atlas needs a repeatable way for a delegated technical carrier — including an AI agent — to operate the product without becoming a Principal, impersonating a Person, or obtaining raw database authority.

The governing movement is:

`Principal authority`
→ `explicit carrier authorization`
→ `finite Atlas command`
→ `authority evaluation`
→ `Principal confirmation when required`
→ `canonical domain service`
→ `durable command receipt`
→ `result / failure accounting`

The Principal remains the source of authority; the agent is only a carrier.

## Canonical boundaries

The command gateway does **not** own booking truth, commerce truth, work truth, Person identity, Ledger authority, or any other domain truth. Each command must terminate in the domain's already-governed service function. The gateway owns only:

- carrier identity;
- explicit delegation envelope;
- hashed access credential custody;
- finite command vocabulary;
- command authorization evaluation;
- confirmation requirement;
- durable command invocation receipt and event history.

There is no `execute_sql` command, arbitrary RPC command, table mutation command, or dynamic handler execution in the database.

## Principal / carrier separation

`atlas.delegated_agent_carriers` identifies the technical carrier. A carrier is not a `reality.entities` Person and is not an `atlas.principals` Principal.

`atlas.delegated_agent_authorizations` records what a Principal has entrusted to that carrier. A delegation can be narrowed by:

- Ledger;
- human delegating Seat;
- maximum execution class (`read`, `prepare`, `commit`);
- explicit command allowlist and denylist;
- time window;
- target kinds and target IDs;
- additional JSON scope;
- confirmation policy.

An empty command allowlist grants nothing. A delegation cannot create Ledger authority. The authority evaluator re-checks the Principal's current Ledger authority and, where present, the current human Seat relationship.

## Credentials

`atlas.delegated_agent_credentials` stores only SHA-256 token hashes. Raw bearer tokens are generated and held outside the database. Credential possession authenticates a particular delegation; it never enlarges that delegation.

Revoking a delegation revokes its live credentials.

## Command vocabulary

`atlas.agent_command_definitions` is a finite registry. Every command has:

- stable key + version;
- scope kind (`personal`, `ledger`, or `either`);
- execution class;
- confirmation requirement;
- symbolic handler key;
- optional existing Atlas capability requirement;
- input and target contracts.

Targets use the universal envelope `{ "kind": ..., "id": ... }`. Authorization scope may constrain either field.

The symbolic handler key is not executable SQL. The application Agent Gateway must map it through a hard-coded/typed registry to an existing governed domain service. Unknown handlers fail closed.

## Command lifecycle

`atlas.begin_delegated_agent_command_service_v1` authenticates the hashed credential, evaluates both command-level and target-level authority, and creates one idempotent command invocation.

Possible admission states are:

- `rejected` — the carrier lacks authority;
- `needs_confirmation` — authority exists but the command requires Principal confirmation;
- `authorized` — the command may proceed under standing delegation.

A Principal may confirm only their own pending invocation through `atlas.confirm_delegated_agent_command_self_api_v1`.

Before execution, Atlas re-evaluates current authority and target scope. The application then marks the invocation `executing`, calls the canonical domain service, and records `succeeded` or `failed`. `atlas.agent_command_invocation_events` preserves the transition history append-only.

A successful domain effect does not erase a failed or unauthorized command path; the command receipt is independent accounting of the method used.

## Initial proof domain

The initial registry proves the membrane against booking, because booking already has mature canonical domain services and meaningful consequence boundaries:

- `booking.request.read` — read;
- `booking.request.evaluate_commitment` — read;
- `booking.request.place_hold` — commit + explicit Principal confirmation;
- `booking.request.approve` — commit + explicit Principal confirmation.

This is not a wedding-specific subsystem. The schema remains domain-neutral while each handler stays domain-owned.

## Application contract

The Atlas application layer should expose a server-side Agent Gateway with these operations:

1. discover the command catalog available under the current delegation;
2. begin a command using a delegated bearer credential + idempotency key;
3. if admitted and immediately authorized, dispatch only through a typed handler registry;
4. if confirmation is required, return the pending invocation without executing;
5. allow the carrier to query the invocation receipt;
6. after Principal confirmation, allow the same invocation to resume rather than creating a second one.

The server must hash the bearer token before sending it to Supabase. Raw delegated credentials must never be logged or stored in Atlas tables.

## Not established by v1

This implementation does not:

- create an active AI carrier;
- give ChatGPT or any other provider standing authority;
- issue a bearer credential;
- deploy an Agent Gateway endpoint;
- create dynamic cross-domain execution;
- authorize financial transfer, refund, cancellation, policy mutation, deployment, infrastructure changes, or external communication.

Those become available only when a finite command is registered, a canonical handler exists, and the Principal explicitly delegates that command class.
