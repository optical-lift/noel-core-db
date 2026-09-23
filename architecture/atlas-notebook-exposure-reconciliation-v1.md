# Atlas Notebook Exposure Reconciliation v1

Status: candidate architecture
Date: 2026-09-23

## Purpose

Close the write-side gap between production-live Domain Exposure and durable Notebook carriers.

The governing distinction remains:

```text
domain truth exists
!= notebook encounter is admitted
!= durable carrier exists
!= source binding is active
!= Index advertises
!= source truth may be read
!= Today placement
!= action authority
```

This tranche owns only carrier/source-binding maintenance after Exposure has already decided Person-relative notebook admission.

## Canonical artery

```text
Person Position
→ Domain Exposure Evaluation
→ Notebook Exposure Admission
→ carrier-spec adapter
→ reconciliation plan
→ governed carrier/source-binding apply
→ admitted Index / admitted NotebookAddress
→ separately authorized source read
```

## Plan → Apply

The read-only planner emits a deterministic plan from:

- the production-live Domain Exposure envelope;
- current durable carrier state;
- current source-binding descriptors;
- a domain-owned carrier specification for an eligible place.

The mutating self command may apply only that plan.

The apply command MUST NOT:

- re-derive Organization authority from Membership;
- re-derive Person Life authority from private tables;
- infer exposure from carrier existence;
- create source-domain truth;
- grant source-read authority;
- place material on Today;
- grant action or execution authority;
- mint a second carrier when the durability key already identifies a different semantic identity.

## Domain-owned carrier specifications

The shared reconciler is not allowed to invent a page identity.

For the first proof domains, carrier specifications preserve the already-established notebook identities:

### Person Life

- durability: `life:<definitionId>`
- scope: authenticated Person credential scope used by the current Person Life read
- subject: `person/person_life_definition/<definitionId>`
- purpose: `life-orientation`
- horizon: `current`
- thread: `thread:life:<definitionId>`
- title/recipe/composition: derived from the current governed Person Life projection using the existing durable-spread presentation law
- source binding: `person/life_definition_v1/<definitionId>/<progress|cadence|state>`

Retired Person Life remains eligible historical notebook territory: the carrier closes but its governed source binding remains active for owner retrieval.

### Connections

Preserve the existing permanent Principal orientation:

- durability: `connections`
- scope: current Principal orientation scope
- subject: `principal/connections/<principalId>`
- purpose: `source-coverage-orientation`
- horizon: `current`
- thread: `connections`
- source binding: `principal/connected_sources_v1/<principalId>/evidence`

### Organization Ledger

Preserve the currently-live durable identity:

- durability: `ledger:<organizationId>`
- scope: Organization
- subject: `organization/organization_ledger/<organizationId>`
- purpose: `recent-ledger-orientation`
- horizon: `rolling-30-days`
- thread: `thread:organization-ledger:<organizationId>`
- source binding: `organization/ledger_recent_v1/<organizationId>/evidence`

The current owner-role rule remains transitional and is evaluated only by Domain Exposure. The reconciler consumes the resulting eligibility; it never checks the role itself.

## Lifecycle law

```text
eligible + no carrier
→ ensure same semantic carrier
→ ensure desired active source binding

eligible + closed carrier + desired open
→ reopen same carrier

eligible + open carrier + desired closed
→ close same carrier
→ preserve desired active binding when Exposure still warrants historical retrieval

ineligible/unresolved + existing carrier
→ close same carrier
→ retire active bindings
→ preserve durable identity/history

eligible again
→ reopen same carrier
→ reactivate/replace desired binding
→ never mint duplicate identity
```

## Binding law

For eligible exposure, the reconciler may retire stale active bindings for the same source-domain/source-id family when they do not match the current governed binding, then ensure the exact desired binding active.

For exposure loss, all active bindings on the closed carrier are retired. This does not delete binding history.

## Proof requirements

The production-schema clone must prove, in one ephemeral fixture:

1. Person Life gain creates one carrier.
2. Person Life retirement closes the same carrier without deleting it.
3. Person Life restoration reopens the same carrier with the same id.
4. Organization Ledger owner exposure creates one carrier.
5. Loss of owner compatibility closes that same carrier and removes admitted Index/direct-address encounter.
6. Restoration reopens the same Ledger carrier with the same id and active governed binding.
7. Connections reconciliation is idempotent and does not duplicate the permanent carrier.
8. Repeated reconciliation is idempotent.
9. The reconciler never mutates source-domain truth and grants no Today/action/source-read authority.

## Retirement boundary

Passing this tranche does not yet revoke the raw carrier reader.

Retirement comes only after:

- application source invokes reconciliation before ordinary notebook admission reads;
- no ordinary application path bypasses admitted Index/direct address;
- gain/loss/restoration is clone-proved and live;
- raw reader use is reduced to internal implementation behind the admitted resolver.

