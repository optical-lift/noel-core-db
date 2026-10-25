# Author source identity, canonical Program storage

Source-only candidate. Reuses the **existing** `atlas.personal_training_programs` and immutable `personal_training_program_versions`; introduces no second Program table.

The default v2 create operation serializes requests by author Principal and a SHA-256 fingerprint of the sorted unique **source-content digests**, and rejects a separate create attempt if an authored draft or any approved version already cites the identical source set. The same original request key retains canonical idempotency. An additional private append-only `personal_program_author_source_receipts` register preserves the source fingerprint on **every create and save**, including documents replaced in an unapproved draft before any immutable version exists. These receipts are custody metadata, not a second Program store. The author-only lookup displays existing matches for review; it is not an access grant.

A separate, explicitly named `personal_program_author_create_distinct_self_api_v1` operation requires a reason and stores it in an append-only, inaccessible-to-clients author fork-audit table. Distinct endeavors are intentional, not automatic reimports. All API commands preserve current Principal and Personal Atlas access checks.

Original source SHA-256 values describe submitted text, **not** independently verified Dropbox content. A subset or superset of source digests is not assumed identical; semantic similarity is not inferred.

No new recipient, client, Goal, Task, medical observation, measurement, invitation, permissions, or existing source history is changed.

**Release requirements:** PostgreSQL 16 and 17 tests, production-shaped clone, true GoTrue/PostgREST two-person signed tests, source owner approval, canonical migration generation, and separate exact-version protected release. A UI choice among reopen/revise and distinct endeavor must be reviewed before exposing the distinct-create API.

## Free signed production-shaped clone validation

Use the existing **Production Schema Clone Validation** workflow in this public noel-core-db repository. It runs on included standard GitHub-hosted Linux CI, makes read-only schema/role snapshots from the live database using protected credentials, runs a disposable local Supabase/GoTrue/PostgREST stack, applies the reviewed migration only to that clone, and proves A/B private author isolation with real locally issued tokens. No Supabase paid branch or RiverSong local Docker installation is required.

This candidate now includes `fixture.sql`, a copy of the existing synthetic Program author identity fixture; the source-owned `validate-atlas-program-source-identity-signed-http.py` covers duplicate source denial, durable preapproval source receipts, audited deliberate forks, cross-author privacy, and still-valid-JWT grant revocation. Clone harness selects the test **only** for exact migration name `atlas_universal_program_source_identity_v1` and refuses remote database URLs.

Governed activation: source-owner review and merge the source-only changes to main; generate a versioned Atlas migration via the existing owner-issue migration-source-generation workflow using candidate.sql, fixture.sql, and postconditions.sql from this folder; review the generated migration; initiate the existing protected production-schema clone request for exact version/SHA. Verify signed outputs before a **separately authorized** protected production release. Synthetic PostgreSQL fixture tests and Python syntax proof are not substitutes for the full clone's signed evidence.
