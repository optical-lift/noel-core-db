# Atlas Verified Personnel Subject Standing v1

**Status:** First executable bridge from authenticated Principal identity to individually governed Sealed Reality standing.  
**Scope:** Verified Principal↔canonical-person binding, Personnel subject standing, and narrowly policy-governed `reveal_to_device`.  
**Governing constitution:** `architecture/ATLAS_SEALED_REALITY_CONSTITUTION_V0_1.md`.  
**Cryptographic carrier:** `architecture/ATLAS_PRINCIPAL_DEVICE_RECIPIENT_AUTHORITY_V1.md`.

## 1. Problem

Atlas already knows several different identity objects:

```text
auth credential
→ atlas.people
→ atlas.principals

canonical Shared Intelligence person
→ local_intel.entities

restricted Personnel subject
→ restricted_vault_subjects.canonical_entity_id
```

Those are not interchangeable.

A login proves control of an auth credential.

A Principal proves an Atlas operating identity.

A canonical person represents one real person in Shared Intelligence.

A Personnel subject says a protected Personnel vault concerns that canonical person.

Until Atlas has an explicit verified bridge between the authenticated `atlas.people` identity and the canonical person, it must not infer:

```text
signed-in Principal
=
human subject of this Personnel reality
```

from name, email, phone, resolver probability, or private match evidence alone.

## 2. Verified Person↔Canonical binding

The new bridge is:

```text
atlas.people
        ↓ verified identity binding
local_intel.entities(person)
```

This binding is durable identity truth.

It is not:

- a resolver candidate;
- a claimant-safe display projection;
- an email match;
- a name match;
- a device registration;
- a Personnel-vault entitlement.

A binding may only be established through a trusted verification service after an external proof process has already concluded.

v1 records:

- Atlas Person;
- canonical person entity;
- verification method;
- SHA-256 proof-artifact hash;
- verification authority;
- optional verifying Principal;
- verification basis;
- timestamp;
- lifecycle state.

The raw proof artifact is not stored in this table.

## 3. Recognition is not standing

Atlas may privately recognize that a claimant likely matches a canonical person without being allowed to create this binding.

Therefore:

```text
identity resolver match
≠
verified Person↔canonical binding
```

and:

```text
claimant-safe projection
≠
verified Person↔canonical binding
```

The future signup/self-claim workflow may create this binding only after its verification ceremony has earned that authority.

This tranche does not invent that ceremony.

## 4. Conflict law

One active Atlas Person may bind to one canonical person.

One canonical person may bind to one active Atlas Person.

A conflicting verified binding must fail closed.

Rebinding requires an explicit retirement/dispute/recovery process; it must not happen silently because a resolver later produces a different candidate.

## 5. Personnel subject standing

Verified subject standing exists when all of these are true:

```text
Principal is active
Principal.person_id → active atlas.people
verified Person↔canonical binding exists
restricted_vault_subject is active
restricted_vault_subject.canonical_entity_id
    =
verified binding.canonical_entity_id
```

This proves:

> **This Principal operates as the Atlas Person already verified to be the human represented by this Personnel subject.**

It does not prove that every operation on every record class is self-authorized.

## 6. Standing is not universal reveal authority

The fact that a Personnel record concerns a person does not mean the person alone governs every possible Personnel record.

Examples such as disciplinary decisions, performance reviews, background records, or jointly governed compensation may have institutional or relational standing as well.

Therefore v1 introduces a domain policy:

`atlas.restricted_vault_subject_operation_policies`

The policy says which record-class/operation pairs may use verified subject standing as an authority source.

Absence of a policy row means subject standing alone is insufficient.

## 7. Conservative v1 self-governed classes

The first subject-standing operation is:

`reveal_to_device`

v1 enables it only for:

```text
identity_document
tax_identity
banking_payroll
```

These are the clearest current examples of individually governed secret material that an institution may legitimately use while not becoming the ultimate source of the person's authority over their own value.

v1 does **not** enable subject-standing-only reveal for:

```text
accommodation_record
background_record
compensation
disciplinary_record
other_personnel_sensitive
performance_review
```

This is a conservative architecture boundary, not a legal conclusion about access rights in every jurisdiction.

Additional record classes require their own standing analysis before promotion.

## 8. Two lawful sources for reveal_to_device

For an enabled self-governed record class, `reveal_to_device` may be authorized by either:

### Institutional Personnel authority

```text
vault_record_read
+ record-class scope
+ purpose scope
```

or:

### Verified subject standing

```text
Principal
→ verified Atlas Person↔canonical person
→ same canonical person as vault subject
→ active subject-operation policy
```

The authority decision snapshots which source actually authorized the operation.

Examples:

```text
authoritySource = vault_entitlement

authoritySource = verified_subject_standing
```

The shared Sealed Reality kernel still carries the operation in exactly the same way after the domain has decided it is lawful.

## 9. Device possession remains separate

Even when verified subject standing authorizes `reveal_to_device`, the Principal must still possess:

- one active Principal cryptographic device;
- one active recipient-bound key envelope for that Handle/device.

Therefore:

```text
verified human standing
≠
device possession
```

and:

```text
device possession
≠
verified human standing
```

Both are required for the individually held cryptographic path.

## 10. Recipient carrier now carries the full local-decrypt bundle

To prevent subject self-governance from secretly depending on an institutional `vault_record_read` call, the `principal_device_recipient_v1` carrier may deliver, under the already-authorized one-time warrant:

1. the recipient-bound encrypted record data key; and
2. the encrypted Personnel record envelope required for local decryption.

It must **not** deliver:

- the KMS-wrapped record data key;
- plaintext record data key;
- protected plaintext.

The device can therefore perform:

```text
recipient-bound key envelope
        +
encrypted Personnel ciphertext
        ↓
local unwrap
        ↓
local AES-GCM decrypt
        ↓
plaintext exists only at the authorized device boundary
```

The durable shared completion remains:

```json
{"delivered": true}
```

## 11. Why the existing KMS wrapper is omitted

During transition, Personnel records still retain the original KMS-wrapped data key.

The individually governed carrier does not need to expose it.

Once a device-specific recipient envelope exists, the reveal path uses:

```text
device recipient envelope
+
record ciphertext
```

The central KMS wrapper becomes irrelevant to that individual reveal execution.

This is the first path where Atlas governance can authorize a person's own reveal without requiring the corporate/global wrapping authority at reveal time.

## 12. What this does not solve

This tranche does not yet solve:

- the full signup/self-claim verification ceremony;
- recovery from loss of every authorized personal device;
- joint standing for relational records;
- subject amendment/correction authority;
- subject deletion/destruction authority;
- legal records-access requirements by jurisdiction;
- migration of old KMS-only records into recipient-bound envelopes without a lawful data-key provisioning event.

Those remain distinct problems.

## 13. Required proof

The implementation is valid only if rollback validation proves:

1. no verified Person↔canonical binding can be created from a mere match inside this service;
2. conflicting verified identity bindings fail;
3. an active Principal with the verified binding is recognized as the matching Personnel subject;
4. a Principal with no binding is not;
5. subject standing alone does not authorize a non-policy record class;
6. subject standing alone can authorize `reveal_to_device` for an enabled self-governed class;
7. no institutional `vault_record_read` grant is required in that subject-standing case;
8. the recipient carrier delivers only encrypted local-decrypt material;
9. the existing KMS-wrapped data key is not returned by the individual carrier;
10. a different device cannot redeem the warrant;
11. durable completion remains only `{"delivered":true}`.

## 14. Governing sentence

> **Atlas may recognize a person's own authority over a sealed fact only after it has separately proved that the operating Principal is the human with standing in that reality; login, recognition, device possession, and institutional permission are not substitutes for that proof.**
