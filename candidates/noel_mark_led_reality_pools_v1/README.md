# Noel mark-led Reality Pools — candidate for structural review

Release lane `noel`; project `zirqkouammpwxlqfbsvf`; status **unreleased candidate**.

This is the user's October 15 architectural correction: define R2 evidence-bounded Noel mark identities (NMI) as default lexical research addresses, retain exact-form NMF IDs and unique source-token occurrence identities, retain multiple historical Strong's identifiers without allowing those labels to divide raw mark identities, and preserve existing founder pool definitions and IDs. A common NMI is not proof of identical function. Hebrew only; Greek, R0 and R1 admissions require separately reviewed profiles.

## Contents and separation of authority

- `registry_candidate.sql`: seven structural registry tables, immutable form/mark IDs, private read projections, custody and ratification gates. **For independently reviewed, production-shaped clone validation first; NOT production.**
- `postconditions.sql`: clone validation of seven tables, two private security-invoker views, RLS, direct client privilege exclusion, and rollback-only synthetic tests for immutability, allowed witness scope, NMI/NMF grouping, decision scope and primary-pool uniqueness. Produces no founder research data.
- `operator_backfill_template.sql`: privileged, book-scoped, idempotent **data** loading template. Must NEVER be copied into an ordinary structural migration. Run only after separately authorized release and snapshots.
- `operations_amendment.md`: proposed post-release research instruction correction; do not make Strong's required for mark identity.

## Governing progression — no paid Supabase branch or production trial DDL

1. Review this **non-executable structural source candidate** in PR #1590. Only after reviewer acceptance, merge the candidate source/validation under `candidates/` to canonical `main`. This does not install any tables.
2. The repository OWNER opens the exact `Migration generation request: Noel noel_mark_led_reality_pools_v1` issue, providing the immutable `main` candidate commit SHA and canonical `candidates/` paths. The existing `Governed Migration Source Generation` workflow uses the repository-pinned CLI to generate the real 14-digit version on a separate branch; never fabricate one.
3. Review the generated migration PR and request the existing `Production Schema Clone Validation` workflow with that **versioned migration** and its immutable commit SHA. It reads production schema/roles without modifying production, then executes DDL, synthetic rollback-only behavioral postconditions, and lint in an isolated disposable CI PostgreSQL instance. No paid Supabase branch is needed. GitHub Actions runner usage may consume plan minutes; verify quota before running if zero added cost is required.
4. Keep the structural release on hold until the schema-clone test actually passes, the generated source is reviewed/merged and live custody gates are clear. Then run the separately protected, manually authorized `Production Database Release` workflow for the exact migration version. This is NOT authorized by the current candidate PR.
3. Snapshot source-token census, identities and all founder lexical definition fields; after protected deployment conduct a separate book-by-book data backfill, checking provenance, idempotency, duplicate bindings, and unchanged migrations.
4. Reconcile **132 aggregate legacy collision cases** privately. This count is an aggregate only, not an instruction to merge pools. Steward decisions are necessary for primary lexical pool establishment.
5. No Titus/Atlas access expansion, no public corpus/founder publication, no Strong's alias rewrite or promotion through dictionary associations.

## Known gates

Live October 15 read-only audit: 306,785 Hebrew MT source tokens, 112,067 exact stored R2 forms, 39,956 consonantal comparison identities, 287 lexical pools (196 founder-seeded, 2 steward-governed, 89 indexed-attested), 278 historical Strong's aliases, 132 NMI comparison keys with more than one historic pool. These are inventory expectations, not an authorization to import or change definitions.

Read-only live-data projection and hash checks passed. **No PostgreSQL clone execution has happened yet.** The repository already has a protected, owner-requested disposable-schema-clone workflow, but it requires a *generated* versioned migration candidate. No migration version exists, no schema validation pass is claimed, and no production change is permitted from this PR.
