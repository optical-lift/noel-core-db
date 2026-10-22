# Existing-person recovery candidate

Source-only. An authorized organization owner begins an email recovery for an existing Person, and the claimant verifies the new inbox with a short-lived code. The reviewer must independently verify the individual in person or on a video call. The original Person and Auth user IDs must be preserved.

The database candidate provides service-scoped request, code verification, review, preparation and readback receipts. Atlas's Edge Function handles code delivery through its configured email provider and the protected Auth Admin update after both verifications.

No account is activated, invitation issued, or database migration deployed by this document. Before release, clone validation and authenticated cross-person, expired-code, wrong-code, ownership, and concurrent-request tests are required.