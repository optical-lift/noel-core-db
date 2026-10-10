# Privacy-preserving custody for Noel research sources
Status (2026-10-10): signed historical inclusion proof merged in PR #1440; owner then directed removal of the research-bearing SQL copies and README from the private Git `main` branch. The proof records past inclusion, not present-day source-file presence. Noel's original research data remains in its database; the executed migration receipts remain in Supabase.

## Why
The public `optical-lift/noel-core-db` repository is suitable for reviewed executable structure and algorithms. A migration body embedding a founder definition, unpublished research notes or evidence interpretation may not be published merely to clear CI. The previously executed H1847 Knowledge migrations in issue #1435 demonstrate this problem.

## Approved design requirements
1. Keep original SQL/source bytes in an **access-restricted, durable, immutable/versioned store** under independent owner-controlled permissions. A filename and SHA alone is not custody.
2. A protected verifier must read that source and the exact live executed-statement body, verify a byte-for-byte hash equality, check a sealed version/name/source-store identifier and custody actor, and emit a minimal public **attestation** with hashes, status and approval provenance. Do not expose the private SQL body or private source links publicly.
3. The public global reconciler may treat a private source as nonblocking **only after** independently verifying a valid attestation under an approved trust root. Never accept arbitrary filenames/hashes, manually self-certifying claims, empty SQL files, or user-generated JSON as proof of protected-source custody.
4. Publication of private research to Titus is an **independent** permission, not a consequence of source custody.
5. Neither custody nor this document authorizes replay, removal/renaming of migration history, source materialization in a public repo, or bypassing protected production release.
6. Future ordinary research row writes must not create executed migration statements, and thus will not need this historical repair mechanism.

## H1847 historical mistake — source once in private Git, removed from current tree

- Original SQL versions `20261010214537` and `20261010214627` were copied **byte-for-byte** from the private production migration ledger to private versioned Git escrow inside `optical-lift/song-ontology`, under `provenance/noel-private-migration-custody/2026-10-10/`. They were merged by private PR #19 with signed commit `6a5aa00cbf96895170c1c369372fc21a6a4f97fa`. Escrow is **not** the executable migration authority and not an experimental Song ontology claim.
- The expected original Git blob SHA-1s are `b94131f94526032acdfbdf0b81718c7fc7964afd` (anchors) and `c632c6464203485a1c85db3277554c0efc616506` (edges).
- Public `custody/private-noel-h1847-signed-source-inclusion-v1.json` includes **only signed Git commit metadata, Git tree entries/hashes, file paths and blob hashes**. No founder definition, verse note, or private SQL string is in that file.
- `scripts/verify-private-source-custody.py` verifies the commit signature under GitHub's official web-flow GPG public key, reconstructs the entire rooted private Git tree Merkle chain to both SQL blob IDs, and validates two exact filenames, versions and SHA-1s. The live reconciler separately checks each cryptographically proven private blob hash against the live migration body before classifying `canonical_private_attested`. Any mismatch, missing source in signed tree, damaged signature, missing verifier or unrecognized migration remains **blocking**.
- Verified on PR #1440 Database Custody CI (run 38095211239): `canonical_exact=954`, `canonical_reconciled=67`, `canonical_private_attested=2`, `blockingCount=0`, `globalErrorCount=0`.
- The SQL files were removed from the current private repository tree by the owner's explicit direction. Their content remains in the previously executed Supabase migration ledger and their research results remain in Noel. Older private Git commits and pull-request references may retain the past blobs; deletion from `main` is not a historical purge. No research may be replayed, republished to Titus or rematerialized into Git through this audit mechanism. Eight other public-safe executed function migrations were resolved through merged PR #1438; obsolete #1436 was closed.

## Continuing maintenance

Do **not** recreate the removed private SQL copies, export research definitions to code repositories, or use migrations for ordinary Noel records. The signed historical inclusion proof is retained strictly for audit of two already-executed migration receipts; it does not establish current Git-based research custody. A complete purge of historical commits/PR objects is separate from current-tree deletion and must be performed without erasing unrelated repository history or weakening the production custody gate. Future word-definition/evidence rows are **data transactions**, not executable migrations.

## Future extensibility (not required for this bounded historical repair)
Do not generalize the exceptional private-source attestation to new live migration gaps without separate owner approval and equivalent independently verifiable provenance. Future protected-source store or key changes must prove negative scenarios (wrong source, changed blob, missing source, wrong owner/root, invalid signature) and preserve the original exact live/body/hash linkage.
