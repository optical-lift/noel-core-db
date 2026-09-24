# Atlas Sealed Reality Shared Kernel — Cross-Domain Design v0.1

**Status:** Shared-kernel design candidate.  
**Promotion basis:** Restricted Personnel + Sealed Treasury two-domain proof.  
**Governing constitution:** `architecture/ATLAS_SEALED_REALITY_CONSTITUTION_V0_1.md`.  
**Database status:** Not yet released as a shared schema. This document defines the exact promotion boundary before migration.

## 1. What survived both domains

The two proof domains are genuinely different:

```text
Restricted Personnel
  protected reality:
    personnel record / derived assertion

  primary standing:
    person-associated personnel custody relation

  domain-specific scope:
    record class
    vault subject
    purpose

Sealed Treasury
  protected reality:
    institution-governed financial destination

  primary standing:
    Ledger / institutional governance

  domain-specific scope:
    treasury endpoint
    operation
    purpose
```

The common structure is not "a vault."

The common structure is:

```text
domain-owned reality
        ↓
domain-owned standing / authority decision
        ↓
named operation
        ↓
purpose + time boundary
        ↓
short-lived execution authority
        ↓
replaceable carrier
        ↓
bounded result
        ↓
append-only audit lineage
```

That is the shared kernel candidate.

## 2. What must remain domain-owned

The shared kernel must **not** own or infer:

- who has standing in a personnel relationship;
- who has standing in an institution;
- personnel record classes;
- treasury endpoint lifecycle;
- employment law;
- treasury/payment law;
- whether a person or institution may delegate authority;
- domain-specific revocation consequences;
- domain-specific recovery law;
- canonical payment state;
- canonical personnel state;
- the protected plaintext.

Those remain in their owning domains.

This prevents the shared kernel from becoming a universal permission table.

## 3. The shared kernel's one truthful question

The shared kernel owns:

> **Given that a domain authority has established that this Principal may perform this named operation for this purpose, how is that authority carried safely through one execution and reduced to a bounded durable result?**

It does not answer:

> Who should be allowed?

That answer belongs to the domain adapter.

## 4. Shared object: Sealed Reality Handle

The first shared noun should be a **Sealed Reality Handle**, not an Authority Capsule and not a generic encrypted blob.

Conceptually:

```text
Sealed Reality Handle

id
domain_key
domain_object_id
handle_state
created_at
metadata
```

Its meaning is only:

```text
this domain-owned object participates in Sealed Reality operation governance
```

It does not duplicate the domain object.

It does not contain plaintext.

It does not establish standing.

It does not establish reveal authority.

It is a stable cross-domain execution handle.

### Proposed table

```text
atlas.sealed_reality_handles
  id uuid
  domain_key text
  domain_object_id uuid
  handle_state active|retired
  metadata jsonb
  created_at
  updated_at

unique(domain_key, domain_object_id)
```

The two initial domain keys would be:

```text
restricted_personnel_record
sealed_treasury_endpoint
```

A future domain must explicitly register its own adapter before it may create handles.

## 5. Domain adapter contract

Every Sealed Reality domain must implement an authority adapter.

The adapter contract answers a narrow question:

```text
resolve_operation_authority(
  sealed_reality_handle,
  principal,
  operation,
  purpose,
  context
)
```

and returns a decision envelope:

```json
{
  "authorized": true,
  "authorityVersion": "restricted_personnel_v1",
  "authorityBasis": { "...": "domain-owned proof" },
  "resultPolicy": "boolean",
  "revealsPlaintext": false,
  "carrier": {
    "carrierKey": "some_carrier",
    "carrierLocator": "opaque locator",
    "carrierVersion": "..."
  },
  "warrantTtlSeconds": 180
}
```

or:

```json
{
  "authorized": false,
  "authorityVersion": "restricted_personnel_v1",
  "denialReason": "operation_authority_required"
}
```

The shared kernel must not manufacture or reinterpret this authority decision.

## 6. Adapter registry

The kernel may have a small explicit registry:

```text
atlas.sealed_reality_domain_adapters

domain_key
adapter_version
adapter_state
authority_resolver_key
metadata
```

For v1, the resolver dispatcher should be explicit code with known adapter keys.

Do **not** store arbitrary SQL function names and dynamically execute them from user-controlled registry values.

The initial dispatcher should contain only reviewed branches:

```text
restricted_personnel_record
  → personnel authority adapter

sealed_treasury_endpoint
  → treasury authority adapter
```

Adding a domain is therefore a governed schema/code change, not a metadata trick.

## 7. Shared operation vocabulary is namespaced, not universalized

The kernel should not pretend that all domains have the same operations.

Use:

```text
domain_key + operation_key
```

Examples:

```text
restricted_personnel_record / reveal
restricted_personnel_record / verify
restricted_personnel_record / derive_assertion

sealed_treasury_endpoint / verify_destination
sealed_treasury_endpoint / compare_destination
sealed_treasury_endpoint / submit_payment_destination
sealed_treasury_endpoint / reveal_full
```

Common semantic families may later emerge, but the v1 shared kernel must not rename domain truth merely to make the tables look uniform.

## 8. Result policy is shared

The two domains prove that durable results can be smaller than the protected fact.

The shared kernel may own a small result-policy vocabulary:

```text
none
boolean
string
receipt
scalar
ephemeral_reveal
```

The domain adapter chooses the allowed policy.

The shared completion membrane validates it.

### Rule

```text
carrier output
    must fit the operation's declared result policy

otherwise
    reject completion
```

For `ephemeral_reveal`:

```text
plaintext delivery may occur outside canonical storage

durable result:
  {"delivered": true}
```

The shared kernel must never persist revealed plaintext merely because the carrier returned it.

## 9. Shared operation warrant

The treasury proof established a useful cross-domain primitive that personnel does not yet use: the **one-time operation warrant**.

This should be promoted.

### Proposed table

```text
atlas.sealed_reality_operation_warrants

id
sealed_reality_handle_id
principal_id
domain_key
operation_key
purpose_key
authority_version
authority_basis
result_policy
reveals_plaintext
carrier_key
carrier_locator
carrier_version
warrant_token_hash
warrant_state
issued_at
expires_at
consumed_at
revoked_at
reason_text
request_context
created_at
```

The raw bearer token is returned once to the trusted caller/carrier.

Only its cryptographic hash is retained.

### Invariants

- short-lived;
- one-time;
- bound to one Sealed Reality Handle;
- bound to one Principal;
- bound to one operation;
- bound to one purpose;
- carrier snapshot fixed at issuance;
- result policy fixed at issuance;
- authority basis fixed at issuance;
- replay rejected.

## 10. Shared operation receipt

### Proposed table

```text
atlas.sealed_reality_operation_receipts

id
warrant_id unique
outcome
safe_result
carrier_receipt_ref
completed_at
metadata
```

The receipt records the governed effect of the operation without becoming a second copy of the protected reality.

Examples:

```text
verify
  → true

compare
  → false

submit
  → provider/carrier receipt reference

derive
  → bounded scalar/assertion

reveal
  → {"delivered": true}
```

## 11. Shared audit lineage

Both proof domains require durable access/accountability history.

### Proposed table

```text
atlas.sealed_reality_operation_events

id
sealed_reality_handle_id
principal_id
domain_key
event_key
outcome
operation_key
purpose_key
warrant_id
receipt_id
reason_text
context
occurred_at
created_at
```

Append-only.

Events should include:

```text
operation_request_allowed
operation_request_denied
warrant_issued
carrier_completed
carrier_failed
warrant_expired
warrant_revoked
audit_read
```

The event log must not contain plaintext protected values.

## 12. Shared request service

The central service shape should be:

```text
atlas.request_sealed_reality_operation_service_v1(
  handle_id,
  principal_id,
  operation_key,
  purpose_key,
  reason,
  context
)
```

Execution:

```text
1. load handle
2. dispatch to the handle's domain authority adapter
3. if denied:
     write durable denied event
     return denial
4. if authorized and no carrier is required:
     return bounded domain-safe response
5. if carrier required:
     issue short-lived one-time warrant
     snapshot authority/result/carrier contract
     write audit event
     return bearer warrant + carrier instructions
```

The service never independently grants authority.

## 13. Shared completion service

```text
atlas.complete_sealed_reality_operation_service_v1(
  warrant_token,
  outcome,
  carrier_key,
  safe_result,
  carrier_receipt_ref,
  metadata
)
```

Execution:

```text
1. hash bearer token
2. locate and lock warrant
3. require issued + unexpired + unconsumed
4. require carrier identity match
5. validate result against snapshotted result policy
6. consume warrant
7. write receipt
8. write append-only event
9. return safe result
```

For ephemeral reveal:

```text
accepted durable result:
  {"delivered": true}

rejected:
  any plaintext-like result
```

## 14. Why durable grants should NOT be promoted yet

Personnel currently has:

```text
restricted_vault_entitlements
  capability
  record_class_scope
  purpose_scope
```

Treasury has:

```text
sealed_treasury_operation_grants
  operation
  purpose_scope
```

The overlap is tempting.

Do not merge them yet.

The record-class scope in Personnel is meaningful domain law. Treasury does not have it.

A generic `scope jsonb` permission table would merely hide domain differences.

Therefore v1 promotion should stop at:

```text
domain authority decision
→ shared warrant
→ shared carrier completion
→ shared bounded receipt/audit
```

Durable authority remains domain-owned.

This is the key anti-flattening boundary.

## 15. Why standing should NOT become a shared table yet

The constitution names standing as a shared concept, but the two domains do not yet prove one shared storage shape for it.

Personnel standing can arise from:

```text
person
personnel custody
employment/institution relation
vault subject
```

Treasury standing arises from:

```text
institution
Ledger governance
delegated treasury operation authority
```

A generic `standing_party` table would currently be a vocabulary abstraction, not a proven reality abstraction.

Therefore:

> **Standing is shared constitutional language, but remains domain-owned executable truth in shared-kernel v1.**

## 16. Carrier boundary

The shared kernel should understand only this carrier contract:

```text
carrier_key
carrier_locator
carrier_version
warrant
operation
purpose
bounded input reference / request context
```

It must not require that the carrier be:

- KMS;
- Atlas-owned;
- cloud-owned;
- device-held;
- threshold;
- HSM-backed;
- enclave-backed;
- MPC;
- selective-disclosure credential.

Carrier type is implementation detail unless the domain's authority law depends upon it.

## 17. Personnel migration path

Do not replace the Personnel Vault tables.

Instead:

```text
restricted_vault_record
        ↓
sealed_reality_handle
        ↓
personnel authority adapter
        ↓
shared warrant/receipt/event kernel
```

Initial personnel operation mapping may be:

```text
verify
  → vault_assertion_read or approved verification carrier path

derive_assertion
  → vault_assertion_write path

reveal
  → vault_record_read authority
  → ephemeral_reveal result policy

write
  remains domain-owned command
```

Personnel record lifecycle and encrypted payload storage remain in the Personnel domain.

## 18. Treasury migration path

Treasury already closely resembles the target execution kernel.

Migration should be:

```text
sealed_treasury_endpoint
        ↓
sealed_reality_handle
        ↓
treasury authority adapter
        ↓
shared warrant/receipt/event kernel
```

After equivalent behavior is proven, the treasury-specific warrant/receipt/event tables may be retired.

Treasury endpoint and treasury operation grants remain domain-owned.

## 19. No caller receives universal "sealed access"

The shared kernel must never introduce:

```text
sealed_reality_admin
superuser_reveal
global_decrypt
all_domains_read
```

Its shared administration authority may eventually include only things such as:

```text
register approved domain adapter
retire handle
inspect non-secret kernel health
repair carrier routing
```

None implies reveal.

## 20. Kernel health

A future health projection may answer:

```text
active handles
warrants issued
warrants expired unused
carrier failures
reveal operations requested
denied operations
replayed warrant attempts
orphaned handles
adapter-version drift
```

without exposing protected values.

## 21. Promotion sequence

The shared kernel should be released in this order:

### Phase A — handles + adapter registry

Register personnel records and treasury endpoints as domain-owned Sealed Reality Handles.

No behavior cutover.

### Phase B — shared warrant / receipt / event kernel

Add the shared execution carrier membrane.

Treasury first because its current operation model already proves the shape.

### Phase C — treasury cutover

Treasury authority stays domain-owned, but operation execution moves to the shared kernel.

Prove behavior equivalence.

### Phase D — personnel adapter

Add personnel record operation adapter and migrate protected read/derived-operation execution behind shared warrants.

### Phase E — retirement

Only after both domains run through the shared execution kernel:

- retire treasury-specific warrant/receipt/event execution tables;
- retain treasury domain authority tables;
- retain personnel domain authority and payload tables.

## 22. What this kernel is

```text
not a universal permission engine
not a universal secrets database
not a KMS
not an ACL system
not a replacement for domain law

it is:

a governed one-operation execution membrane
between domain authority and replaceable cryptographic carriers
```

## 23. Shared governing sentence

> **The domain decides whether an operation is lawful. The Sealed Reality kernel carries that lawful authority through one bounded execution without enlarging it, revealing more than necessary, or becoming the source of the authority itself.**

## 24. Phase A implementation receipt

Phase A is now implemented by:

`supabase/migrations/20260924050000_atlas_sealed_reality_phase_a_handles_adapters_v1.sql`

Released objects:

- `atlas.sealed_reality_domain_adapters`;
- `atlas.sealed_reality_handles`;
- `atlas.register_sealed_reality_handle_service_v1`;
- `atlas.resolve_sealed_reality_operation_authority_service_v1`;
- explicit internal personnel and treasury authority adapters.

Current registered domains:

```text
restricted_personnel_record
  → restricted_personnel_record_v1

sealed_treasury_endpoint
  → sealed_treasury_endpoint_v1
```

The dispatcher is explicit code. It does not dynamically execute function names from registry metadata.

### Validation

Rollback validation passed.

Proved:

- Personnel and Treasury domain objects receive stable, idempotent Sealed Reality Handles.
- Registering a personnel handle requires existing personnel-vault governance authority.
- Registering a treasury handle requires existing treasury delegation authority.
- The Personnel adapter does not enlarge authority: `reveal` remains denied until the existing `vault_record_read` capability exists.
- The Personnel adapter preserves the personnel record's purpose boundary.
- Once existing Personnel authority exists, the adapter resolves the operation to `ephemeral_reveal` through the replaceable `restricted_vault_envelope_v1` carrier.
- The Treasury adapter does not enlarge authority: `reveal_full` remains denied until the existing Treasury domain grants it.
- Treasury `observe_existence` remains a no-carrier metadata operation.
- Treasury `verify_destination` preserves existing purpose-scoped operation authority, boolean result policy, and current carrier routing.
- A Treasury grant for `vendor_payout` does not authorize the same operation for `payroll`.
- No shared warrant, receipt, or execution path was introduced; existing Personnel and Treasury behavior remains authoritative.

No validation domain objects or handles persisted.

### Phase boundary

Phase A therefore establishes:

```text
domain object
→ stable Sealed Reality Handle
→ explicit domain authority adapter
→ normalized authority decision envelope
```

It does not yet establish:

```text
shared execution warrant
shared carrier completion
shared receipt
shared audit lineage
```

Those remain Phase B.

## 25. Phase B implementation receipt

Phase B is now implemented by:

- `supabase/migrations/20260924053000_atlas_sealed_reality_phase_b_execution_kernel_v1.sql`;
- `supabase/migrations/20260924054500_atlas_sealed_reality_phase_b_validation_repair_v1.sql`.

Released shared execution objects:

- `atlas.sealed_reality_operation_warrants`;
- `atlas.sealed_reality_operation_receipts`;
- `atlas.sealed_reality_operation_events`;
- `atlas.request_sealed_reality_operation_service_v1`;
- `atlas.complete_sealed_reality_operation_service_v1`.

The Phase B kernel consumes the Phase A normalized domain-authority decision. It does not create durable grants and does not decide standing.

### Shared warrant law

A carrier-backed authorized operation now produces one short-lived bearer warrant bound to:

```text
Sealed Reality Handle
Principal
domain adapter + version
operation
purpose
authority version + basis snapshot
result policy
reveal classification
carrier key / locator / version
expiry
```

Only the SHA-256 hash of the bearer token is stored.

Warrants expire within 15 minutes and are one-time. A consumed warrant cannot be replayed.

### Shared completion law

Carrier completion:

1. hashes and resolves the presented bearer warrant;
2. requires issued + unexpired state;
3. requires the carrier key snapshotted at issuance;
4. validates the durable result against the snapshotted result policy;
5. consumes the warrant;
6. writes one immutable receipt;
7. writes append-only audit lineage.

Result-policy enforcement includes:

```text
boolean
  → boolean only

string
  → bounded string only

scalar
  → bounded JSON scalar only

receipt
  → bounded object only

ephemeral_reveal
  → {"delivered":true} only

failed execution
  → optional bounded {"errorClass":"..."} only
```

The canonical shared receipt therefore cannot become a second copy of an exceptionally revealed value.

### No-carrier boundary

An authorized decision with `requiresCarrier=false` is **not** falsely executed by the shared kernel.

Phase B returns:

```text
authorized = true
requiresCarrier = false
executionState = domain_owned
```

and records only that authority was resolved.

The owning domain remains responsible for any actual no-carrier effect.

### Validation

Rollback validation passed independently against both proof domains.

Personnel proved:

- existing Personnel authority can issue a shared one-time `reveal` warrant;
- the carrier remains `restricted_vault_envelope_v1`;
- the shared kernel rejects a non-acknowledgement durable result for an ephemeral reveal;
- successful reveal completion persists only `{"delivered":true}`.

Treasury proved:

- a no-carrier `observe_existence` authority decision does not create a shared warrant;
- the shared kernel does not enlarge existing Treasury authority;
- after a domain-owned `verify_destination` grant, the shared kernel preserves the boolean result policy and Treasury carrier routing;
- carrier completion persists the bounded boolean result;
- the one-time warrant cannot be replayed;
- `vendor_payout` authority does not leak into `payroll`;
- shared event rows reject mutation;
- shared receipt rows reject deletion.

All validation data rolled back. The live shared warrant, receipt, and event tables remained empty after validation.

### Release repair note

The initial Phase B migration was applied, then its source file was temporarily hardened after release. To preserve exact post-fence migration-source custody, the original applied migration bytes were restored and the hardening was released as the separate `20260924054500` repair migration.

The repair makes result-policy validation fail closed on missing values and explicitly rejects missing/invalid warrant TTLs.

### Phase boundary

Phase B establishes the shared execution carrier membrane.

It does **not** cut either domain over from its existing execution service.

The next phase is Phase C:

```text
Treasury domain authority
→ shared Sealed Reality request/completion kernel
```

with behavioral equivalence proved before the treasury-specific execution warrant/receipt/event path is retired.

## 26. Phase C implementation receipt — Treasury cutover

Phase C is now implemented by:

`supabase/migrations/20260924060000_atlas_sealed_reality_phase_c_treasury_cutover_v1.sql`.

Treasury standing, durable operation grants, endpoint lifecycle, and no-carrier domain effects remain Treasury-owned.

Carrier-backed Treasury execution now flows through the shared Sealed Reality kernel:

```text
Treasury endpoint
→ Treasury domain authority adapter
→ shared Sealed Reality warrant
→ Treasury carrier
→ shared bounded receipt
→ shared append-only execution lineage
```

### Compatibility behavior

The existing Treasury service contracts remain callable:

- `atlas.create_sealed_treasury_endpoint_service_v1`;
- `atlas.request_sealed_treasury_operation_service_v1`;
- `atlas.complete_sealed_treasury_operation_service_v1`;
- `atlas.read_sealed_treasury_operation_events_service_v1`.

Their domain semantics remain Treasury-owned, but carrier-backed request/completion now delegate to the shared kernel.

New Treasury endpoint creation automatically establishes its `sealed_treasury_endpoint` Sealed Reality Handle after bootstrap governance has been created.

The migration also contains a conservative backfill for pre-cutover active endpoints whose creator still holds the bootstrap `delegate_operation` grant.

### No-carrier preservation

Treasury operations with `requiresCarrier=false` remain domain-owned.

For `observe_existence`, the compatibility service preserves the existing endpoint projection while the shared kernel records only the authority-resolution lineage.

No shared execution warrant is minted for a no-carrier operation.

### Audit continuity

The existing Treasury audit service now projects:

```text
legacy/domain Treasury events
+
shared Sealed Reality execution events
```

through the same Treasury audit contract.

This preserves domain history while moving execution lineage to the shared kernel.

### Legacy execution tables

The Treasury-specific execution tables remain present in this phase:

- `atlas.sealed_treasury_operation_warrants`;
- `atlas.sealed_treasury_operation_receipts`;
- `atlas.sealed_treasury_operation_events`.

However, carrier-backed Treasury request/completion no longer writes new Treasury-specific warrant or receipt rows.

The event table remains relevant for historical/domain events such as endpoint creation and operation-grant governance until retirement is separately proven.

### Validation

Rollback validation passed.

Proved:

- new Treasury endpoints automatically receive a Sealed Reality Handle;
- `observe_existence` preserves its existing no-carrier response shape;
- ungranted `verify_destination` remains denied with `operation_authority_required`;
- existing Treasury operation grants remain the source of authority;
- governed `verify_destination` requests mint a shared Sealed Reality warrant, not a Treasury-specific warrant;
- the compatibility request preserves carrier key, carrier locator, result policy, operation, purpose, and expiry semantics;
- carrier mismatch preserves the prior Treasury authorization failure behavior;
- completion writes a shared bounded receipt, not a Treasury-specific receipt;
- shared one-time warrant replay is rejected;
- Treasury audit compatibility includes both domain history and shared carrier completion;
- legacy Treasury warrant and receipt tables receive no new rows from the cutover path.

All validation data rolled back.

Post-validation live counts were zero for:

- Treasury endpoints;
- Treasury Sealed Reality Handles;
- shared Treasury warrants;
- shared Treasury receipts;
- legacy Treasury warrants;
- legacy Treasury receipts.

### Phase boundary

Treasury carrier-backed execution is now cut over.

The next phase is Phase D:

```text
Restricted Personnel domain authority / encrypted payload
→ shared Sealed Reality warrant
→ restricted personnel carrier
→ shared bounded receipt / audit
```

Personnel payload custody and Personnel durable authority remain domain-owned.

