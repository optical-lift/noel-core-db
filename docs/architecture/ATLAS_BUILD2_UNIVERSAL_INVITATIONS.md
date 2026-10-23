# Atlas Build 2 — Universal Person Invitations (source-only candidate)

Every invitation is an access **offer**, never a Person/employee/Ledger seat. Source custody lives in `noel-core-db`. The new `atlas.universal_person_invitations` stores one exact organization, canonical Person (or a *new-Person candidate label only*), normalized verified recipient email, identity case reference, complimentary access offer, issued/expired/revoked/claimed status and delivery evidence. No employee-seat dependency.

## Release flow

1. Authorized institution owner or native Ledger root prepares using a real Person or a new person *candidate*. A confirmed existing account with a **different** email is held for Build 1's unreleased retirement route, not guessed from name/email.
2. Issue generates 256-bit link code in SQL and persists SHA-256 only; plaintext returned once. Manual link copy is available; there is NO sender or provider-confirmed delivery yet.
3. The recipient signs in through Supabase OTP on the exact email, and uses the secret link to inspect. Existing Person requires same canonical Auth binding; otherwise a Build 1 claim case is required. New Person remains a candidate until canonical Personal Atlas Bookplate setup promotes the authenticated Person using the separately governed source.
4. Claim delegates to `redeem_personal_atlas_complimentary_test_self_api_v1` and the existing `begin_personal_atlas_self_api_v1`/Bookplate system. Stripe records and billing are never written by the invitation source. Ordinary paid onboarding remains unchanged.
5. Decline and Not me revoke the unused entitlement and do not touch historical Persons or relationships; operator revoke, manual send assertion and reissue are auditable, link secrets are rotated.

## Critical release gates

- Genuine disposable signed-auth recipient/owner/wrong-email tests, including no-bound new Auth, existing bound Person and Build 1 pending Person, session refresh/re-entry and canonical identity continuity.
- No-charge test reconciles ZERO new Stripe Customers/invoices/subscriptions in the real connected backend (database checks alone cannot attest external Stripe). A signed test cannot prove external Stripe side effects without querying them.
- Verify unique recipient entitlement behavior when a complimentary invitation was previously claimed. Reissue/expiry/revocation and duplicate claim must fail appropriately.
- Complete real UI and user interaction, protected schema clone, no leakage of link codes via logs, strict private ACL and current source ownership review.
- Katie has an existing Person/login: no issued link and NO send while Builds 3–5 incomplete.
- No invitation delivery provider is claimed. Manual-copy and manual-send assertions are explicitly distinct from provider receipts.
- Build 1 **active-credential replacement** is a separate release-gated dependency and remains blocked.

No candidate data rows or production emails are created by this migration.
