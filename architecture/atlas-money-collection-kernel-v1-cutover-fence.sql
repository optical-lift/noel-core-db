-- Atlas Money Collection Kernel v1 — cutover concurrency fence.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- In the generated migration, run this immediately after BEGIN and BEFORE
-- establishing source-adapter coverage or replacing any source writer.
--
-- SHARE ROW EXCLUSIVE conflicts with INSERT/UPDATE/DELETE RowExclusive locks.
-- Once these locks are acquired, all transactions already writing these source
-- tables have completed, and no new legacy Registration/Sale birth can commit
-- until this migration commits or rolls back.

lock table
  atlas.community_registrations,
  atlas.community_registration_payments,
  atlas.flower_sale_orders
in share row exclusive mode;

-- Re-evaluate the clean Registration cutover only AFTER writer quiescence.
do $$
begin
  if exists(select 1 from atlas.community_registrations) then
    raise exception 'Money kernel clean Registration cutover aborted: canonical registrations now exist.' using errcode='23514';
  end if;
  if exists(select 1 from atlas.community_registration_payments) then
    raise exception 'Money kernel clean Registration cutover aborted: legacy payment rows now exist.' using errcode='23514';
  end if;
end;
$$;

-- IMPORTANT GENERATED-MIGRATION RULE:
-- Do not use transaction_timestamp() as coverage_started_at. A migration may
-- wait to acquire the locks above; transaction_timestamp() would then predate
-- legacy writes that completed while this transaction was waiting.
--
-- After the locks are held and all reviewed writer replacements are installed,
-- activate both adapters with ONE actual post-lock timestamp, for example:
--
-- do $$
-- declare
--   v_cutover_at timestamptz := clock_timestamp();
-- begin
--   perform atlas.activate_money_source_adapter_coverage_core_v1(
--     'community_registration','registration','participation_fee',
--     'community_registration_money_v1',v_cutover_at,
--     <REAL_GENERATED_MIGRATION_PROVENANCE>,null,
--     '{"cleanCutover":true}'::jsonb
--   );
--   perform atlas.activate_money_source_adapter_coverage_core_v1(
--     'flower_commerce','flower_sale_order','sale_total',
--     'flower_sale_money_v1',v_cutover_at,
--     <REAL_GENERATED_MIGRATION_PROVENANCE>,null,
--     '{"historicalAbsenceMeans":"payment_truth_unknown_pre_kernel"}'::jsonb
--   );
-- end;
-- $$;
--
-- The real provenance token may be filled only after `supabase migration new`
-- generates the canonical migration identity.
