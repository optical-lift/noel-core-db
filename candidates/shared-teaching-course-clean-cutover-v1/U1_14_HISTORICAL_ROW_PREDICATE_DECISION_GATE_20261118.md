# U1.14 — column-level FK evidence before row-specific retirement planning

**STATUS: HELD / SOURCE ONLY. No production catalog query or customer row read was performed by this increment.**

## New artifact
`U1_14_HISTORICAL_FK_COLUMNS_CATALOG_ONLY.sql` is a read-only `pg_catalog` query that returns the ordered child/parent column pairing for each Titus-side FK constraint, its exact constraint name, delete/update action codes and deferrability. It deliberately does not select from customer or curriculum tables. It is not a migration and it must not be promoted into a customer-data reader.

`scripts/titus-u114-audit-fk-columns-only.py` accepts a separately obtained JSON catalog and compares it to U1.13's frozen 168 unique relation pairs. The present structural observation was 170 FK constraints (including duplicate relation pairs). The validator rejects changed topology, unknown columns, malformed pair order, duplicate evidence and forged authorization flags. It returns only generic PASS/BLOCKED with no row data or selectors. CI uses **fictional column names**, not a captured live result.

## Why this matters
A relation-only graph cannot safely answer which historical rows belong *exclusively* to the 9 old McMillan Courses, the 6 other obsolete Course shells or the associated Program/Formation graph. One shared teacher, lesson, Canon, Song, Reality Person or Auth parent may remain independently valid. Even an FK marked CASCADE is a database behavior, **not** permission for scope expansion or deletion.

Next, after a separately scoped catalog-only inspection, a reviewer can design held predicates using the precise **ordered FK columns** and check whether rows are reachable through multiple roots. For every historical relation classify:

1. Exact original whose existing ID, revision bytes, authorship, grants and history must survive.
2. Row set exclusively owned by a named retired Course/Program root, **pending protected proof**.
3. Shared independent original or mixed relation, not deletable by graph membership.
4. Unresolved relation, blocks retirement until evidence and owner decision.

These are *review classes*, not current row decisions. Do not classify by table name, FK reachability, or age alone. Do not run a production row query, broad export or actual delete to fill gaps.

## Carry-forward protection
- Preserve the six existing customer-original relations, including the external workspace parent, pending the actual row manifest and encrypted no-loss restore.
- Restore SK 101's original source Course UUID, authors, timestamps, manuscript and Unit revision bytes and source-issued Titus grant exactly. Resolve Auth/Person references through independently authorized canonical identity handling, not copied credentials.
- Keep the obsolete program, Formation, Canon, teacher, lesson and other dependent graph independently reviewable. The target is ultimately a **clean cutover**, not a forever legacy shadow.
- An owner-chosen persistent vault, recipient cert, separately recoverable private key, independent off-device recovery, reviewed actual-row selectors and a new protected customer-data-read authorization remain **missing**.
- Never merge/deploy or remove source originals based on synthetic success.

## Boundary of evidence
U1.13 establishes the frozen 168 pair/39 descendant/13 external parent structural snapshot. U1.14 prepares a column-level query and fictional checker **but does not claim the live 170-column FK set was collected or attested**. When a future read is independently authorized, store its evidence only in suitable reviewed custody; do not assume all catalog metadata is safe to publish. Before any row capture, recheck graph drift, full FK closure, source SHA and precise owner authority. Real encrypted backup, independent PostgreSQL restoration and no-loss equality must precede any reviewed `DROP ... RESTRICT` operation.
