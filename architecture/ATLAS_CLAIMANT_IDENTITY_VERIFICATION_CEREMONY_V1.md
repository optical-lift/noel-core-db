# Atlas Claimant Identity Verification Ceremony v1

**Status:** Claimant-safe verification kernel for establishing verified Atlas Person ↔ canonical-person identity.  
**Purpose:** Let a claimant earn durable identity standing without exposing private resolver evidence and without treating self-assertion as identity truth.  
**Governing dependencies:**
- `architecture/ATLAS_CLAIMANT_SAFE_IDENTITY_DISCLOSURE_V1.md`
- `architecture/ATLAS_VERIFIED_PERSONNEL_SUBJECT_STANDING_V1.md`

## 1. The problem

Atlas may privately recognize that an authenticated claimant probably corresponds to an existing canonical person.

That recognition is useful for resolution.

It is not enough to establish durable identity.

The dangerous shortcut would be:

```text
claimant signs in
→ resolver finds likely canonical person
→ claimant clicks "that's me"
→ durable Person↔canonical binding
```

Atlas must not do that.

A mistaken resolver result, recycled identifier, shared contact point, private Ledger observation, or malicious self-claim must not become permanent human identity truth merely because the claimant agrees with it.

## 2. Ceremony sequence

The lawful v1 sequence is:

```text
authenticated Atlas Person
        ↓
trusted resolver/operator selects internal canonical candidate
        ↓
claimant-safe projection only
        ↓
verification case
        ↓
independent proof factors
        ↓
policy threshold satisfied
        ↓
trusted commit
        ↓
verified Person↔canonical-person binding
```

The claimant may see only the claimant-safe projection.

The claimant does not receive:

- private resolver signals;
- private identifiers;
- contributing Ledgers;
- blind-match tokens;
- confidence score internals;
- source-record provenance;
- the reason Atlas suspected the match.

## 3. Candidate selection is not self-service truth

A claimant verification case is started only by trusted service code.

The client does not create a case by supplying an arbitrary canonical entity id to a self-service binding API.

The case may originate from:

```text
identity_resolution
operator_selected
recovery_continuity
migration_review
```

The origin is recorded, but the private underlying resolver artifact is not copied into the case.

Instead Atlas retains only an opaque SHA-256 `candidate_basis_hash` that can reconcile the case to a trusted upstream decision without disclosing that decision to the claimant.

## 4. Claimant-safe snapshot

Case creation calls the existing:

`atlas.claimant_safe_identity_projection_service_v1(canonical_entity_id)`

and freezes that safe projection into the case.

This snapshot is what claimant-facing UI may display.

The snapshot can be:

```text
anonymous_match
public_identity
public_identity_with_affiliations
```

A case is allowed even when the projection is `anonymous_match`.

That means Atlas can verify a claimant against an internally recognized identity without leaking the private facts that produced the recognition.

## 5. Self-assertion is not a proof factor

The claimant may say:

```text
"yes, that is me"
```

but v1 does not count that statement toward the verification threshold.

Likewise these do not count as proof by themselves:

- being signed in;
- knowing a public name;
- possessing a newly registered Atlas device;
- matching a resolver probability;
- clicking a confirmation button.

## 6. Proof factors

v1 supports trusted-verifier factor receipts in three families.

### contact_possession

Factor kind:

`verified_contact_possession`

Meaning:

The claimant demonstrated control of a contact route they themselves presented to a trusted challenge adapter.

The durable factor stores no email address or phone number.

The verifier records only a SHA-256 proof-artifact hash and verifier identity.

Assurance: `medium`.

### identity_document

Factor kind:

`government_identity_document`

Meaning:

A trusted verification adapter or authorized human verification ceremony checked a government identity document sufficiently to conclude that it supports the candidate identity.

The raw document is not stored in the ceremony tables.

If the document itself must be retained, it belongs in Sealed Reality under its own custody law.

Assurance: `high`.

### trusted_presence

Factor kind:

`trusted_in_person`

Meaning:

An authorized verifier completed an in-person or equivalently controlled identity check against the candidate.

Assurance: `high`.

The factor vocabulary can later expand only through a schema/governance change.

## 7. v1 verification threshold

The v1 policy is intentionally conservative.

A claimant-binding case requires:

```text
at least 2 passed factors
AND
at least 2 distinct factor families
AND
at least 1 high-assurance factor
```

Therefore:

```text
verified_contact_possession
+
government_identity_document
→ may qualify

verified_contact_possession
+
trusted_in_person
→ may qualify

two contact challenges
→ do not qualify

government document alone
→ does not qualify

claimant click + document
→ claimant click does not count
```

This is an Atlas architectural safety threshold, not a claim that every external identity regime uses the same standard.

## 8. Factor receipts are not raw evidence

A factor receipt contains:

- case id;
- factor kind;
- factor family;
- assurance level;
- passed/failed/revoked state;
- verifier key;
- SHA-256 proof-artifact hash;
- verified-at time;
- bounded metadata.

It must not contain the raw secret used for verification.

The ceremony kernel therefore knows:

```text
this verifier says this factor passed
```

without becoming a second store of the claimant's identity documents, OTPs, phone numbers, or private resolver data.

## 9. Trusted factor recording

Only trusted service code can record a factor result.

There is no authenticated self API that says:

```text
mark my factor passed
```

The external verification adapter must actually perform its proof ceremony first.

The database service records the result after that adapter has decided.

## 10. Commitment is separate from proof collection

Satisfying the factor threshold does not silently mutate identity.

The case enters:

`ready_to_commit`

A separate trusted commit service then:

1. re-checks case expiry/state;
2. re-checks factor threshold;
3. re-checks that the canonical entity is still an active person;
4. calls the existing verified Person↔canonical binding service;
5. records the resulting binding id;
6. marks the case `verified`.

This separation prevents a single factor-recording call from accidentally becoming durable identity truth.

## 11. Conflict behavior

The existing verified binding kernel already fails closed when:

- one Atlas Person is already verified to another canonical person; or
- one canonical person is already verified to another Atlas Person.

The ceremony does not bypass that law.

If commit encounters such a conflict, the case does not silently rebind either identity.

It moves to a non-success state requiring explicit resolution.

## 12. Case states

```text
pending_proof
→ ready_to_commit
→ verified

pending_proof / ready_to_commit
→ rejected
→ cancelled
→ expired

commit conflict
→ conflicted
```

A verified case is historical evidence of the ceremony.

It is not the canonical identity binding itself.

The canonical binding remains `atlas.person_canonical_entity_bindings`.

## 13. Claimant-facing read

An authenticated claimant may read only their own case projection.

The self view may expose:

- case id;
- case state;
- expiration;
- frozen claimant-safe identity projection;
- required factor count/families/high-assurance rule;
- factor kinds already completed;
- whether the case is ready to commit.

It must not expose:

- `canonical_entity_id` when the safe projection is anonymous merely as a debugging convenience;
- candidate basis hash;
- factor artifact hashes;
- verifier internal identifiers;
- private resolution evidence.

## 14. Cancellation

The authenticated claimant may cancel their own unverified case.

Cancellation does not delete resolver evidence and does not assert that the candidate was wrong.

It means only:

```text
this claimant is not continuing this verification ceremony
```

## 15. Expiry

Cases are short-lived.

v1 default expiry is 30 minutes.

A case that is not committed before expiry must be restarted so that:

- the claimant session is fresh;
- the candidate can be re-evaluated;
- factor validity does not persist indefinitely.

## 16. Relationship to claimant-safe disclosure

Recognition and disclosure remain separate.

Even after a case is verified, the ceremony itself does not promote private evidence into Shared Intelligence.

The verified Person↔canonical binding says:

```text
this authenticated Atlas Person is this canonical human
```

It does not say:

```text
show the claimant every fact Atlas knows about that human
```

All disclosure still follows its own authority.

## 17. Relationship to individual Sealed Reality standing

Once committed:

```text
verified claimant ceremony
→ Person↔canonical binding
→ Personnel subject standing may resolve
→ policy-approved individual Sealed Reality operations may become lawful
```

The ceremony therefore establishes identity standing.

It does not itself reveal any sealed Personnel record.

Device authority and recipient-bound cryptographic capability remain separate requirements.

## 18. Required validation

v1 is valid only if rollback proof shows:

1. case start is trusted-service only;
2. claimant receives only the claimant-safe projection;
3. private candidate basis hash is not returned by claimant self read;
4. one high-assurance factor alone is insufficient;
5. two same-family factors are insufficient;
6. medium + high from distinct families becomes `ready_to_commit`;
7. factor recording alone does not create a verified identity binding;
8. commit creates the binding only after the threshold is satisfied;
9. conflicting binding commit fails closed;
10. another authenticated Person cannot read or cancel the case;
11. cancellation never creates a binding;
12. no raw OTP, contact value, identity document, or private resolver signal is stored in ceremony tables.

## 19. Governing sentence

> **Atlas may privately recognize a likely identity, but durable human standing is established only by a separate claimant-safe verification ceremony whose proof threshold is independent of the private evidence that produced the match.**
