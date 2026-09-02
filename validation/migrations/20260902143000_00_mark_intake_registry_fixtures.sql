\set ON_ERROR_STOP on

-- Production schema-clone validation is intentionally schema-only, so seeded
-- registry rows are absent from the disposable clone. Recreate only the
-- physical registry fixtures exercised by this postcondition. These rows live
-- only in the disposable validator database; production release does not run
-- validation/migrations SQL.

insert into mark.channel_registry(
  channel_key, channel_family, channel_name, physical_basis, strict_blind_allowed
)
values
  ('ink_dark', 'pigment', 'Dark ink/pigment', 'Observed low-luminance deposited material.', true),
  ('pigment_red', 'pigment', 'Red pigment', 'Observed red-hued deposited material.', true)
on conflict (channel_key) do nothing;

insert into mark.relation_registry(
  relation_key, relation_family, relation_name, directed, physical_definition,
  inverse_relation_key, strict_blind_allowed
)
values
  ('touches', 'junction', 'Touches', false,
   'Two observed components meet at one or more physical boundary points.',
   null, true)
on conflict (relation_key) do nothing;
