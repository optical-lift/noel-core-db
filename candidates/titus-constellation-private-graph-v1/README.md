# Titus Constellation — Private Live Graph Read Contract

Source: governed noel-core-db. Product: optical-lift/titus PR #3.

This SQL is a **read projection** of the exact live private source records, not a new dictionary, graph authority or research fact table. It includes active Reality Pool nodes/edges, Song objects, registered patterns, pattern-to-pattern relations, pattern-to-Song relations, node aliases, limited verified lexical token anchors, and Song lane labels. It preserves directional typed edges, authority states and disconnected nodes. Inactive endpoints are excluded, counted as omissions and never inferred.

The read is a SECURITY INVOKER SQL function in the PostgREST-accessible public schema, with EXECUTE explicitly revoked for PUBLIC, anon and authenticated and granted to service_role. It must be called **only server-side after independent principal-bound Atlas/Titus authorization**. A service-role bearer token is transport, never proof of viewer authority. Do NOT add browser grants or serverless unauthenticated endpoints. For now the Constellation application remains accessible only in local Next development; Atlas-to-Titus product authorization is held in existing PRs #1427/#230/#1 and must pass its independent security lifecycle before public-preview or production private access. No unreviewed user identity, teacher access or new entitlement is created.

Use exact documented noel-core-db workflow: staged candidate -> merge source -> governed Shared migration source generator -> disposable production-shaped schema clone test -> merge migration -> protected manual production release -> live readback. No direct apply_migration. The validation tests **schema and access contract without synthetic data**. After release, run a separate read-only live data check to confirm Grain→Bread→Restoration, Eat, Bless, isolated nodes, real pattern links, and source-token provenance.

No publication of protected Noel research, no Titus deployment, no change to founder definitions, no identity handoff release.
