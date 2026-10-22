# Existing-person recovery candidate

Source-only. An authorized organization owner begins an email recovery for an existing Person, and the claimant verifies the new inbox with a short-lived code. The reviewer must independently verify the individual in person or on a video call. The original Person and Auth user IDs must be preserved.

The database candidate provides service-scoped request, code verification, review, preparation and readback receipts. Atlas's Edge Function handles code delivery through its configured email provider and the protected Auth Admin update after both verifications.

No account is activated, invitation issued, or database migration deployed by this document. Before release, clone validation and authenticated cross-person, expired-code, wrong-code, ownership, and concurrent-request tests are required.
## Additional production gates

The verification challenge expires after 15 minutes, is consumed only once and
is limited to five incorrect attempts. Review and recovery may occur after code
consumption but within the separately bounded 24-hour case lifetime. A case
may not be promoted by a mere knowledge of its ID.

The finish step atomically retires the historical primary email and records
the new verified, preferred native OTP email for the **same existing Auth user
and Person**. It cannot create a second account or entitle a Personal Atlas.

Before production release, determine the proper handling of old active Auth
sessions. A new confirmed primary email alone does not necessarily revoke
previously issued JWTs or refresh tokens. Validate revocation/re-authentication
behavior against current Supabase Auth; do not declare security acceptance
solely because the email text was updated.

The Edge Function must have public `verify_jwt=false` only for the claimant's
anonymous code-verification action. All privileged actions must independently
verify an actual Supabase bearer and the canonical owning-organization authority.
Set `NEXT_PUBLIC_ATLAS_EXISTING_PERSON_RECOVERY_V1=enabled` only after source,
secrets, email provider and negative tests are accepted.
