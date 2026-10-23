-- Data-only, read-only schema-clone fixture, accepted by the protected fixture contract.
-- Original source records and approval tests are supplied by genuine local signed
-- GoTrue/PostgREST fixture after migration, never copied from production.
-- The existing-principal backfill and future-principal trigger are verified in
-- generated postconditions and the isolated signed synthetic-person test.
select count(*) as existing_active_person_principals
  from atlas.principals
 where status='active' and user_id is not null;
