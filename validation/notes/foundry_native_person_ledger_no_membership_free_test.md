# Native Person-only Foundry signed validation

**Validation candidate only — never merge/deploy this file.** Test version `20261024213000`, shared lane.

- Directly replaces Foundry's two private membership-based reviewer functions with the same canonical Person/native Ledger relationship used in Build 5.
- Never checks `atlas.organization_memberships` or its `employee`, `consultant`, `member` roles for reviewer eligibility.
- Private helper `atlas.persons_share_active_native_ledger_v1` is not an external RPC or information disclosure grant. A shared Ledger is a participation fact, not blanket Ledger permission or AI consent.
- Fixture creates fictional canonical owner, signed reviewer, signed unrelated Principal and a **Person without an Atlas login**, with owner/reviewer/accountless seats to the same synthetic Ledger and **zero legacy organization memberships**.
- The protected full production-schema-clone free runner signs in separate local GoTrue users, verifies list and writer agree, outsider and anonymous denials, source case review/revoke, session revocation, no historical Foundry/Person/Ledger mutation.
- Proves accountless Person and login independence at the relation layer, though only an authenticated reviewer can actually sign a human decision. General source reviewers without a shared Ledger require a later bounded Personal People relationship/invitation mechanism, not a new membership/seat identity.

No live production write, no paid Supabase branch and no cross-organization content exposure.
