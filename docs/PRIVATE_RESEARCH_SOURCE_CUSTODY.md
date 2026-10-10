# Privacy-preserving custody for Noel research sources
Status: boundary specification; **not** a declaration that private source storage or approval has been provisioned.

## Why
The public `optical-lift/noel-core-db` repository is suitable for reviewed executable structure and algorithms. A migration body embedding a founder definition, unpublished research notes or evidence interpretation may not be published merely to clear CI. The previously executed H1847 Knowledge migrations in issue #1435 demonstrate this problem.

## Approved design requirements
1. Keep original SQL/source bytes in an **access-restricted, durable, immutable/versioned store** under independent owner-controlled permissions. A filename and SHA alone is not custody.
2. A protected verifier must read that source and the exact live executed-statement body, verify a byte-for-byte hash equality, check a sealed version/name/source-store identifier and custody actor, and emit a minimal public **attestation** with hashes, status and approval provenance. Do not expose the private SQL body or private source links publicly.
3. The public global reconciler may treat a private source as nonblocking **only after** independently verifying a valid attestation under an approved trust root. Never accept arbitrary filenames/hashes, manually self-certifying claims, empty SQL files, or user-generated JSON as proof of protected-source custody.
4. Publication of private research to Titus is an **independent** permission, not a consequence of source custody.
5. Neither custody nor this document authorizes replay, removal/renaming of migration history, source materialization in a public repo, or bypassing protected production release.
6. Future ordinary research row writes must not create executed migration statements, and thus will not need this historical repair mechanism.

## Pending legacy exception
- The source-protected H1847 token-anchor and evidence-edge bodies in #1435 are still awaiting an approved protected storage and verifier.
- The eight public-safe source-function recoveries were merged through PR #1438 (v54, all eight exact original live Git blob identities). Obsolete draft PR #1436 was closed as superseded. **Only the two H1847 research-bearing SQL bodies are still uncustodied.**
- Live executed-source Git blob SHA-1 identifiers (public hashes only): `20261010214537_noel_reality_h1847_knowledge_source_anchors_v1.sql` = `b94131f94526032acdfbdf0b81718c7fc7964afd`; `20261010214627_noel_reality_h1847_evidence_scoped_edges_v1.sql` = `c632c6464203485a1c85db3277554c0efc616506`. These hashes are verification targets, NOT a substitute for source storage.
- Global production audit must continue reporting uncustodied history. Per-lane release filters are **not** proof of privacy custody or a reason to close the issue.

## Confirmed current baseline

Main audit run 38094506142: 954 canonical exact, 67 canonical reconciled, 2 post-cut active-tail H1847 sources, 0 global errors. Only private-source custody, not source recovery of eight public-safe files, is pending. Do not mark issue #1435 completed or suppress the remaining audit failures.

## Next implementation tranche
Choose and approve protected source storage, establish IAM/access revocation and immutability, create a verifier with a signed attestation contract, build negative tests (missing body / wrong hash / wrong actor / revoked approval / cross-project mismatch), and extend global reconciler only after independent review. Never call this complete before a real verifier has passed against the exact private SQL source.
