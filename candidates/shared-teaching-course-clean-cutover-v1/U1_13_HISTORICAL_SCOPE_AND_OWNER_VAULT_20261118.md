# U1.13 — historical row scope lock and persistent-vault preflight

**Status: HELD. NO production row access or backup.** Stacked on U1.12 draft source. U1.9 schema/roles and U1.10 fictional historical clone remain separately passed.

## What is now frozen for independent review

From Noel's November 18, 2026 SELECT-only `pg_catalog` relationships, the metadata-only edge snapshot contains **168 unique foreign-key child/parent pairs**. The three historical roots reach **39 descendant relations**, referencing **13 external parent relations through 38 directed edges**. This is structural scope, not row selection.

The source-only row-scope manifest explicitly marks six original customer-history relations for exact preservation (workspace, entitlement, original Course, material revisions, Units, Unit revisions). Every other dependent relation is **pending row-scoped review**. External parents, including Auth, Person/Song/teacher/lesson originals, are independently governed and must not be copied wholesale or casually retired. All `rowSelector` entries are `not_authorized`; the manifest's capture, backup, production-write, and deletion flags are false.

The checker `scripts/titus-u113-check-historical-row-scope.py` rejects new/missing historical descendants, unreviewed FK parents, altered existing scope, altered authorizations, forged row selectors, unexpected source SHA and changed catalog counts. `U1_13_HISTORICAL_FK_PAIRS_METADATA_ONLY.json` stores relation names only. No customer row values, IDs, bytes, hashes, names, login or receipts were queried.

## Owner-controlled, persistent vault preflight

The new `scripts/titus-u113-preflight-private-vault.py` checks an **existing** private directory that the owner selects outside Git, outside a GitHub runner, and outside known temporary directories. It requires owned 0700 directory permissions, no symlink substitution, an X.509 certificate valid beyond seven days, an exclusive 0600 random canary, synchronous file/directory flush and cleanup. It prints only a generic PASS/BLOCKED statement. The `--fictional-ci-temp` switch is for synthetic CI fixtures only and **does not** authorize real records.

Neither this preflight nor the U1.12 encrypted transport knows the user's local mount paths or key custody. The owner's future choice of a durable writable vault (e.g. a private Mac directory replicated encrypted to owner-controlled storage), a public recipient certificate, and a separately held private key must be confirmed before a live historical capture. A passed filesystem canary does not establish backup replication or verified off-device recovery.

## First two backup scopes must remain distinct

**SK 101 six-source Course history:** same-ID private Course, its two Units, manuscript/unit revision bytes, founder Auth references and source-issued grant. Row-preserving migration will need a separate private Auth/Person mapping strategy without indiscriminate Auth secrets. No actual original rows have been extracted.

**Former McMillan program and fifteen obsolete course shells:** not part of the six-source customer capture. Program descendants and external teacher, lesson, Formation, canon and Song originals need individually reviewed row predicates and retain/retire classification. FK closure does not imply deleting or exporting every row from its 39 relations.

## Next protected-data execution remains blocked

A **new owner-authored, protected** request must bind (1) exact source SHA, (2) reviewed row-level selectors and dependency-satisfied restore manifest, (3) a trusted persistent encrypted vault + independent key recovery, (4) consistent read-only production capture, (5) independently restored offline PG clone with no-loss attestation, and (6) secretless PASS/FAIL-only results. Neither U1.9 nor U1.10 owner issue authorized reading actual customer rows. No live SQL write, deletion, migration or Titus/Atlas release is allowed.

**Acceptance boundary:** U1.13 green tests establish *reviewed structural scope lock* and *synthetic vault write/readiness*. Actual historical data retention, restore, signed API behavior, and release remain unproven.
