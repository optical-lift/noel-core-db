# Atlas Principal Decision Read Membrane v1

## Purpose

The Principal UI needs one authenticated read seam for decision-shaped claims without learning every source domain's schema.

This membrane sits after source-specific admission and before any notebook/Clock presentation:

```text
canonical source truth
  -> explicit Principal admission / escalation evidence
  -> optional specialized domain adapter
  -> Principal Decision Packet
  -> authenticated Principal decision read membrane
  -> notebook / Work / Today projection
```

The membrane does not create the underlying obligation, does not create Principal authority, does not arbitrate Clock priority, and does not execute a domain command.

## Version 1 coverage

`principal_decision_packets_api_v1()` covers only **explicit operational escalations** belonging to the authenticated Principal.

It therefore returns:

- `coverageState: partial`
- `coverageMode: explicit_operational_escalations_v1`
- `completeFieldClaim: false`

An empty candidate array means only that no candidate was produced from this included source class. It does **not** prove the Principal has no other decision anywhere in Atlas.

Future source classes may join the same packet contract without changing the notebook's domain vocabulary.

## Default operational-escalation adapter

An open or acknowledged `operational_escalations` row already preserves explicit Principal-admission evidence:

- stable source identity;
- threshold crossed;
- consequence;
- owner decision required;
- options;
- severity/floor/timing metadata.

The default adapter translates that evidence into the generic Principal Decision Packet and invokes `evaluate_principal_decision_packet_v1`.

This is a translation only. The operational escalation establishes that Principal jurisdiction was explicitly crossed; it does not replace the source domain's truth.

## Specialized adapter registry

Some decision kinds need stronger domain-specific readiness than the escalation row alone can prove. Those bindings live in `principal_decision_adapter_registry`.

Version 1 registers:

```text
flower_commerce
+ flower_demand_order
+ sale_commitment_decision
    -> flower_demand_sale_v1
```

The dispatcher is intentionally controlled rather than arbitrary dynamic SQL. A registered key without a governed dispatch implementation returns `translation_required` rather than guessing semantics.

The flower adapter therefore retains the stricter rule already established by the Principal Decision Packet release: even an explicitly admitted Sale-commitment escalation remains contained unless the canonical Demand -> Sale transition is actually executable.

## Application boundary

The only authenticated app endpoint added by this slice is:

```text
atlas.principal_decision_packets_api_v1()
```

Internal adapter and dispatch functions are not executable by `authenticated` or `anon`.

The API resolves the Principal from `auth.uid()` and accepts no Principal identifier from the caller. It is registered in the authenticated RPC custody registry.

A notebook may consume the returned generic candidates without reading:

- flower demand tables;
- allocation tables;
- Sale tables;
- operational escalation rows directly;
- adapter registry rows.

## Command boundary

A candidate may contain an inert command descriptor produced by a specialized adapter or explicitly stored in trusted escalation metadata.

The read membrane does not execute that command.

The application must map an allowed command descriptor to the same governed domain command used elsewhere. For Flower Demand -> Sale, that remains `record_flower_sale_from_demand_core_v1`.

## Clock boundary

Decision admission and Clock arbitration remain distinct.

A decision packet says:

> This claim is sufficiently established to belong to the Principal decision field.

Clock arbitration separately asks:

> Does this already-warranted claim have the floor now relative to other lawful claims and capacity?

The decision read membrane does not answer the second question.

## Resolution boundary

The read membrane only scans open/acknowledged operational escalations. Source-specific systems remain responsible for resolving those escalations when canonical source truth changes.

The Flower Demand -> Sale trigger is the first proof: when canonical Sale lineage is created, the matching Sale-commitment escalation resolves. A subsequent Principal decision read therefore no longer returns the stale decision.

## Truth guarantees

1. Authenticated Principal identity is server-derived.
2. Partial coverage is explicit and never promoted to a complete-field claim.
3. Operational escalation proves admission, not domain truth.
4. Specialized adapters may further contain an admitted claim when domain readiness is absent.
5. Unknown adapter semantics return `translation_required`.
6. The read membrane does not arbitrate Clock priority.
7. The read membrane does not execute commands.
8. The read membrane does not create Commitment Ledger truth.
9. Domain resolution remains source-owned.
10. The notebook can remain domain-neutral.
