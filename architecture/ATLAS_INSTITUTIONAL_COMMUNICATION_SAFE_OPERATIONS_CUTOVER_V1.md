# Atlas Institutional Communication Safe Operations Cutover v1

Status: governing implementation architecture  
Date: 2026-09-25

## Scope

This cut moves the communication operations that do **not** establish Company Work behind `institutional_communication_context_v1`.

Covered now:

- draft read;
- draft write;
- draft authorization;
- new outbound send;
- send into an already-governed conversation;
- attachment staging;
- attachment storage insert/delete authorization;
- attachment confirmation;
- scheduled draft execution.

Not covered:

- claim;
- handoff;
- collaborator allocation;
- response-work state transitions;
- response completion;
- conversation close/disposition.

Those remain a separate Company Work authority problem.

## Authenticated command rule

Authenticated communication commands must resolve:

```text
Reality Person
→ institutional_communication_operations
→ Elm Farm Reality Entity
→ exact endpoint
→ exact operation
→ legacy carrier constraint
```

The returned Organization Membership UUID is an implementation carrier for old tables such as draft authorship and outbound-operation attribution. It is not the source of permission.

## Sending

`message.send` authorizes ordinary outbound communication.

It does not authorize a Person to silently take an unclaimed inbound response case.

Before an authenticated send enters the existing transport internals, `resolve_institutional_communication_send_self_v1` checks whether the target conversation currently has an unclaimed response case.

If so, send fails unless `conversation.claim` is independently authorized.

At this checkpoint `conversation.claim` is deliberately unavailable because the existing claim operation creates a Company Work item and assigns its responsibility.

## Drafts

Draft reads and writes now use the communication resolver rather than endpoint capability as authority.

Draft authorship still stores a legacy Organization Membership UUID. That UUID identifies the compatibility author carrier only.

Every newly written draft stores its resolved Reality communication authority in metadata.

A future scheduled send may be created only when current send authority is valid and the scheduled action would not implicitly claim an unclaimed response case.

## Scheduled release

Scheduled release has no live Auth session, so it cannot call a self-authority resolver.

Instead, `communication_operation_authority_snapshot_valid_v1` revalidates the authority snapshot stored when the draft was authored:

- exact responsibility relation still active;
- same Reality Person;
- same Reality Entity;
- same endpoint scope;
- requested operation still explicitly permitted;
- old author carrier still present;
- matching legacy endpoint carrier grant still active.

Revoking the Reality responsibility therefore stops later scheduled execution.

There were zero scheduled drafts at this cutover, so no pre-context draft required grandfathering.

## Attachments

Attachment prepare, storage access, and confirmation now resolve through communication operations.

The staging membership UUID remains only the old storage carrier.

Storage insert requires both:

1. live Reality communication authority; and
2. the object belongs to the authenticated Person's staging carrier.

Delete additionally retains the existing same-stager/admin carrier constraint.

## Transport availability

At this checkpoint Elm has no connected send transport.

A normal outbound send therefore proves the authority membrane by passing authorization and then stopping with the existing transport-state error:

`Exactly one connected send transport is required ... found 0.`

That is expected. Transport connectivity is not authority.

## Validation result

The rolled-back production proof established:

- draft write succeeds;
- attachment staging succeeds;
- storage insert authorization succeeds;
- attachment confirmation passes authority and stops only because bytes were not uploaded;
- new outbound send passes authority and stops only because transport is disconnected;
- reply to a known unclaimed conversation fails earlier with `42501`;
- no test draft or attachment persists.

## Non-implications

This cut does not grant:

- Company Work creation;
- Company Work assignment;
- claim;
- handoff;
- collaboration allocation;
- close;
- response completion;
- generic institutional authority.
