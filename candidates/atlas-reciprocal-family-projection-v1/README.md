# Identity-only Family retrieval — governed source candidate

The first real two-person acceptance created exactly one confirmed Household identity link, but the recipient's Personal Atlas still rendered only “Household of Lex” in Home, and the Family section did not appear in their Index because section membership was derived solely from Foundry answers.

## Repair
- Enrich the existing **recipient-only** `atlas.household_identity_received_links_self_v1()` with `relationshipAsRecorded`, sourced from the inviting Household member's `relationship` field (not independently confirmed by recipient); add explicit `relationshipSource`, `relationshipReciprocallyConfirmed:false`, `householdAccessGranted:false`.
- Let the existing notebook-index reader make the **Family** section retrievable when the signed-in Principal is the accepted target of an active identity-only link. Index inclusion is an address / retrieval decision, never a canonical family-membership claim or authorization.
- Neither function mutates rows, binds Person into `household_members`, changes `principal.active_household_id`, merges Person records, grants access, or creates a second relationship object. If an identity link is disconnected, its projection disappears on re-read; Foundry-established Family remains independently retrievable.

## Access/privacy
No new tables or public RPCs. Reuse the already-authenticated recipient-scoped functions and `auth.uid()` filters. The only additional relationship text is a value the inviter recorded on **the specific member** that the recipient explicitly accepted as representing themselves. Display as *“Recorded as spouse in Lex's household”* and not *“Mutually confirmed spouse”*. Never expose other members, contact information, or household operating details.

## Required clone tests
- Two distinct authenticated adults, one accepted link: recipient index includes Family; inviter index unchanged except independent orientation. A foreign Principal cannot read this association.
- Recipient receives only their accepted link to the owner; the role text is attributed to the inviting household record and is not a reciprocal canon fact.
- Revoked identity link removes the derived Family inclusion absent other evidence.
- No household membership, Principal scope, Ledger/access permissions or any source table rows change.
- Verify the existing public wrappers and grants remain intact. Independent protected database release still required.

Current candidate source only; **not live**. UI consumer follows independently through Atlas PR review and Preview.