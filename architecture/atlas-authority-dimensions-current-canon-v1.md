# Atlas Authority Dimensions — Current Canon v1

**Status:** Governing architecture for the Knowledge / Action Authority structural tranche  
**Established:** September 19, 2026  
**Canonical repository:** optical-lift/noel-core-db  
**First repair domain:** Organization Correspondence / Communication Endpoint authority

## 1. Governing problem

Atlas already contains several truthful authority systems because different real questions require different answers.

Current source distinguishes, among other things:

- Organization Membership — institutional relationship;
- Member Exposure Grant — bounded information exposure;
- Organization Responsibility — durable institutional function;
- Work Allocation — responsibility for exact Company Work;
- Execution Lease — present execution warrant;
- Ledger Entitlement — commercial/system entitlement to a Ledger;
- Capability Entitlement Grant — entitlement for a Ledger to use a capability;
- Principal Ledger Authority — root governing authority;
- Communication Endpoint Member Grant — bounded endpoint capability;
- Connected Source authorization — external carrier custody and authorization.

These must not converge into one convenient role or permission check.

The governing law is:

> **Authority is dimensional. A truthful grant answers one question; it does not silently answer adjacent questions.**

## 2. Required authority dimensions

### Relationship / membership

Answers:

> What institutional relationship does this Person currently have?

Examples:

- Organization Membership;
- Position Appointment;
- Principal / Person relationship;
- external institutional relationship.

Membership may be a prerequisite for authority, but membership is not itself knowledge, responsibility, action authority, or present execution warrant.

### Knowledge / exposure

Answers:

> What reality may this Person know exists, discover, inspect, or read?

Examples:

- Organization Member Exposure Grants;
- Communication Endpoint `view`;
- future field/claim-level Knowledge-Jurisdiction policy.

Knowledge authority is not responsibility and does not grant mutation or execution.

### Operational action authority

Answers:

> Which bounded operation may this Person invoke?

Examples:

- Communication Endpoint `send`;
- a governed planning command;
- a bounded domain transition.

Action authority does not establish responsibility merely because the actor can execute the command.

### Responsibility / custody of response

Answers:

> Who currently carries the institutional obligation or exact Work consequence?

Examples:

- Work Allocation;
- Institutional Conversation response responsibility;
- durable Position/Responsibility relationship.

Responsibility is not inferred from opening/reading, membership, administration, or technical capability.

### Present execution warrant

Answers:

> May this Person execute this particular work now, under current conditions?

Examples:

- Execution Lease;
- domain operation-fit warrant;
- safety/readiness gate.

Responsibility does not automatically imply present execution warrant.

### Configuration administration

Answers:

> May this Person configure the carrier, projection, identity, or bounded operational surface?

Examples:

- Communication Endpoint administration;
- correspondence identity branding/binding;
- shared signature configuration;
- provider-connection administration where separately governed.

Configuration administration does not imply permission to read the carried content, act through the carrier, assume responsibility, or override another Person's responsibility.

### Governing / grant authority

Answers:

> May this Person establish, revoke, or adjudicate another authority relationship?

Examples:

- Principal root-governing Ledger authority;
- current Organization owner grant establishment;
- future delegated authority-administration role.

Grant authority is not the same as the authority being granted.

### Entitlement

Answers:

> Is this institution/Ledger legitimately entitled to use this capability or resource?

Examples:

- Ledger Entitlement;
- Capability Entitlement Grant.

Entitlement is not actor permission and does not identify which human may activate or use the capability.

### Carrier/source custody

Answers:

> Under whose institutional/human custody does this external carrier or source exist?

Examples:

- Connected Source human/Organization custody;
- Communication Endpoint institutional custody.

Carrier custody does not imply knowledge or action rights over everything the carrier contains.

## 3. Non-implication law

Unless an explicit current-canon rule says otherwise:

```text
membership
!= knowledge
!= action authority
!= responsibility
!= execution warrant
!= configuration administration
!= governing/grant authority
!= entitlement
!= carrier custody
```

A higher-order or root authority may lawfully **establish** a lower-order grant. That does not mean every read/command should substitute a root-role check for the lower-order authority forever.

## 4. Why this is now a proven horizontal concern

The separation is already independently represented across unrelated Atlas domains:

- exposure grants answer information access;
- Company Work allocations answer exact-work responsibility;
- execution leases answer present execution permission;
- Ledger/Capability entitlements answer institutional right to use machinery;
- Principal Ledger Authority answers root governance;
- provider connection authority answers carrier administration;
- Communication Endpoint grants answer endpoint-specific capabilities.

This is sufficient cross-domain proof for a shared authority grammar.

It is **not** proof that every authority must move into one universal authority table.

## 5. First live collision — Communication Endpoint `admin`

Current production helper:

`atlas.communication_endpoint_membership_has_capability_v1(...)`

currently treats an active Endpoint grant of:

```text
admin
```

as satisfying any requested Endpoint capability:

```text
view
send
claim
handoff
close
admin
```

`atlas.communication_endpoint_authorized_self_v1(...)` carries the same wildcard pattern.

That collapses configuration administration into knowledge, action, responsibility-management, and closure authority.

There are currently zero live rows in `communication_endpoint_member_grants`, so no present non-owner grant depends on this wildcard.

## 6. Second live collision — administration can override responsibility

`atlas.prepare_institutional_email_send_internal_v2(...)` currently permits a member with Endpoint `admin` to send a response even when another member owns the active response Work and the sender is neither that responsible member nor a participant/approver.

That creates the false implication:

```text
endpoint configuration administration
→ may bypass another Person's active response responsibility
```

This is prohibited.

Correct movement:

```text
send authority
+ response responsibility / lawful collaboration
→ reply may be authorized
```

If another Person owns the response, a different Person must enter through a truthful responsibility seam such as handoff or collaboration. Administration is not a response takeover warrant.

## 7. Communication Endpoint capability meanings

For current Correspondence:

### view

Knowledge/exposure authority for the Endpoint's communication content.

Does not imply send, claim, handoff, close, or administration.

### send

Operational authority to originate/transport communication through the Endpoint, still subject to conversation responsibility and send-specific domain gates.

Does not imply view of all existing conversations.

### claim

Authority to assume an unclaimed response responsibility through the governed claim operation.

Does not imply that responsibility exists before the claim succeeds.

### handoff

Authority to perform the governed responsibility-transfer operation where its other prerequisites hold.

Does not itself make the actor responsible.

### close

Authority to perform the governed closure/disposition operation where domain prerequisites hold.

Does not imply view/send/admin.

### admin

Configuration administration for the Endpoint and its configuration-adjacent identity/surface.

It may support explicitly named operations such as:

- correspondence identity creation/binding;
- shared signature administration, when send authority is also required;
- configuration cleanup such as another member's staged/revoked attachment where explicitly governed.

It must **not** act as a wildcard for `view`, `send`, `claim`, `handoff`, or `close`.

## 8. Grant authority remains separate from `admin`

Current:

`atlas.set_communication_endpoint_member_capability_self_api_v1(...)`

requires active Organization owner authority.

This tranche does not reinterpret Endpoint `admin` as permission to grant/revoke Endpoint authority.

If delegated grant administration is later required, Atlas must create/prove that governing authority explicitly.

## 9. Owner compatibility

Current Communication Endpoint capability helpers also treat active Organization `owner` membership as implicitly satisfying every Endpoint capability.

This is **transitional compatibility**, not permanent Knowledge-Jurisdiction law.

Removing it immediately would change current production owner access because there are zero explicit Endpoint member grants.

The first implementation slice therefore preserves owner compatibility while removing `admin`-as-wildcard behavior.

Future Knowledge-Jurisdiction work must decide how sensitive/private Organization endpoints materialize explicit owner knowledge/action grants or lawful root-governance exceptions without assuming:

```text
organization ownership
→ may know every institutional fact
```

That question is deliberately not solved by the first Correspondence repair.

## 10. First implementation slice

The first migration should:

1. change `communication_endpoint_membership_has_capability_v1` so non-owner grants satisfy only the exact requested capability;
2. change `communication_endpoint_authorized_self_v1` the same way;
3. preserve current owner compatibility;
4. preserve direct explicit `admin` checks in configuration-administration functions;
5. ensure `admin` no longer grants Correspondence `view`;
6. ensure `admin` no longer grants `send`, `claim`, `handoff`, or `close`;
7. remove Endpoint `admin` as a bypass around another member's active response responsibility in the institutional email send path;
8. preserve lawful send by the responsible member and active response collaborators/approvers;
9. preserve governed handoff/claim operations as the way responsibility changes;
10. leave owner-wide compatibility explicitly visible as debt rather than hiding it inside a generic universal authority claim.

No new universal permission table is required.

## 11. Read/configuration consequence

Once `admin` stops implying `view`, a configuration administrator without `view` must not be forced through the shared inbox merely to administer configuration.

If Product needs a configuration screen for such an administrator, expose a bounded Endpoint configuration projection that reveals configuration metadata but not communication content.

Do not restore the wildcard merely to make the current UI convenient.

## 12. Cross-domain implementation rule

New domain code must identify which question it is checking.

Do not write generic checks equivalent to:

```text
is_owner
is_admin
is_manager
has_access
```

when the operation actually requires one of:

```text
may_know
may_act
is_responsible
may_execute_now
may_configure
may_grant_authority
is_entitled
has_custody
```

Role may contribute evidence to one of those answers. Role is not the answer by itself.

## 13. Acceptance conditions for the first repair

Production-schema clone validation must prove:

1. active member with only `admin` cannot view Endpoint correspondence;
2. `admin` alone cannot send;
3. `admin` alone cannot claim;
4. `admin` alone cannot handoff;
5. `admin` alone cannot close;
6. `admin` can still satisfy explicit configuration-administration checks;
7. `send` alone can pass the Endpoint send-capability check;
8. `view` alone can pass the Endpoint view-capability check;
9. exact grants do not imply sibling capabilities;
10. Organization owner compatibility remains unchanged in this first slice;
11. another member's active response responsibility cannot be bypassed merely by `admin`;
12. responsible member can still send;
13. active participant/approver collaborator can still send where current domain rules permit;
14. handoff remains the truthful transfer path;
15. current claim behavior remains separate from opening/viewing;
16. no current Communication Event, Conversation, Work Allocation, or outbound-operation identity is rewritten.

## 14. Next authority audits

After Correspondence exact-capability repair, inspect in order:

1. Organization owner-as-universal-knowledge compatibility;
2. management/planning authority versus responsibility establishment;
3. Ledger entitlement versus human activation/use authority;
4. provider/source administration versus source-content knowledge;
5. Principal root governance versus delegated operational execution;
6. exposure/disclosure distinctions for sensitive domains;
7. agent/tool authority versus human/institutional delegation.

The objective is not one permission engine immediately.

The objective is one authority grammar that prevents each new domain from inventing a role wildcard and calling it governance.
