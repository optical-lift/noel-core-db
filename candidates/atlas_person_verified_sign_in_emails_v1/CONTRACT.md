# Person multi-email sign-in evidence registry — gated canonical candidate

**Candidate only.** No production Auth, Person, invitation, email or Ledger changes.

## What is implemented here
- One canonical Person can retain multiple address evidence records, each bound
  to the same original Auth user, but only **one current native primary**.
- A sign-in transport is separate from email possession and Person identity.
- Verified addresses cannot be claimed by two Persons; only one can be preferred.
- A prior native email becomes a retired historical alias when Supabase Auth
  has independently confirmed a replacement on the SAME user ID.
- The signed-in user's self-only read and post-confirmation reconciliation are
  allowed only when one existing active Person credential matches auth.uid().
- Neither function manufactures Auth users, email proof, Principal ownership,
  entitlements, Ledger connections, another person's Person, or a second seat.
- The unimplemented alias OTP transport is explicitly prohibited by CHECK.

## What is not implemented here
- A secondary alias add/verify transport.
- Email challenge delivery for recovery without the old inbox.
- Independent high-assurance claimant-factor approval and trusted reviewer.
- Admin Auth update after two independent proofs.
- OTP routing to a secondary alias (future verified broker).
- End-to-end Katie sign-in / account claim.

Atlas H8 and H6/H7 release remain separate. The source and app eligibility
policy must not be promoted as a complete login feature.

## Recovery without original mailbox
The recipient verifies a fresh delivery challenge to the NEW inbox and passes
the canonical Person-claimant verification ceremony; only a protected service
then updates **the original Auth user's** primary email using Supabase Auth Admin.
After a successful provider readback, the recipient can sign in via OTP to
the new primary and run `public.reconcile_person_native_sign_in_email_self_api_v1()`.

The old address stays as historical evidence, not an automatically login-able
alias while its inbox is unavailable. No privileged service may issue a sign-in
code to an address simply because a Principal typed that address or asserted
a relationship.

## Acceptance
- Auth actor missing/unsigned → no source inventory/transition.
- Credential ambiguity or other Person → reject, preserve history.
- Changed email not yet confirmed by Supabase → no preferred update.
- Secondary alias without independently released broker → no login.
- Two Persons try to claim one verified address → reject.
- Existing preferred / old Auth email retired only after verified Auth change.
- Any mail or claimant-case failure → no primary rewrite.
- Historical Elm institution membership / Person UUID unchanged.
- No new bill, account, or employee-seat records from an address change.
