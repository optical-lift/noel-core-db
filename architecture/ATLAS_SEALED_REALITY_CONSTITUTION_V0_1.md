# Atlas Sealed Reality Constitution v0.1

**Status:** Constitutional architecture; governs future sensitive-reality work.  
**Promotion state:** Law established; universal database kernel not yet promoted.  
**Reason for restraint:** Restricted Personnel Vault is the first proof domain. A second genuinely different domain must prove the shared abstraction before Atlas creates one universal Sealed Reality schema.

## 1. The problem Atlas is solving

Conventional encryption usually begins from an institutional premise:

```text
corporation possesses data
→ corporation controls master key
→ corporation decides who may decrypt
```

Atlas rejects that premise as a universal model.

Sensitive reality can be individually governed, institutionally governed, or jointly governed. The organization carrying the bytes is not automatically the Source of authority over the reality represented by those bytes.

Atlas therefore treats cryptography as a **carrier of governed authority**, not as the source of authority.

The constitutional sequence is:

```text
reality
→ parties with standing
→ governance constitution
→ lawful operations
→ delegated authority
→ cryptographic capability
→ carrier / storage
```

Not:

```text
database owner
→ administrator
→ master key
→ everyone else's reality
```

## 2. Core constitutional law

> **Possession of encrypted bytes does not establish authority over the reality they carry.**

> **Infrastructure administration does not establish reveal authority.**

> **Encryption policy follows standing in reality; reality does not inherit authority from whoever happens to host the ciphertext.**

> **Atlas should reveal less often than it computes, verifies, compares, proves, or submits.**

> **There must be no requirement for a universal Atlas master key capable of revealing every sealed fact.**

## 3. Sealed Reality

A **Sealed Reality** is a fact, document, identifier, relation, or protected state whose ordinary representation is intentionally unavailable outside its governing authority, while specifically authorized operations may still be performed upon it.

A sealed reality is not merely:

```text
encrypted_value
```

Its full constitutional object is conceptually:

```text
Sealed Reality

what reality is represented?
who has standing in it?
who governs which operations?
what purposes are lawful?
what operations may occur?
which operations reveal plaintext?
which operations return only derived results?
who may delegate?
when does authority begin/end?
how is recovery constituted?
what carrier currently enforces the law?
what audit lineage proves its use?
```

Cryptographic representation is subordinate to that constitution.

## 4. Standing precedes permission

Atlas must distinguish **standing** from **permission**.

Standing means a party has a legitimate governing relation to the reality itself.

Examples:

### Individually governed

```text
person's private tax identifier
person's private health fact
person's personal recovery material
```

The person is the primary governing party.

### Institutionally governed

```text
organization's private treasury credential
organization's proprietary pricing model
organization's internal signing key
```

The institution is the primary governing party.

### Jointly / relationally governed

```text
employment agreement
compensation agreement
signed contract
shared custody record
joint financial obligation
```

Authority may arise from more than one party and may differ by operation.

Atlas must not reduce every sensitive fact to either "the individual owns it" or "the organization owns it."

**Authority follows the nature of the reality.**

## 5. The operation is the unit of authority

Traditional systems tend to collapse sensitive access into:

```text
read
write
```

Sealed Reality requires finer operations.

Candidate constitutional operations include:

```text
observe_existence
verify
compare
prove
derive
submit
reveal
amend
delegate
revoke
retire
destroy
recover
```

These operations are not interchangeable.

Examples:

```text
may compare tax identifier
≠ may reveal tax identifier

may submit bank destination to payroll processor
≠ may display bank destination

may verify age threshold
≠ may disclose birth date

may prove identity match
≠ may browse identity document
```

The operation contract must therefore be explicit before a cryptographic carrier is chosen.

## 6. Reveal is exceptional

For sealed reality, plaintext reveal is not the default form of use.

Atlas should prefer:

```text
sealed fact
→ governed operation
→ minimum sufficient result
```

Examples:

```text
birth date
→ age_over(21)
→ true

tax identifier
→ exact_match(candidate)
→ true

identity document
→ verification_current()
→ true

banking detail
→ submit_to(payroll_processor)
→ completed

compensation
→ within_budget(limit)
→ true
```

This creates a distinction Atlas must preserve:

```text
exists
verified
operable
revealed
```

Those are different states.

## 7. Authority may be delegated without copying reality

The default modern pattern is duplication:

```text
person gives identifier to Employer A
Employer A stores copy

person gives identifier to Employer B
Employer B stores copy

person gives identifier to Bank
Bank stores copy
```

Sealed Reality should prefer:

```text
one sealed fact
        │
        ├── bounded capability → Employer A
        ├── bounded capability → Employer B
        └── bounded capability → Bank
```

Delegation must specify at least:

```text
delegating authority
recipient authority
operation
purpose
scope
valid_from
valid_until
delegation / redelegation rules
revocation semantics
```

An institution should receive the capability it needs, not automatically receive an uncontrolled plaintext copy.

## 8. Individual governance is constitutional, not interactive noise

Individual governance must not devolve into endless consent prompts.

A person may establish durable standing rules, for example:

```text
While I am actively employed by Elm:

Payroll may:
  verify tax identity
  submit legally required payroll filings
  submit my payroll destination

HR may:
  verify employment documentation

Management may:
  observe verification_complete

No Elm authority may:
  promote the protected values into Shared Intelligence
  use them for marketing
  expose them to ordinary AI context
```

The human establishes governing law; Atlas enforces it over time.

## 9. Joint authority may require more than one party

Some operations may require the concurrence of multiple parties with standing.

Example:

```text
Compensation Agreement

reveal:
  Person OR authorized institutional compensation authority

amend:
  Person AND authorized institutional compensation authority

publish:
  neither, unless separately authorized

terminate:
  governed by the underlying employment/contract law
```

A future cryptographic carrier may implement this through threshold signatures, multi-recipient wrapping, secure enclaves, MPC, or another method.

The cryptographic technique must not define the governance. It must implement it.

## 10. Recovery is governance, not customer support

Atlas must not assume a global support administrator can reset sensitive authority.

Recovery should itself have a constitution.

Examples:

```text
2 of 4:
  personal device A
  personal device B
  physical recovery share
  designated recovery guardian
```

or:

```text
1 trusted device
+
1 human recovery guardian
```

or a jointly governed institutional recovery rule.

Therefore:

```text
identity recovery
≠ customer-support override
```

An Atlas support role must not become a universal cryptographic recovery authority merely because it can administer accounts.

## 11. Platform administration is not reality authority

Atlas must preserve:

```text
can administer infrastructure
≠ can reveal sealed reality
```

An Atlas infrastructure administrator may need to:

```text
restore encrypted objects
move ciphertext
repair indexes
replace carriers
rotate service credentials
inspect operational metadata
```

without having authority to reveal:

```text
personal tax identifiers
private health facts
banking secrets
restricted correspondence
other sealed payloads
```

There should be no constitutional requirement for a `SUPERADMIN` capable of universal plaintext access.

## 12. AI is downstream of the same law

AI does not receive an exception.

The ordinary AI path must not be:

```text
database
→ retrieve all sensitive context
→ model
```

For sealed reality it should be:

```text
question
→ determine required operation
→ establish authority
→ execute governed operation
→ return minimum sufficient result
→ model
```

Example:

```text
Instead of:
  salary = 84250
  tax_identifier = ...
  bank_account = ...

AI may receive:
  compensation_within_budget = true
  tax_identity_verified = true
  payroll_ready = true
```

A model's ability to use a plaintext fact is not authority to reveal that fact to the model.

## 13. Authority Capsule — candidate portable unit

The candidate portable abstraction is an **Authority Capsule**.

Conceptually:

```text
Authority Capsule

sealed payload / payload reference
reality type
subject(s)
standing parties
governance constitution
lawful operations
delegations
purpose limits
time limits
recovery law
carrier description
audit lineage
```

The payload may be carried by:

```text
Supabase
a user's device
an organization's server
an encrypted archive
another compatible Atlas carrier
```

The bytes' physical location does not determine governance.

**Authority Capsule is a candidate abstraction only.** It must not become a universal database object until a second non-personnel domain independently proves the same structure.

## 14. Cryptographic carriers are replaceable

Possible carriers include:

```text
conventional envelope encryption
recipient-bound encryption
threshold cryptography
user/device-held keys
secure enclaves
selective-disclosure credentials
MPC / privacy-preserving computation
hardware-backed keys
combinations of the above
```

Atlas must not make any one of these synonymous with Sealed Reality.

The constitutional law survives carrier replacement.

## 15. Current Restricted Personnel Vault status

The current Restricted Personnel Vault is the first proof domain.

Its present structure:

```text
ciphertext
wrapped data key
kms_key_ref
vault entitlement
safe assertions
audit
```

remains lawful as a **transitional cryptographic carrier**.

However:

```text
kms_key_ref
≠ constitutional source of authority
```

The current external-KMS adapter must therefore remain replaceable.

A future personnel-vault revision may replace centralized wrapping authority with individually governed, jointly governed, recipient-bound, threshold, device-held, or privacy-computing carriers without changing the underlying personnel reality.

## 16. Promotion rule

Atlas must not build one universal Sealed Reality table yet.

The Restricted Personnel Vault proves:

- sensitive payload custody;
- operation-specific authority;
- reveal vs assertion distinction;
- audit;
- infrastructure / content authority separation.

A second genuinely different domain must independently prove the shared abstraction.

Strong candidate second domains include:

```text
private financial identity / bank-routing authority
private practitioner/health facts
private correspondence
organization treasury secrets
personal legal identity documents
```

Only after cross-domain proof should Atlas promote common nouns such as:

```text
sealed_reality
standing
operation_authority
delegation
recovery_constitution
authority_capsule
```

into a shared database kernel.

## 17. Tests any future implementation must pass

A Sealed Reality implementation is not valid unless it can prove:

1. **Carrier possession does not imply reveal authority.**
2. **Infrastructure administration does not imply reveal authority.**
3. **A party may perform an allowed operation without receiving plaintext when the operation does not require plaintext reveal.**
4. **Different operations can have different authorities over the same reality.**
5. **Delegation is bounded by purpose, operation, scope, and time.**
6. **Revocation ends future authority without pretending previously revealed plaintext can be made unknowable.**
7. **Joint reality can require joint authority.**
8. **Recovery has its own governance and is not an administrator backdoor.**
9. **AI receives no broader authority than a human/software caller.**
10. **Changing cryptographic carriers does not require redefining who has standing in the reality.**
11. **No universal Atlas master key is constitutionally required.**
12. **No domain becomes public/shared merely because Atlas can compute over it.**

## 18. Governing sentence

> **Atlas does not begin with who holds the key. Atlas begins with who has standing in the reality, what operation is lawful, and under whose authority. Cryptography exists to preserve that order.**

## 19. Second-domain proof completed: Sealed Treasury Authority

The second genuinely different proof domain is now implemented in
`architecture/ATLAS_SEALED_TREASURY_AUTHORITY_SECOND_DOMAIN_PROOF_V1.md`
and migration
`20260924043000_atlas_sealed_treasury_second_domain_proof_v1.sql`.

It proves the constitution outside personnel custody:

```text
Personnel:
  person-associated restricted reality

Treasury:
  institution-governed financial destination authority
```

The treasury proof passed these controls:

- Ledger governing authority may establish the sealed treasury reality but does not inherit `reveal_full`;
- `verify_destination` can return only a boolean through a short-lived one-time operation warrant;
- purpose-scoped authority does not leak into another purpose;
- one-time warrants cannot be replayed;
- `reveal_full` requires a separately granted, explicitly time-bounded authority;
- plaintext-like reveal output is rejected by the canonical receipt membrane;
- the database stores governance plus an opaque carrier locator, not the protected financial destination itself.

Across Personnel + Treasury, Atlas now has cross-domain evidence for these shared constitutional nouns:

```text
standing
sealed reality
operation authority
purpose scope
time scope
delegation
bounded result
reveal exception
carrier independence
audit lineage
```

Treasury additionally proves the usefulness of a short-lived **operation warrant** between governance and a cryptographic carrier.

This satisfies the two-domain promotion threshold for **designing** a shared Sealed Reality kernel.

It does not authorize flattening personnel and treasury into one generic table without first preserving their distinct standing laws and domain-owned lifecycle truth.

