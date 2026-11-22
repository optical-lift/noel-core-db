-- Reviewed Shared native source type; first migration in a two-stage release.
-- This transaction must COMMIT before a later migration uses the enum label.
BEGIN;
ALTER TYPE transcript_core.asset_provenance_class ADD VALUE IF NOT EXISTS 'manuscript_source';
COMMIT;
