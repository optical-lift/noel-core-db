# Author source identity, canonical Program storage

Source-only candidate. Reuses the **existing** `atlas.personal_training_programs` and immutable `personal_training_program_versions`; introduces no second Program table.

The default v2 create operation serializes requests by author Principal and a SHA-256 fingerprint of the sorted unique **source-content digests**, and rejects a separate create attempt if an authored draft or any approved version already cites the identical source set. The same original request key retains canonical idempotency. An additional private append-only `personal_program_author_source_receipts` register preserves the source fingerprint on **every create and save**, including documents replaced in an unapproved draft before any immutable version exists. These receipts are custody metadata, not a second Program store. The author-only lookup displays existing matches for review; it is not an access grant.

A separate, explicitly named `personal_program_author_create_distinct_self_api_v1` operation requires a reason and stores it in an append-only, inaccessible-to-clients author fork-audit table. Distinct endeavors are intentional, not automatic reimports. All API commands preserve current Principal and Personal Atlas access checks.

Original source SHA-256 values describe submitted text, **not** independently verified Dropbox content. A subset or superset of source digests is not assumed identical; semantic similarity is not inferred.

No new recipient, client, Goal, Task, medical observation, measurement, invitation, permissions, or existing source history is changed.

**Release requirements:** PostgreSQL 16 and 17 tests, production-shaped clone, true GoTrue/PostgREST two-person signed tests, source owner approval, canonical migration generation, and separate exact-version protected release. A UI choice among reopen/revise and distinct endeavor must be reviewed before exposing the distinct-create API.
