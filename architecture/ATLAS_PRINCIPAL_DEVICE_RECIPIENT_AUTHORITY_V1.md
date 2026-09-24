# Atlas Principal / Device Authority + Recipient-Bound Reveal Carrier v1

**Status:** First individual-governance cryptographic carrier skeleton.  
**Scope:** Public device authority, recipient-bound data-key envelopes, and a one-time device reveal handshake.  
**Production-secret status:** No production secret material is established by this tranche.  
**Governing law:** `architecture/ATLAS_SEALED_REALITY_CONSTITUTION_V0_1.md`.

## 1. Purpose

The Sealed Reality kernel already proves that Atlas can decide whether one operation is lawful without making the shared kernel the source of that authority.

This tranche moves the cryptographic carrier one step away from corporate/global key custody.

The target shape is:

```text
domain authority
    ↓
one-time Sealed Reality warrant
    ↓
specific Principal
    ↓
specific Principal-controlled device public key
    ↓
recipient-bound wrapped record key
    ↓
local/device decryption
    ↓
Atlas receives only:
{"delivered": true}
```

Atlas does not need a universal private key in order for that device to decrypt the record.

## 2. Device authority is not login authority

A Principal cryptographic device is separate from:

- Supabase/Auth login credentials;
- organization membership credentials;
- Ledger authority;
- personnel-vault entitlement;
- Sealed Reality standing.

A signed-in Principal may register public device authority, but device registration alone grants no access to any sealed fact.

The device object means only:

```text
this Principal has registered this public cryptographic authority
```

It does not mean:

```text
this device may reveal every fact the Principal can name
```

## 3. Two device key pairs

v1 uses two independent P-256 key pairs.

### Signing key

Profile:

`ecdsa_p256_sha256_v1`

Purpose:

- future device-possession challenges;
- future signing of authority/recovery actions;
- distinguishing "logged in as Principal" from "possesses this device authority."

### Wrapping key

Profile:

`p256_ecdh_hkdf_sha256_aes256gcm_v1`

Purpose:

- recipient-bound data-key envelopes;
- local derivation of an AES-256 wrapping key;
- no private wrapping key leaves the recipient device.

Only public JWKs are stored in Atlas.

The private JWK member `d` is forbidden at the database membrane.

## 4. Device lifecycle

```text
pending
  ↓ possession proof
active
  ↓ self revocation / governance revocation
revoked
```

Self-registration creates a **pending** device.

A trusted application verifier must prove possession of the registered signing private key before a service-role activation function may mark the device active.

This tranche creates the activation membrane but does not wire a production challenge route.

Therefore no production device becomes active merely because somebody submitted public keys.

## 5. Recipient-bound key envelope

A recipient-bound envelope contains a record data key encrypted specifically to one active Principal device.

Conceptually:

```text
record data key
      ↓
ephemeral P-256 ECDH
      +
recipient device P-256 public wrapping key
      ↓
shared secret
      ↓ HKDF-SHA-256
AES-256 wrapping key
      ↓ AES-GCM
recipient-bound wrapped record key
```

Stored durable material:

- Sealed Reality Handle;
- recipient Principal;
- recipient device authority;
- envelope profile;
- ephemeral public JWK;
- HKDF salt;
- AES-GCM nonce;
- wrapped data key;
- context hash;
- provisioning basis.

Not stored:

- recipient private key;
- ephemeral private key;
- plaintext record data key;
- plaintext protected fact.

## 6. Context binding

The recipient envelope context includes at least:

```text
schemaVersion = sealed_reality_recipient_key_envelope_v1
sealedRealityHandleId
deviceAuthorityId
recipientPrincipalId
operation = reveal_to_device
```

The same canonical context is:

- hashed into `context_hash`;
- used as AES-GCM associated data;
- used as HKDF info by the application crypto helper.

Moving an envelope to another Handle, Principal, or device therefore fails cryptographic authentication.

## 7. Envelope possession does not establish reveal authority

The recipient-bound envelope is cryptographic capability material, but Atlas still requires a lawful Sealed Reality operation warrant before releasing it.

The law remains:

```text
domain authority
AND
active recipient device
AND
active recipient envelope
AND
one-time reveal warrant
=
recipient envelope may be delivered
```

The envelope table is not a permission table.

## 8. First Personnel operation: reveal_to_device

The Restricted Personnel adapter gains a distinct operation:

`reveal_to_device`

v1 authority is intentionally conservative:

- the requesting Principal must still hold existing `vault_record_read` authority for the record class and purpose;
- the request context must identify one active device owned by that Principal;
- one active recipient-bound key envelope must already exist for that Handle/device.

If these hold, the adapter returns:

```text
requiresCarrier = true
carrier = principal_device_recipient_v1
resultPolicy = ephemeral_reveal
revealsPlaintext = true
```

This does **not** claim the final individual-standing law is solved.

It proves the cryptographic carrier can be individually held while standing/authority remains domain-owned.

A later tranche may let the Personnel subject's own standing authorize operations independently of an institutional vault grant once canonical person ↔ Principal standing is proven safely.

## 9. One-time reveal handshake

### Request

```text
request_sealed_reality_operation(
  handle,
  principal,
  reveal_to_device,
  purpose,
  context.deviceAuthorityId
)
```

If lawful, the shared kernel returns a short-lived one-time warrant whose authority basis snapshots:

- device authority id;
- recipient envelope id;
- existing Personnel authority basis.

### Recipient carrier fetch

The trusted application presents:

- warrant bearer token;
- device authority id.

The carrier service verifies:

- warrant exists;
- warrant is issued and unexpired;
- operation is `reveal_to_device`;
- carrier is `principal_device_recipient_v1`;
- warrant Principal owns the active device;
- snapshotted recipient envelope matches that Handle/device;
- envelope is active.

It returns only the recipient-bound envelope material.

### Local completion

The device:

1. derives the ECDH shared secret using its private wrapping key;
2. derives the AES wrapping key with HKDF-SHA-256;
3. unwraps the record data key locally;
4. decrypts the protected record locally;
5. calls shared completion with only:

```json
{"delivered": true}
```

No plaintext is sent back to the shared receipt.

## 10. Important v1 boundary

This tranche does not yet replace the existing KMS-wrapped key stored on the Restricted Personnel record.

During transition, a record may have:

```text
existing carrier:
  KMS-wrapped data key

plus

individual carrier:
  recipient-bound device envelope
```

The recipient envelope is a second carrier of the same record data key, created outside the database when the plaintext data key is lawfully available.

The database does not unwrap the KMS key to manufacture recipient envelopes.

That would merely recreate a central decryption authority.

## 11. Provisioning law

Recipient-bound envelopes must be produced by a trusted local/application cryptographic path that already has lawful access to the plaintext record data key.

The database service records the resulting envelope and provenance.

It does not decrypt, rewrap, or derive the key.

Provisioning is therefore deliberately separate from reveal authorization.

## 12. No universal device super-key

The registry must not introduce:

- Atlas master device key;
- organization master recipient key;
- support-agent recovery key;
- universal wrapping private key.

Each recipient device has its own private wrapping authority.

Infrastructure can store public keys and encrypted envelopes without possessing the private recipient key.

## 13. Recovery remains unresolved

Device loss is not solved by copying the device private key into Atlas.

Recovery must later follow the Sealed Reality recovery constitution.

Possible future forms include:

- another already-authorized personal device;
- threshold recovery guardians;
- hardware recovery token;
- jointly governed recovery ceremony.

v1 intentionally stops before choosing one.

## 14. Application crypto profile

The Atlas application helper uses WebCrypto-compatible primitives:

- ECDSA P-256 / SHA-256 for signing authority;
- ECDH P-256 for shared-secret derivation;
- HKDF-SHA-256;
- AES-256-GCM;
- 32-byte random HKDF salt;
- 12-byte random AES-GCM nonce;
- non-extractable private keys where the runtime supports persisted `CryptoKey` objects.

Public JWK fingerprints are SHA-256 over this canonical JSON shape:

```json
{"crv":"P-256","kty":"EC","x":"...","y":"..."}
```

## 15. What this proves if validation passes

This tranche is successful if Atlas can prove:

1. a Principal can register public device cryptographic authority without storing private key material;
2. the device remains unusable until a separate possession-proof activation occurs;
3. a recipient envelope is bound to one Handle + Principal + device;
4. recording an envelope does not itself create reveal authority;
5. existing domain authority is still required;
6. one authorized `reveal_to_device` request produces a one-time shared warrant;
7. the carrier releases only recipient-bound encrypted key material;
8. a different device cannot redeem that warrant;
9. local decryption can be performed with the recipient private key without Atlas possessing it;
10. durable completion remains only `{"delivered":true}`.

## 16. Governing sentence

> **Atlas may know which device is authorized to receive a cryptographic capability without possessing the private authority that makes that capability usable.**

## 17. Implementation receipt

Implemented by:

- `supabase/migrations/20260924070000_atlas_principal_device_recipient_authority_v1.sql`;
- Atlas application module `lib/sealed-reality/principal-device-authority.ts`;
- Atlas application contract `docs/PRINCIPAL_DEVICE_RECIPIENT_AUTHORITY_V1.md`.

Released database objects include:

- `atlas.principal_cryptographic_devices`;
- `atlas.sealed_reality_recipient_key_envelopes`;
- self registration/list/revocation APIs;
- service-role possession-proof activation;
- recipient-envelope recording;
- Personnel `reveal_to_device` authority resolution;
- recipient-envelope warrant redemption.

### Database validation

Rollback validation passed.

Proved:

- signed-in self registration binds the public device authority to the current Principal;
- registration creates `pending`, not `active`;
- no private JWK member is retained;
- a pending device cannot receive an active recipient key envelope;
- a trusted possession-proof activation is required before the device becomes active;
- an envelope is bound to one Sealed Reality Handle, Principal, and device;
- recording the envelope does not grant reveal authority;
- existing Personnel `vault_record_read` authority is still required in v1;
- after that authority exists, `reveal_to_device` issues a shared one-time warrant for `principal_device_recipient_v1`;
- a different device cannot redeem the warrant;
- the correct device receives only recipient-bound encrypted key-envelope material;
- durable shared completion remains only `{"delivered":true}`.

All validation rows rolled back.

Post-validation live counts were zero for:

- Principal cryptographic devices;
- recipient-bound key envelopes;
- `reveal_to_device` warrants;
- `reveal_to_device` receipts.

### Application crypto validation

The Atlas TypeScript module compiled under the repository's strict DOM/WebCrypto TypeScript profile.

Runtime WebCrypto validation proved:

- device signing private key is non-extractable;
- device wrapping private key is non-extractable;
- ECDSA possession challenge signs and verifies;
- P-256 ECDH + HKDF-SHA-256 + AES-256-GCM wraps and unwraps a 32-byte data key correctly;
- wrapped data-key size is 48 bytes (32-byte key + 16-byte GCM tag);
- context hash matches the database constitution;
- changing the recipient context causes unwrap failure.

No production key material was created or persisted.

## 18. Remaining boundary

The cryptographic carrier now exists, but **individual standing itself is not yet the source of Personnel reveal authority**.

v1 still requires the existing Personnel-domain `vault_record_read` capability before the recipient-device warrant may be issued.

That is deliberate.

The next constitutional question is not another cryptographic primitive. It is:

> How does Atlas prove that a Principal is the human subject with standing in a sealed Personnel reality, so that the person's own authority can govern appropriate operations without depending on institutional grant?

Until that identity/standing bridge is proven, device authority must not be mistaken for subject standing.

## 19. Standing bridge succession

The boundary described above is now partially resolved by:

`architecture/ATLAS_VERIFIED_PERSONNEL_SUBJECT_STANDING_V1.md`

Atlas can now prove, through an explicit verified Atlas Person↔canonical-person binding, that an operating Principal is the same human represented by one Restricted Personnel subject.

For the narrowly approved v1 self-governed record classes:

```text
identity_document
tax_identity
banking_payroll
```

that verified subject standing can itself authorize `reveal_to_device` without an institutional `vault_record_read` grant.

Device possession still remains a separate requirement.

The unresolved identity frontier is now the claimant-verification ceremony that is allowed to establish the verified Person↔canonical-person binding.
