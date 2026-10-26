# Final zero-cost signed Foundry end-to-end owner and reviewer notebook

Validation only. **Do not merge or deploy this test artifact.** Uses immutable candidate SQL version `20261024010000` for the existing GitHub-hosted local production-schema clone.

Covered:
- signed owner initiates a provisional workspace and reopens it from their verified owner-only Index;
- a second signed Principal has an independent Index; unrelated workspaces never leak;
- the owner chooses a separate reviewer by name from an existing active shared Atlas connection;
- reviewer sees assigned pending cases in their own inbox;
- reviewer independently approves/rejects source-scope claim; owner or reviewer may revoke, with append-preserved evidence;
- anonymous/no-Principal/outsider/expired or removed GoTrue sessions remain denied;
- no AI carrier permission, canonical Person, Ledger, task or legacy stream backfill.

The protected workflow executes this only in disposable local PostgreSQL/GoTrue/PostgREST and reads production structure/roles without writes. It must produce a signed test receipt and no new Atlas schema-lint errors before any source can be released. This does not verify real-world subject consent, permission to fetch private documents, or a production deployment.
