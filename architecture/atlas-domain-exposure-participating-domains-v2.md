# Atlas Domain Exposure Participating Domains v2

**Status:** candidate architecture only  
**Date:** 2026-09-23  
**Repository role:** canonical database candidate custody. No notebook carrier mutation, private Atlas deployment, or production release is implied.

## Purpose

Extend the production-live Domain Exposure artery beyond its first three proof domains without allowing notebook-carrier existence to become knowledge authority.

Production currently has durable notebook carriers for Household, Flower Operations, and Correspondence in addition to Person Life, Connections, and Organization Ledger. The Atlas application must not be cut over to fail-closed admitted reads until those already-participating domains can independently explain why the authenticated Person may encounter them.

The governing law remains:

```text
canonical domain truth
→ domain-owned authority/read membrane
→ normalized Domain Exposure Evaluation
→ shared Domain Exposure composition
→ notebook read admission
```

Never:

```text
notebook carrier exists
→ therefore Person may know it exists
```

## V2 composition

V2 keeps `atlas.domain_exposure_evaluations_self_api_v1()` intact as the first proof layer and adds three domain-owned exposure membranes:

- `atlas.household_domain_exposure_self_api_v1()`
- `atlas.flower_domain_exposure_self_api_v1()`
- `atlas.correspondence_domain_exposure_self_api_v1()`

The table-blind shared composer is:

- `atlas.domain_exposure_evaluations_self_api_v2()`

It concatenates only normalized `domain_exposure_evaluation_v1` items returned by the v1 evaluator and those three domain membranes.

Notebook admission remains generic. The existing admitted Index and direct NotebookAddress reads are revised only to consume v2 rather than v1. They do not learn Household, Flower, or Correspondence semantics.

## Household exposure law

Household exposure is rooted in Person Position's established `active_principal_household` context.

That position warrants three stable orientation places:

| Durable key | Subject | Governed source read |
| --- | --- | --- |
| `home-care` | household care | `atlas.principal_household_care_snapshot_v1` |
| `household-rhythm` | household rhythm | `public.personal_setup_self_api_v1` |
| `laundry` | household world kernel | `atlas.personal_laundry_kernel_self_api_v1` |

These places are stable/open/listed while the Person has that active household context. Their existence nominates no current attention and grants no household mutation authority.

The household membrane does not query notebook carrier tables.

## Flower exposure law

Flower exposure is explicitly domain-local. Farm roles are not promoted into a universal Atlas role matrix.

The Flower membrane may inspect Flower-owned canonical farm and farm-membership state because it owns that domain law.

For an active farm membership:

- Harvest is encounter-eligible for `owner`, `manager`, or `farm_hand`, matching the governed Harvest read.
- Ready inventory is encounter-eligible only for `owner` or `manager`.
- Commercial commitments are encounter-eligible only for `owner` or `manager`.

Stable durable keys are:

- `flower-harvest:<farmId>`
- `flower-ready:<farmId>`
- `flower-orders:<farmId>`

The subject is the farm. The context is the farm's canonical Organization Unit. A farm lacking a canonical Organization Unit cannot silently manufacture an organization-unit NotebookAddress; exposure remains unresolved/absent.

Primary governed reads are:

- Harvest → `atlas.flower_harvest_notebook_self_api_v1`
- Ready → `atlas.flower_ready_inventory_notebook_self_api_v1`
- Commercial → `atlas.flower_commercial_commitments_notebook_self_api_v1`

Ready/Harvest carrier source projections may contain additional supporting Flower bindings; those remain separately source-authorized and are not collapsed into the exposure warrant.

## Correspondence exposure law

Correspondence exposure is endpoint-capability based, not generic Organization Membership.

An institutional communication endpoint is encounter-eligible only when:

```text
atlas.communication_endpoint_authorized_self_v1(endpoint_id, 'view') = true
```

That existing authority membrane already requires:

- active Organization endpoint;
- present-effective Organization Membership;
- an active endpoint capability grant;
- an allowed grant basis;
- owner role when the grant is only owner-compatibility based.

The stable durable key is:

```text
letters:<communicationEndpointId>
```

The Notebook scope is the endpoint's effective Organization and the subject is the communication endpoint. The governed source read remains `atlas.organization_correspondence_list_self_api_v4`, which separately enforces endpoint view authority and per-conversation read authority.

Correspondence page existence does not nominate attention; communication attention remains downstream and person-relative.

## Shared evaluator remains table-blind

`atlas.domain_exposure_evaluations_self_api_v2()` may call only governed exposure/self membranes. It must not directly read:

- farms or farm memberships;
- communication endpoints or grants;
- household tables;
- notebook spread instances or source bindings;
- Person/Principal/Organization Membership truth tables.

Domain-local exposure membranes may read their own domain tables, but may not inspect notebook carrier tables.

## Notebook admission cutover

The production-live functions:

- `atlas.notebook_index_admitted_self_api_v1()`
- `atlas.notebook_address_admitted_self_api_v1(text)`

remain the read boundary.

This candidate revises their Domain Exposure dependency from v1 to v2. Their semantics do not change:

- listed → Index + direct resolution;
- quiet → direct resolution only;
- absent/unresolved → not exposed;
- source read authority remains separate.

## No carrier mutation

This candidate does not create, open, close, bind, retire, or delete notebook carriers.

It contains no durable mutation path in its production functions.

Carrier reconciliation remains later work.

## Required proof

Clone validation must prove at minimum:

1. v2 shared composition remains table-blind and mutation-free;
2. household exposure derives from Person Position, not notebook carrier existence;
3. active household emits exactly the three stable listed Household addresses;
4. Flower `farm_hand` receives Harvest but not Ready or Commercial exposure;
5. Flower owner/manager receives Harvest, Ready, and Commercial exposure;
6. Flower exposure uses farm identity plus canonical Organization Unit coordinates;
7. Correspondence requires real endpoint `view` capability;
8. revoking endpoint view capability removes Correspondence exposure without deleting any notebook carrier;
9. admitted Index/address functions consume v2 and remain generic;
10. no domain exposure item grants Today placement, action authority, or execution authority.

## Deployment boundary

The private Atlas application has source-only cutover work but private Actions are intentionally unavailable until 2026-10-01.

Public database work may proceed independently. Private application deployment must wait until:

- all production-participating notebook domains have a governed Exposure rule;
- the app source cutover has static/local proof;
- private CI is available again or an explicitly governed alternative exists.

The raw direct spread reader must remain transitional until that application proof is complete.
