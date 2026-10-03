\set ON_ERROR_STOP on
-- Validation-only ordered-pair carrier. Never merge or release.
-- Apply the two already-generated immutable Atlas migration packages in release order.
\ir 20261003013634_atlas_implementation_reality_identity_resolution_v2.sql
\ir 20261003013635_atlas_implementation_reality_position_responsibility_definition_v1.sql
