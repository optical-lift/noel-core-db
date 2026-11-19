# Shared listening delivery artifact binding — held candidate

Generic, no customer or episode data. Existing Transcript Core production, asset, master and delivery package IDs remain original. Live metadata and function inspection confirmed manuscript and production creation APIs, but source_ingest handles observed recordings/scripts (not a completed generated MP3). Existing delivery_packages has production_master_id and delivery_profile_id but no exact derivative asset relation.

This restricted candidate links a valid/exported delivery package to one existing, distinct generated-render MP3 asset, with matching production workspace, profile, master content hash, derivative hash and byte size. The receipt digest is lineage evidence, not authorization or proof that remote bytes were checked. No new media registry, public RPC, bucket, membership, listener grant, publication, or storage policy. The table is RLS enabled with explicit revocation from client and service roles. A trusted future verified admission operation must establish actual carrier bytes, caller's signed production authority and exact derivation before inserting; this candidate is not an exposed writer. Revalidate master, package, asset and carrier identity at delivery because upstream rows may change. No production DDL authorized.

## Required proof before any integration
- Protected isolated exact-source clone: matching production/profile/master/generated-render and exact hashes admit; cross-workspace, wrong profile, master-as-derivative, missing/null/hash mismatch, invalid package, wrong MIME/provenance/path, replacement and deletion fail closed.
- Prove identical request replay returns existing binding rather than inserting again in the eventual writer; conflicting receipt cannot overwrite it.
- Check RLS and grants for authenticated, anon, service_role; no direct writes or reads, trigger and relation not reachable through public RPC.
- Verify server-side staged bytes and immutable object identity, before admission. Existing production workspace access is not a listener entitlement.
- Resolve author/publisher's real rights and exact Person-based issuance; use existing canonical authority, not a fake enrollment or owner inferred from title. Separate generic circulation permission operation and signed outsider/revocation tests required before audio delivery.

Status: source candidate only, SQL execution/clone validation not performed. No release migration. The first real listening proof lives in private Titus PR #88, not in this public repository.
