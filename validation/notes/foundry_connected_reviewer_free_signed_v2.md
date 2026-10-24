# Free signed connected-reviewer validation V2

**Not a production release.** This immutable candidate follows the successfully tested [two-human source review run](https://github.com/optical-lift/noel-core-db/actions/runs/40041609478), and adds the final Atlas connected-People reviewer chooser.

- The private list RPC returns only active authenticated Principals sharing an active Atlas organization membership with the signed owner. No global account directory, no guessed IDs, and no personal information for unrelated users.
- The private review request independently rechecks that same relationship. Altering the browser's selected Principal ID cannot assign an arbitrary Atlas stranger.
- A reviewer still must independently sign in and review, and the owner cannot self-approve.
- The review record leaves AI workspace custody `pending`; no carrier credential or Person/Ledger is created.
- A source-specific extension of the signed GoTrue/PostgREST proof checks owner may see the correct connected reviewer, while unrelated signed users and anonymous requests cannot enumerate the list.
- Local synthetic fixture adds one fictional organization and two separate human memberships; no real users or documents.

The protected GitHub production-schema-clone workflow reads production structure/roles **read-only**, executes this exact candidate on an ephemeral local Postgres/GoTrue/REST stack, and incurs no paid Supabase branch costs.

This validation candidate is not to be merged or deployed itself.
