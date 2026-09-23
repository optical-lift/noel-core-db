# Atlas Restricted Personnel Vault Kernel v1

## Purpose

Atlas needs a stronger custody boundary than an ordinary Ledger for highly sensitive personnel material such as compensation, tax identity, payroll banking, background records, disciplinary records, performance material, accommodation records, and identity documents.

The vault law is:

```text
canonical identity
    may point to the existence of restricted custody

Ledger authority
    does not automatically grant vault access

vault access
    requires an explicit time-bounded capability entitlement

vault payload
    is ciphertext only

every attempted read
    becomes durable audit reality
```

## Security boundary

`atlas.restricted_vaults` belongs to one existing Atlas Ledger but has its own entitlement boundary.

Owning or administering the Ledger is not equivalent to being able to read the vault.

Vault creation requires existing governing authority over the Ledger. After creation, routine vault access is governed by vault-specific entitlements.

## Subject binding

`atlas.restricted_vault_subjects` binds a restricted personnel vault to the canonical Shared Intelligence person it concerns.

The binding establishes only:

```text
this Ledger has restricted personnel custody for this canonical person
```

It does not place personnel contents into Shared Intelligence and does not create a traversal path from Shared Intelligence into vault records.

## Capability entitlements

`atlas.restricted_vault_entitlements` grants one Principal one explicit capability for one vault.

Initial capabilities:

- `vault_metadata_read`
- `vault_subject_index`
- `vault_subject_admin`
- `vault_record_read`
- `vault_record_write`
- `vault_assertion_read`
- `vault_assertion_write`
- `vault_entitlement_admin`
- `vault_bulk_export`
- `vault_key_admin`

Entitlements carry:

- valid-from / valid-until;
- status;
- optional record-class scope;
- optional purpose scope;
- grantor;
- grant basis.

Empty record-class/purpose scopes mean all classes/purposes for that capability.

Temporary access is therefore a normal state rather than a special case.

## Record classes

`atlas.restricted_vault_record_classes` defines recognized personnel categories and their default sensitivity.

Initial classes:

- `compensation`
- `tax_identity`
- `banking_payroll`
- `background_record`
- `disciplinary_record`
- `performance_review`
- `accommodation_record`
- `identity_document`
- `other_personnel_sensitive`

Record classes are policy vocabulary. They are not merely free-text labels supplied by application code.

## Ciphertext-only storage

`atlas.restricted_vault_records` contains no plaintext payload column.

A writer must supply:

- encrypted ciphertext;
- an externally wrapped data key;
- a declared crypto profile;
- the vault's external KMS key reference/version;
- a content hash of the plaintext or canonical payload produced by the trusted crypto layer;
- purpose, record class, and retention metadata.

The database never receives a plaintext field for the protected payload.

v1 assumes envelope encryption is performed by a trusted application/crypto service before the write reaches Postgres. The KMS master key itself is never stored in Atlas tables.

Recommended profile contract:

```text
plaintext personnel document
        ↓
per-record data key
        ↓ AES-256-GCM
ciphertext

data key
        ↓ external KMS
wrapped data key
```

## Safe assertions

`atlas.restricted_vault_assertions` lets the vault expose controlled derived answers without revealing the underlying secret.

Examples:

- `tax_identity_verified = true`
- `payroll_setup_complete = true`
- `background_check_complete = true`
- `has_current_direct_deposit = true`

Assertions remain vault-controlled in v1. They do not automatically become Ledger or Shared Intelligence facts.

A later purpose-specific membrane may selectively promote approved assertion types upward.

## Audit

`atlas.restricted_vault_audit_events` is append-only.

Every protected read attempt records:

- principal;
- vault;
- subject/record when applicable;
- requested capability/action;
- allow/deny outcome;
- purpose key;
- reason;
- timestamp;
- session/context metadata.

Direct service-role DML is revoked from the audit table. Audit rows are written through security-definer services.

Updates and deletes are blocked by trigger.

Denied reads return an authorization result rather than raising after the audit write, so the denial receipt is not rolled back.

## Read path

The read service returns an encrypted envelope only:

```text
authorized principal
    ↓
vault entitlement check
    ↓
audit receipt
    ↓
ciphertext + wrapped key + crypto metadata
    ↓
external KMS/crypto layer
    ↓
plaintext to the authorized caller
```

Postgres itself never returns plaintext because it never stores plaintext.

## Default-deny rule

No vault entitlement means no protected access.

Ledger administration is not a fallback read permission.

The only Ledger-level exception is initial vault creation by an already-authorized governing Principal. Creation automatically grants that creator `vault_entitlement_admin`, `vault_metadata_read`, and `vault_subject_admin` so the vault can be administered. It does not automatically grant record-read, record-write, bulk-export, or key-admin capability.

Those powers must be granted explicitly.

## Separation of duties

The capability model keeps these authorities separate:

```text
can administer who has access
≠
can read personnel contents
≠
can write personnel contents
≠
can administer encryption keys
≠
can bulk export the vault
```

v1 establishes those boundaries even though external KMS key-admin workflows and two-person bulk-export approval are later tranches.

## Core law

```text
the Ledger may know the vault exists
the vault may know the personnel secret
the rest of Atlas receives only what a separate membrane explicitly permits
```
