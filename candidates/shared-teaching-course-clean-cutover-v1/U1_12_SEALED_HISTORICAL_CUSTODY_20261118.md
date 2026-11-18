# U1.12 — sealed custody transport before real historical capture

**HELD, no production data access.** The user-selected pre-deletion safeguard is an encrypted, independently restorable backup of historical source rows before any Course or Program retirement. This increment proves only **cryptographic transport of opaque synthetic bytes**, not PostgreSQL restoration, actual customer-row preservation, selection, or release.

## Separate scopes

- U1.9 passed protected production **schema and roles** restoration.
- U1.10 passed **fictional** history rows on that production-shaped schema, not actual customer rows.
- U1.11's catalog-only FK audit identified 39 reachable descendant relations and 13 external parent relations. It did not identify which particular rows belong to historical Courses or the old McMillan Program.
- PostgreSQL 17 explicitly warns that a table-selective dump does not automatically include referenced objects. Encrypting six tables alone is not full historical restore assurance.

## Source-only synthetic transport

The CLI at scripts/titus-u112-sealed-custody-transport.py:

1. Encrypts **opaque stdin** only using OpenSSL CMS authenticated envelope AES-256-GCM. It has no DB connection or production credential path.
2. Makes a separately encrypted private receipt containing the source byte count and SHA-256. Neither private digest nor plaintext is printed, committed, stored outside the encrypted vault, or uploaded to GitHub.
3. Requires a caller-owned private (0700) vault directory outside worktrees and the GitHub workspace, creates new restricted files exclusively with no overwrite and removes partial outputs on failure.
4. Independently verifies both encrypted artifacts using the private X.509 key, authenticates the content and compares byte count and SHA-256 without emitting plaintext.
5. Tests in CI using fictional data and ephemeral test certificates only: genuine encryption, separate-process verification, tampering, wrong private key, unsafe directory and overwrite refusal. There is no data dump, restore, protected database call, migration, or deployment.

The user's private key must **never** be committed to Git, uploaded to an artifact, placed in an issue/chat message, or exposed in logs. This synthetic test is not a license to copy actual customer records.

## Remaining prerequisites

**A. Row-level inclusion manifest:** For each specific historical Course/Program root, identify its actual dependents, external FK parents, source ownership and exact preservation or retirement disposition. Preserve independent Auth/Person, Song, medical, teacher and lesson originals. Never take an indiscriminate data dump to get FKs green. A reviewed synthetic Auth ID-only parent may be added to a disconnected clone when the real database constraints support it.

**B. Durable protected real data restore:** Select trusted owner-controlled persistent encrypted storage, a recipient certificate, separate private-key custody, recovery/retention/cleanup policy and consistent read-only source cut. Seal exactly the reviewed row set plus independently necessary schema/roles, verify its private byte witness, and **restore to a separate disconnected local PostgreSQL clone**. Test original identifiers, requests/receipts, UTF-8 manuscript bytes, timestamps, authors and FKs with no private row/text/hash/ID leakage to runner logs. A verified CMS capsule is not a completed PostgreSQL restore.

**C. Distinct owner authorization:** The production-row extraction and private encrypted backup need a new explicit, exact owner-authored protected request; the U1.9/U1.10 issues only allowed schema and roles. No production DDL, release, actual Course migration or retirement is authorized. The owner-selected backup-before-deleting-15-Course-shells-and-one-McMillan-Program condition remains.

## Proof boundary

Synthetic encryption and independently authenticated byte verification are proven only after CI passes. Real customer inclusion, durable backup, independent PostgreSQL restore, full historical no-loss, signed full-schema API behavior, Atlas Ledger/Reality root eligibility and product/license lifecycle are separate gates.
