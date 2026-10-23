# Build 1 — Existing Person / new Auth claim verification gate

**Status:** source-only review protocol. NOT a record of tests passing.
**Owning source:** `candidates/shared/shared_existing_person_new_auth_claim_v1.sql`
**Application:** `optical-lift/atlas` draft PR #365.
**Database:** draft PR #2071. 
**No productive user or Katie fixture is writable by this protocol.**

## Canonical invariants

- One Reality Person and existing `atlas.people` identity, exactly matching UUID;
  no clone of `reality.entities`, `atlas.people`, work history or `ledger.seats`.
- An old Auth credential and a new Auth user are not the same identity.
  Changing an email on the **same** Auth user is handled by the separately
  released email-recovery procedure and is never a new-Auth claim.
- Operator/source identity, recipient Auth verification, explicit acceptance,
  independent in-person/video identity review, and binding are distinct receipts.
- The writer changes only `atlas.person_auth_credentials`,
  `reality.auth_person_bindings`, `atlas.person_sign_in_emails`, and claim case
  state; no `atlas.principals`, memberships, roles, financial access,
  responsibilities, purchases, seats, or Personal Atlas entitlement is generated.
- Newly introduced Reality active-Person unique index must be audited for
  compatibility with every other authentic Person admission writer.

## Required environment

An isolated production-shaped schema clone with Auth service, genuine
signed Supabase email-verified sessions, **disposable** People and
Organization/Ledger fixtures, and at least:
- S: authorized institutional Person steward;
- C: independently signed and email-verified intended claimant, with no
  existing Person/Principal/Organization identity;
- W: independent wrong-email, email-verified Auth user;
- X: another authorized steward/second concurrent writer;
- P: exact existing canonical Person with established historical non-Auth
  participation and native Ledger seats.

Do not generate real invitations or production identities as fixtures.

## Mandatory green suite (not yet executed)

1. S prepares P for C's exact verified email and evidence.
   Inspect as S: `prepared`. Inspect as C with the case reference:
   minimal intended Person information. W is denied and learns nothing.
2. S cannot `accept`; C must explicitly accept. C can reject before accepting.
   A repeated prepare/accept returns the original case and no duplicate records.
3. C cannot approve. W cannot approve. A steward for another Organization
   cannot prepare, approve, list, or reject the case.
4. S records a genuine independent identity review only after acceptance.
   No evidence, wrong method, or wrong status fails closed.
5. C completes the approved claim. Assert exactly one new active credential,
   exactly one Reality active Auth binding, exactly one primary verified
   sign-in email; all reference the original P UUID and the verified C user.
6. Assert **zero** mutations to existing Ledger seats, Work and historical
   provenance, Principal, membership, entitlement, billing and financial
   authority. Repeat `finish`, sign out/in, and prove `current_person_id_v1`
   resolves P. Review original case receipt.
7. Competing C and X bindings to P from concurrent signed sessions cannot
   both commit: one active Person constraint is enforced independently of
   presentation. Verify idempotency vs duplicate constraint failure.
8. Change C's verified email after acceptance; finalization must fail rather
   than bind a different email. Recycle the proposed email to W: reject.
9. Use a previously bound new claimant, active old credential, active old
   Principal, session that has been revoked from `auth.sessions`,
   old active institution access, and decommissioned-but-re-enabled old Auth:
   each must fail closed without writes or revived authority.
10. Expiry, rejection, dispute, repeated review, absent case, malformed UUID,
    missing signed session, anonymous role, forged JWT principal/user and
    attempted direct table SELECT/UPDATE must all deny without data disclosure.
11. Confirm new-Person establishment remains separately governed and cannot
    be reached by this claim API. Confirm invitation transport is absent.
12. Run `supabase db advisors`, source-ownership checks, exact schema-clone
    validation, and app typecheck, prebuild/Next build. Inspect approved RPC
    grants and migration receipt once released.

## Release stops

Do **not** merge or release a partial migration if any of the above has not
passed. There is no permission to use a production Auth user, especially
Katie, as a writable fixture. Do not treat successful static contract tests
or Database Custody CI as proof of signed identity verification.

If existing Auth credentials must be retired, the separate provider-backed
revocation/retirement ceremony must be implemented and tested first. This
draft's new-account writer rightly **refuses** to displace a still-active
Auth/Principal instead of guessing authority. Closing Build 1 requires that
separate lifecycle and verified historical continuity, not merely the
no-active-credential happy path.

## Required handoff receipt

Include reviewed source SHA, generated migration version, schema-clone run,
negative and concurrent Auth-session test receipts, protected production
release run and migration hash, exact Atlas app SHA and production deployment,
authenticated sign-out/in observations, and unchanged historical
Person/Ledger/Work counts. Only then mark Build 1 released.
