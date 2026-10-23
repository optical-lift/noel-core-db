# Existing-Person account transition readiness (Build 1)

Status: source-only additional Build 1 verification. This is a **nonmutating**
operator-gated projection. It is not a credential transfer.

## Evidence from current Atlas architecture

The existing new-Auth claim completion is deliberately prohibited when an
active credential, Reality binding or Principal exists for its Person.
`atlas.principals.user_id` is tied to the old Auth identity, while
`atlas.current_principal_id_v1()` resolves by canonical Person.
`atlas.principal_person_compatibility_v1()` runs on Principal user change and
can call `atlas.ensure_person_for_auth_user_v1()`, a compatibility writer.
Consequently, rewriting a Principal's Auth id directly is not a safe stand-in
for governed account replacement.

## Read-only classification

`public.existing_person_auth_transition_readiness_self_api_v1(org,person)`
requires the current signed verified steward for the **exact canonical Person**
and returns states:
- `ready_for_existing_person_claim`
- `claim_in_progress`
- `retired_access_needs_revocation`
- `requires_old_credential_retirement`
- `requires_explicit_authority_transfer_review`
- `identity_conflict`

The response does **not** expose old Auth IDs, email addresses, sessions, or
private evidence. It does **not** mutate Person, Principal, Ledger seats,
credential, Auth, billing, or access.

## Retirement ceremony not yet source-approved

An authorized recipient's consent and independently witnessed review must be
captured for the **old** identity as well as the new. Supabase Auth provider
must disable old credential and revoke every old session; deleting or banning
by itself is not enough to invalidate issued JWTs. All persisted identity
bindings and legacy compatibility writers must reject the retired account.
Any Principal re-home must preserve original Principal ID and source attribution,
and explicitly review household, finance, employment, institutional membership,
and root governing authority. Do not silently transfer those privileges.

Until that separate transaction is released and genuinely tested, the current
approved Build 1 claim continues to fail closed for active legacy credentials.

## Katie

Katie's live Person has one active credential, one active Reality Auth binding,
one active Principal, two Elm native Ledger seats, and no active institutional
membership or native Ledger root grant in the examined Principal tables.
She also has an unexpired old Auth session. **This is diagnostic evidence,
not permission to disable or move her account.**

No real Katie email or legacy account may be used as a writable test fixture.
Use disposable GoTrue-authenticated actors in the protected local clone.
