# Noel mark-led Reality Pools — candidate for structural review

Release lane `noel`; project `zirqkouammpwxlqfbsvf`; status **unreleased candidate**.

This is the user's October 15 architectural correction: define R2 evidence-bounded Noel mark identities (NMI) as default lexical research addresses, retain exact-form NMF IDs and unique source-token occurrence identities, retain multiple historical Strong's identifiers without allowing those labels to divide raw mark identities, and preserve existing founder pool definitions and IDs. A common NMI is not proof of identical function. Hebrew only; Greek, R0 and R1 admissions require separately reviewed profiles.

## Contents and separation of authority

- `registry_candidate.sql`: seven structural registry tables, immutable form/mark IDs, private read projections, custody and ratification gates. **For independently reviewed, production-shaped clone validation first; NOT production.**
- `postconditions.sql`: clone validation of seven tables, two private security-invoker views, RLS, and direct client privilege exclusion. Produces no founder research data.
- `operator_backfill_template.sql`: privileged, book-scoped, idempotent **data** loading template. Must NEVER be copied into an ordinary structural migration. Run only after separately authorized release and snapshots.
- `operations_amendment.md`: proposed post-release research instruction correction; do not make Strong's required for mark identity.

## Requirements before approval

1. Run structural source and `postconditions.sql` in a disposable **production-schema clone**, not production. Verify zero unexpected DDL or API access, migration ownership, exact R2 Unicode projector behavior, and restored compatibility.
2. Source-reviewed `noel_` migration generation from an immutable candidate commit on `main` through the repo-owner workflow `docs/GOVERNED_MIGRATION_SOURCE_GENERATION.md`. Then separate migration PR, production-clone validation, protected manual release.
3. Snapshot source-token census, identities and all founder lexical definition fields; after protected deployment conduct a separate book-by-book data backfill, checking provenance, idempotency, duplicate bindings, and unchanged migrations.
4. Reconcile **132 aggregate legacy collision cases** privately. This count is an aggregate only, not an instruction to merge pools. Steward decisions are necessary for primary lexical pool establishment.
5. No Titus/Atlas access expansion, no public corpus/founder publication, no Strong's alias rewrite or promotion through dictionary associations.

## Known gates

Live October 15 read-only audit: 306,785 Hebrew MT source tokens, 112,067 exact stored R2 forms, 39,956 consonantal comparison identities, 287 lexical pools (196 founder-seeded, 2 steward-governed, 89 indexed-attested), 278 historical Strong's aliases, 132 NMI comparison keys with more than one historic pool. These are inventory expectations, not an authorization to import or change definitions.

Local deterministic digest/structural static test passed. **No PostgreSQL clone execution has happened yet.** No migration version exists, and no production change is permitted from this PR.
