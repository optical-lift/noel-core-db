-- Normalize authority-catalog source custody to the durable repository path.
-- The live migration ledger remains the version authority; this label must not
-- self-reference a guessed migration timestamp.
update atlas.architecture_truth_authorities
set source_custody='optical-lift/noel-core-db:supabase/migrations',
    updated_at=now()
where domain_key='crop_lifecycle';

select atlas.assert_architecture_truth_authorities_v1();