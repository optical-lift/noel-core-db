# Atlas Personal weekly-fit transactional reissue (v3)

Source-only until canonically generated, production-schema clone-tested and authorized for separate protected release.

Original function source is byte-for-byte retained between new `BEGIN;` / `COMMIT;` statements from `candidates/atlas-personal-week-fit-readonly-v1/candidate.sql` (clone-proven as generated version `20261016200957`, run #38962283183). The prior generated migration is unexecuted in production: governed release run #38965691264 rejected it *before SQL execution* with "Governed production release requires the migration to begin with BEGIN;". The release guard **must not** be weakened.

This reissue has a **fresh migration name and version**, preserving immutable migration history and noncollision of canonical source. It uses the same native Person/Household fixture and full behavioral+privacy postconditions including current-week no-past placement, next-week positive fit, prep linked to a Friday source event, cross-Person rejection, and read-only no mutation.

Do not produce a second source or scheduler. Its public APIs merely preview; a human capacity answer goes through the existing released native Personal capacity APIs. No task/Clock admission or physical completion.

After source custody merge, canonical source generation, and newly repeated clone proof, the release workflow requires an exact manual production approval and separate receipt. The old version must stay unreleased, with its failed release clearly noted.
