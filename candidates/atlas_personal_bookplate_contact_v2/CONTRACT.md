# Personal Bookplate contact alternatives and optional identity facts (draft)
Founder direction 2026-10-12: Keep the approved photographic front leaf. Use small + affordances for additional labeled emails, phones and addresses, and optional DOB and sex. Stripe's email/name/billing address are candidate evidence; never equate billing with residence or alternate email with authenticated login/mailbox permission. The normal bookplate event remains the canonical identity establishment seam and normal deterministic Foundry follows; no AI dependency.

This candidate adds bounded structured contact arrays and DOB/sex to the per-user append-only personal bookplate events. Both v2 RPCs are security-definer but explicitly check auth.uid, and the read binds to the current active Principal and owner. The existing v1 writer remains the sole authority establishing Principal and Home. The v2 writer calls v1 and writes extra values into the same new event within the same transaction. No live table or RPC has been changed.

Open issues for review: enforce date-of-birth/sex privacy and retention policy; confirm preferred controlled vocabulary for 'sex'; ensure v2 audit event idempotency tests, malformed JSON, XSS in labels, multiple same-address entries, auth email correction not changing login, and verify the v1 result after commit. Limit contacts to eight per kind before approving. The later consentful mailbox connection is a separate scope, not created by listing contact details.

Source-first release required in noel-core-db; reviewed clone test and governed migration before Atlas UI PR deployment. No production DDL.
### Required public Auth gateway (Oct 12 review)

Found a source-level incompatibility: browser Supabase JS `.rpc()` calls resolve the `public` API wrapper, not the internal `atlas.*` routines. The initial candidate only granted authenticated access to internal v2 functions, unlike the existing v1 pattern. The candidate now installs `public.personal_atlas_bookplate_self_api_v2` and `public.set_personal_atlas_bookplate_self_api_v2` as restricted `SECURITY DEFINER` pass-throughs, revokes direct authenticated internal invocation, keeps auth.uid and canonical v1 writer checks, and adds v2 entries in the authenticated RPC registry. Clone-only validation asserts the gateway ACL and registry; further user-scoped fixture tests are still required.

### Production-schema clone feedback

The first generated Bookplate migration 20261012204319 (PR #1471) **failed** at PL/pgSQL writer parse during candidate application: `syntax error at end of input` adjacent to a nested `CASE WHEN contactAddress ... END` inside a compound IF. A simplified direct JSON comparison under an existing not-null guard removes that expression; explicit terminators are retained. Regenerate a fresh migration version from corrected candidate bytes. Never release the old failed PR.
