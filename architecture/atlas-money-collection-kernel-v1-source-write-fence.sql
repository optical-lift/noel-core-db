-- Atlas Money Collection Kernel v1 — source-domain write membrane fence.
-- Reviewed migration-source SQL only; not a generated Supabase migration.
--
-- Production audit at this boundary proves:
-- - only record_flower_sale_core_v1/v2 insert flower_sale_orders;
-- - only submit_public_household_registration_v1 inserts community_registrations.
--
-- SECURITY DEFINER governed commands execute as their owning database role and
-- therefore do not require service_role direct table mutation privileges.
-- Remove those raw mutation paths so a service-role application cannot bypass
-- the source-domain command and silently omit the Money postcondition.

revoke insert,update,delete,truncate
  on atlas.flower_sale_orders
  from service_role;
revoke insert,update,delete,truncate
  on atlas.flower_sale_order_lines
  from service_role;

revoke insert,update,delete,truncate
  on atlas.community_registrations
  from service_role;
revoke insert,update,delete,truncate
  on atlas.community_registration_participants
  from service_role;

-- Keep existing SELECT/REFERENCES privileges unless a separate read-custody
-- change requires tightening them. This tranche governs mutation authority only.
