-- Governed release wrapper for the already clone-validated Principal Capacity authority.
-- The original migration predates the current transaction-owned release contract.
-- Execute its canonical bytes inside this migration's transaction so schema change and
-- production custody receipt remain atomic under the protected release workflow.

BEGIN;

\i supabase/migrations/20260911001900_atlas_principal_capacity_authority_v1.sql

COMMIT;
