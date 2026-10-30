# Ledger Person disclosure and compulsory assignment P0 source candidate

This is a **source-only** release candidate for [Noel #2409](https://github.com/optical-lift/noel-core-db/issues/2409), not a migration or permission change. It relies on the original canonical Person and existing Principal, with exact-Ledger root authority. It creates **zero** People, Principals, Ledger seats or alternate employee accounts.

The SQL preserves current RPC signatures and public facades while denying the unsafe all-seat personnel lookup, direct compulsory peer assignment and person-targeted dispatch for ordinary connected employees. It also guards the establishment trigger's `ledger_connection_direct_assignment` path, not any other accepted standing scope.

Before promotion, exercise the source candidate in a disposable full-schema clone with authenticated **Anna employee on Elm**, **Anna root on her own test Ledger**, **Lex root on Elm but limited in Anna's Ledger**, a third-person outsider, and revoked permissions. Verify real 42501 from both public and atlas RPCs, no roster/name/count/UUID leak, no allocation/Work/plan side effects on denied attempts, no change to historic work allocation lifecycle, and still-successful governed standing scopes.

**Known caveat:** this legacy path is temporarily restricted to Ledger roots. A separate *explicit delegated* assignment/directory grant will require its own source contract; broad mutual Ledger connection is not a valid delegation. Hidden UI controls alone are insufficient.

This source MUST be rerun against the exact deployed function definitions and never forced through a drift failure. No direct production SQL or bypass of Noel's guarded migration workflow.