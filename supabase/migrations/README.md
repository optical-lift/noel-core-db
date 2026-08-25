# Migration custody

This directory will become the canonical executable migration history for the physical `noel-core` Supabase project.

No migration has been imported here yet.

The first database-custody operation must be a provenance/parity bootstrap against the production migration ledger. Existing Atlas migration files must not be copied, renamed, or declared obsolete without that adjudication.

New Write Now migrations should not be applied before this repository has a baseline proving where canonical migration custody begins.

Migration names should clearly identify their owning product/schema, for example:

```text
YYYYMMDDHHMMSS_wnph_creator_corpus_v1.sql
YYYYMMDDHHMMSS_wnph_source_circle_v1.sql
```
