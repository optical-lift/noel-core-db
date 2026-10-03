# Atlas Institutional Communication Context v1

Status: governing implementation architecture  
Date: 2026-09-25

## Purpose

Institutional communications should not contain a separate authorization theory inside every send, draft, claim, handoff, close, note, or attachment function.

The canonical sequence is:

```text
Auth
→ Reality Person
→ Reality Responsibility
→ institution jurisdiction
→ exact Communication Endpoint
→ Institutional Communication Context
→ requested operation
```

The context answers which operations are lawful for this Person against this endpoint. It does not itself create authority.

## Authority versus carrier

Authority comes from `reality.responsibility_relations`.

Legacy communication endpoint grants remain temporarily because the transport schema still stores actor and endpoint custody through Organization Membership UUIDs. Those grants are only compatibility carrier constraints.

Therefore:

```text
Reality responsibility = may this Person perform the operation?
legacy endpoint grant   = can the old transport/storage carrier represent it?
```

A carrier grant can restrict an operation. It cannot create one.

Generic Organization role is irrelevant to the communication context.

## Elm communication operation responsibility

Lex receives `institutional_communication_operations` for the Elm Farm Reality Entity, scoped to the exact `hello@elmfarm.co` endpoint.

The initial operation set is deliberately limited to communication activity that does not itself establish Company Work:

- `conversation.read`;
- `draft.read`;
- `draft.write`;
- `draft.authorize`;
- `message.send`;
- `attachment.prepare`;
- `attachment.confirm`;
- `attachment.storage.insert`;
- `attachment.storage.delete`.

Existing correspondence-identity operations continue to resolve through the separate `institutional_correspondence_administration` responsibility.

## Company Work boundary

The following operations are represented in the context but are **not** granted:

- `conversation.claim`;
- `conversation.handoff`;
- `collaborator.manage`;
- `response.transition`;
- `response.complete`;
- `conversation.close`.

The current implementation of these actions creates, transfers, changes, completes, or cancels Company Work and/or Company Work allocations.

They therefore cannot be obtained merely from communication authority, even though old endpoint grants currently contain `claim`, `handoff`, and `close`.

For these operations the context reports:

```text
allowed = false
reason = company_work_authority_required
migrationState = deferred_company_work
```

## Contracts

`atlas.resolve_institutional_communication_operation_self_v1(endpoint_id, operation_key)`

is the internal resolver. It returns:

- Person and institution;
- exact endpoint;
- responsibility key and relation;
- required legacy carrier capability;
- carrier membership;
- whether the carrier constraint is satisfied;
- whether Company Work authority is additionally required;
- final allowed/denied state and reason.

`atlas.current_institutional_communication_context_self_api_v1(endpoint_id)`

is the authenticated projection. It returns the institution, endpoint, compatibility carrier, complete operation map, and truth boundary.

## Non-implications

A communication context does not imply:

- ownership;
- Organization Membership authority;
- generic organizational role;
- Company Work responsibility;
- permission to claim incoming work;
- permission to assign or hand off work;
- permission to complete or cancel work;
- permission to administer another endpoint;
- authority outside the named Reality Entity.

## Transport state

Authority and transport availability are separate.

At this cutover, Elm has no connected outbound send transport. The context may therefore correctly say `message.send = allowed` while an actual send attempt still stops because no connected send transport exists.

That is not an authorization contradiction. It means:

```text
lawful operation
≠
currently executable transport
```

## Acceptance

Accepted only when:

1. Elm context resolves through Lex Reality Person and Elm Reality Entity;
2. send/draft/attachment operations resolve true only through the new bounded responsibility;
3. correspondence identity operations continue to use their existing bounded responsibility;
4. claim/handoff/response-work operations remain false despite legacy carrier grants;
5. denied claim reports the Company Work boundary;
6. the legacy Organization Membership UUID is exposed only as routing/carrier compatibility;
7. no generic role creates an operation.


## Safe-operation implementation

The first callers are now cut to the context membrane in `ATLAS_INSTITUTIONAL_COMMUNICATION_SAFE_OPERATIONS_CUTOVER_V1.md`.

Drafts, send commands, attachment custody, and scheduled release no longer treat endpoint capability as the source of authority. Work-coupled response operations remain deferred.


## Safe outbound execution cutover

The first execution slice behind the context is now:

- draft read;
- draft write;
- draft authorization;
- send intent preparation;
- attachment preparation;
- attachment confirmation;
- attachment storage insert/delete authorization.

Every authenticated edge resolves its operation through the Institutional Communication Context before a legacy membership UUID is used. That UUID is therefore a transport/storage actor token, not the source of authority.

### Response-work boundary

Sending is not allowed to smuggle Company Work authority through an old endpoint `claim` grant.

Before an authenticated send or draft authorization enters transport compatibility, Atlas checks whether the target conversation has an unclaimed response case with no responsible allocation. If so, `conversation.claim` must independently resolve.

That operation remains deferred, so ordinary `message.send` cannot establish response work by implication.

### Transport availability

Elm currently has no connected send transport. A production send proof can therefore pass the Reality authority boundary and then stop at the independent transport requirement. This is expected:

```text
authorized to send
≠
send transport currently available
```

## Response-work bridge

The context now distinguishes endpoint-level authority from exact Work authority.

conversation.claim maps to the bounded Reality operation response_work.claim_self. It may create Company Work only from an exact unresolved response case and may establish only caller self-responsibility.

conversation.handoff and collaborator.manage report receiver_uptake_required; direct assignment is not authorized.

response.transition and response.complete report exact_work_responsibility_required at endpoint-context level. Once a conversation has been claimed, the response-state command checks the exact active Work allocation instead of endpoint capability.

conversation.close remains deferred from response-work authority. Mailbox disposition and Work completion/cancellation are not the same operation.
