-- Atlas Money Collection Kernel v1 — retire obsolete source coverage reader.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- Assemble after atlas-money-collection-kernel-v1-source-consistency.sql, which
-- installs the source-currency-aware overload and rebinds both current domain
-- readers. The seven-argument draft reader cannot verify source currency and
-- must not remain as a competing internal authority.

drop function atlas.money_source_coverage_state_core_v1(
  uuid,text,text,text,text,timestamptz,numeric
);
