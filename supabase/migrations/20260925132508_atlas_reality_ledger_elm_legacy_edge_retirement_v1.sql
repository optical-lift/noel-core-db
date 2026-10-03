insert into compatibility.legacy_bindings(
  legacy_schema,legacy_table,legacy_key,disposition,basis
) values
  (
    'atlas','ledger_relationships','f108d4b1-ea1c-49a4-bb31-d0dfc753e6d9','retired',
    '{"reason":"Legacy sibling relation does not become a new Ledger connection. Both Ledgers already share Elm Farm as their canonical subject; observational composition must be established separately."}'::jsonb
  ),
  (
    'atlas','ledger_organization_participations','09616f9f-7afe-429e-b7d6-ddc7b7874eb5','retired',
    '{"reason":"Organization intermediary removed. New Flower Ledger points directly to canonical Elm Farm Entity."}'::jsonb
  ),
  (
    'atlas','ledger_organization_participations','740d55cf-2fd3-4c4e-ad81-a4dce4f31009','retired',
    '{"reason":"Organization intermediary removed. New Venue Ledger points directly to canonical Elm Farm Entity."}'::jsonb
  );
