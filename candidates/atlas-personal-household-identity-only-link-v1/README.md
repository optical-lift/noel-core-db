# Household identity-only connection — governed Atlas candidate

**Source-only candidate. Not deployed.** Two independent signed-in adult Personal Atlas owners can affirm that a particular existing non-account member row in one owner's household corresponds to the accepting adult's existing canonical Person identity. This does not give the accepting adult Household read/write permission, change `household_members.user_id`/`person_id`, modify either `principal.active_household_id`, introduce a second Person/household, grant Personal Atlas access, or merge Ledgers/notebooks.

## Encounter
1. Owner selects **Connect Atlas account** on an existing member row, generating an unpredictable one-use link. Link secret is returned once; only a SHA-256 digest is stored. Reissue revokes previous unaccepted invites. Link expires after seven days.
2. Owner shares link out-of-band. **No email search or invitation email** is made; knowing someone's email alone is not verified account authority.
3. Recipient signs in to their own Personal Atlas, sees only the invited label and owner label, chooses **Accept identity connection**, and the backend checks their already-established Principal, Person, active verified canonical Auth binding, credentials and native Personal Atlas.
4. Only a separate `household_member_identity_links` record is written. The owner sees **Connected** next to that member, never the recipient's credential/email or private notebook.
5. Either the originating owner or the accepted recipient can disconnect via the separately authorized endpoint. History retained as revoked link rows. No visibility grant is ever made.

## Hard protections
- No access can be inferred from invitation, Person relationship, or the new link table. Existing Household resolver still uses `principal_current_household_id_v1` and is unchanged.
- Tables are not exposed directly to `authenticated`; RLS enabled. Public RPCs are owner/recipient gated SECURITY DEFINER.
- Unknown/expired/revoked tokens return the same generic failure; secrets never appear in source logs, PR fixtures, or database tables in plaintext.
- Existing household-member row remains untouched (including user_id/person_id). Exact Person UUID from verified Principal is used; name/email never merges identities.
- One active link per member and per target Person within one household; one pending invitation per member; no replay effects.
- Secrets carried in browser URL **fragment**, removed from history on recipient UI load; no query string or server referrer token.
- Only explicit user actions cause writes. Both independently consent.

## Release gates
Generate new canonical `atlas_` migration from merged exact candidate. Run disposable production-shaped clone tests for: unauthorized owner, wrong Household member, replay/expired/revoked token, owner-self-accept denial, signed-in Personal Atlas without canonical binding, duplicate Person, second household, recipient-authorized disconnect, RLS/grants and **no delta** to `household_members`, `principals`, `personal_atlas_access_grants`, Person or Ledger. Independent protected DB production release required, followed by consumer Preview tests and independent Atlas production release. Do not silently add email delivery or shared access.
