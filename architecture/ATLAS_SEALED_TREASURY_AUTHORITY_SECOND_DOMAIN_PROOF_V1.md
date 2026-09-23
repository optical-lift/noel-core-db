# Atlas Sealed Treasury Authority — Second-Domain Proof v1

**Status:** Second proof domain for Sealed Reality.  
**Domain:** Institution-governed treasury destination authority.  
**Governing constitution:** `architecture/ATLAS_SEALED_REALITY_CONSTITUTION_V0_1.md`.

## 1. Why this is the second proof

The Restricted Personnel Vault proved Sealed Reality where the protected reality concerns a person and where the first implementation carrier is an encrypted personnel vault.

Treasury is deliberately different.

A treasury destination such as an organization's receiving or disbursement bank destination is:

- not a personnel record;
- not primarily governed by an individual data subject;
- not Shared Intelligence;
- not payment-event truth;
- not ordinary Ledger metadata;
- not something every Ledger administrator should automatically reveal;
- useful through operations that often do **not** require plaintext reveal.

This domain therefore tests whether the Sealed Reality constitution survives a shift from:

```text
person-associated restricted custody
```

to:

```text
institution-governed financial authority
```

without inventing a universal schema first.

## 2. Treasury reality is distinct from payment reality

Existing Atlas commercial payment tables describe payment observations and financial continuation.

This tranche does not replace them.

```text
commercial payment
    = economic/payment reality

sealed treasury endpoint
    = authority over a sensitive payment destination or treasury credential
```

A payment may lawfully use a sealed treasury endpoint without the payment ledger becoming the custodian of the endpoint's secret.

## 3. The endpoint is not the secret

`atlas.sealed_treasury_endpoints` records that a governed treasury endpoint exists and where its current cryptographic carrier may be addressed.

It does **not** contain:

- bank account number;
- routing number;
- card PAN;
- plaintext credential;
- KMS master key;
- decrypted financial secret.

The sensitive payload may be carried by:

- a user-held device;
- a recipient-bound encrypted capsule;
- an Atlas-owned cryptographic carrier;
- a future threshold service;
- a hardware-backed carrier;
- another compatible sealed-reality carrier.

The database stores governance and an opaque carrier locator, not the protected value.

## 4. Ledger authority establishes the institution, not reveal authority

An existing Principal with governing authority over a Ledger may establish the Ledger's sealed treasury endpoint.

That act does not grant the Principal `reveal_full`.

Creation bootstraps only:

- `observe_existence`;
- `delegate_operation`;
- `audit_operations`.

The institution can therefore exist cryptographically without its root administrator inheriting plaintext access.

## 5. Treasury operation vocabulary

The proof domain defines these operations:

### observe_existence

Answer whether the treasury endpoint exists and its non-secret state.

No carrier operation is required.

### verify_destination

Ask the carrier whether the sealed destination is currently valid/verified.

Result policy: boolean only.

### compare_destination

Compare a candidate destination against the sealed destination.

Result policy: boolean only.

The stored destination is not returned.

### submit_payment_destination

Authorize a carrier or payment adapter to use the sealed destination for an approved payment purpose.

Result policy: bounded submission receipt.

The secret need not be revealed to the human operator.

### reveal_hint

Reveal only a deliberately bounded hint, such as an approved institution label or masked ending.

Result policy: scalar string.

### reveal_full

Permit an exceptional plaintext reveal.

The Atlas database never stores the revealed plaintext in an operation receipt.

The carrier may deliver plaintext only to the already-authorized caller and records only that delivery occurred.

### delegate_operation

Grant or revoke bounded treasury-operation authority.

### audit_operations

Read treasury-operation audit/receipt history.

## 6. Governance warrant

This domain introduces a critical Sealed Reality mechanism: the **operation warrant**.

```text
Principal requests operation
        ↓
Atlas establishes lawful operation authority
        ↓
Atlas issues short-lived one-time warrant
        ↓
cryptographic carrier performs only that operation
        ↓
carrier returns bounded result
        ↓
warrant is consumed
        ↓
receipt becomes durable audit reality
```

The warrant is not the secret.

It is a short-lived capability proving that Atlas governance authorized one specific operation for:

- one endpoint;
- one Principal;
- one purpose;
- one operation;
- one narrow time interval.

Only a hash of the bearer warrant is stored.

## 7. Purpose and time are part of authority

Treasury-operation grants carry:

- Principal;
- operation;
- purpose scope;
- valid-from;
- valid-until;
- grantor;
- basis;
- state.

Therefore:

```text
may submit payroll destination
≠
may reveal bank destination

may compare for account verification
≠
may use for vendor payout

authorized today
≠
authorized forever
```

## 8. Results are smaller than facts

The carrier callback is constrained by the operation catalog.

Examples:

```text
verify_destination
    → true

compare_destination
    → false

submit_payment_destination
    → { "submitted": true, "receiptRef": "..." }

reveal_hint
    → "…4821"

reveal_full
    → { "delivered": true }
```

For `reveal_full`, plaintext must not be returned to or persisted by the canonical database receipt.

This domain therefore proves that Atlas can govern an operation whose useful result is not the protected fact itself.

## 9. Infrastructure and carrier separation

The carrier may reject an otherwise lawful warrant because its own cryptographic policy fails.

Likewise, possession of the carrier or ciphertext does not grant a lawful Atlas warrant.

```text
Atlas governance authorization
        AND
carrier cryptographic acceptance
        =
operation may occur
```

Neither side substitutes for the other.

## 10. Recovery is intentionally not solved here

This second proof does not create a universal recovery engine.

It proves that the endpoint's carrier is replaceable and that reveal authority is not implicit.

A later shared Sealed Reality kernel may model recovery constitutions only after the personnel and treasury proofs are compared.

## 11. Cross-domain comparison target

After validation, compare the two proof domains:

| Question | Personnel Vault | Treasury Authority |
| --- | --- | --- |
| Primary standing | person / personnel custody relation | institution / Ledger governance |
| Protected object | personnel record | treasury destination |
| Ordinary useful use | safe assertion / scoped record operation | verify / compare / submit |
| Plaintext reveal | exceptional | exceptional |
| Authority unit | vault capability | operation grant |
| Time/purpose bounds | yes | yes |
| Admin implies reveal | no | no |
| Carrier replaceable | yes | yes |
| Audit required | yes | yes |
| Safe result smaller than fact | yes | yes |

If both domains pass, the following shared concepts have cross-domain evidence:

```text
standing
sealed reality
operation vocabulary
operation authority
purpose scope
time scope
delegation
one-time execution warrant
bounded result
reveal exception
carrier independence
audit lineage
```

That is enough evidence to **design** a shared Sealed Reality kernel next.

It is not permission to erase the two domain-specific authorities or flatten their standing rules.

## 12. Governing sentence

> **The treasury secret is not handed to whoever administers the institution. The institution governs lawful operations upon it, and each operation must earn its own authority.**
