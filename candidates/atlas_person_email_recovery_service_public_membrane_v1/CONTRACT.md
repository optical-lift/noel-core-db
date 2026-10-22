# Atlas existing Person recovery — service-only PostgREST transport
This candidate creates seven small `public` wrappers calling the existing
`atlas` identity-recovery authority. Supabase Data API may not expose the private
`atlas` schema; an Edge Function cannot assume it can call private RPCs by
setting a header. Only `service_role` may execute these wrappers.

- Browser roles `anon` and `authenticated` are explicitly denied.
- An actual, verified bearer token for the reviewing Owner is still checked
  inside the Edge Function and passed into the underlying owner-scoped
  functions; the wrappers are not a source of new authority.
- The recovery worker calls the default `public` PostgREST RPC schema.
- This is structurally dependent on the verified-address registry and recovery
  ceremony migrations in that order.
- It does not create an Auth user, issue access, or email anyone.
- Protected schema-clone validation and separate production release are
  mandatory before any worker rollout.
**Institutional Person correction:** The signed-in owner relation is checked against active `institutional_person_records` rather than requiring a legacy `organization_memberships` seat for the recipient. This allows existing Katie Elm history to remain canonical and does not create an employee seat. These two corrected private functions are included in the same migration as the service-only public RPC transport, before the transport is released.
